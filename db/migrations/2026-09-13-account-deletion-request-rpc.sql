-- ─────────────────────────────────────────────────────────────────────────────
-- ACCOUNT DELETION REQUESTS, FILED FROM THE ANDROID APP
--
-- Google Play's User Data policy: an app in which an account can be created must give users an
-- IN-APP path to request that account's deletion AND a web link. NIVORA accounts are created
-- inside the app — an owner creates staff, a warden registers residents — so both are owed. The
-- web has had its half since lib/actions/account.ts (a "Delete my account and data" card on the
-- resident profile). The Android app had none: legal_documents.dart said so in as many words.
--
-- WHY AN RPC, AND NOT THE WEB'S SERVER ACTION. requestAccountDeletion() runs on the Next.js server
-- with the service-role key, which it needs twice: notifications_insert only admits the service
-- role, and a resident may not read audit_log even for their own rows. A phone must never hold
-- that key. So the same two writes happen here, inside a SECURITY DEFINER function, under the
-- caller's own session — both tables are owned by postgres with FORCE ROW LEVEL SECURITY off, the
-- same arrangement accept_legal_terms() already relies on to write audit_log.
--
-- IT MIRRORS THE WEB ACTION EXACTLY, because the two must agree on what counts as "on file":
--   who may file   student, warden, manager, owner. NOT gated on the subscription: a data-subject
--                  request refused because a hostel's plan lapsed is, for Play, no route at all.
--   rate limit     3 per user per day (app.spend — fails open, as it does everywhere)
--   de-duplication a request already filed in the last 30 days is returned, not re-filed
--   who is told    student → the hostel's wardens and its owner; warden/manager → the owner;
--                  owner → the super admins. Never the requester.
--   the record     audit_log action 'account.deletion.requested', target the user. The web reads
--                  exactly this row, so a request filed on either surface shows on both.
--   the reason     copied into the staff notification (trimmed to 200) and deliberately NOT into
--                  audit_log, which is kept 365 days and readable by the owner — data minimisation,
--                  docs/data-retention-and-privacy.md §8. meta records only whether one was given.
--
-- IT FILES A REQUEST; IT DELETES NOTHING. Nobody in this product holds a delete privilege on their
-- own record, deliberately: fee_payments cascade from students, and "erase my data" sent by the
-- wrong person is an attack on the person it names. Identity is verified in person, then the
-- runbook in docs/account-deletion.md is followed.
--
-- ERROR CODES. Every refusal a person can actually reach is raised as P0001, because the app's
-- failure mapping (nivora_app/lib/data/models/failure.dart) passes a P0001 message through word
-- for word and turns 42501 into a generic "You do not have access to that". Only 'Not signed in'
-- keeps 42501, and it is unreachable through PostgREST anyway: anon holds no EXECUTE on this.
--
-- An advisory lock on the user serialises two taps that arrive together, so a double-tap cannot
-- pass the 30-day check twice and file two requests.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.request_account_deletion(
  p_reason    text default null,
  p_hostel_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_role        public.user_role;
  v_name        text;
  v_user_hostel uuid;
  v_hostel      uuid;
  v_owner       uuid;
  v_student     uuid;
  v_reason      text := nullif(btrim(coalesce(p_reason, '')), '');
  v_existing    timestamptz;
  v_body        text;
  v_notified    integer := 0;
  v_at          timestamptz;
begin
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;

  select u.role, u.full_name, u.hostel_id
    into v_role, v_name, v_user_hostel
    from public.users u
   where u.id = v_user
     and u.deleted_at is null;

  if v_role is null then
    raise exception 'This account is not set up yet.' using errcode = 'P0001';
  end if;
  if v_role not in ('student', 'warden', 'manager', 'owner') then
    raise exception 'Deletion requests for this account are handled by the platform administrator.'
      using errcode = 'P0001';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Keep the reason under 500 characters.' using errcode = 'P0001';
  end if;

  -- The hostel the request is about. An owner may run several: honour the one the app is showing
  -- when it is theirs, otherwise fall back to their own home hostel, then their oldest.
  if v_role = 'owner' then
    select h.id, h.owner_user_id
      into v_hostel, v_owner
      from public.hostels h
     where h.owner_user_id = v_user
       and (p_hostel_id is null or h.id = p_hostel_id)
     order by (h.id = v_user_hostel) desc nulls last, h.created_at
     limit 1;
  else
    select h.id, h.owner_user_id
      into v_hostel, v_owner
      from public.hostels h
     where h.id = v_user_hostel;
  end if;

  if v_hostel is null then
    raise exception 'No hostel is linked to this account. Please contact the address on the account deletion page.'
      using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('account-deletion:' || v_user::text));

  perform app.spend(
    'account-deletion', 3, 86400,
    'You have already sent this request. Your warden and hostel owner can see it.'
  );

  select max(a.at)
    into v_existing
    from public.audit_log a
   where a.action = 'account.deletion.requested'
     and a.actor_user_id = v_user
     and a.at >= now() - interval '30 days';

  if v_existing is not null then
    return jsonb_build_object('requested_at', v_existing, 'already_pending', true, 'notified', 0);
  end if;

  if v_role = 'student' then
    select s.id
      into v_student
      from public.students s
     where s.user_id = v_user
       and s.status <> 'vacated'
     limit 1;
  end if;

  v_body := coalesce(nullif(btrim(v_name), ''), 'A user')
         || ' asked for their NIVORA account and personal data to be deleted.'
         || case when v_reason is not null then ' Reason: "' || left(v_reason, 200) || '"' else '' end
         || ' Verify who they are in person before acting.';

  with recipients as (
    select u.id, 'super_admin' as role
      from public.users u
     where v_role = 'owner'
       and u.role = 'super_admin' and u.status = 'active' and u.deleted_at is null
    union
    select u.id, 'warden'
      from public.users u
     where v_role = 'student'
       and u.role = 'warden' and u.hostel_id = v_hostel and u.status = 'active' and u.deleted_at is null
    union
    select u.id, 'owner'
      from public.users u
     where v_role <> 'owner'
       and u.id = v_owner and u.status = 'active' and u.deleted_at is null
  ),
  delivered as (
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    select v_hostel, r.id, 'system', 'Account deletion requested', v_body,
           case r.role
             when 'super_admin' then '/super-admin/hostels'
             when 'owner' then case when v_student is not null
                                    then '/owner/students/' || v_student::text
                                    else '/owner/staff' end
             else '/warden/rooms'
           end
      from recipients r
     where r.id <> v_user
    returning 1
  )
  select count(*) into v_notified from delivered;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (
    v_user, v_role, 'account.deletion.requested', 'user', v_user::text, v_hostel,
    jsonb_build_object(
      'requesterRole', v_role::text,
      'studentId',     v_student,
      'notified',      v_notified,
      'hasReason',     v_reason is not null,
      'surface',       'app'
    )
  )
  returning at into v_at;

  return jsonb_build_object('requested_at', v_at, 'already_pending', false, 'notified', v_notified);
end $$;

revoke all on function public.request_account_deletion(text, uuid) from public, anon;
grant execute on function public.request_account_deletion(text, uuid) to authenticated;

-- The caller's own request still on file, for the profile screen. Definer because a resident may
-- not read audit_log; pinned to auth.uid(), so nobody else's trail is reachable through it.
create or replace function public.my_account_deletion_request()
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select max(a.at)
    from public.audit_log a
   where a.action = 'account.deletion.requested'
     and a.actor_user_id = auth.uid()
     and a.at >= now() - interval '30 days'
$$;

revoke all on function public.my_account_deletion_request() from public, anon;
grant execute on function public.my_account_deletion_request() to authenticated;

-- ═══ AFTER APPLYING ═══
--   select has_function_privilege('anon', 'public.request_account_deletion(text, uuid)', 'execute');          -- false
--   select has_function_privilege('authenticated', 'public.request_account_deletion(text, uuid)', 'execute'); -- true

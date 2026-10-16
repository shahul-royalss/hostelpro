-- Undo 2026-10-17-google-sign-in.sql.
--
-- Drops the identity guard and the account lookup, and puts public.email_link_proof() back to
-- the body measured on live on 2026-10-17 (arms A and B, comment-free), proved by its md5.
--
-- Turn Google off in the dashboard (Authentication → Sign In / Providers) BEFORE running this:
-- without the trigger, GoTrue links a Google identity to any account with the same address,
-- staff included. Google identities already linked stay linked; this file does not delete them.

begin;
set local lock_timeout = '10s';

drop trigger if exists identities_guard_external on auth.identities;
drop function if exists app.guard_external_identity();
drop function if exists public.login_account_for_email(text);

create or replace function public.email_link_proof(p_user uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  with floor_at as (
    select coalesce(pu.email_verification_reset_at, '-infinity'::timestamptz) as since
    from public.users pu
    where pu.id = p_user
  )
  select greatest(
    (
      select max(f.auth_code_issued_at)
      from auth.flow_state f
      where f.user_id = p_user
        and f.authentication_method in ('magiclink', 'otp', 'recovery')
        and f.auth_code_issued_at is not null
        and f.auth_code_issued_at >= (select since from floor_at)
    ),
    (
      select max(a.created_at)
      from auth.audit_log_entries a
      where a.payload ->> 'actor_id' = p_user::text
        and a.payload ->> 'action' = 'login'
        and coalesce(a.payload -> 'traits' ->> 'provider', 'link')
              in ('link', 'magiclink', 'otp')
        and a.created_at >= (select since from floor_at)
        and exists (
          select 1
          from auth.audit_log_entries r
          where r.payload ->> 'actor_id' = p_user::text
            and r.payload ->> 'action'
                  in ('user_recovery_requested', 'user_confirmation_requested')
            and r.created_at <= a.created_at
            and r.created_at >= a.created_at - interval '1 hour'
        )
    )
  )
  where exists (select 1 from floor_at);
$$;

do $verify$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.email_link_proof(uuid)'::regprocedure)
       <> '87dd8e31d2789103bb6d11669d1689d6' then
    raise exception 'email_link_proof is not back to the 2026-10-17 body';
  end if;
  if has_function_privilege('anon', 'public.email_link_proof(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.email_link_proof(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.email_link_proof(uuid)', 'execute') then
    raise exception 'email_link_proof has the wrong grants';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'auth.identities'::regclass and tgname = 'identities_guard_external') then
    raise exception 'the identity guard trigger is still there';
  end if;
end
$verify$;

delete from supabase_migrations.schema_migrations where version = '20261017100000';

commit;

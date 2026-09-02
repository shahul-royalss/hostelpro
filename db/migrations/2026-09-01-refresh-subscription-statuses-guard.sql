-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Give public.refresh_subscription_statuses() the internal authorization check that
-- THREAT-MODEL.md §4 already claims it has.
--
-- FOUND BY: Supabase security advisor lint 0029, while auditing the "is the server unhealthy"
-- question (docs/server-health.md §5). The lint flags all 17 SECURITY DEFINER RPCs that
-- `authenticated` may execute. Sixteen of them do re-check authorization internally. This one
-- did not: it had no role guard and no `raise`, yet `grant execute ... to authenticated` means
-- ANY signed-in user — including a student — could invoke it.
--
-- IMPACT, stated honestly so this is not mistaken for a breach:
--   · It returns void and reads nothing back to the caller — no disclosure.
--   · It recomputes subscriptions.status and hostels.status from `end_date`, which the caller
--     cannot influence. The result is the correct state by definition, so it is idempotent.
--   · Its one cross-tenant side effect is inserting a templated "subscription expiring" notice
--     for an OWNER, already self-limited to one per owner per hostel per 7 days.
-- So this was a least-privilege gap and a documentation inaccuracy, not a privilege escalation.
--
-- WHY A GUARD AND NOT A REVOKE. Three call sites invoke it through the cookie-authenticated
-- USER client, not the service role:
--   · app/super-admin/page.tsx   (after requireRole("super_admin"))
--   · app/owner/page.tsx         (owner dashboard load)
--   · lib/actions/super-admin.ts (after assertRole("super_admin"))
-- Revoking EXECUTE from `authenticated` would break all three. The guard below admits exactly
-- the two roles those sites run as, plus the service role for server-side jobs.
--
-- WHY THIS CANNOT BREAK THE DASHBOARDS. Both page call sites are already best-effort — they
-- swallow errors via `.then(() => undefined, () => undefined)` (DECISIONS #14: read-only
-- enforcement is computed live by app.subscription_state, never by this function's output).
-- The third runs only after assertRole("super_admin") has passed. No call site can reach the
-- new raise except one that was never entitled to call it.
--
-- The body below is unchanged from db/schema.sql; only the guard is prepended.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

create or replace function public.refresh_subscription_statuses()
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare r record;
begin
  -- Maintenance recompute, not a user feature. Roles are checked here rather than by the
  -- EXECUTE grant because the owner and super-admin dashboards call this as themselves.
  --
  -- The coalesce is load-bearing, and this is the second version of this guard. app.user_role()
  -- returns NULL when auth.uid() matches no row that is active and not soft-deleted. Without
  -- the coalesce the predicate is `false or NULL` = NULL, `if not NULL` never fires, and the
  -- function FAILS OPEN for exactly the callers that should be refused hardest — a suspended or
  -- deleted account still holding a valid JWT. Verified: manager and anon are refused, owner and
  -- super_admin pass. Same fail-closed rule as app.mfa_satisfied() reading a missing aal claim.
  if not coalesce(
    app.is_service_role()
    or app.user_role() = any (array['super_admin', 'owner']::public.user_role[]),
    false
  ) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  for r in
    select s.id, s.hostel_id, s.owner_user_id, h.name, s.end_date
    from public.subscriptions s join public.hostels h on h.id = s.hostel_id
    where s.status in ('active', 'expiring')
      and s.end_date >= current_date and s.end_date - current_date <= 15
      and s.owner_user_id is not null
      and s.id = (select x.id from public.subscriptions x where x.hostel_id = s.hostel_id order by x.end_date desc limit 1)
      -- at most one expiry notice per owner per hostel per 7 days
      and not exists (
        select 1 from public.notifications n
         where n.user_id = s.owner_user_id
           and n.hostel_id = s.hostel_id
           and n.type = 'subscription'
           and n.created_at > now() - interval '7 days'
      )
  loop
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (r.hostel_id, r.owner_user_id, 'subscription', 'Subscription expiring soon',
            format('%s subscription ends on %s. Contact support to renew.', r.name, to_char(r.end_date, 'DD Mon YYYY')), '/owner');
  end loop;

  update public.subscriptions
     set status = case when end_date < current_date then 'expired' when end_date - current_date <= 15 then 'expiring' else 'active' end::public.subscription_status
   where status is distinct from (case when end_date < current_date then 'expired' when end_date - current_date <= 15 then 'expiring' else 'active' end::public.subscription_status);
  update public.hostels h set status = 'readonly' where h.status = 'active' and app.subscription_state(h.id) = 'expired';
  update public.hostels h set status = 'active'   where h.status = 'readonly' and app.subscription_state(h.id) <> 'expired';
end $fn$;

comment on function public.refresh_subscription_statuses() is
  'Recomputes stored subscription/hostel status and sends owner expiry notices (DECISIONS #14). Callable by super_admin, owner and service_role only — the owner and super-admin dashboards invoke it as themselves.';

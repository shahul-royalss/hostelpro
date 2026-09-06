-- THE FUNCTION THAT DECIDES WHERE RENT GOES WAS REACHABLE WITHOUT SIGNING IN.
--
-- Found by Supabase's own security advisor while auditing for release, not by reading the code:
-- lint 0028, "Public Can Execute SECURITY DEFINER Function", naming both overloads of
-- sa_set_hostel_payout_account on /rest/v1/rpc/.
--
-- WHY THE ORIGINAL MIGRATION DID NOT PREVENT IT. 2026-09-06-route-linked-accounts.sql ends with
-- `revoke all on function ... from public; grant execute ... to authenticated;` which looks
-- exactly right and is not. Supabase grants EXECUTE on every new function in the `public`
-- schema to the `anon` role EXPLICITLY, and revoking from PUBLIC does not touch a grant held by
-- a named role. The revoke ran, the grant to anon survived, and the endpoint answered
-- unauthenticated POSTs.
--
-- It was not exploitable. The first statement in the body is `if not app.is_super_admin() then
-- raise`, and an anonymous caller fails that. But the guard inside being the ONLY line of
-- defence is not how this file has treated money anywhere else, and an unauthenticated caller
-- could still make the database do work on demand — the same surface the rate limiting is for.

revoke execute on function public.sa_set_hostel_payout_account(uuid, text, boolean) from anon, public;
grant  execute on function public.sa_set_hostel_payout_account(uuid, text, boolean) to authenticated;

-- ── AND THE DEAD OVERLOAD GOES ────────────────────────────────────────────────────────────
--
-- sa_set_hostel_payout_account(uuid, text) is the original two-argument version, superseded when
-- direct settlement arrived. Nothing calls it — SaRepository.setPayout passes all three — and it
-- predates the rule that the two settlement modes are mutually exclusive, so it can write
-- razorpay_account_id without ever considering razorpay_direct_for_owner. A second door into the
-- same room, and the older door has the weaker lock.
drop function if exists public.sa_set_hostel_payout_account(uuid, text);

-- ── WHAT IS DELIBERATELY LEFT OPEN ────────────────────────────────────────────────────────
--
-- public.password_reset_gate(text) keeps EXECUTE for `anon`, and that is correct rather than an
-- oversight: somebody who has forgotten their password is by definition signed out, so the
-- function that decides whether to send them a reset has to answer an anonymous caller. It is a
-- rate-limiting target, not a grant to revoke.

-- ═══ AFTER APPLYING ═══
--   select p.oid::regprocedure, array_to_string(p.proacl,' | ')
--     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and p.proname='sa_set_hostel_payout_account';
-- Exactly one row, and `anon=X` must not appear in it.

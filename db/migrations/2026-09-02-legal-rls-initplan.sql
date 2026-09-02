-- The two legal-consent policies missed the earlier InitPlan hoist
-- (2026-08-31-rls-initplan-hoist.sql predates 2026-09-02-legal-consent.sql).
--
-- Bare `auth.uid()` in a USING clause is re-evaluated PER ROW. Wrapped in a scalar subquery it
-- is hoisted into an InitPlan and evaluated once for the whole statement. Identical semantics,
-- and the same change already applied to every other policy in this schema.
--
-- legal_versions is read at every cold start by every user — the consent gate compares the
-- version the app ships against the versions published here — so this sits on the login path,
-- not on a back-office query.

alter policy legal_versions_select on public.legal_versions
  using ((select auth.uid()) is not null);

alter policy legal_acceptances_select on public.legal_acceptances
  using (user_id = (select auth.uid()));

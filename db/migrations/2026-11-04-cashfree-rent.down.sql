-- UNDO 2026-11-04-cashfree-rent.sql. Run as postgres, and only while no real Cashfree payment
-- has been taken (the tables hold money records; dropping them loses the audit trail).
begin;
set local lock_timeout = '10s';

do $guard$
begin
  if exists (select 1 from public.rent_payments where payment_status in ('SUCCESS', 'REFUNDED')) then
    raise exception 'Cashfree payments exist; export them before undoing. Nothing changed.';
  end if;
end
$guard$;

select cron.unschedule('apnivaas-cashfree-tick')
 where exists (select 1 from cron.job where jobname = 'apnivaas-cashfree-tick');

drop function if exists app.cashfree_tick();
drop function if exists public.ow_rent_payment_summary();
drop function if exists public.svc_cf_vendor_status(text, text, jsonb, text);
drop function if exists public.svc_cf_vendor_save(uuid, text, text, text, text, text, text, text, text, text, int, text, jsonb);
drop function if exists public.svc_cf_webhook_end(uuid, text, text);
drop function if exists public.svc_cf_webhook_begin(text, text, text, text);
drop function if exists public.svc_cf_refund_result(text, text, text, jsonb, text);
drop function if exists public.svc_cf_request_refund(uuid, uuid, bigint, text, text);
drop function if exists public.svc_cf_settlement_event(text, text, text, numeric, text, text, timestamptz, jsonb);
drop function if exists public.svc_cf_link_settlement(text, text, text, numeric, timestamptz);
drop function if exists public.svc_cf_split_result(uuid, text, jsonb, text);
drop function if exists public.svc_cf_split_claim(int);
drop function if exists public.svc_cf_close_unpaid(text, text);
drop function if exists public.svc_cf_apply_payment(text, text, text, text, bigint, text, text, text, timestamptz, text);
drop function if exists public.svc_cf_abandon_order(text, text);
drop function if exists public.svc_cf_attach_session(text, text, text, timestamptz);
drop function if exists public.cf_reserve_payment(text, bigint);
drop function if exists public.st_rent_gateway();
drop function if exists app.cf_outstanding_paise(uuid, text);
drop function if exists app.cf_require_service();

drop table if exists public.rent_refunds;
drop table if exists public.owner_settlements;
drop table if exists public.payment_webhook_events;
drop table if exists public.rent_payments;
drop table if exists public.owner_payment_accounts;
drop function if exists app.cf_touch_updated_at();

alter table public.hostels drop column if exists rent_gateway;

delete from supabase_migrations.schema_migrations where version = '20261104090000';
notify pgrst, 'reload schema';
commit;

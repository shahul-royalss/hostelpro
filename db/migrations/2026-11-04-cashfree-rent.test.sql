-- TESTS FOR 2026-11-04-cashfree-rent.sql. One batch, as postgres, inside BEGIN ... ROLLBACK.
-- Before applying: run the migration (without its BEGIN/COMMIT) and this file (without its BEGIN)
-- as one batch ending in ROLLBACK. Builds its own world with fresh ids (@example.com addresses).
-- Callers are impersonated through request.jwt.claims, as PostgREST does. A failure raises
-- 'FAIL <section>: ...'; success ends with 'ALL CASHFREE TESTS PASSED'.

begin;

create function pg_temp.as_user(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function pg_temp.as_service()
returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
end $$;

create function pg_temp.as_postgres()
returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.ok(p_cond boolean, p_label text)
returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'FAIL %', p_label;
  end if;
end $$;

grant execute on function pg_temp.as_user(uuid), pg_temp.as_service(), pg_temp.as_postgres(),
                         pg_temp.ok(boolean, text) to authenticated;

do $test$
declare
  v_tag   text := 'cf-' || left(gen_random_uuid()::text, 8);
  v_ownA  uuid := gen_random_uuid();  v_ownB uuid := gen_random_uuid();
  v_wdn   uuid := gen_random_uuid();
  v_ten   uuid := gen_random_uuid();  v_ten2 uuid := gen_random_uuid();
  v_pgA   uuid := gen_random_uuid();  v_pgB  uuid := gen_random_uuid();
  v_st    uuid := gen_random_uuid();  v_st2  uuid := gen_random_uuid();
  v_vendor text := 'apvo_' || replace(gen_random_uuid()::text, '-', '');
  v_order  text := 'apv_' || replace(gen_random_uuid()::text, '-', '');
  v_order2 text := 'apv_' || replace(gen_random_uuid()::text, '-', '');
  v_period text := to_char(app.today(), 'YYYY-MM');
  v_j jsonb;
  v_pay uuid;
  v_n int;
  v_txt text;
  p1 text; p2 text;
  r record;
begin
  p1 := '9' || substr(regexp_replace(md5(v_tag || '1'), '\D', '', 'g') || '123456789', 1, 9);
  p2 := '8' || substr(regexp_replace(md5(v_tag || '2'), '\D', '', 'g') || '123456789', 1, 9);

  -- ─── Fixtures ───────────────────────────────────────────────────────────────────────────
  insert into auth.users (id, email) values
    (v_ownA, v_tag || '-a@example.com'), (v_ownB, v_tag || '-b@example.com'), (v_wdn, v_tag || '-w@example.com'),
    (v_ten, p1 || '@student.hostelpro.local'), (v_ten2, p2 || '@student.hostelpro.local');
  insert into public.users (id, role, full_name, email, status, must_change_password) values
    (v_ownA, 'owner', v_tag || ' Owner A', v_tag || '-a@example.com', 'active', false),
    (v_ownB, 'owner', v_tag || ' Owner B', v_tag || '-b@example.com', 'active', false);
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms, city, locality, pincode, address, status)
  values (v_pgA, v_tag || ' A PG', v_ownA, 1, 1, 'Pune', 'Sector 5', '411001', '5 Test Road', 'active'),
         (v_pgB, v_tag || ' B PG', v_ownB, 1, 1, 'Pune', 'Sector 6', '411001', '6 Test Road', 'active');
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount)
  values (v_pgA, v_ownA, current_date - 10, current_date + 100, 0), (v_pgB, v_ownB, current_date - 10, current_date + 100, 0);
  insert into public.users (id, role, full_name, email, hostel_id, status, created_by) values
    (v_wdn, 'warden', v_tag || ' Warden', v_tag || '-w@example.com', v_pgA, 'active', v_ownA),
    (v_ten, 'student', v_tag || ' Tenant', null, v_pgA, 'active', v_wdn),
    (v_ten2, 'student', v_tag || ' Tenant Two', null, v_pgA, 'active', v_wdn);
  insert into public.students (id, hostel_id, user_id, full_name, phone, date_of_joining, monthly_fee, created_by) values
    (v_st, v_pgA, v_ten, v_tag || ' Tenant', p1, app.today() - 20, 5000, v_wdn),
    (v_st2, v_pgA, v_ten2, v_tag || ' Tenant Two', p2, app.today() - 20, 3000, v_wdn);

  perform pg_temp.ok((select rent_gateway from public.hostels where id = v_pgA) = 'cashfree', '0 new PGs default to Cashfree');
  perform pg_temp.ok(not exists (select 1 from public.hostels where owner_user_id = '1312e8e1-5216-4eac-b4a6-e276aeeddd1f'
                                  and rent_gateway <> 'razorpay'), '0 Rukesh Akanambattu''s PGs keep Razorpay');

  -- ─── 1. No verified vendor: no checkout ─────────────────────────────────────────────────
  perform pg_temp.as_user(v_ten);
  v_j := public.st_rent_gateway();
  perform pg_temp.ok(v_j ->> 'gateway' = 'cashfree' and not (v_j ->> 'ready')::boolean, '1 not ready without an account');
  begin
    perform public.cf_reserve_payment(v_order, 500000);
    raise exception 'FAIL 1 reserved without a vendor';
  exception when sqlstate 'P0001' then
    perform pg_temp.ok(sqlerrm like 'Online rent payment is not set up%', '1 refusal: ' || sqlerrm);
  end;

  -- A tenant cannot write the vendor table or call service routines.
  begin
    perform public.svc_cf_vendor_save(v_ownA, v_vendor, 'Owner A', 'a@example.com', '9876543210', 'success@upi',
                                      'OWNER A', '934N', null, 'ACTIVE', null, null, null);
    raise exception 'FAIL 1 a tenant called a service routine';
  exception when insufficient_privilege then null;
  end;

  -- ─── 2. Vendor onboarding: pending until Cashfree says ACTIVE ───────────────────────────
  perform pg_temp.as_service();
  v_j := public.svc_cf_vendor_save(v_ownA, v_vendor, 'Owner A Legal', v_tag || '-a@example.com', '9876543210',
                                   'success@upi', 'OWNER A', '934N', null, 'IN_BENE_CREATION', 1, 'T+1', '{"status":"IN_BENE_CREATION"}');
  perform pg_temp.ok(v_j ->> 'verification_status' = 'pending', '2 IN_BENE_CREATION is pending');
  perform pg_temp.as_user(v_ten);
  perform pg_temp.ok(not (public.st_rent_gateway() ->> 'ready')::boolean, '2 pending vendor: not ready');
  begin
    perform public.cf_reserve_payment(v_order, 500000);
    raise exception 'FAIL 2 reserved against a pending vendor';
  exception when sqlstate 'P0001' then null;
  end;
  perform pg_temp.as_service();
  v_j := public.svc_cf_vendor_status(v_vendor, 'ACTIVE', '{"status":"ACTIVE"}', null);
  perform pg_temp.ok(v_j ->> 'verification_status' = 'verified', '2 ACTIVE is verified');
  perform pg_temp.as_user(v_ownB);
  perform pg_temp.ok((select count(*) from public.owner_payment_accounts) = 0, '2 another owner sees no account');
  perform pg_temp.as_user(v_ownA);
  perform pg_temp.ok((select count(*) from public.owner_payment_accounts) = 1, '2 the owner sees their account');

  -- ─── 3. Reserve: the database decides the amount ────────────────────────────────────────
  perform pg_temp.as_user(v_ten);
  perform pg_temp.ok((public.st_rent_gateway() ->> 'ready')::boolean, '3 ready once verified');
  begin
    perform public.cf_reserve_payment(v_order, 100);
    raise exception 'FAIL 3 reserved a chosen amount';
  exception when sqlstate 'P0001' then
    perform pg_temp.ok(sqlerrm like 'Your balance changed%', '3 amount refusal: ' || sqlerrm);
  end;
  v_j := public.cf_reserve_payment(v_order, 500000);
  perform pg_temp.ok(v_j ->> 'outcome' = 'reserved' and (v_j ->> 'amount_paise')::bigint = 500000, '3 reserved: ' || v_j::text);
  v_pay := (v_j ->> 'payment_id')::uuid;
  v_j := public.cf_reserve_payment(v_order2, 500000);
  perform pg_temp.ok(v_j ->> 'outcome' = 'reconcile' and v_j ->> 'order_id' = v_order, '3 a second order waits for the first');
  perform pg_temp.as_service();
  perform public.svc_cf_attach_session(v_order, 'cf123', 'session_abc', now() + interval '30 minutes');
  perform pg_temp.as_user(v_ten);
  v_j := public.cf_reserve_payment(v_order2, 500000);
  perform pg_temp.ok(v_j ->> 'outcome' = 'reuse' and v_j ->> 'payment_session_id' = 'session_abc', '3 a live session is reused');
  begin
    perform payment_session_id from public.rent_payments where id = v_pay;
    raise exception 'FAIL 3 the session column is readable by the tenant';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.ok((select count(*) from public.rent_payments where id = v_pay) = 1, '3 the tenant reads their payment');

  -- ─── 4. Applying Cashfree's answer ──────────────────────────────────────────────────────
  perform pg_temp.as_service();
  begin
    perform public.svc_cf_apply_payment(v_order, 'PAID', '777', 'SUCCESS', 400000, 'INR', 'upi', 'UTR1', now(), null);
    raise exception 'FAIL 4 an amount mismatch was credited';
  exception when sqlstate 'P0001' then
    perform pg_temp.ok(sqlerrm like 'Amount mismatch%', '4 mismatch: ' || sqlerrm);
  end;
  perform pg_temp.ok((select payment_status from public.rent_payments where id = v_pay) = 'INITIATED', '4 nothing changed on mismatch');
  begin
    perform public.svc_cf_apply_payment(v_order, 'ACTIVE', '777', 'SUCCESS', 500000, 'INR', 'upi', 'UTR1', now(), null);
    raise exception 'FAIL 4 credited an order that is not PAID';
  exception when sqlstate 'P0001' then null;
  end;
  v_j := public.svc_cf_apply_payment(v_order, 'ACTIVE', '776', 'FAILED', 500000, 'INR', 'upi', null, now(), 'Insufficient balance');
  perform pg_temp.ok(v_j ->> 'outcome' = 'failed' and (select closed_at is null from public.rent_payments where id = v_pay),
                     '4 a failed attempt leaves the order open');
  v_j := public.svc_cf_apply_payment(v_order, 'ACTIVE', '778', 'PENDING', 500000, 'INR', 'upi', null, now(), null);
  perform pg_temp.ok((select payment_status from public.rent_payments where id = v_pay) = 'PENDING', '4 pending');
  v_j := public.svc_cf_apply_payment(v_order, 'PAID', '777', 'SUCCESS', 500000, 'INR', 'upi', 'UTR1', now(), null);
  perform pg_temp.ok(v_j ->> 'outcome' = 'success', '4 success: ' || v_j::text);
  select * into r from public.rent_payments where id = v_pay;
  perform pg_temp.ok(r.payment_status = 'SUCCESS' and r.receipt_no is not null and r.credited_paise = 500000
                     and r.split_status = 'PENDING' and r.settlement_status = 'SPLIT_PENDING'
                     and r.split_due_at > now() + interval '2 minutes' and r.closed_at is not null, '4 success row');
  perform pg_temp.ok((select amount_paid from public.fee_payments where student_id = v_st and period_month = v_period) = 5000,
                     '4 the rent ledger is credited');
  v_j := public.svc_cf_apply_payment(v_order, 'PAID', '777', 'SUCCESS', 500000, 'INR', 'upi', 'UTR1', now(), null);
  perform pg_temp.ok(v_j ->> 'outcome' = 'already', '4 a duplicate success is a no-op');
  perform pg_temp.ok((select amount_paid from public.fee_payments where student_id = v_st and period_month = v_period) = 5000,
                     '4 credited once');
  v_j := public.svc_cf_apply_payment(v_order, 'PAID', '779', 'FAILED', 500000, 'INR', 'upi', null, now(), 'late failure');
  perform pg_temp.ok(v_j ->> 'outcome' = 'ignored' and (select payment_status from public.rent_payments where id = v_pay) = 'SUCCESS',
                     '4 a later failure never undoes a success');
  perform pg_temp.ok((select count(*) from public.notifications where dedupe_key like 'cf_paid:' || v_pay || ':%') = 2,
                     '4 tenant and owner are told');
  perform pg_temp.as_user(v_ten);
  begin
    perform public.cf_reserve_payment('apv_' || replace(gen_random_uuid()::text, '-', ''), 500000);
    raise exception 'FAIL 4 a paid month took another order';
  exception when sqlstate 'P0001' then
    perform pg_temp.ok(sqlerrm like 'There is nothing to pay%', '4 nothing left: ' || sqlerrm);
  end;

  -- ─── 5. Split After Payment ─────────────────────────────────────────────────────────────
  perform pg_temp.as_service();
  select count(*) into v_n from public.svc_cf_split_claim(20) c where c.payment_id = v_pay;
  perform pg_temp.ok(v_n = 0, '5 not before the two-minute wait');
  perform pg_temp.as_postgres();
  update public.rent_payments set split_due_at = now() - interval '1 second' where id = v_pay;
  perform pg_temp.as_service();
  select * into r from public.svc_cf_split_claim(20) c where c.payment_id = v_pay;
  perform pg_temp.ok(r.vendor_id = v_vendor and r.amount_paise = 500000 and r.attempts = 1, '5 claimed for the owner''s vendor');
  perform public.svc_cf_split_result(v_pay, 'retry', '{"code":"api_request_failed"}', 'Transaction is not synced, please retry after 2 mins');
  perform pg_temp.ok((select split_status = 'PENDING' and split_due_at > now() from public.rent_payments where id = v_pay), '5 retried later');
  perform pg_temp.as_postgres();
  update public.rent_payments set split_due_at = now() - interval '1 second' where id = v_pay;
  perform pg_temp.as_service();
  select * into r from public.svc_cf_split_claim(20) c where c.payment_id = v_pay;
  perform pg_temp.ok(r.idempotency_key is not null and r.attempts = 2, '5 the same idempotency key, second attempt');
  perform public.svc_cf_split_result(v_pay, 'created', '{"status":"OK","message":"Order split created"}', null);
  perform pg_temp.ok((select split_status = 'CREATED' and settlement_status = 'SPLIT_CREATED' from public.rent_payments where id = v_pay),
                     '5 split created');

  -- ─── 6. Settlement ──────────────────────────────────────────────────────────────────────
  perform public.svc_cf_link_settlement(v_order, v_vendor, v_tag || '-S1', 5000.00, now());
  perform pg_temp.ok((select settlement_status = 'SETTLEMENT_PENDING' and settlement_id = v_tag || '-S1'
                        from public.rent_payments where id = v_pay), '6 linked to its settlement');
  v_j := public.svc_cf_settlement_event(v_vendor, v_tag || '-S1', 'SUCCESS', 5000.00, 'UTRSETTLE', null, now(), '{}');
  perform pg_temp.ok(v_j ->> 'outcome' = 'recorded' and (v_j ->> 'payments')::int = 1, '6 settlement event: ' || v_j::text);
  perform pg_temp.ok((select settlement_status = 'SETTLED' and settlement_utr = 'UTRSETTLE' from public.rent_payments where id = v_pay),
                     '6 settled with the UTR');
  perform pg_temp.ok((select count(*) from public.owner_settlements where settlement_id = v_tag || '-S1' and settlement_status = 'SUCCESS') = 2,
                     '6 batch and payment rows both succeed');
  v_j := public.svc_cf_settlement_event('nobody', 'S0', 'SUCCESS', 1, null, null, now(), '{}');
  perform pg_temp.ok(v_j ->> 'outcome' = 'unknown_vendor', '6 an unknown vendor changes nothing');

  -- A settlement that fails: tenant two pays, the split goes through, the settlement fails first.
  perform pg_temp.as_user(v_ten2);
  v_j := public.cf_reserve_payment(v_order2, 300000);
  perform pg_temp.ok(v_j ->> 'outcome' = 'reserved', '6 second tenant reserves');
  perform pg_temp.as_service();
  perform public.svc_cf_attach_session(v_order2, 'cf124', 'session_def', now() + interval '30 minutes');
  perform public.svc_cf_apply_payment(v_order2, 'PAID', '880', 'SUCCESS', 300000, 'INR', 'upi', 'UTR2', now(), null);
  perform public.svc_cf_settlement_event(v_vendor, v_tag || '-S2', 'FAILED', 3000.00, null, 'INVALID_OR_NO_SUCH_ACCOUNT_TYPE', null, '{}');
  perform public.svc_cf_link_settlement(v_order2, v_vendor, v_tag || '-S2', 3000.00, now());
  perform pg_temp.ok((select settlement_status from public.rent_payments where cashfree_order_id = v_order2) = 'SETTLEMENT_FAILED',
                     '6 a failed settlement is carried onto the payment');
  perform pg_temp.ok((select payment_status from public.rent_payments where cashfree_order_id = v_order2) = 'SUCCESS',
                     '6 a failed settlement never fails the payment');

  -- ─── 7. Refunds ─────────────────────────────────────────────────────────────────────────
  begin
    perform public.svc_cf_request_refund(v_pay, v_ownB, 100000, null, 'apvr_' || replace(gen_random_uuid()::text, '-', ''));
    raise exception 'FAIL 7 another owner refunded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.svc_cf_request_refund(v_pay, v_ten, 100000, null, 'apvr_' || replace(gen_random_uuid()::text, '-', ''));
    raise exception 'FAIL 7 a tenant refunded';
  exception when insufficient_privilege then null;
  end;
  v_txt := 'apvr_' || replace(gen_random_uuid()::text, '-', '');
  v_j := public.svc_cf_request_refund(v_pay, v_ownA, 100000, 'Overcharged', v_txt);
  perform pg_temp.ok(v_j ->> 'vendor_id' = v_vendor and v_j ->> 'split_status' = 'CREATED', '7 partial refund requested');
  begin
    perform public.svc_cf_request_refund(v_pay, v_ownA, 100000, null, 'apvr_' || replace(gen_random_uuid()::text, '-', ''));
    raise exception 'FAIL 7 two refunds in flight';
  exception when sqlstate 'P0001' then
    perform pg_temp.ok(sqlerrm like '%already in progress%', '7 one at a time: ' || sqlerrm);
  end;
  v_j := public.svc_cf_refund_result(v_txt, 'SUCCESS', 'cfr1', '{"refund_status":"SUCCESS"}', null);
  perform pg_temp.ok(v_j ->> 'outcome' = 'success' and (v_j ->> 'reversed_paise')::bigint = 100000, '7 partial success');
  perform pg_temp.ok((select amount_paid from public.fee_payments where student_id = v_st and period_month = v_period) = 4000,
                     '7 the ledger gives back ₹1000');
  perform pg_temp.ok((select payment_status = 'SUCCESS' and refunded_paise = 100000 from public.rent_payments where id = v_pay),
                     '7 still a success after a partial refund');
  v_j := public.svc_cf_refund_result(v_txt, 'SUCCESS', 'cfr1', '{}', null);
  perform pg_temp.ok(v_j ->> 'outcome' = 'already', '7 a duplicate refund webhook is a no-op');
  begin
    perform public.svc_cf_request_refund(v_pay, v_ownA, 450000, null, 'apvr_' || replace(gen_random_uuid()::text, '-', ''));
    raise exception 'FAIL 7 refunded more than was left';
  exception when sqlstate 'P0001' then null;
  end;
  v_txt := 'apvr_' || replace(gen_random_uuid()::text, '-', '');
  perform public.svc_cf_request_refund(v_pay, v_ownA, 400000, null, v_txt);
  perform public.svc_cf_refund_result(v_txt, 'SUCCESS', 'cfr2', '{}', null);
  perform pg_temp.ok((select payment_status = 'REFUNDED' and refunded_paise = 500000 from public.rent_payments where id = v_pay),
                     '7 fully refunded');
  perform pg_temp.ok((select amount_paid from public.fee_payments where student_id = v_st and period_month = v_period) = 0,
                     '7 the ledger is back to nothing paid');

  -- ─── 8. Webhook ledger: at-least-once delivery, processed once ──────────────────────────
  v_j := public.svc_cf_webhook_begin(v_tag || '-evt1', 'PAYMENT_SUCCESS_WEBHOOK', v_order, 'hash1');
  perform pg_temp.ok(v_j ->> 'outcome' = 'new', '8 new event');
  perform public.svc_cf_webhook_end((v_j ->> 'id')::uuid, 'processed', null);
  v_j := public.svc_cf_webhook_begin(v_tag || '-evt1', 'PAYMENT_SUCCESS_WEBHOOK', v_order, 'hash1');
  perform pg_temp.ok(v_j ->> 'outcome' = 'duplicate', '8 a redelivery is a duplicate');
  v_j := public.svc_cf_webhook_begin(v_tag || '-evt2', 'PAYMENT_SUCCESS_WEBHOOK', v_order, 'hash2');
  perform public.svc_cf_webhook_end((v_j ->> 'id')::uuid, 'failed', 'boom');
  v_j := public.svc_cf_webhook_begin(v_tag || '-evt2', 'PAYMENT_SUCCESS_WEBHOOK', v_order, 'hash2');
  perform pg_temp.ok(v_j ->> 'outcome' = 'retry', '8 a failed event is retried');

  -- ─── 9. Who sees what ───────────────────────────────────────────────────────────────────
  perform pg_temp.as_user(v_ownB);
  perform pg_temp.ok((select count(*) from public.rent_payments where pg_id = v_pgA) = 0, '9 another owner sees none');
  perform pg_temp.ok((select count(*) from public.rent_refunds rf join public.rent_payments rp on rp.id = rf.payment_id
                       where rp.pg_id = v_pgA) = 0, '9 another owner sees no refunds');
  perform pg_temp.ok((select count(*) from public.owner_settlements where cashfree_vendor_id = v_vendor) = 0, '9 nor settlements');
  begin
    perform public.ow_rent_payment_summary();
  exception when others then
    raise exception 'FAIL 9 owner B summary errored: %', sqlerrm;
  end;
  perform pg_temp.ok((public.ow_rent_payment_summary() ->> 'collected_paise')::bigint = 0, '9 owner B collected nothing');
  perform pg_temp.as_user(v_ownA);
  perform pg_temp.ok((select count(*) from public.rent_payments where pg_id = v_pgA) = 2, '9 the owner sees both payments');
  v_j := public.ow_rent_payment_summary();
  perform pg_temp.ok((v_j ->> 'collected_paise')::bigint = 300000 and (v_j ->> 'failed_settlements')::int = 1,
                     '9 owner summary: ' || v_j::text);
  perform pg_temp.as_user(v_ten2);
  perform pg_temp.ok((select count(*) from public.rent_payments) = 1, '9 a tenant sees only their own payment');
  perform pg_temp.ok((select count(*) from public.payment_webhook_events) = 0, '9 tenants never see webhook events');

  perform pg_temp.as_postgres();
  raise notice 'ALL CASHFREE TESTS PASSED';
end
$test$;

rollback;

-- ============================================================================
--  db/migrations/2026-09-02-payment-refunds.sql
--  A refunded payment must stop counting as paid.
--
--  Apply AFTER db/migrations/2026-08-24-payments.sql. Idempotent — safe to re-run.
--  Adds one enum, one table and two functions. Changes NO existing column and NO
--  existing function.
--
--  ═══ THE PROBLEM ═══
--  Both webhook implementations answered every event that was not payment.captured
--  or payment.failed with 200 {"outcome":"ignored"}. A refund issued from the
--  Razorpay dashboard therefore left the resident marked `paid` in fee_payments
--  forever: the hostel's books said the rent was collected, the bank said
--  otherwise, and nobody was told. That is finding F3 in
--  docs/razorpay-money-path.md.
--
--  ═══ WHICH EVENT IS AUTHORITATIVE ═══
--  Razorpay emits refund.created, refund.processed and refund.failed for the same
--  refund, in that order but NOT reliably in that order on the wire.
--
--    refund.created    an INTENTION. The refund exists as an instruction; the
--                      money has not left. It can still fail — an instant refund
--                      to a closed card falls back or fails outright. Reversing a
--                      ledger here reverses it for money that may never move.
--    refund.processed  THE MONEY HAS LEFT. This, and only this, moves fee_payments.
--    refund.failed     the instruction died. The ledger was never moved, so there
--                      is nothing to undo.
--
--  So `pending` is recorded and `processed` is reversed, and the two are different
--  columns' worth of truth on the same row rather than the same thing.
--
--  ═══ WHY A TABLE AND NOT A COLUMN ═══
--  A partial refund is the NORMAL case: a resident who overpaid ₹500 on a ₹5,000
--  rent gets ₹500 back, not ₹5,000. So a refund is an AMOUNT, not a flag, and one
--  captured payment can carry SEVERAL of them (₹500 this week, ₹200 next). A
--  nullable `refunded_amount_paise` column on payment_intents cannot hold two
--  refunds, and a running total column cannot be made idempotent — replaying a
--  webhook would add the same amount again.
--
--  A child row per refund, with a UNIQUE INDEX on razorpay_refund_id, is what
--  makes "the same refund reverses the ledger exactly once" a property of the
--  DATABASE rather than of a code path that could be edited away. It is the same
--  device payment_intents_payment_key already uses for captures, for the same
--  reason.
--
--  ═══ THE REVERSAL IS A NEW FACT, NOT AN ERASURE ═══
--  fee_payments.amount_paid goes DOWN by the refunded amount and the existing
--  BEFORE trigger app.fee_status_compute recomputes `status`. Nothing sets status
--  by hand. The fee row is never deleted, `paid_on` and `mode` are left alone, and
--  a line is appended to `notes` — the resident really did pay on that day by that
--  method, and was then refunded. Both halves stay visible. Retention deliberately
--  never touches fee_payments (db/migrations/2026-09-02-retention-and-erasure.sql),
--  and this does not change that.
--
--  ═══ WHO MAY WRITE ═══
--  Nobody, through PostgREST. payment_refunds carries RLS with a SELECT policy only
--  plus an explicit REVOKE, exactly like payment_intents. Both functions below are
--  service_role and re-check app.is_service_role() in their own body, so a future
--  GRANT cannot quietly open them.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TYPE
--
-- Mirrors Razorpay's own refund lifecycle. 'pending' is their `created`, renamed
-- because `created` next to a created_at column reads as a timestamp, not a state.
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
  create type public.payment_refund_status as enum ('pending', 'processed', 'failed');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. TABLE
--
-- hostel_id / student_id / period_month are copied from the intent rather than
-- joined at read time: they are what the RLS policy and the tenant trigger need,
-- and a refund must stay attributable even if the intent row is ever archived.
--
-- amount_paise is RAZORPAY'S figure here, unlike payment_intents.amount_paise
-- which is the server's. It has to be — the server did not decide this amount, the
-- owner did, in the Razorpay dashboard. What protects it instead is the ceiling:
-- the total of a payment's refunds may never exceed what was captured, checked in
-- rz_record_refund under a row lock on the intent.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.payment_refunds (
  id                  uuid primary key default gen_random_uuid(),
  intent_id           uuid not null references public.payment_intents(id) on delete cascade,
  hostel_id           uuid not null references public.hostels(id) on delete cascade,
  student_id          uuid not null references public.students(id) on delete cascade,
  period_month        text not null check (period_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  -- `rfnd_` + base62, same shape discipline as the order and payment ids.
  razorpay_refund_id  text not null check (length(razorpay_refund_id) between 6 and 80),
  razorpay_payment_id text not null check (length(razorpay_payment_id) between 6 and 80),
  amount_paise        bigint not null check (amount_paise > 0 and amount_paise <= 1000000000),
  currency            text not null default 'INR' check (currency = 'INR'),
  status              public.payment_refund_status not null default 'pending',
  -- Razorpay's 'normal' | 'optimum' | 'instant'. Display only, never a predicate.
  speed               text,
  failure_reason      text,
  processed_at        timestamptz,
  -- The moment fee_payments actually moved. NULL means the money has left Razorpay
  -- but the ledger has not been reduced yet — the reconciliation queue below.
  reversed_at         timestamptz,
  -- What was subtracted, in rupees. Kept so the trail can be read without redoing
  -- the paise arithmetic, and so a later partial correction is explicable.
  reversed_amount     numeric(10,2),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ── THE IDEMPOTENCY CONSTRAINT ──────────────────────────────────────────────
-- Razorpay retries a webhook until it gets a 2xx and may deliver the same event
-- more than once regardless. One row per refund id, enforced by the database.
create unique index if not exists payment_refunds_refund_key
  on public.payment_refunds (razorpay_refund_id);

create index if not exists payment_refunds_intent_idx
  on public.payment_refunds (intent_id);
create index if not exists payment_refunds_payment_idx
  on public.payment_refunds (razorpay_payment_id);
create index if not exists payment_refunds_student_idx
  on public.payment_refunds (student_id, created_at desc);
create index if not exists payment_refunds_hostel_idx
  on public.payment_refunds (hostel_id, created_at desc);
-- The reconciliation queue: money that has LEFT the merchant account and has not
-- come off the fee ledger. Should always be empty. Same shape as
-- payment_intents_unreconciled_idx.
create index if not exists payment_refunds_unreversed_idx
  on public.payment_refunds (created_at)
  where status = 'processed' and reversed_at is null;

drop trigger if exists set_updated_at on public.payment_refunds;
create trigger set_updated_at before update on public.payment_refunds
  for each row execute function app.set_updated_at();

-- Cross-tenant integrity, the same guard fee_payments and payment_intents carry.
drop trigger if exists payment_refunds_student_tenant on public.payment_refunds;
create trigger payment_refunds_student_tenant
  before insert or update of student_id, hostel_id on public.payment_refunds
  for each row execute function app.assert_student_in_hostel();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS — read-only for humans, no write path at all through PostgREST
--
-- Byte-for-byte the payment_intents policy. The resident sees their own refunds
-- because "was I actually given my money back" is their question; the warden and
-- owner see their hostel's because they are the people who reconcile it.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.payment_refunds enable row level security;

drop policy if exists payment_refunds_select on public.payment_refunds;
create policy payment_refunds_select on public.payment_refunds for select
  using (
    student_id = app.current_student_id()
    or app.has_role_in(hostel_id, 'warden', 'owner')
  );

revoke insert, update, delete on public.payment_refunds from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. rz_record_refund — write down that a refund exists. EXACTLY ONCE per refund.
--
-- Does NOT touch fee_payments. Recording and reversing are split for the same
-- reason rz_record_capture and rz_credit_fee are split: the ledger move can
-- legitimately be refused (§4.4, hostel not writable), and if that refusal rolled
-- back the record that Razorpay gave the money away, the app would forget a real
-- refund because a subscription lapsed. Split, the refund stays recorded and only
-- the reversal is outstanding — a reconcilable state rather than a lost one.
--
-- p_status is derived by the caller from the EVENT NAME, not from the entity body:
-- the event name is what Razorpay is asserting on this delivery.
--
-- STATUS ONLY EVER MOVES FORWARD. Deliveries arrive out of order — refund.processed
-- routinely lands before refund.created — so:
--   'processed' always wins and is terminal.
--   'failed' applies only to a row that is still 'pending'.
--   'pending' never overwrites anything.
-- A 'failed' arriving for a refund already processed is a CONFLICT, not an
-- instruction to put the money back: it is returned as such so the webhook can put
-- it in front of a human instead of silently re-crediting rent.
--
-- Returns { outcome: 'recorded' | 'advanced' | 'duplicate' | 'conflict', … }
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_record_refund(
  p_payment_id   text,
  p_refund_id    text,
  p_amount_paise bigint,
  p_status       text default 'processed',
  p_reason       text default null,
  p_speed        text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_intent    public.payment_intents;
  v_row       public.payment_refunds;
  v_status    public.payment_refund_status;
  v_other     bigint;
  v_outcome   text;
begin
  -- Defense in depth: the GRANTs below already limit this to service_role. If one
  -- is ever widened, this still refuses. Mirrors public.audit_event().
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_payment_id is null or p_refund_id is null or p_amount_paise is null then
    raise exception 'Incomplete refund.' using errcode = 'P0001';
  end if;
  if p_status is null or p_status not in ('pending', 'processed', 'failed') then
    raise exception 'Unknown refund state.' using errcode = 'P0001';
  end if;
  v_status := p_status::public.payment_refund_status;
  if p_amount_paise <= 0 then
    raise exception 'Refund amount must be greater than zero.' using errcode = 'P0001';
  end if;

  -- ── The payment being refunded must be one of ours, and must have been captured.
  -- `for update` serialises two refunds on the same payment, which is what makes
  -- the ceiling check below race-free rather than merely usually-right.
  select * into v_intent from public.payment_intents
   where razorpay_payment_id = p_payment_id
   for update;
  if not found then
    -- Signature verified, so this really is our Razorpay account — but no payment
    -- of ours matches. Never invent a row to hang a refund on.
    raise exception 'Unknown Razorpay payment.' using errcode = 'P0001';
  end if;
  if v_intent.status <> 'captured' or v_intent.captured_at is null then
    -- Refunding something we never recorded as captured. Razorpay cannot actually
    -- do this, so if it happens our record of the capture is missing, not theirs.
    raise exception 'Refund for a payment that was never captured.' using errcode = 'P0001';
  end if;

  -- ── THE CEILING. A payment cannot be refunded for more than it took.
  -- Counts every OTHER refund on this payment that is pending or processed; a
  -- failed one has released its claim on the money and does not count.
  select coalesce(sum(r.amount_paise), 0) into v_other
    from public.payment_refunds r
   where r.intent_id = v_intent.id
     and r.razorpay_refund_id is distinct from p_refund_id
     and r.status in ('pending', 'processed');

  if v_status <> 'failed' and v_other + p_amount_paise > v_intent.amount_paise then
    raise exception 'Refunds exceed the captured amount.' using errcode = 'P0001';
  end if;

  -- ── Claim the refund id. The unique index is what decides the winner if two
  -- deliveries arrive at once; `do nothing` turns the loser into a re-select
  -- rather than an error.
  insert into public.payment_refunds (
    intent_id, hostel_id, student_id, period_month,
    razorpay_refund_id, razorpay_payment_id, amount_paise,
    status, speed, failure_reason,
    processed_at
  ) values (
    v_intent.id, v_intent.hostel_id, v_intent.student_id, v_intent.period_month,
    p_refund_id, p_payment_id, p_amount_paise,
    v_status, left(p_speed, 20), left(p_reason, 200),
    case when v_status = 'processed' then now() else null end
  )
  on conflict (razorpay_refund_id) do nothing
  returning * into v_row;

  if found then
    v_outcome := 'recorded';
  else
    select * into v_row from public.payment_refunds where razorpay_refund_id = p_refund_id;

    -- The amount must not change under us. Razorpay does not mutate a refund's
    -- amount, so a disagreement means this is not the refund we recorded.
    if v_row.amount_paise is distinct from p_amount_paise then
      raise exception 'Refund amount does not match the recorded refund.' using errcode = 'P0001';
    end if;

    if v_row.status = v_status then
      v_outcome := 'duplicate';
    elsif v_status = 'processed' then
      -- created → processed. The money moved. Terminal.
      update public.payment_refunds
         set status = 'processed', processed_at = coalesce(processed_at, now()), failure_reason = null
       where id = v_row.id
      returning * into v_row;
      v_outcome := 'advanced';
    elsif v_status = 'failed' and v_row.status = 'pending' then
      update public.payment_refunds
         set status = 'failed', failure_reason = left(coalesce(p_reason, 'Refund failed'), 200)
       where id = v_row.id
      returning * into v_row;
      v_outcome := 'advanced';
    else
      -- 'pending' arriving after 'processed'/'failed' (ordinary out-of-order
      -- delivery — harmless), or 'failed' arriving after 'processed' (a real
      -- contradiction that must reach a person).
      v_outcome := case when v_status = 'pending' then 'duplicate' else 'conflict' end;
    end if;
  end if;

  return jsonb_build_object(
    'outcome',         v_outcome,
    'refund_row_id',   v_row.id,
    'intent_id',       v_row.intent_id,
    'hostel_id',       v_row.hostel_id,
    'student_id',      v_row.student_id,
    'period_month',    v_row.period_month,
    'amount_paise',    v_row.amount_paise,
    'status',          v_row.status,
    'already_reversed', v_row.reversed_at is not null
  );
end $$;

revoke all on function public.rz_record_refund(text, text, bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.rz_record_refund(text, text, bigint, text, text, text) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. rz_reverse_fee — take the refunded money back off the fee ledger.
--
-- A SECOND transaction, called after rz_record_refund() has committed. See the
-- note above and rz_credit_fee's header for why the split exists.
--
-- WHY THIS DOES NOT GO THROUGH wd_correct_payment(), when the credit goes through
-- wd_record_payment(). Three reasons, and none of them is convenience:
--   • wd_correct_payment SETS a month's total to a figure the caller names. Here
--     the truth is a DELTA — "₹500 came back" — and computing `new total = old −
--     500` in the function and then posting it as an absolute would lose to any
--     concurrent desk payment between the read and the write. The subtraction
--     below happens inside the UPDATE, under the row lock, so it cannot.
--   • It writes a `warden.fee.corrected` audit row. No warden corrected anything;
--     mislabelling the one edit an owner will need explained is worse than having
--     no label.
--   • At a total of zero it nulls paid_on and mode. That is right for "this was
--     recorded against the wrong resident" and wrong for a refund: the resident
--     DID pay, on that day, by that method, and was then refunded. Both facts stay.
--
-- WHAT IT WILL NOT DO
--   • It will not set `status`. The BEFORE trigger app.fee_status_compute owns that
--     column and recomputes paid/partial/unpaid from the new amount_paid.
--   • It will not delete the fee row. Fee history is permanent.
--   • It will not let amount_paid go negative, and it will not CLAMP it to zero
--     either — a clamp would silently absorb a real disagreement. `amount_paid >=
--     v_amount` is a predicate on the UPDATE, so the row simply is not matched and
--     the raise below says which of the two possible reasons it was.
--   • It will not reverse a capture that was never credited: if the ledger never
--     went up, there is nothing to take down. That returns 'not_credited' and stays
--     in the queue rather than inventing a debit.
--
-- Returns { outcome: 'reversed' | 'already_reversed' | 'not_processed' | 'not_credited', … }
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_reverse_fee(p_refund_row_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row      public.payment_refunds;
  v_intent   public.payment_intents;
  v_fee      public.fee_payments;
  v_existing public.fee_payments;
  v_amount   numeric(10,2);
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  select * into v_row from public.payment_refunds where id = p_refund_row_id;
  if not found then
    raise exception 'Unknown refund.' using errcode = 'P0001';
  end if;

  -- The credit has to have happened before it can be undone. Checked before the
  -- claim below so a replay gets this same answer instead of burning the claim.
  select * into v_intent from public.payment_intents where id = v_row.intent_id;
  if v_intent.credited_at is null then
    return jsonb_build_object(
      'outcome', 'not_credited', 'refund_row_id', v_row.id, 'intent_id', v_row.intent_id
    );
  end if;

  -- ── THE CLAIM. Identical in kind to rz_credit_fee's: a predicate a second
  -- caller cannot satisfy once the first has committed. This, not an if-statement,
  -- is what makes a replayed refund.processed reverse the ledger zero more times.
  update public.payment_refunds r
     set reversed_at = now()
   where r.id          = p_refund_row_id
     and r.status      = 'processed'
     and r.reversed_at is null
  returning r.* into v_row;

  if not found then
    select * into v_row from public.payment_refunds where id = p_refund_row_id;
    return jsonb_build_object(
      'outcome', case when v_row.reversed_at is not null then 'already_reversed' else 'not_processed' end,
      'refund_row_id',  v_row.id,
      'intent_id',      v_row.intent_id,
      'student_id',     v_row.student_id,
      'period_month',   v_row.period_month,
      'reversed_amount', v_row.reversed_amount
    );
  end if;

  v_amount := round(v_row.amount_paise::numeric / 100, 2);

  -- ── THE REVERSAL. amount_paid goes down; app.fee_status_compute recomputes
  -- status on the way through. paid_on and mode are deliberately untouched.
  update public.fee_payments f
     set amount_paid = f.amount_paid - v_amount,
         notes = left(
           coalesce(f.notes || chr(10), '')
             || format('Refunded %s · Razorpay %s', to_char(v_amount, 'FM999999990.00'), v_row.razorpay_refund_id),
           2000)
   where f.student_id   = v_row.student_id
     and f.period_month = v_row.period_month
     -- Never negative. Not clamped either — an unmatched row is a question, not a
     -- rounding problem, and the raise below asks it out loud.
     and f.amount_paid >= v_amount
  returning f.* into v_fee;

  if not found then
    select * into v_existing from public.fee_payments
     where student_id = v_row.student_id and period_month = v_row.period_month;
    if not found then
      -- Raising rolls back the reversed_at claim above, so the refund stays in the
      -- reconciliation queue and a later delivery can try again.
      raise exception 'No fee record for % to reverse.', v_row.period_month using errcode = 'P0001';
    end if;
    raise exception 'Refund of % exceeds the % recorded for %.',
      v_amount, v_existing.amount_paid, v_row.period_month using errcode = 'P0001';
  end if;

  update public.payment_refunds set reversed_amount = v_amount where id = v_row.id;

  return jsonb_build_object(
    'outcome',       'reversed',
    'refund_row_id', v_row.id,
    'intent_id',     v_row.intent_id,
    'student_id',    v_row.student_id,
    'hostel_id',     v_row.hostel_id,
    'period_month',  v_row.period_month,
    'amount',        v_amount,
    'fee_status',    v_fee.status,
    'amount_paid',   v_fee.amount_paid,
    'amount_due',    v_fee.amount_due
  );
end $$;

revoke all on function public.rz_reverse_fee(uuid) from public, anon, authenticated;
grant execute on function public.rz_reverse_fee(uuid) to service_role;

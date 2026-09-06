-- ─────────────────────────────────────────────────────────────────────────────
-- RENT BELONGS TO THE PG OWNER, NOT TO THE PLATFORM
--
-- NIVORA is sold as a service to people who run PGs. A resident paying rent is paying THEIR
-- hostel's owner; the platform is only carrying the message. Until now the code did not know
-- that: `razorpay-order` created an order against one platform-wide RAZORPAY_KEY_ID with no
-- `transfers`, so every rupee from every resident of every hostel settled into the platform's
-- own Razorpay account and stayed there. There was no field anywhere in this schema — no
-- bank account, no IFSC, no linked account id — capable of saying where it should have gone.
--
-- Razorpay's answer to this shape is Route: each PG owner becomes a LINKED ACCOUNT under the
-- platform account, and a payment names the linked account it belongs to, so Razorpay settles
-- to the owner's own bank rather than to ours. This migration is the database half of that.
--
-- ── THE GUARD IS THE POINT OF THIS FILE ──────────────────────────────────────────────────────
--
-- Adding a column is the easy part. The change that matters is that rz_open_intent now REFUSES
-- to open a payment for a hostel with no linked account. That refusal is deliberately a hard
-- one, and it is worth being clear about why, because it makes the product less capable today:
--
--   Money that arrives with nowhere to go is worse than money that never arrives. A resident
--   who cannot pay online is inconvenienced and pays their warden in cash — a path this product
--   already supports. A resident whose ₹6,500 settles into a platform account that has no
--   lawful mechanism to release it has handed their rent to a stranger, and the hostel owner
--   they actually owe is still owed it. The second failure is not recoverable by trying again.
--
-- So the gate closes now, before real volume, rather than after. Today's exposure is one ₹1 test
-- payment and five residents; that is the cheapest this fix will ever be.
--
-- ── WHAT THIS DOES NOT DO ────────────────────────────────────────────────────────────────────
--
-- It does not create linked accounts. Those need each owner's own KYC — PAN, bank account,
-- business type — submitted to Razorpay, which is an out-of-band process with a human decision
-- at the end of it. This stores the RESULT of that process and refuses to move money until it
-- has one.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.hostels
  add column if not exists razorpay_account_id text,
  add column if not exists razorpay_account_linked_at timestamptz;

-- Razorpay linked account ids are `acc_` followed by an alphanumeric id. Constraining the shape
-- means a typo or a pasted order id is refused here rather than becoming a failed transfer at
-- the moment a resident is trying to pay.
alter table public.hostels drop constraint if exists hostels_razorpay_account_id_shape;
alter table public.hostels
  add constraint hostels_razorpay_account_id_shape
  check (razorpay_account_id is null or razorpay_account_id ~ '^acc_[A-Za-z0-9]{6,30}$');

comment on column public.hostels.razorpay_account_id is
  'The Razorpay Route LINKED ACCOUNT this hostel''s rent settles into — the owner''s account, '
  'not the platform''s. NULL means the owner has not completed Razorpay onboarding, and '
  'rz_open_intent refuses online payment for the hostel until it is set. See '
  'db/migrations/2026-09-06-route-linked-accounts.sql.';

comment on column public.hostels.razorpay_account_linked_at is
  'When the linked account was recorded. Kept for the audit trail: it is the moment this '
  'hostel became able to take money, and the first thing to look at if a settlement is disputed.';

-- ── ONLY A SUPER ADMIN MAY SET IT ────────────────────────────────────────────────────────────
--
-- Not the owner, and this is the important half. The linked account id decides WHERE THE MONEY
-- GOES; an owner who could write it could point another owner's rent at their own account. It
-- is set by the platform after Razorpay confirms the onboarding, which is also the only moment
-- anybody actually knows the value.
create or replace function public.sa_set_hostel_payout_account(
  p_hostel_id uuid,
  p_account_id text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  if not app.is_super_admin() then
    raise exception 'Only the platform can set where a hostel''s rent settles.'
      using errcode = 'P0001';
  end if;

  if p_account_id is not null and p_account_id !~ '^acc_[A-Za-z0-9]{6,30}$' then
    raise exception 'That does not look like a Razorpay linked account id (acc_...).'
      using errcode = 'P0001';
  end if;

  update public.hostels
     set razorpay_account_id = p_account_id,
         razorpay_account_linked_at = case when p_account_id is null then null else now() end,
         updated_at = now()
   where id = p_hostel_id
   returning name into v_name;

  if v_name is null then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;

  -- public.audit_event, not app.audit — the latter does not exist. Where a hostel's money
  -- settles is exactly the kind of change the audit trail is for, so the hostel is the target
  -- and the account id goes in the meta.
  perform public.audit_event(
    'hostel.payout_account.set',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('account_id', p_account_id),
    null, null, null, null
  );

  return jsonb_build_object('hostel_id', p_hostel_id, 'name', v_name, 'account_id', p_account_id);
end $$;

revoke all on function public.sa_set_hostel_payout_account(uuid, text) from public;
grant execute on function public.sa_set_hostel_payout_account(uuid, text) to authenticated;

-- ═══ AFTER APPLYING ═══
--   select name, razorpay_account_id, razorpay_account_linked_at from public.hostels order by name;
-- Every hostel that should be able to take rent online needs a non-null account id.

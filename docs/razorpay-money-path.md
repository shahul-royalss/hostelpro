# The money path, audited adversarially

**Date:** 2026-09-02 · **Scope:** everything between a resident tapping *Pay* and
`public.fee_payments` moving · **Method:** read the code, then try to break it against the live
project `nimxvgzscbanhtvgnjll` and the live deployments.

This is not a description of the feature — [`payments.md`](./payments.md) and
[`razorpay-in-app.md`](./razorpay-in-app.md) do that. This is the record of eight attacks, what
each one actually returned, and the five things that still need a human.

**Headline: no way was found to take rent for free, to pay someone else's rent, to pay twice for
one bill, to be credited twice for one payment, or to read another hostel's money.** Every attack
below was refused, and refused by the database rather than by a comment. What is left is a short
list of operational gaps — one of which will silently stop the feature working, and one of which
is a landmine in an existing runbook.

---

## 1. "End-to-end encryption" is not what protects this money

The request was for the payment path to work "with end-to-end encryption". That phrase does not
describe anything a payment gateway does, and repeating it back would be pretending the system has
a property it does not have and does not need.

End-to-end encryption means a message is readable only by the two endpoints and not by the server
in the middle — what WhatsApp does. A rent payment is the opposite shape: the server *must* read
the amount, because the server is the thing that decides the amount. There is no version of this
where NIVORA holds a payment it cannot read.

Four real things protect this money. They are worth knowing by name, because they are what to
check when something looks wrong:

**1. TLS, in transit.** Every hop — phone to Supabase, browser to Vercel, either to Razorpay,
Razorpay back to the webhook — is HTTPS. Nobody on the café wi-fi, the ISP, or the hostel's router
can read or alter any of it. This is the part people mean when they say "encrypted", and it is
already true everywhere, with no work outstanding.

**2. Card details never touch NIVORA. This is the real reason the design is safe.** When the
resident types a card number, they are typing it into an iframe served by `checkout.razorpay.com`
— Razorpay's own document, on Razorpay's own origin. The browser's same-origin policy means our
JavaScript cannot read those fields, not by choice but by construction. The same is true of UPI
PINs and net-banking passwords. NIVORA never sees a card number, never stores one, never logs one,
and therefore cannot leak one. The database has no column for it. This is worth saying plainly to
anyone who asks whether the app is safe with their card: **the app never has your card.**

**3. An HMAC signature that only Razorpay and our server can compute.** The single moment that
matters is Razorpay telling us "this rent was paid". That message arrives at a URL with no login on
it, because Razorpay is not a user and never will be. What makes it trustworthy is that Razorpay
computes a SHA-256 HMAC over the exact bytes of the message using a shared secret, and the server
recomputes it and compares. Anyone can send us a message; only someone holding the secret can send
one that verifies. The secret lives in the server environment and nowhere else — not in the app,
not in the browser, not in the repository.

**4. Row-level security, scoping every row to its tenant.** Postgres itself, not application code,
decides which rows a request may see. A resident's session can read that resident's own payment
rows and nothing else; a warden's session can read their own hostel's and nothing else. This is
enforced below the application, so a bug in a query cannot widen it — verified live in §4 below.

To that add the property this feature was built around: **the amount is never a parameter.** The
client cannot name a price, a student, or a month. It asks "let me pay", and the server answers
with a figure it derived twice, independently, from that resident's own ledger.

---

## 2. Verdict table

| # | Attack | Verdict | Severity |
| --- | --- | --- | --- |
| 1 | Client dictates the amount | **Refused.** No amount parameter exists anywhere a client can reach | — |
| 2 | Forged client callback marks a bill paid | **No.** `POST /api/payments/verify` DOES exist (added after this audit was written — the earlier wording said it did not, which was true when measured and false by the time it shipped). It verifies HMAC-SHA256(`order_id\|payment_id`) with `timingSafeEqual` and **cannot settle a bill**: only the signed webhook and the warden's action write to the ledger. A forged call at worst produces a wrong screen for the forger. | — |
| 3 | Same `razorpay_payment_id` credits twice | **Refused** by a unique index and a claim predicate | — |
| 4 | Hostel A pays against, or reads, hostel B | **Refused** by RLS, by a tenant trigger, and by role checks | — |
| 5 | Signature compared in constant time; forged header refused | **Yes / refused**, in both implementations | — |
| 6 | Missing `RAZORPAY_WEBHOOK_SECRET` → fail open? | **Fails CLOSED.** Verified in code and in production | — |
| 7 | Secret reachable from a bundle, log, or error | **No.** Not in the client bundle, the APK, git history, or any error string | — |
| F1 | Vercel has no webhook secret — that route 503s every delivery | Action needed | **Medium** |
| F2 | A genuine capture against an *expired* intent is permanently rejected | Latent, in a runbook | **Medium** |
| F3 | Refunds and chargebacks are never reflected in the ledger | Action needed | **Medium** |
| F4 | `scripts/_qa-payments.mjs` reports all-pass without signing in | Action needed | **Medium** |
| F5 | Forged webhooks write an unbounded audit row each, unthrottled | Worth fixing | **Low** |
| F6 | A wrong-but-present webhook secret is indistinguishable from a right one | Owner must test | **Low** |
| F7 | `NEXT_PUBLIC_RAZORPAY_KEY_ID` is set and read by nothing | Setup trap | **Low** |
| F8 | Two orders in one month can both be paid | Informational | **Info** |

Nothing here is Critical or High. The two Mediums that need doing before a resident pays real money
are **F1** and **F3**.

---

## 3. Attack 1 — can a client dictate the amount?

Traced end to end, on both clients.

**Web.** `createRentOrder()` in `lib/actions/payments.ts` **takes no arguments at all.** There is no
field to tamper with. The student is the session, the period is the current month, and the amount is
`summariseFee()` over that student's own ledger read under their own RLS.

**Mobile.** `supabase/functions/razorpay-order/index.ts` never reads the request body. Confirmed
mechanically rather than by eye:

```
$ grep -n "req.json\|req.text\|req.body\|req.formData" supabase/functions/razorpay-order/index.ts
(the request body is never read)
```

I sent it a body designed to be believed, with an anon token:

```
$ curl -X POST .../functions/v1/razorpay-order -H "Authorization: Bearer <anon>" \
    -d '{"amount_paise":1,"student_id":"50d63aef-…","period_month":"2026-09"}'
HTTP 401
{"ok":false,"error":"Please sign in again."}
```

The anon key is a structurally valid project JWT, so it passes the platform's `verify_jwt`; it is
`auth.getUser()` that turns "a valid token" into "a specific person" and refuses. With no header at
all the gateway answers first: `{"code":"UNAUTHORIZED_NO_AUTH_HEADER"}`.

**And then the database disagrees on purpose.** `rz_open_intent()` recomputes the expected paise
from the same ledger, under the caller's own identity, and refuses to write the row if what it was
handed is not exactly that. Signed in as a real resident who owes ₹5,000, asking for a ₹1 order:

```sql
set local role authenticated;
set local request.jwt.claims = '{"sub":"d7ea9751-…","role":"authenticated"}';
select public.rz_open_intent('order_AUDITCHEAP1', 100);
-- ERROR:  P0001: Your balance changed while the payment was being set up. Please try again.
```

**And the webhook checks a third time.** Even a *signed* delivery claiming a smaller capture is
refused against the figure the server wrote at order time:

```
capture #4 (1 paise for a 5000 rupee order) RAISED  "Captured amount does not match the order."
```

Three independent derivations of one number, in three processes. To underpay you would have to
compromise all three.

---

## 4. Attack 2 — can a forged client callback mark a bill paid?

No, because there is nothing to forge *to*. Razorpay Checkout hands the browser a
`{razorpay_payment_id, razorpay_order_id, razorpay_signature}` triple on success. Most integrations
post that back to their own server and settle on it. **This one throws it away.** In
`components/payments/pay-rent-sheet.tsx` the success handler is:

```js
handler: () => {
  settled.current = true;
  if (!alive.current) return;
  setPhase("confirming");
  void poll(order.orderId);
},
```

It takes no argument. The type exists in `razorpay-checkout.ts` and is never consumed anywhere:

```
$ grep -rn "razorpay_signature" --include=*.ts --include=*.tsx --include=*.dart .
./components/payments/razorpay-checkout.ts:24:  razorpay_signature: string;
```

One line, a type declaration, no reader. The sheet then *polls a read* until the server says the
signed webhook has credited it. The browser is never believed.

Enumerating every writer to the fee ledger confirms there are exactly two:

```
$ grep -rn "wd_record_payment" lib/actions/*.ts app/api --include=*.ts
lib/actions/warden.ts:261   (the warden's desk — assertWritableContext("warden"))
app/api/webhooks/razorpay/route.ts:112  (a comment; the call is inside rz_credit_fee)
```

And a resident cannot borrow the warden's one. Signed in as a real student, calling it against
their own record:

```sql
select public.wd_record_payment('50d63aef-…','2026-09',5000.00,'upi',current_date,'audit');
-- ERROR:  42501: Not allowed.
-- CONTEXT:  PL/pgSQL function wd_record_payment(…) line 9 at RAISE
```

The settlement functions themselves are unreachable from any human session — checked against the
live ACLs, not the migration file:

| Function | `proacl` on the live database |
| --- | --- |
| `rz_open_intent` | `postgres=X`, **`authenticated=X`**, `service_role=X` |
| `rz_record_capture` | `postgres=X`, `service_role=X` |
| `rz_credit_fee` | `postgres=X`, `service_role=X` |
| `rz_mark_failed` | `postgres=X`, `service_role=X` |
| `rz_expire_stale_intents` | `postgres=X`, `service_role=X` |

Called as a signed-in resident anyway:

```
select public.rz_record_capture(…)  -- ERROR: 42501: permission denied for function rz_record_capture
select public.rz_credit_fee(…)      -- ERROR: 42501: permission denied for function rz_credit_fee
```

And the table has no write path through PostgREST at all. Live grants are
`SELECT` only for `anon` and `authenticated`; `INSERT/UPDATE/DELETE` belong to `service_role` and
`postgres`. Inserting a pre-captured row for oneself:

```
ERROR:  42501: permission denied for table payment_intents
HINT:   Grant the required privileges to the current role with: GRANT INSERT ON public.payment_intents TO authenticated;
```

---

## 5. Attack 3 — can one payment credit twice?

Run against the live database inside a transaction that was rolled back. Six calls, one order:

| Step | Result |
| --- | --- |
| capture #1 (genuine) | `{"outcome":"captured", …, "already_credited":false}` |
| capture #2 (replay, same payment id) | `{"outcome":"duplicate", …}` |
| capture #3 (a second payment id on the same order) | **RAISED** `Order already settled by a different payment.` |
| capture #4 (1 paise for a ₹5,000 order) | **RAISED** `Captured amount does not match the order.` |
| credit #1 | `{"outcome":"credited","amount":5000,"fee_status":"paid"}` |
| credit #2 (replay) | `{"outcome":"already_credited"}` |
| **ledger afterwards** | `{"amount_due":5000,"amount_paid":5000,"status":"paid"}` |

`amount_paid` is 5000, not 10000. The idempotency is not an `if` statement that could be edited
away — it is a unique partial index on `razorpay_payment_id` plus a claim predicate of
`razorpay_payment_id is null` re-evaluated under the row lock, so two concurrent deliveries
serialise and the loser updates zero rows.

A late `payment.failed` also cannot un-settle a capture that already landed:

```
A2 rz_mark_failed on a captured order  →  {"outcome":"ignored"}
A3 row afterwards  →  status "captured", failure_reason null, razorpay_payment_id "pay_AUDITFAIL01"
```

---

## 6. Attack 4 — cross-tenant

The live project has two hostels: *Xeyrion* (two residents) and *Kushi* (a warden and an owner, no
residents). A payment intent for a Xeyrion resident was inserted inside a transaction, read from
three different identities, and rolled back.

| Persona | Rows of that intent visible |
| --- | --- |
| Warden of **Kushi** (the other hostel) | **0** — and `sum(amount_paise) = 0` |
| The **other Xeyrion resident** (same hostel, different person) | **0** |
| Warden of **Xeyrion** (positive control) | **1** |

The positive control matters: it proves the 0s are RLS refusing, not the fixture failing.

Writing across the tenant boundary is refused twice over. The other hostel's warden calling the
desk function against a Xeyrion resident:

```
ERROR:  42501: Not allowed.   (app.has_role_in(v_hostel,'warden','owner') is false)
```

And a row that *mismatches* its own tenant cannot exist at all, even written as `postgres`:

```sql
insert into public.payment_intents (hostel_id, student_id, …)
values ('a117d24d-…' /* Kushi */, '50d63aef-…' /* a Xeyrion resident */, …);
-- ERROR:  42501: That student belongs to a different hostel.
-- CONTEXT:  PL/pgSQL function app.assert_student_in_hostel() line 10 at RAISE
```

Paying *against* another resident is not a permission question but a shape question:
`rz_open_intent()` takes no student parameter. It reads `app.current_student_id()` from
`auth.uid()`. There is no argument to point at somebody else.

---

## 7. Attacks 5 and 6 — the signature, and what happens with no secret

**This was the most important question in the job, and the answer is: it fails closed.** Verified
three ways.

### In code

Both implementations *throw* rather than return a verdict when the secret is absent —
`lib/razorpay.ts` raises `RazorpayNotConfiguredError`, `_shared/razorpay.ts` raises a plain `Error`
— and both route handlers refuse before reading the body at all (`isWebhookConfigured()` /
`webhookSecret()` → `503`). There is no code path on which an unverifiable delivery is treated as
genuine.

### In a new test

There was no test of the signature anywhere in the repository, which for the one function that is
the entire perimeter is a gap worth closing. Added: **`scripts/_qa-webhook-signature.mts`**, which
exercises *both* implementations against the same table of cases.

```
$ NODE_OPTIONS=--conditions=react-server npx tsx scripts/_qa-webhook-signature.mts
═══ WEBHOOK SIGNATURE: 53 passed, 0 FAILED ═══
```

It covers: secret absent / empty / whitespace-only → must throw; the genuine signature (lowercase,
uppercase, whitespace-padded) → true; one nibble flipped, missing header, empty header, non-hex,
63 chars, 65 chars, all-zeroes → false; **signed with the API key secret instead of the webhook
secret** → false; the amount edited from ₹5,000 to 1 paisa after signing → false; the order id
swapped after signing → false; a genuine signature for a different body replayed → false; and the
body re-serialised through `JSON.parse`/`stringify` → false, which is the concrete demonstration of
why the raw bytes must be the thing verified. It also pins the constant-time compare at the source:
`timingSafeEqual` in the Node copy, `crypto.subtle.verify` in the Edge copy, and no hex digest
rendered for a `===`.

### In production, with a forged header

Against the deployed Edge Function:

```
$ curl -X POST .../functions/v1/razorpay-webhook -H "x-razorpay-signature: deadbeef…deadbeef" -d '<a captured-payment body>'
HTTP 401  {"error":"Invalid signature."}
$ curl -X POST .../functions/v1/razorpay-webhook -d '<the same body, no signature header>'
HTTP 401  {"error":"Invalid signature."}
$ curl -X POST .../functions/v1/razorpay-webhook -H "x-razorpay-signature: not-a-signature" -d '…'
HTTP 401  {"error":"Invalid signature."}
$ curl .../functions/v1/razorpay-webhook          # GET
HTTP 405  {"error":"Method not allowed."}
```

Against the deployed Next.js route on Vercel:

```
$ curl -X POST https://hostelpro-three.vercel.app/api/webhooks/razorpay -H "x-razorpay-signature: deadbeef…" -d '…'
HTTP 503  {"error":"Webhook is not configured."}
```

Every rejection was recorded. `public.audit_log` shows the three 185-byte probes arriving as
`payment.webhook.rejected / bad_signature / source:"edge"` — so the trail the Super Admin security
console alerts on is genuinely being written.

### The state of the secret today — read this carefully

The two endpoints are in **different states**, and the audit log dates it:

- Up to `2026-09-02 08:27:26Z`, deliveries to the Edge Function were refused with
  `reason: "webhook_secret_missing"` — the 503 branch, no secret present.
- From `2026-09-02 08:40:55Z` onward, deliveries are refused with `reason: "bad_signature"` — which
  is only reachable when a secret *is* present.

So `RAZORPAY_WEBHOOK_SECRET` **was set as a Supabase Edge Function secret earlier today**, between
those two timestamps, by someone other than this audit. It is **not** set in `.env.local`, and the
Vercel deployment's 503 above proves it is not set there either.

That is not a contradiction to resolve — only one endpoint should be registered anyway — but it
decides which one. See F1.

---

## 8. Attack 7 — is the secret reachable from a bundle, a log, or an error?

No, on every check.

- **Repository, including build output.** Searching every tracked and untracked file for the
  literal `RAZORPAY_KEY_SECRET` value (24 characters), excluding `.env.local` and `node_modules`
  but *including* `.next/`, `dist/` and `public/`: no match.
- **Git history.** `git log --all -S"<secret>"` returns nothing. `.gitignore` covers `.env*`.
- **The repo's own scanner.** `npm run security:scan` →
  `no server secrets in client bundle (151 files scanned)`,
  `no .env value appears in tracked files (6 secrets compared)`,
  `no credentials in git history (2,15,434 diff lines scanned)`, and
  `RESULT: 0 blocker(s), 0 warning(s)`.
- **The APK.** `nivora_app/lib/core/config/env.dart` holds only the Supabase URL and anon key, and
  says so in a comment: the Razorpay key secret, the webhook secret and the service-role key are
  named as things that must never be there. There is no Razorpay key of any kind in the Flutter
  app — the key id was removed with the in-app checkout.
- **The type system.** `lib/razorpay.ts` imports `server-only`, so importing it from a client
  component is a build error rather than a leak. That is why the new test has to run with
  `--conditions=react-server`: the guard is real enough to get in the test's way.
- **Error strings.** The Razorpay Orders API error body is `console.error`'d server-side in
  `_shared/razorpay.ts` and never returned to the caller — the student gets
  `Razorpay refused the order (HTTP 502).` `errorMessage()` in `lib/permissions.ts` only passes
  through our own `P0001` messages and a narrow allowlist; anything else is logged and replaced
  with a generic line. The `Authorization: Basic` header is constructed inline at the call and is
  never part of a thrown object.

The one Razorpay value that *does* reach a browser is `RAZORPAY_KEY_ID` — publishable by design,
handed to the one student who is actually paying, at the moment they pay.

---

## 9. Findings that need action

### F1 — Vercel has no webhook secret, so that route refuses every delivery · Medium

`https://hostelpro-three.vercel.app/api/webhooks/razorpay` answers `503 Webhook is not configured.`
to everything, including a genuine Razorpay delivery. The Edge Function has a secret; the web route
does not.

This is fail-closed, so no money is at risk — but if the Vercel URL is the one registered on the
Razorpay dashboard, **every payment will be taken and no rent will ever be credited**, and the
symptom is identical to having no webhook at all.

**Fix:** register the Edge Function URL (see §11), which already has its secret. Or, if the web
route is preferred, set `RAZORPAY_WEBHOOK_SECRET` in the Vercel production environment first.
Do not register both — the unique index makes a double credit impossible, but every payment would
appear twice in `audit_log`, which is the one table people read when money is missing.

### F2 — a genuine capture against an *expired* intent is permanently rejected · Medium (latent)

`rz_record_capture()` claims a row with `status in ('created','failed')`. `'expired'` is not in that
list, and the diagnostic branch that follows compares a **null** payment id against the incoming
one, so it reports the wrong reason. Reproduced live:

```
B1 rz_expire_stale_intents()                       →  1 row expired
B2 a real capture against that expired intent      →  RAISED "Order already settled by a different payment."
```

There is no other payment. The webhook classifies that message as **permanent**, answers `200`, and
Razorpay never retries. The resident's money is with Razorpay, `fee_payments` never moves, and the
only trace is a `payment.reconcile.required` audit row.

**Today this cannot happen**, and that is the only reason it is not High: nothing runs
`rz_expire_stale_intents()`. The live `cron.job` table holds three jobs — `hostelpro-retention`,
`hostelpro-keepwarm`, `nivora-drain-storage-erasures` — and none of them call it, nor does
`app.apply_retention()`.

It becomes real the moment anyone follows the runbook. `payments.md` §7 "Housekeeping" says to run
`select public.rz_expire_stale_intents();`, and the migration header says to call it "from the same
place `app.apply_retention()` is called". Do either of those and any checkout older than a day
becomes uncreditable — which is exactly the payment most likely to arrive late (a UPI collect
request approved the next morning, a checkout tab left open overnight).

**Fix (for the agent who owns this code, not for this audit):** add `'expired'` to the claim
predicate in `rz_record_capture()` so a late genuine capture can still claim its order, and correct
the diagnostic so a null payment id reports "this order was never paid" rather than "settled by a
different payment". **Until that is done, do not schedule `rz_expire_stale_intents()`.**

### F3 — refunds and chargebacks never reach the ledger · Medium

The webhook handles exactly two events: `payment.captured` and `payment.failed`. Everything else is
answered `200 {"outcome":"ignored"}`. That means:

- A **refund** issued from the Razorpay dashboard leaves the resident marked `paid` in
  `fee_payments`. The hostel's books say the rent was collected; the bank says otherwise. Nobody is
  notified.
- A **chargeback / dispute** is likewise invisible.
- If the Razorpay account is **not set to auto-capture**, payments stop at `payment.authorized`,
  which this endpoint ignores. The resident is charged, the money is held, and nothing is ever
  credited — indistinguishable to them from a broken app.

**Fix:** two owner actions, both in §11 — confirm auto-capture is ON, and treat refunds as a manual
two-step (refund in Razorpay, then correct the ledger at the warden desk with
`wd_correct_payment`). Handling refund events properly is a feature, not a fix, and belongs in a
later pass.

### F4 — the existing payments QA script passes without ever signing in · Medium

`scripts/_qa-payments.mjs` is the repo's stated safety net for this feature. It signs in as
`9000000001@student.hostelpro.local` — a seed account that **does not exist in this project**; the
live residents are `8328533543` and `9177220441` in *Xeyrion*, and the hostels it names (*Sunrise*,
*Lakeview*) are gone. Its `must()` helper counts *any* error or throw as a PASS, so with no session
at all it still reports:

```
$ node scripts/_qa-payments.mjs
  PASS  rz_open_intent claiming they owe 1 paisa
          permission denied for function rz_open_intent
  …
═══ PAYMENTS: 10 passed, 0 FAILED ═══
```

Read the reason text: `permission denied for function rz_open_intent` is the **anon** role being
refused a grant. The assertion it claims to make — *a signed-in resident cannot talk the order
function into a discount* — is never made. Two more report `[threw]` because the student lookup
returned null and the arrow function died on `stu.hostel_id`.

A control that reports success without testing anything is worse than no control, because it is
quoted in sign-offs. The equivalent assertions *were* made in this audit with a real resident
identity (§3, §4) and all held — so the property is fine; the test is not.

**Fix:** point the script at real accounts, and make `must()` fail when there is no session and when
an error arrives for the wrong reason (an ACL denial is not proof that a business rule fired).

### F5 — a forged-webhook flood is an unthrottled database write · Low

Both rejection branches that matter — no secret configured, and bad signature — call
`audit_event()`, and the endpoint is unauthenticated by necessity. There is no rate limit on it. An
attacker with a loop writes one
`audit_log` row per request indefinitely: storage cost, and — worse — the `payment.webhook.rejected`
signal the security console alerts on gets buried under noise the attacker controls.

**Fix:** throttle the audit on the reject path (record the first N per minute plus a count), or put
the endpoint behind a WAF rule. Not urgent; the perimeter itself holds.

### F6 — a wrong secret looks exactly like a right one until real money moves · Low

From outside, "the secret is set to the value Razorpay uses" and "the secret is set to something
else entirely" both produce `401 Invalid signature.` The audit cannot tell them apart, and neither
can the owner, until a genuine delivery fails. The failure mode is the expensive one: money taken,
rent not credited.

**Fix:** one real ₹1 test payment after registering the webhook, and confirm the fee row moves. §11.

### F7 — `NEXT_PUBLIC_RAZORPAY_KEY_ID` is set and nothing reads it · Low

`.env.local` carries `NEXT_PUBLIC_RAZORPAY_KEY_ID`, and `docs/razorpay-demo-setup.md` §3 instructs
adding it to Vercel. No code reads it — `lib/razorpay.ts` reads `RAZORPAY_KEY_ID`, and its header
explains at length why the `NEXT_PUBLIC_` form is deliberately avoided. Following the demo doc
therefore produces a permanently dead Pay button while looking configured.

It is not a leak: the key id is publishable, and an unreferenced `NEXT_PUBLIC_` variable is not
inlined into a bundle at all. It is a setup trap, already flagged in `data-safety.md` §379 and
`play-submission-pack.md`, and repeated here because it sits on this feature's setup checklist.

**Fix:** correct `razorpay-demo-setup.md` §3 to say `RAZORPAY_KEY_ID`, and delete the
`NEXT_PUBLIC_` line from `.env.local`.

### F8 — two orders in one month can both be paid · Informational

The 15-minute reuse window prevents the common double-tap, and `rz_open_intent` caps a resident at
10 intents an hour, but nothing forbids two *distinct* open orders for the same period being paid.
A determined resident could be charged twice; `wd_record_payment` adds, so `amount_paid` would
exceed `amount_due` and the ledger would show the overpayment rather than hide it. Recoverable by a
manual refund. Not worth code today.

---

## 10. What this audit did to the live project

Everything destructive ran inside an explicit transaction that was rolled back. Verified afterwards:

```sql
select (select count(*) from public.payment_intents) as intents_after_audit,      -- 0
       (select count(*) from public.fee_payments
         where student_id='50d63aef-…' and period_month='2026-09') as fee_rows;   -- 0
```

The only durable trace is five `payment.webhook.rejected` rows in `audit_log` from the forged-header
probes — three against the Edge Function, two against Vercel. They are evidence, and they are meant
to be there.

---

## 11. Owner actions, in order

Everything below needs a person with the Razorpay dashboard login. None of it can be done from
code, and none of it should be guessed at.

**1. Confirm auto-capture is ON.** Razorpay Dashboard → Settings → Payment Configuration → *Auto
capture payments*. If this is off, payments stop at `authorized`, this app ignores them, and no rent
is ever credited. (F3.)

**2. Create the webhook — this is where the secret is minted.** Razorpay Dashboard → Settings →
Webhooks → *Add New Webhook*.

| Field | Value |
| --- | --- |
| Webhook URL | `https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-webhook` |
| Secret | a long random string **you** choose — this becomes `RAZORPAY_WEBHOOK_SECRET` |
| Active Events | `payment.captured` **and** `payment.failed`, nothing else |

Use the **Edge Function URL above**, not the Vercel one: the Edge environment already has a secret
and the Vercel one does not (F1). The secret is **not** the API key secret — reusing the key secret
makes every delivery fail its check, with a symptom identical to having no webhook at all.

**3. Make the secret the app holds match the one you just typed.** The Edge Function already has
*some* value set (see §7), and this audit cannot see whether it matches. Set it again from the
dashboard value, so the two are known to agree:

```
supabase secrets set RAZORPAY_WEBHOOK_SECRET='<the string you typed in step 2>' \
  --project-ref nimxvgzscbanhtvgnjll
```

Do **not** put it in `.env.local` or Vercel unless you are switching to the Vercel route, in which
case do the reverse and register that URL instead.

**4. Prove it end to end with one real ₹1 payment.** This is the only thing that distinguishes a
correct secret from a wrong one (F6). Pay as a test resident, then check:

```sql
select razorpay_order_id, razorpay_payment_id, status, credited_at
  from public.payment_intents order by created_at desc limit 1;
select amount_due, amount_paid, status from public.fee_payments
 where student_id = '<that resident>' and period_month = to_char(current_date,'YYYY-MM');
```

`credited_at` must be non-null and `amount_paid` must have moved. If `status = 'captured'` but
`credited_at` is null, the signature verified and the ledger step failed — see `payments.md` §7.

**5. Do not schedule `rz_expire_stale_intents()` until F2 is fixed**, and do not run it by hand from
`payments.md` §7 in the meantime.

**6. Know the refund procedure before you need it.** Refund in the Razorpay dashboard, then correct
the ledger at the warden desk (`wd_correct_payment`). The app will not do it for you, and nothing
will warn you that the two disagree. (F3.)

**7. Tidy the two setup traps** when convenient: remove `NEXT_PUBLIC_RAZORPAY_KEY_ID` from
`.env.local`, and fix `docs/razorpay-demo-setup.md` §3 to name `RAZORPAY_KEY_ID` (F7).

---

## 12. How to re-run this audit

```bash
# The signature perimeter, both implementations, no network needed.
NODE_OPTIONS=--conditions=react-server npx tsx scripts/_qa-webhook-signature.mts

# Secrets: bundle, git history, client components.
npm run security:scan

# A forged delivery must be refused by whichever endpoint is registered.
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-webhook \
  -H 'x-razorpay-signature: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' \
  -d '{"event":"payment.captured"}'
# 401 = secret present, forgery refused.  503 = no secret, everything refused.  200 = STOP.
```

The cross-tenant and idempotency checks in §4–§6 were run as SQL against the live database by
impersonating real identities inside a rolled-back transaction:

```sql
begin;
set local role authenticated;
set local request.jwt.claims = '{"sub":"<a real user id>","role":"authenticated"}';
--  … the attack …
rollback;
```

That harness is worth keeping: it is the only way to make an assertion *as a specific person*
rather than as `anon`, which is the flaw in `_qa-payments.mjs` (F4).

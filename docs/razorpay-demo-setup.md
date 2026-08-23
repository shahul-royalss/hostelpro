# Razorpay: a working end-to-end demo in about five minutes

Everything on our side is built and tested. The only thing missing is credentials, and those have
to come from a Razorpay account — I cannot create one for you, and you would not want me to: it is
a financial account in your name.

**Use Test mode.** It is not a lesser version of the demo — it is the same code, the same webhook,
the same database path, with test cards instead of real money. Nothing is charged, and no KYC,
business registration or bank account is required to get the keys.

---

## 1. Get the keys (2 minutes)

1. Sign up or sign in at <https://dashboard.razorpay.com>.
2. Flip the mode switch at the top to **Test Mode**. This matters — Live keys need KYC.
3. **Account & Settings → API Keys → Generate Test Key**.
4. You get `rzp_test_XXXXXXXX` (the key id) and a secret. **The secret is shown once.**

## 2. Create the webhook (2 minutes)

Razorpay has to be able to tell us the payment succeeded. Without this the student pays and the
fee ledger never updates.

1. **Account & Settings → Webhooks → Add New Webhook**.
2. URL: `https://hostelpro-three.vercel.app/api/webhooks/razorpay`
3. Secret: invent a long random string. This is *your* value, not one Razorpay gives you — it is
   what our server checks the signature against.
4. Active events: tick **`payment.captured`** and **`payment.failed`**.

## 3. Give the app the three values

Locally, in `.env.local`:

```
NEXT_PUBLIC_RAZORPAY_KEY_ID=rzp_test_XXXXXXXX
RAZORPAY_KEY_SECRET=<the secret from step 1>
RAZORPAY_WEBHOOK_SECRET=<the string you invented in step 2>
```

And on Vercel, so the deployed demo works:

```bash
npx vercel env add NEXT_PUBLIC_RAZORPAY_KEY_ID production
npx vercel env add RAZORPAY_KEY_SECRET production
npx vercel env add RAZORPAY_WEBHOOK_SECRET production
```

Then redeploy: `npx vercel --prod`.

Until all three are set the Pay button **fails closed** — no order is created, so the app can never
take money it cannot credit. That is deliberate.

## 4. Demo it

Sign in as a student who has rent outstanding, open the fees card, tap **Pay**. On Razorpay's
checkout use a test card:

| Field | Value |
|---|---|
| Card | `4111 1111 1111 1111` |
| Expiry | any future date |
| CVV | any 3 digits |
| OTP page | click **Success** |

Or pick UPI and use `success@razorpay`.

The receipt should roll out, and the student's fee status should flip to **Paid**.

---

## What is already proven, and what this step actually adds

Tested against the live database, in a transaction that rolled itself back:

| | |
|---|---|
| `rz_record_capture` on a real order | `captured` |
| `rz_credit_fee` | `credited` — fee_payments went `0.00 → 6000.00`, status `paid` |
| The same webhook delivered twice | second returns `duplicate`, **no double credit** |
| Webhook with no signature / a wrong secret / a body tampered after signing | all rejected `401` |
| Webhook with a correct signature | `200` |
| A student calling the credit functions directly | `permission denied` (10/10 attack cases) |

So the money path works. What the keys add is the one segment nobody can simulate: Razorpay's own
hosted checkout, and Razorpay actually calling our webhook over the internet.

## If the demo misbehaves

**Fee does not update after a successful payment.** The webhook is not arriving. Check
**Webhooks → the webhook → Recent Deliveries** in the Razorpay dashboard. A `401` there means
`RAZORPAY_WEBHOOK_SECRET` differs between Razorpay and Vercel. A timeout means the URL is wrong.

**"Payments are not configured".** One of the three variables is missing on the environment you
are using. Local `.env.local` and Vercel production are separate — setting one does not set the other.

**Checkout will not open.** Look for a CSP violation in the browser console. Razorpay's origins are
granted only under `/student` (deliberately — see `lib/security-headers.ts`), so the Pay button has
to be on a student route.

**Going live later:** swap in `rzp_live_` keys and add a second webhook pointing at the same URL
from Live mode. Live keys require KYC. Nothing in the code changes.

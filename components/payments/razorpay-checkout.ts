/**
 * Razorpay Checkout — loaded LAZILY, on the tap that starts a payment.
 *
 * checkout.js is a third-party script of roughly 100 kB that opens sockets and
 * runs telemetry the moment it evaluates. Putting it in the page — a <Script>
 * tag, a layout import, anything that runs at load — would tax every student on
 * every visit for a screen most of them are not opening today, and this app's
 * navigation budget was fought for (4.5s → 1.2s). So it is fetched from here,
 * once, when someone actually means to pay, and cached on `window` afterwards.
 *
 * CSP: the injected <script> carries no nonce and does not need one. Our bundle
 * runs under a nonce, 'strict-dynamic' propagates that trust to what it appends,
 * and lib/security-headers.ts additionally lists checkout.razorpay.com in
 * script-src for browsers that ignore 'strict-dynamic'.
 *
 * No secret is involved: `key` below is the publishable key id, and the ORDER —
 * created server-side for a server-computed amount — is what actually fixes the
 * price. Nothing a tampered client passes here can change what is charged.
 */

export interface RazorpayCheckoutSuccess {
  razorpay_payment_id: string;
  razorpay_order_id: string;
  razorpay_signature: string;
}

export interface RazorpayCheckoutOptions {
  key: string;
  order_id: string;
  /** display only — Razorpay charges the order's amount, not this one */
  amount: number;
  currency: string;
  name: string;
  description?: string;
  image?: string;
  prefill?: { name?: string; email?: string; contact?: string };
  notes?: Record<string, string>;
  theme?: { color?: string; backdrop_color?: string };
  retry?: { enabled: boolean };
  modal?: { ondismiss?: () => void; confirm_close?: boolean; escape?: boolean };
  handler?: (response: RazorpayCheckoutSuccess) => void;
}

export interface RazorpayCheckoutInstance {
  open(): void;
  close(): void;
  on(event: string, handler: (payload: unknown) => void): void;
}

type RazorpayCheckoutCtor = new (options: RazorpayCheckoutOptions) => RazorpayCheckoutInstance;

const CHECKOUT_SRC = "https://checkout.razorpay.com/v1/checkout.js";
const LOAD_TIMEOUT_MS = 20_000;

/** In-flight load, shared between concurrent callers. Cleared on failure so a retry can work. */
let inFlight: Promise<RazorpayCheckoutCtor> | null = null;

function fromWindow(): RazorpayCheckoutCtor | null {
  const w = window as unknown as { Razorpay?: RazorpayCheckoutCtor };
  return typeof w.Razorpay === "function" ? w.Razorpay : null;
}

export function loadRazorpayCheckout(): Promise<RazorpayCheckoutCtor> {
  if (typeof window === "undefined") {
    return Promise.reject(new Error("Checkout can only be opened in a browser."));
  }
  const already = fromWindow();
  if (already) return Promise.resolve(already);
  if (inFlight) return inFlight;

  inFlight = new Promise<RazorpayCheckoutCtor>((resolve, reject) => {
    const settle = (fn: () => void) => {
      window.clearTimeout(timer);
      fn();
    };

    // A blocked or throttled CDN must not leave the Pay button spinning forever.
    const timer = window.setTimeout(() => {
      inFlight = null;
      reject(new Error("The payment window took too long to load. Check your connection and try again."));
    }, LOAD_TIMEOUT_MS);

    const onReady = () => {
      const ctor = fromWindow();
      if (ctor) settle(() => resolve(ctor));
      else
        settle(() => {
          inFlight = null;
          reject(new Error("The payment window could not start. Please try again."));
        });
    };
    const onFail = () => {
      settle(() => {
        inFlight = null;
        reject(new Error("Couldn't reach the payment provider. Check your connection and try again."));
      });
    };

    // A previous attempt may have left the tag behind (timed out, then recovered).
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${CHECKOUT_SRC}"]`);
    if (existing) {
      existing.addEventListener("load", onReady, { once: true });
      existing.addEventListener("error", onFail, { once: true });
      // It may already have finished between the window check and this line.
      if (fromWindow()) onReady();
      return;
    }

    const script = document.createElement("script");
    script.src = CHECKOUT_SRC;
    script.async = true;
    script.crossOrigin = "anonymous";
    script.addEventListener("load", onReady, { once: true });
    script.addEventListener("error", onFail, { once: true });
    document.body.appendChild(script);
  });

  return inFlight;
}

/** Open the modal. Resolves with the instance so the caller can close it. */
export async function openRazorpayCheckout(options: RazorpayCheckoutOptions): Promise<RazorpayCheckoutInstance> {
  const Checkout = await loadRazorpayCheckout();
  const instance = new Checkout(options);
  instance.open();
  return instance;
}

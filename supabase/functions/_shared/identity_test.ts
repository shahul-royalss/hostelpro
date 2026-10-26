// deno test supabase/functions/_shared/identity_test.ts
// The pure helpers behind self sign-up. No network, no secrets.
import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { HttpError } from "./http.ts";
import {
  appSecretProof,
  displayName,
  indianMobile,
  isPkceVerifier,
  parsePersona,
  passwordProblem,
  personaRole,
  syntheticEmail,
} from "./identity.ts";
import { verifyCheckoutSignature } from "./razorpay.ts";

Deno.test("persona: allowlist only, absent means sign-in", () => {
  assertEquals(parsePersona(undefined), null);
  assertEquals(parsePersona(null), null);
  assertEquals(parsePersona(""), null);
  assertEquals(parsePersona("owner"), "owner");
  assertEquals(parsePersona("tenant"), "tenant");
  for (const bad of ["warden", "manager", "super_admin", "student", "OWNER", 1, {}]) {
    assertThrows(() => parsePersona(bad), HttpError);
  }
  assertEquals(personaRole("owner"), "owner");
  assertEquals(personaRole("tenant"), "student");
  assertEquals(parsePersona("staff"), "staff");
  assertEquals(personaRole("staff"), "staff");
});

Deno.test("synthetic addresses are non-routable and sanitised", () => {
  assertEquals(syntheticEmail("facebook", "1234567890"), "fb-1234567890@identity.apnivaas.invalid");
  assertEquals(syntheticEmail("truecaller", "AbC-1_x@y"), "tc-abc-1_xy@identity.apnivaas.invalid");
  assertThrows(() => syntheticEmail("truecaller", "@@@"), HttpError);
});

Deno.test("indian mobile normalisation", () => {
  assertEquals(indianMobile("+91 98765 43210"), "9876543210");
  assertEquals(indianMobile("919876543210"), "9876543210");
  assertEquals(indianMobile("09876543210"), "9876543210");
  assertEquals(indianMobile("5876543210"), null);
  assertEquals(indianMobile("+1 415 555 0100"), null);
  assertEquals(indianMobile(undefined), null);
});

Deno.test("display name falls back", () => {
  assertEquals(displayName("  Asha   Rao "), "Asha Rao");
  assertEquals(displayName("", "x", null, "Ravi"), "Ravi");
  assertEquals(displayName(undefined), "New member");
});

Deno.test("PKCE verifier shape", () => {
  assertEquals(isPkceVerifier("a".repeat(43)), true);
  assertEquals(isPkceVerifier("a".repeat(42)), false);
  assertEquals(isPkceVerifier("a".repeat(129)), false);
  assertEquals(isPkceVerifier("a".repeat(42) + "!"), false);
});

Deno.test("appsecret_proof is HMAC-SHA256(token, secret) hex", async () => {
  // RFC 4231 test case 2: key "Jefe", data "what do ya want for nothing?"
  assertEquals(
    await appSecretProof("what do ya want for nothing?", "Jefe"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("checkout signature: order_id|payment_id keyed with the secret", async () => {
  Deno.env.set("RAZORPAY_KEY_SECRET", "Jefe");
  const order = "order_ABCDEF123";
  const payment = "pay_ABCDEF123";
  const good = await appSecretProof(`${order}|${payment}`, "Jefe");
  assertEquals(await verifyCheckoutSignature(order, payment, good), true);
  assertEquals(await verifyCheckoutSignature(order, "pay_ZZZZZZ999", good), false);
  assertEquals(await verifyCheckoutSignature(order, payment, "not-hex"), false);
  assertEquals(await verifyCheckoutSignature(order, payment, undefined), false);
  Deno.env.delete("RAZORPAY_KEY_SECRET");
  await assertRejects(() => verifyCheckoutSignature(order, payment, good));
});

Deno.test("password sign-up rules mirror the app", () => {
  assertEquals(passwordProblem("Abcdef1!"), null);
  assertEquals(passwordProblem("Ab1!"), "Use at least 8 characters");
  assertEquals(passwordProblem("ABCDEFG1!"), "Include at least one letter");
  assertEquals(passwordProblem("Abcdefgh!"), "Include at least one number");
  assertEquals(passwordProblem("abcdefg1!"), "Include at least one capital letter");
  assertEquals(passwordProblem("Abcdefg12"), "Include at least one symbol, like ! or @");
  assertEquals(passwordProblem("A1!" + "a".repeat(200)), "That password is too long");
});

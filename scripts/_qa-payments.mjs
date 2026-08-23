// Can a student get free rent? Every way a client could try to credit themselves.
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";
const env = Object.fromEntries(fs.readFileSync(".env.local","utf8").split(/\r?\n/)
  .filter(l=>l && !l.startsWith('#') && l.includes('=')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i).trim(), l.slice(i+1).trim()];}));
const anon = () => createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth:{persistSession:false} });
const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth:{persistSession:false} });

let pass=0, fail=0;
const must = async (label, fn) => {
  try {
    const { data, error } = await fn();
    const rows = Array.isArray(data) ? data.length : data ? 1 : 0;
    if (error) { console.log(`  PASS  ${label}\n          ${String(error.message).slice(0,90)}`); pass++; }
    else if (rows === 0) { console.log(`  PASS  ${label}  [0 rows]`); pass++; }
    else { console.log(`  FAIL  ${label}  *** ${JSON.stringify(data).slice(0,140)}`); fail++; }
  } catch (e) { console.log(`  PASS  ${label}  [threw]`); pass++; }
};

const s = anon();
await s.auth.signInWithPassword({ email:"9000000001@student.hostelpro.local", password:"Student@12345" });
const { data: stu } = await admin.from("students").select("id,hostel_id,monthly_fee").eq("phone","9000000001").maybeSingle();

console.log("\n=== A student must not be able to credit their own rent ===");
await must("call rz_record_capture directly (the function that marks money received)",
  () => s.rpc("rz_record_capture", { p_order_id:"order_FAKE123456", p_payment_id:"pay_FAKE123456", p_amount_paise: 1 }));
await must("call rz_credit_fee directly (the function that writes the fee ledger)",
  () => s.rpc("rz_credit_fee", { p_intent_id: "00000000-0000-0000-0000-000000000000" }));
await must("call rz_mark_failed", () => s.rpc("rz_mark_failed", { p_order_id:"order_FAKE123456" }));
await must("call rz_expire_stale_intents", () => s.rpc("rz_expire_stale_intents", {}));

console.log("\n=== ...nor write the payment table directly through PostgREST ===");
await must("INSERT a captured intent for themselves",
  () => s.from("payment_intents").insert({ hostel_id: stu.hostel_id, student_id: stu.id, period_month:"2026-08",
        amount_paise: 100, razorpay_order_id:"order_SELF12345", razorpay_payment_id:"pay_SELF12345", status:"captured" }).select());
await must("UPDATE an intent to captured", () => s.from("payment_intents").update({ status:"captured" }).eq("period_month","2026-08").select());
await must("DELETE their intents", () => s.from("payment_intents").delete().eq("period_month","2026-08").select());

console.log("\n=== ...nor talk the order function into a discount ===");
await must("rz_open_intent claiming they owe 1 paisa",
  () => s.rpc("rz_open_intent", { p_order_id:"order_CHEAP12345", p_amount_paise: 1 }));
await must("rz_open_intent with a junk order id (column-stuffing)",
  () => s.rpc("rz_open_intent", { p_order_id:"'; drop table public.fee_payments; --", p_amount_paise: 100 }));

console.log("\n=== another hostel's student must not see these rows ===");
const o = anon();
await o.auth.signInWithPassword({ email:"9000000101@student.hostelpro.local", password:"Student@12345" });
await must("Lakeview student reads Sunrise payment_intents", () => o.from("payment_intents").select("*").eq("student_id", stu.id));

console.log(`\n═══ PAYMENTS: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail ? 1 : 0);

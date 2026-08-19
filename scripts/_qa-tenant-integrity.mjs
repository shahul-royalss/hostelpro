// Verify the cross-tenant / least-privilege fixes (IV-01..03, LMP-01, LMP-05, LMP-06).
import { createClient } from "@supabase/supabase-js";
import fs from "node:fs";

const env = Object.fromEntries(
  fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => l && !l.startsWith("#") && l.includes("="))
    .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim()]; }),
);
const URL = env.NEXT_PUBLIC_SUPABASE_URL, ANON = env.NEXT_PUBLIC_SUPABASE_ANON_KEY, SVC = env.SUPABASE_SERVICE_ROLE_KEY;
const admin = createClient(URL, SVC, { auth: { persistSession: false } });

async function login(email, password) {
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  const { data, error } = await c.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`login ${email}: ${error.message}`);
  return { c, uid: data.user.id };
}
let pass = 0, fail = 0;
async function mustFail(label, fn) {
  try {
    const { data, error } = await fn();
    const rows = Array.isArray(data) ? data.length : data ? 1 : 0;
    if (error) { console.log(`  PASS  ${label}\n          blocked: ${String(error.message).slice(0, 90)}`); pass++; }
    else if (rows === 0) { console.log(`  PASS  ${label}  [0 rows]`); pass++; }
    else { console.log(`  FAIL  ${label}  *** ${rows} row(s) ${JSON.stringify(data).slice(0, 160)}`); fail++; }
  } catch (e) { console.log(`  PASS  ${label}  [threw]`); pass++; }
}
async function expectRows(label, fn, expected) {
  const { data, error } = await fn();
  const n = Array.isArray(data) ? data.length : data ? 1 : 0;
  if (error) { console.log(`  FAIL  ${label}  *** error: ${error.message.slice(0, 80)}`); fail++; }
  else if (n === expected) { console.log(`  PASS  ${label}  [${n} rows]`); pass++; }
  else { console.log(`  FAIL  ${label}  *** got ${n}, expected ${expected}`); fail++; }
}

const ids = {};
{
  const { data: h } = await admin.from("hostels").select("id,name");
  ids.sunrise = h.find((x) => x.name === "Sunrise Residency").id;
  ids.lakeview = h.find((x) => x.name === "Lakeview PG").id;
  const { data: s } = await admin.from("students").select("id,user_id,phone,hostel_id,room_id");
  ids.stuSun = s.find((x) => x.hostel_id === ids.sunrise && x.phone === "9000000001");
  ids.stuLake = s.find((x) => x.hostel_id === ids.lakeview);
  const { data: u } = await admin.from("users").select("id,email,role,hostel_id");
  ids.wardenLake = u.find((x) => x.email === "warden2@demo.hostelpro.app");
  ids.mgrSun = u.find((x) => x.email === "manager@demo.hostelpro.app");
  ids.admin = u.find((x) => x.role === "super_admin");
}

console.log("\n=== IV-01  students.user_id must not be re-pointable (account takeover) ===");
{
  const { c } = await login("warden@demo.hostelpro.app", "Warden@12345");
  await mustFail("warden repoints student.user_id -> Lakeview warden",
    () => c.from("students").update({ user_id: ids.wardenLake.id }).eq("id", ids.stuSun.id).select());
  await mustFail("warden repoints student.user_id -> super admin",
    () => c.from("students").update({ user_id: ids.admin.id }).eq("id", ids.stuSun.id).select());
  await mustFail("warden inserts student linked to a foreign account",
    () => c.from("students").insert({ hostel_id: ids.sunrise, user_id: ids.wardenLake.id, full_name: "AUDIT X", phone: "9111100001", monthly_fee: 1 }).select());
}

console.log("\n=== IV-02  cross-tenant student_id on fee_payments / visitors ===");
{
  const { c } = await login("warden@demo.hostelpro.app", "Warden@12345");
  await mustFail("Sunrise warden inserts fee debt against a Lakeview student",
    () => c.from("fee_payments").insert({ hostel_id: ids.sunrise, student_id: ids.stuLake.id, period_month: "2026-08", amount_due: 99999, amount_paid: 0 }).select());
  await mustFail("Sunrise warden logs a visitor for a Lakeview student",
    () => c.from("visitors").insert({ hostel_id: ids.sunrise, student_id: ids.stuLake.id, visitor_name: "AUDIT V" }).select());
  await mustFail("Sunrise warden files a complaint for a Lakeview student",
    () => c.from("complaints").insert({ hostel_id: ids.sunrise, student_id: ids.stuLake.id, category: "other", title: "AUDIT C" }).select());
  await mustFail("Sunrise warden creates a leave for a Lakeview student",
    () => c.from("leaves").insert({ hostel_id: ids.sunrise, student_id: ids.stuLake.id, from_date: "2026-09-01", to_date: "2026-09-02" }).select());
}

console.log("\n=== IV-03  tasks.assigned_to must be this hostel's active manager ===");
{
  const { c, uid } = await login("owner@demo.hostelpro.app", "Owner@12345");
  await mustFail("owner assigns a task to the Lakeview warden",
    () => c.from("tasks").insert({ hostel_id: ids.sunrise, assigned_to: ids.wardenLake.id, title: "AUDIT T", created_by: uid }).select());
  await mustFail("owner assigns a task to a student",
    () => c.from("tasks").insert({ hostel_id: ids.sunrise, assigned_to: ids.stuSun.user_id, title: "AUDIT T", created_by: uid }).select());
  await mustFail("owner assigns a task to the super admin",
    () => c.from("tasks").insert({ hostel_id: ids.sunrise, assigned_to: ids.admin.id, title: "AUDIT T", created_by: uid }).select());
}

console.log("\n=== LMP-01  Manager must not see resident PII (spec 6.3) ===");
{
  const { c } = await login("manager@demo.hostelpro.app", "Manager@12345");
  await mustFail("manager reads students", () => c.from("students").select("full_name,guardian_phone,permanent_address"));
  await mustFail("manager reads leaves", () => c.from("leaves").select("*"));
  await mustFail("manager reads visitors", () => c.from("visitors").select("*"));
  await mustFail("manager reads complaints", () => c.from("complaints").select("*"));
  await mustFail("manager reads fee_payments", () => c.from("fee_payments").select("*"));
  await mustFail("manager reads rpc_fee_ledger", () => c.rpc("rpc_fee_ledger", { p_hostel_id: ids.sunrise, p_period_month: "2026-08" }));
  await mustFail("manager enumerates student accounts", () => c.from("users").select("id,email,phone").eq("role", "student"));
  await expectRows("manager still sees staff accounts (owner/manager/warden)", () => c.from("users").select("id,role"), 3);
  const { data: st } = await c.rpc("rpc_hostel_stats", { p_hostel_id: ids.sunrise }).maybeSingle();
  const okStats = st && Number(st.revenue_month) >= 0 && Number(st.expenses_month) >= 0;
  console.log(okStats ? `  PASS  manager dashboard stats still work [rev=${st.revenue_month} exp=${st.expenses_month}]` : "  FAIL  manager dashboard stats broken");
  okStats ? pass++ : fail++;
}

console.log("\n=== LMP-05/06  student surface (spec 4.8) ===");
{
  const { c } = await login("9000000001@student.hostelpro.local", "Student@12345");
  const { data: beds } = await c.from("beds").select("id,student_id");
  const own = beds?.length ?? 0;
  console.log(own > 0 && own <= 4 ? `  PASS  student sees only own room's beds [${own}]` : `  FAIL  student sees ${own} beds (expected own room only)`);
  own > 0 && own <= 4 ? pass++ : fail++;
  const { data: rm } = await c.rpc("st_my_roommates");
  const cols = rm?.[0] ? Object.keys(rm[0]) : [];
  const noPhoto = !cols.includes("photo_url");
  console.log(noPhoto ? `  PASS  roommates RPC returns only [${cols.join(", ")}]` : `  FAIL  roommates RPC still returns photo_url`);
  noPhoto ? pass++ : fail++;
  await expectRows("student still sees own student row", () => c.from("students").select("id"), 1);
}

console.log("\n=== wd_record_payment hardening ===");
{
  const { c } = await login("warden@demo.hostelpro.app", "Warden@12345");
  await mustFail("NaN amount", () => c.rpc("wd_record_payment", { p_student_id: ids.stuSun.id, p_period_month: "2026-08", p_amount: "NaN", p_mode: "cash", p_paid_on: "2026-08-17" }));
  await mustFail("absurd amount", () => c.rpc("wd_record_payment", { p_student_id: ids.stuSun.id, p_period_month: "2026-08", p_amount: 99999999, p_mode: "cash", p_paid_on: "2026-08-17" }));
  await mustFail("future-dated payment", () => c.rpc("wd_record_payment", { p_student_id: ids.stuSun.id, p_period_month: "2026-08", p_amount: 100, p_mode: "cash", p_paid_on: "2030-01-01" }));
}

// The RPC is only one door into the money columns — warden/owner can also INSERT and UPDATE
// fee_payments / expenses / revenues / students straight through PostgREST, bypassing every
// check inside wd_record_payment. Postgres numeric NaN passes `>= 0` (it sorts above every
// number), so a bare non-negative CHECK let a NaN in and poisoned every sum() downstream.
console.log("\n=== NUM-01  numeric NaN / overflow via direct PostgREST (no RPC) ===");
{
  const { c, uid } = await login("warden@demo.hostelpro.app", "Warden@12345");
  await mustFail("NaN into fee_payments.amount_paid",
    () => c.from("fee_payments").insert({ hostel_id: ids.sunrise, student_id: ids.stuSun.id, period_month: "2026-07", amount_due: 5000, amount_paid: "NaN" }).select());
  await mustFail("NaN into students.monthly_fee",
    () => c.from("students").update({ monthly_fee: "NaN" }).eq("id", ids.stuSun.id).select());
}
{
  // expenses are the manager's surface (spec 6.3), so the warden hits RLS before the CHECK
  const { c, uid } = await login("manager@demo.hostelpro.app", "Manager@12345");
  await mustFail("NaN into expenses.amount",
    () => c.from("expenses").insert({ hostel_id: ids.sunrise, category: "other", note: "AUDIT NaN", amount: "NaN", date: "2026-08-01", uploaded_by: uid }).select());
  await mustFail("absurd overflow into expenses.amount",
    () => c.from("expenses").insert({ hostel_id: ids.sunrise, category: "other", note: "AUDIT BIG", amount: 999999999, date: "2026-08-01", uploaded_by: uid }).select());
}

console.log("\n=== LEN-01  unbounded text via direct PostgREST ===");
{
  const { c } = await login("9000000001@student.hostelpro.local", "Student@12345");
  await mustFail("student files a complaint with a 200k-character title",
    () => c.from("complaints").insert({ hostel_id: ids.sunrise, student_id: ids.stuSun.id, category: "other", title: "A".repeat(200000) }).select());
  await mustFail("student files a complaint with a 200k-character description",
    () => c.from("complaints").insert({ hostel_id: ids.sunrise, student_id: ids.stuSun.id, category: "other", title: "AUDIT LEN", description: "A".repeat(200000) }).select());
  await mustFail("student requests leave with a 200k-character reason",
    () => c.from("leaves").insert({ hostel_id: ids.sunrise, student_id: ids.stuSun.id, from_date: "2026-09-01", to_date: "2026-09-02", reason: "A".repeat(200000) }).select());
}

console.log(`\n═══ RESULT: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail > 0 ? 1 : 0);

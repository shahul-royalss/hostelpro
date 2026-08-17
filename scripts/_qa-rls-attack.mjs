// Direct PostgREST attack suite — bypasses the Next.js app entirely.
// Signs in as real users with the anon key and attempts privilege escalation
// and cross-user / cross-tenant reads+writes. Every attempt MUST fail.
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
/** expect the operation to be BLOCKED (error, or zero rows affected/returned) */
async function mustFail(label, fn) {
  try {
    const { data, error } = await fn();
    const rows = Array.isArray(data) ? data.length : data ? 1 : 0;
    if (error) { console.log(`  PASS  ${label}  [blocked: ${error.code ?? ""} ${String(error.message).slice(0, 70)}]`); pass++; }
    else if (rows === 0) { console.log(`  PASS  ${label}  [no rows affected/visible]`); pass++; }
    else { console.log(`  FAIL  ${label}  *** ${rows} row(s): ${JSON.stringify(data).slice(0, 200)}`); fail++; }
  } catch (e) { console.log(`  PASS  ${label}  [threw: ${String(e.message).slice(0, 70)}]`); pass++; }
}
async function mustSucceed(label, fn) {
  const { data, error } = await fn();
  if (error) { console.log(`  FAIL  ${label}  *** unexpectedly blocked: ${error.message}`); fail++; }
  else { console.log(`  ok    ${label}  [${Array.isArray(data) ? data.length : 1} row(s)]`); pass++; }
}

const ids = {};
{
  const { data: h } = await admin.from("hostels").select("id,name");
  ids.sunrise = h.find((x) => x.name === "Sunrise Residency").id;
  ids.lakeview = h.find((x) => x.name === "Lakeview PG").id;
  const { data: s } = await admin.from("students").select("id,user_id,phone,hostel_id,bed_id,room_id");
  ids.stuA = s.find((x) => x.phone === "9000000001");
  ids.stuB = s.find((x) => x.phone === "9000000002");
  ids.stuLake = s.find((x) => x.hostel_id === ids.lakeview);
  const { data: u } = await admin.from("users").select("id,email,role");
  ids.admin = u.find((x) => x.role === "super_admin");
  ids.ownerSun = u.find((x) => x.email === "owner@demo.hostelpro.app");
  ids.mgr = u.find((x) => x.email === "manager@demo.hostelpro.app");
  ids.wardenLake = u.find((x) => x.email === "warden2@demo.hostelpro.app");
  const { data: c } = await admin.from("complaints").select("id,hostel_id,student_id").limit(50);
  ids.complaintSun = c.find((x) => x.hostel_id === ids.sunrise);
  const { data: l } = await admin.from("leaves").select("id,hostel_id,student_id,status");
  ids.leaveSun = l.find((x) => x.hostel_id === ids.sunrise);
  const { data: e } = await admin.from("expenses").select("id,hostel_id").limit(5);
  ids.expenseSun = e.find((x) => x.hostel_id === ids.sunrise);
  const { data: t } = await admin.from("tasks").select("id,hostel_id").limit(5);
  ids.taskSun = t.find((x) => x.hostel_id === ids.sunrise);
  const { data: b } = await admin.from("beds").select("id,hostel_id,student_id").eq("hostel_id", ids.lakeview).is("student_id", null).limit(1);
  ids.freeLakeBed = b?.[0];
}

console.log("\n═══ A. STUDENT self-escalation (own row) — all must fail ═══");
{
  const { c, uid } = await login("9000000001@student.hostelpro.local", "Student@12345");
  await mustFail("users.role → owner", () => c.from("users").update({ role: "owner" }).eq("id", uid).select());
  await mustFail("users.role → super_admin", () => c.from("users").update({ role: "super_admin" }).eq("id", uid).select());
  await mustFail("users.hostel_id → Lakeview", () => c.from("users").update({ hostel_id: ids.lakeview }).eq("id", uid).select());
  await mustFail("students.monthly_fee → 0", () => c.from("students").update({ monthly_fee: 0 }).eq("id", ids.stuA.id).select());
  await mustFail("students.hostel_id → Lakeview", () => c.from("students").update({ hostel_id: ids.lakeview }).eq("id", ids.stuA.id).select());
  await mustFail("students.status → vacated", () => c.from("students").update({ status: "vacated" }).eq("id", ids.stuA.id).select());
  await mustFail("fee_payments.amount_paid → 99999", () => c.from("fee_payments").update({ amount_paid: 99999 }).eq("student_id", ids.stuA.id).select());
  await mustFail("own leave → approved", () => c.from("leaves").update({ status: "approved" }).eq("student_id", ids.stuA.id).select());
  await mustFail("own complaint → resolved", () => c.from("complaints").update({ status: "resolved" }).eq("student_id", ids.stuA.id).select());
  await mustFail("insert audit_log row", () => c.from("audit_log").insert({ action: "forged.admin", actor_user_id: ids.admin.id }).select());
  await mustFail("insert notification for another user", () => c.from("notifications").insert({ user_id: ids.stuB.user_id, type: "system", title: "AUDIT forged" }).select());
  await mustFail("insert expense (not their role)", () => c.from("expenses").insert({ hostel_id: ids.sunrise, date: "2026-08-16", category: "other", amount: 1 }).select());
}

console.log("\n═══ B. STUDENT cross-user reads/writes — all must fail ═══");
{
  const { c } = await login("9000000001@student.hostelpro.local", "Student@12345");
  await mustFail("read student B row", () => c.from("students").select("*").eq("id", ids.stuB.id));
  await mustFail("read B guardian/address via any select", () => c.from("students").select("full_name,guardian_phone,permanent_address").neq("id", ids.stuA.id));
  await mustFail("read B complaints", () => c.from("complaints").select("*").eq("student_id", ids.stuB.id));
  await mustFail("read B fee_payments", () => c.from("fee_payments").select("*").eq("student_id", ids.stuB.id));
  await mustFail("read B leaves", () => c.from("leaves").select("*").eq("student_id", ids.stuB.id));
  await mustFail("read B notifications", () => c.from("notifications").select("*").eq("user_id", ids.stuB.user_id));
  await mustFail("read other users rows", () => c.from("users").select("id,email,phone,role").neq("id", ids.stuA.user_id));
  await mustFail("read visitors", () => c.from("visitors").select("*"));
  await mustFail("read expenses", () => c.from("expenses").select("*"));
  await mustFail("read revenues", () => c.from("revenues").select("*"));
  await mustFail("read subscriptions", () => c.from("subscriptions").select("*"));
  await mustFail("read audit_log", () => c.from("audit_log").select("*"));
  await mustFail("read Lakeview students", () => c.from("students").select("*").eq("hostel_id", ids.lakeview));
  await mustFail("insert complaint AS student B", () => c.from("complaints").insert({ hostel_id: ids.sunrise, student_id: ids.stuB.id, category: "other", title: "AUDIT forged" }).select());
  await mustFail("insert leave FOR student B", () => c.from("leaves").insert({ hostel_id: ids.sunrise, student_id: ids.stuB.id, from_date: "2026-09-01", to_date: "2026-09-02" }).select());
  await mustSucceed("read OWN student row", () => c.from("students").select("id,full_name").eq("id", ids.stuA.id));
  await mustSucceed("roommates RPC (name/phone/bed only)", () => c.rpc("st_my_roommates"));
}

console.log("\n═══ C. WARDEN (Sunrise) → Lakeview tenant — all must fail ═══");
{
  const { c } = await login("warden@demo.hostelpro.app", "Warden@12345");
  await mustFail("read Lakeview students", () => c.from("students").select("*").eq("hostel_id", ids.lakeview));
  await mustFail("read Lakeview complaints", () => c.from("complaints").select("*").eq("hostel_id", ids.lakeview));
  await mustFail("update Lakeview student fee", () => c.from("students").update({ monthly_fee: 1 }).eq("id", ids.stuLake.id).select());
  await mustFail("insert visitor for Lakeview student", () => c.from("visitors").insert({ hostel_id: ids.lakeview, student_id: ids.stuLake.id, visitor_name: "AUDIT" }).select());
  await mustFail("move Sunrise student → Lakeview", () => c.from("students").update({ hostel_id: ids.lakeview }).eq("id", ids.stuA.id).select());
  await mustFail("rpc wd_record_payment on Lakeview student", () => c.rpc("wd_record_payment", { p_student_id: ids.stuLake.id, p_period_month: "2026-08", p_amount: 1, p_mode: "cash", p_paid_on: "2026-08-16", p_notes: "AUDIT" }));
  await mustFail("rpc wd_vacate_student on Lakeview student", () => c.rpc("wd_vacate_student", { p_student_id: ids.stuLake.id }));
  await mustFail("rpc_fee_ledger with Lakeview id", () => c.rpc("rpc_fee_ledger", { p_hostel_id: ids.lakeview, p_period_month: "2026-08" }));
  await mustFail("rpc_sa_hostels (SA only)", () => c.rpc("rpc_sa_hostels"));
  await mustFail("scaffold_hostel direct", () => c.rpc("scaffold_hostel", { p_hostel_id: ids.lakeview, p_floors: 2, p_rooms: 99, p_beds_per_room: 3 }));
  await mustFail("sa_update_hostel_structure", () => c.rpc("sa_update_hostel_structure", { p_hostel_id: ids.sunrise, p_floors: 3, p_rooms: 99 }));
  await mustFail("rate_limit RPC (service-role only)", () => c.rpc("rate_limit", { p_key: "x", p_max: 1, p_window_seconds: 1 }));
  await mustSucceed("read OWN hostel students", () => c.from("students").select("id").eq("hostel_id", ids.sunrise).limit(3));
}

console.log("\n═══ D. OWNER privilege boundaries — all must fail ═══");
{
  const { c, uid } = await login("owner@demo.hostelpro.app", "Owner@12345");
  await mustFail("deactivate the SUPER ADMIN", () => c.from("users").update({ status: "inactive" }).eq("id", ids.admin.id).select());
  await mustFail("promote self to super_admin", () => c.from("users").update({ role: "super_admin" }).eq("id", uid).select());
  await mustFail("deactivate Lakeview warden", () => c.from("users").update({ status: "inactive" }).eq("id", ids.wardenLake.id).select());
  await mustFail("read Lakeview students", () => c.from("students").select("*").eq("hostel_id", ids.lakeview));
  await mustFail("insert own subscription (extend for free)", () => c.from("subscriptions").insert({ hostel_id: ids.sunrise, owner_user_id: uid, start_date: "2026-08-16", end_date: "2030-01-01", amount: 0 }).select());
  await mustFail("extend own subscription end_date", () => c.from("subscriptions").update({ end_date: "2030-01-01" }).eq("hostel_id", ids.sunrise).select());
  await mustFail("un-suspend / change own hostel status", () => c.from("hostels").update({ status: "active" }).eq("id", ids.sunrise).select());
  await mustFail("rpc sa_renew_subscription", () => c.rpc("sa_renew_subscription", { p_hostel_id: ids.sunrise, p_new_end_date: "2030-01-01", p_amount: 0, p_notes: "AUDIT" }));
  await mustFail("rpc sa_create_hostel_with_subscription", () => c.rpc("sa_create_hostel_with_subscription", { p_owner_user_id: uid, p_hostel_name: "AUDIT Free Hostel", p_floors: 1, p_rooms: 1, p_address: "x", p_start_date: "2026-08-16", p_end_date: "2030-01-01", p_amount: 0, p_notes: null, p_beds_per_room: 3 }));
  await mustFail("insert audit_log row", () => c.from("audit_log").insert({ action: "forged", hostel_id: ids.sunrise }).select());
  await mustFail("delete audit_log rows", () => c.from("audit_log").delete().eq("hostel_id", ids.sunrise).select());
  await mustSucceed("read own hostel audit log", () => c.from("audit_log").select("id").eq("hostel_id", ids.sunrise).limit(3));
}

console.log("\n═══ E. EXPIRED tenant (Lakeview) — writes must be blocked ═══");
{
  const { c } = await login("warden2@demo.hostelpro.app", "Warden@12345");
  await mustFail("insert visitor (expired sub)", () => c.from("visitors").insert({ hostel_id: ids.lakeview, student_id: ids.stuLake.id, visitor_name: "AUDIT" }).select());
  await mustFail("update student (expired sub)", () => c.from("students").update({ monthly_fee: 1 }).eq("id", ids.stuLake.id).select());
  await mustFail("record payment (expired sub)", () => c.rpc("wd_record_payment", { p_student_id: ids.stuLake.id, p_period_month: "2026-08", p_amount: 1, p_mode: "cash", p_paid_on: "2026-08-16", p_notes: "AUDIT" }));
  await mustSucceed("read own hostel students (read-only OK)", () => c.from("students").select("id").eq("hostel_id", ids.lakeview));
}

console.log("\n═══ F. ANONYMOUS (no login) — everything must fail ═══");
{
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  for (const t of ["users", "students", "hostels", "subscriptions", "complaints", "fee_payments", "expenses", "revenues", "visitors", "leaves", "notifications", "audit_log", "menus", "beds", "rooms", "tasks", "announcements"]) {
    await mustFail(`anon select ${t}`, () => c.from(t).select("*").limit(1));
  }
  await mustFail("anon rpc rpc_sa_dashboard", () => c.rpc("rpc_sa_dashboard"));
  await mustFail("anon rpc st_my_roommates", () => c.rpc("st_my_roommates"));
  await mustFail("anon rpc audit_event", () => c.rpc("audit_event", { p_action: "forged" }));
  await mustFail("anon rpc rate_limit", () => c.rpc("rate_limit", { p_key: "x", p_max: 1, p_window_seconds: 1 }));
  const r = await fetch(`${URL}/storage/v1/object/public/student-docs/${ids.sunrise}/photos/x.png`);
  console.log(`  ${r.status >= 400 ? "PASS" : "FAIL"}  anon public storage GET → HTTP ${r.status}`);
  r.status >= 400 ? pass++ : fail++;
}

console.log(`\n═══ RESULT: ${pass} passed, ${fail} FAILED ═══`);
process.exit(fail > 0 ? 1 : 0);

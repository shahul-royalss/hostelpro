/**
 * HostelPro — demo seed (CLAUDE_2.md §8.1 + §13)
 *
 *   npm run db:seed                 → super admin + full demo data (two hostels)
 *   npm run db:seed:admin           → super admin only  (= tsx db/seed.ts --admin-only)
 *   npx tsx db/seed.ts --force      → wipe previously seeded demo hostels/accounts first
 *   npx tsx db/seed.ts --force-admin→ (with --force) also recreate the super admin
 *
 * Runs with the SERVICE ROLE key (auth admin API + RLS bypass). app.is_super_admin()
 * returns true for the service role, so the same RPCs the UI uses
 * (sa_create_hostel_with_subscription, wd_register_student, wd_record_payment) work here.
 * Standalone script: no Next.js / lib imports (tsx only).
 *
 * NOTE: the seed refuses to run on top of existing demo accounts; `--force` wipes the demo
 * hostels and accounts (super admin is kept) and recreates everything. The dev project
 * nimxvgzscbanhtvgnjll was (re)seeded with this script on 2026-08-16.
 *
 * Idempotency: without --force the script aborts with "Already seeded — rerun with --force"
 * as soon as it meets an existing demo login; nothing is partially written before that check
 * for the first account, but a mid-run failure leaves partial data → rerun with --force.
 */
import path from "node:path";
import { config as loadEnv } from "dotenv";
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";

loadEnv({ path: path.resolve(process.cwd(), ".env.local") });
loadEnv(); // fallback: .env

/* ─────────────────────────── flags & env ─────────────────────────── */

const argv = new Set(process.argv.slice(2));
const ADMIN_ONLY = argv.has("--admin-only");
const FORCE = argv.has("--force");
const FORCE_ADMIN = argv.has("--force-admin");

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const APP_URL = (process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000").replace(/\/$/, "");

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error(
    "\n✖ Missing NEXT_PUBLIC_SUPABASE_URL and/or SUPABASE_SERVICE_ROLE_KEY.\n" +
      "  Copy .env.example → .env.local and paste the service_role key from\n" +
      "  Supabase Dashboard → Project Settings → API. Then rerun `npm run db:seed`.\n",
  );
  process.exit(1);
}

const sb: SupabaseClient = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/* ─────────────────────────── constants ─────────────────────────── */

type Role = "super_admin" | "owner" | "manager" | "warden" | "student";
type PaymentMode = "cash" | "upi" | "bank";

const DEMO_DOMAIN = "demo.hostelpro.app";
const STUDENT_LOGIN_DOMAIN = "student.hostelpro.local"; // = lib/utils.ts STUDENT_LOGIN_DOMAIN

const PW = {
  owner: "Owner@12345",
  manager: "Manager@12345",
  warden: "Warden@12345",
  student: "Student@12345",
} as const;

const STAFF = {
  owner1: { email: `owner@${DEMO_DOMAIN}`, name: "Ananya Rao", phone: "9876500001" },
  manager1: { email: `manager@${DEMO_DOMAIN}`, name: "Rahul Mehta", phone: "9876500002" },
  warden1: { email: `warden@${DEMO_DOMAIN}`, name: "Priya Nair", phone: "9876500003" },
  owner2: { email: `owner2@${DEMO_DOMAIN}`, name: "Vikram Shetty", phone: "9876500004" },
  warden2: { email: `warden2@${DEMO_DOMAIN}`, name: "Lakeview Warden", phone: "9876500005" },
} as const;

interface StudentSeed {
  name: string;
  phone: string;
  guardian: string;
  guardianPhone: string;
  address: string;
  idProof: string;
  fee: number;
  joinedDaysAgo: number;
  room: string;
  bed: number;
}

/**
 * Sunrise Residency — 3 floors × 12 rooms (101–104, 201–204, 301–304) × 3 beds.
 * Bed spread: 101 full, 102 full, 103 two, 104 one, 201 two, 202 one → 12 students / 36 beds.
 * Index (1-based) = last two digits of the phone; joining dates span the last ~6 months.
 */
const SUNRISE_STUDENTS: StudentSeed[] = [
  { name: "Aarav Sharma", phone: "9000000001", guardian: "Rajesh Sharma", guardianPhone: "9811100001", address: "14, Malviya Nagar, Jaipur, Rajasthan 302017", idProof: "Aadhaar", fee: 7000, joinedDaysAgo: 165, room: "101", bed: 1 },
  { name: "Ishaan Verma", phone: "9000000002", guardian: "Sunil Verma", guardianPhone: "9811100002", address: "B-22, Gomti Nagar, Lucknow, UP 226010", idProof: "Aadhaar", fee: 6500, joinedDaysAgo: 150, room: "101", bed: 2 },
  { name: "Kavya Iyer", phone: "9000000003", guardian: "Ramesh Iyer", guardianPhone: "9811100003", address: "7, Besant Nagar 2nd Ave, Chennai, TN 600090", idProof: "PAN", fee: 7500, joinedDaysAgo: 140, room: "102", bed: 1 },
  { name: "Rohan Deshmukh", phone: "9000000004", guardian: "Prakash Deshmukh", guardianPhone: "9811100004", address: "Flat 302, Kothrud, Pune, MH 411038", idProof: "Driving Licence", fee: 6000, joinedDaysAgo: 120, room: "101", bed: 3 },
  { name: "Sneha Patil", phone: "9000000005", guardian: "Mahesh Patil", guardianPhone: "9811100005", address: "Rajarampuri 5th Lane, Kolhapur, MH 416008", idProof: "Aadhaar", fee: 8000, joinedDaysAgo: 110, room: "102", bed: 2 },
  { name: "Arjun Nair", phone: "9000000006", guardian: "Lakshmi Nair", guardianPhone: "9811100006", address: "Panampilly Nagar, Kochi, Kerala 682036", idProof: "Passport", fee: 7200, joinedDaysAgo: 95, room: "103", bed: 1 },
  { name: "Meera Krishnan", phone: "9000000007", guardian: "Venkat Krishnan", guardianPhone: "9811100007", address: "RS Puram, Coimbatore, TN 641002", idProof: "Aadhaar", fee: 6800, joinedDaysAgo: 80, room: "102", bed: 3 },
  { name: "Aditya Kulkarni", phone: "9000000008", guardian: "Sanjay Kulkarni", guardianPhone: "9811100008", address: "Dharampeth, Nagpur, MH 440010", idProof: "Voter ID", fee: 7000, joinedDaysAgo: 65, room: "103", bed: 2 },
  { name: "Priyanka Singh", phone: "9000000009", guardian: "Anil Singh", guardianPhone: "9811100009", address: "Lanka, Varanasi, UP 221005", idProof: "Aadhaar", fee: 6500, joinedDaysAgo: 50, room: "104", bed: 1 },
  { name: "Karan Malhotra", phone: "9000000010", guardian: "Deepak Malhotra", guardianPhone: "9811100010", address: "Sector 21, Chandigarh 160022", idProof: "PAN", fee: 7800, joinedDaysAgo: 35, room: "201", bed: 1 },
  { name: "Divya Reddy", phone: "9000000011", guardian: "Srinivas Reddy", guardianPhone: "9811100011", address: "Jubilee Hills, Hyderabad, TS 500033", idProof: "Aadhaar", fee: 7500, joinedDaysAgo: 20, room: "202", bed: 1 },
  { name: "Siddharth Bose", phone: "9000000012", guardian: "Amit Bose", guardianPhone: "9811100012", address: "Salt Lake Sector V, Kolkata, WB 700091", idProof: "Aadhaar", fee: 6200, joinedDaysAgo: 6, room: "201", bed: 2 },
];

/** Lakeview PG — 2 floors × 6 rooms (101–103, 201–203) × 3 beds; expired subscription. */
const LAKEVIEW_STUDENTS: StudentSeed[] = [
  { name: "Nikhil Joshi", phone: "9000000101", guardian: "Mohan Joshi", guardianPhone: "9811100101", address: "Aundh, Pune, MH 411007", idProof: "Aadhaar", fee: 6500, joinedDaysAgo: 200, room: "101", bed: 1 },
  { name: "Tanvi Menon", phone: "9000000102", guardian: "Suresh Menon", guardianPhone: "9811100102", address: "Kakkanad, Kochi, Kerala 682030", idProof: "PAN", fee: 7000, joinedDaysAgo: 90, room: "102", bed: 1 },
];

/** Every demo login the seed creates (used by --force cleanup). */
const DEMO_EMAILS = new Set<string>([
  ...Object.values(STAFF).map((s) => s.email),
  ...[...SUNRISE_STUDENTS, ...LAKEVIEW_STUDENTS].map((s) => studentEmail(s.phone)),
]);

/* ─────────────────────────── helpers ─────────────────────────── */

function studentEmail(phone: string) {
  return `${phone}@${STUDENT_LOGIN_DOMAIN}`;
}
function iso(d: Date) {
  return d.toISOString().slice(0, 10);
}
function daysFromNow(n: number) {
  return new Date(Date.now() + n * 86_400_000);
}
function hoursAgo(h: number) {
  return new Date(Date.now() - h * 3_600_000).toISOString();
}
const TODAY = iso(new Date());
const PERIOD = TODAY.slice(0, 7); // YYYY-MM
const MONTH_START = `${PERIOD}-01`;
/** A date n days ago, but never before the 1st of the current month (fees "paid this month"). */
function paidOnDaysAgo(n: number) {
  const d = iso(daysFromNow(-n));
  return d < MONTH_START ? MONTH_START : d;
}

function log(msg: string) {
  console.log(`  • ${msg}`);
}
function section(title: string) {
  console.log(`\n${title}`);
}

interface PgErr {
  message: string;
  details?: string | null;
  hint?: string | null;
}
function must<T>(res: { data: T | null; error: PgErr | null }, what: string): T {
  if (res.error) throw new Error(`${what}: ${res.error.message}${res.error.details ? ` (${res.error.details})` : ""}`);
  if (res.data === null || res.data === undefined) throw new Error(`${what}: no data returned`);
  return res.data;
}
function check(res: { error: PgErr | null }, what: string) {
  if (res.error) throw new Error(`${what}: ${res.error.message}`);
}

/* ─────────────────────────── auth helpers ─────────────────────────── */

let authUsersCache: User[] | null = null;
async function listAllAuthUsers(): Promise<User[]> {
  if (authUsersCache) return authUsersCache;
  const users: User[] = [];
  const perPage = 1000;
  for (let page = 1; ; page++) {
    const { data, error } = await sb.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error(`listUsers: ${error.message}`);
    users.push(...data.users);
    if (data.users.length < perPage) break;
  }
  authUsersCache = users;
  return users;
}
async function findAuthUserByEmail(email: string): Promise<User | undefined> {
  const all = await listAllAuthUsers();
  return all.find((u) => (u.email ?? "").toLowerCase() === email.toLowerCase());
}
async function deleteAuthUser(id: string) {
  const { error } = await sb.auth.admin.deleteUser(id);
  if (error) throw new Error(`deleteUser ${id}: ${error.message}`);
  if (authUsersCache) authUsersCache = authUsersCache.filter((u) => u.id !== id);
}

interface AuthArgs {
  email: string;
  password: string;
  role: Role;
  fullName: string;
  phone?: string | null;
  hostelId?: string | null;
}

/** Create the auth.users record only (used for students — wd_register_student adds public.users). */
async function createAuthUser(a: AuthArgs): Promise<string> {
  const email = a.email.toLowerCase();
  const payload = {
    email,
    password: a.password,
    email_confirm: true,
    user_metadata: { full_name: a.fullName, phone: a.phone ?? null },
    app_metadata: { role: a.role, hostel_id: a.hostelId ?? null, must_change_password: false },
  };
  let res = await sb.auth.admin.createUser(payload);
  const alreadyExists = (e: { status?: number; message: string } | null) =>
    !!e && (e.status === 422 || /already/i.test(e.message));
  if (alreadyExists(res.error)) {
    if (!FORCE) throw new Error(`Already seeded (${email} exists) — rerun with --force`);
    const existing = await findAuthUserByEmail(email);
    if (existing) await deleteAuthUser(existing.id);
    res = await sb.auth.admin.createUser(payload);
  }
  if (res.error || !res.data.user) throw new Error(`createUser ${email}: ${res.error?.message ?? "unknown error"}`);
  return res.data.user.id;
}

/** Auth user + public.users profile row (super admin / owner / manager / warden). */
async function createUser(a: AuthArgs & { createdBy?: string | null }): Promise<string> {
  const id = await createAuthUser(a);
  const { error } = await sb.from("users").insert({
    id,
    role: a.role,
    full_name: a.fullName,
    email: a.email.toLowerCase(),
    phone: a.phone ?? null,
    hostel_id: a.hostelId ?? null,
    status: "active",
    must_change_password: false, // demo accounts go straight to their dashboards
    created_by: a.createdBy ?? null,
  });
  if (error) {
    await deleteAuthUser(id).catch(() => undefined);
    throw new Error(`users row for ${a.email}: ${error.message}`);
  }
  return id;
}

async function setAppMetadata(userId: string, meta: Record<string, unknown>) {
  const { data } = await sb.auth.admin.getUserById(userId);
  const existing = (data?.user?.app_metadata ?? {}) as Record<string, unknown>;
  const { error } = await sb.auth.admin.updateUserById(userId, { app_metadata: { ...existing, ...meta } });
  if (error) throw new Error(`updateUserById ${userId}: ${error.message}`);
}

/* ─────────────────────────── --force cleanup ─────────────────────────── */

const ROLE_DELETE_ORDER: Record<string, number> = { student: 0, warden: 1, manager: 2, owner: 3, super_admin: 4 };

/**
 * Wipe everything a previous seed created:
 *   1. hostels owned by the demo owners (cascades every tenant table)
 *      — users.hostel_id → hostels has no cascade, so hostel members are first
 *        detached (status inactive + hostel_id null; the role-limit trigger skips inactive rows)
 *   2. auth users (cascade → public.users) in child→parent order of `created_by`
 */
async function wipeDemoData() {
  section("Cleaning up previous demo data (--force)");
  const all = await listAllAuthUsers();
  const demoAuth = all.filter((u) => DEMO_EMAILS.has((u.email ?? "").toLowerCase()));
  const ownerEmails: string[] = [STAFF.owner1.email, STAFF.owner2.email];
  const ownerIds = demoAuth.filter((u) => ownerEmails.includes((u.email ?? "").toLowerCase())).map((u) => u.id);

  const toDelete = new Map<string, number>(); // user id → delete order
  for (const u of demoAuth) toDelete.set(u.id, ROLE_DELETE_ORDER[String(u.app_metadata?.role ?? "student")] ?? 0);

  if (ownerIds.length) {
    const hostels = must(
      await sb.from("hostels").select("id, name").in("owner_user_id", ownerIds),
      "find demo hostels",
    ) as { id: string; name: string }[];

    for (const h of hostels) {
      const members = must(
        await sb.from("users").select("id, role").eq("hostel_id", h.id),
        `members of ${h.name}`,
      ) as { id: string; role: string }[];
      for (const m of members) toDelete.set(m.id, ROLE_DELETE_ORDER[m.role] ?? 0);

      check(
        await sb.from("users").update({ status: "inactive", hostel_id: null }).eq("hostel_id", h.id),
        `detach members of ${h.name}`,
      );
      check(await sb.from("hostels").delete().eq("id", h.id), `delete hostel ${h.name}`);
      log(`deleted hostel "${h.name}" (${members.length} member accounts detached)`);
    }
  }

  const ordered = [...toDelete.entries()].sort((a, b) => a[1] - b[1]).map(([id]) => id);
  if (ordered.length) {
    // users.created_by → users has no cascade; drop the audit links between demo accounts
    // so deletion cannot trip over an unexpected creator chain (e.g. QA-created extras).
    check(await sb.from("users").update({ created_by: null }).in("created_by", ordered), "detach created_by links");
    for (const id of ordered) await deleteAuthUser(id);
  }
  log(`deleted ${ordered.length} demo auth accounts`);

  if (FORCE_ADMIN && process.env.SUPER_ADMIN_EMAIL) {
    const sa = await findAuthUserByEmail(process.env.SUPER_ADMIN_EMAIL);
    if (sa) {
      await deleteAuthUser(sa.id);
      log("deleted existing super admin (--force-admin)");
    }
  }
}

/* ─────────────────────────── seed steps ─────────────────────────── */

interface Cred {
  role: string;
  name: string;
  loginId: string;
  password: string;
  url: string;
}
const creds: Cred[] = [];

async function seedSuperAdmin(): Promise<string> {
  section("Super admin");
  const email = process.env.SUPER_ADMIN_EMAIL;
  const password = process.env.SUPER_ADMIN_PASSWORD;
  const name = process.env.SUPER_ADMIN_NAME ?? "Platform Admin";
  if (!email || !password) {
    throw new Error("SUPER_ADMIN_EMAIL and SUPER_ADMIN_PASSWORD must be set in .env.local");
  }

  const existing = await findAuthUserByEmail(email);
  let id: string;
  if (existing) {
    // Keep the platform account across reseeds; make sure its profile row exists.
    id = existing.id;
    check(
      await sb.from("users").upsert(
        { id, role: "super_admin", full_name: name, email: email.toLowerCase(), status: "active", must_change_password: false },
        { onConflict: "id" },
      ),
      "super admin profile",
    );
    log(`super admin ${email} already exists — kept (use --force --force-admin to recreate)`);
  } else {
    id = await createUser({ email, password, role: "super_admin", fullName: name, hostelId: null });
    log(`created super admin ${email}`);
  }
  creds.push({ role: "Super Admin", name, loginId: email, password: existing ? "(unchanged)" : password, url: `${APP_URL}/super-admin` });
  return id;
}

interface HostelSeed {
  ownerId: string;
  name: string;
  floors: number;
  rooms: number;
  address: string;
  start: string;
  end: string;
  amount: number;
  notes: string;
}
async function createHostel(h: HostelSeed): Promise<string> {
  const hostelId = must(
    await sb.rpc("sa_create_hostel_with_subscription", {
      p_owner_user_id: h.ownerId,
      p_hostel_name: h.name,
      p_floors: h.floors,
      p_rooms: h.rooms,
      p_address: h.address,
      p_start_date: h.start,
      p_end_date: h.end,
      p_amount: h.amount,
      p_notes: h.notes,
      p_beds_per_room: 3,
    }),
    `create hostel ${h.name}`,
  ) as string;
  await setAppMetadata(h.ownerId, { hostel_id: hostelId });
  log(`hostel "${h.name}" ${hostelId} (${h.floors} floors × ${h.rooms} rooms × 3 beds)`);
  return hostelId;
}

interface BedRef {
  id: string;
  room_number: string;
  bed_number: number;
}
async function loadBeds(hostelId: string): Promise<BedRef[]> {
  const rooms = must(await sb.from("rooms").select("id, room_number").eq("hostel_id", hostelId), "rooms") as {
    id: string;
    room_number: string;
  }[];
  const beds = must(await sb.from("beds").select("id, room_id, bed_number").eq("hostel_id", hostelId), "beds") as {
    id: string;
    room_id: string;
    bed_number: number;
  }[];
  const roomNo = new Map(rooms.map((r) => [r.id, r.room_number]));
  return beds.map((b) => ({ id: b.id, room_number: roomNo.get(b.room_id) ?? "?", bed_number: b.bed_number }));
}

interface SeededStudent extends StudentSeed {
  studentId: string;
  userId: string;
}
async function registerStudents(hostelId: string, wardenId: string, list: StudentSeed[]): Promise<SeededStudent[]> {
  const beds = await loadBeds(hostelId);
  const out: SeededStudent[] = [];
  for (const s of list) {
    const bed = beds.find((b) => b.room_number === s.room && b.bed_number === s.bed);
    if (!bed) throw new Error(`Bed ${s.room}-${s.bed} not found in hostel ${hostelId}`);

    const userId = await createAuthUser({
      email: studentEmail(s.phone),
      password: PW.student,
      role: "student",
      fullName: s.name,
      phone: s.phone,
      hostelId,
    });
    const res = await sb.rpc("wd_register_student", {
      p_user_id: userId,
      p_hostel_id: hostelId,
      p_full_name: s.name,
      p_phone: s.phone,
      p_email: null,
      p_photo_url: null,
      p_guardian_name: s.guardian,
      p_guardian_phone: s.guardianPhone,
      p_permanent_address: s.address,
      p_id_proof_type: s.idProof,
      p_id_proof_url: null,
      p_date_of_joining: iso(daysFromNow(-s.joinedDaysAgo)),
      p_bed_id: bed.id,
      p_monthly_fee: s.fee,
    });
    if (res.error) {
      await deleteAuthUser(userId).catch(() => undefined);
      throw new Error(`wd_register_student ${s.name}: ${res.error.message}`);
    }
    out.push({ ...s, studentId: res.data as string, userId });
    creds.push({ role: "Student", name: s.name, loginId: s.phone, password: PW.student, url: `${APP_URL}/student` });
  }
  // The RPC sets must_change_password=true / created_by=auth.uid() (null for the service role);
  // demo logins should land straight on the dashboard and show the warden as registrar.
  const userIds = out.map((s) => s.userId);
  check(await sb.from("users").update({ must_change_password: false, created_by: wardenId }).in("id", userIds), "students: profile flags");
  check(await sb.from("students").update({ created_by: wardenId }).in("user_id", userIds), "students: created_by");
  log(`registered ${out.length} students`);
  return out;
}

async function seedSunriseData(hostelId: string, ids: { owner: string; manager: string; warden: string }, students: SeededStudent[]) {
  const S = (i: number) => students[i - 1]; // 1-based, matches the table above

  /* fees — current period: 6 paid, 2 partial, 4 unpaid */
  section("Fees");
  const payments: { s: number; amount?: number; mode: PaymentMode; daysAgo: number }[] = [
    { s: 1, mode: "upi", daysAgo: 0 },
    { s: 2, mode: "cash", daysAgo: 1 },
    { s: 3, mode: "upi", daysAgo: 2 },
    { s: 4, amount: 3000, mode: "upi", daysAgo: 3 },
    { s: 5, mode: "bank", daysAgo: 6 },
    { s: 6, mode: "upi", daysAgo: 12 },
    { s: 7, amount: 4000, mode: "cash", daysAgo: 4 },
    { s: 8, mode: "upi", daysAgo: 8 },
  ];
  for (const p of payments) {
    const st = S(p.s);
    check(
      await sb.rpc("wd_record_payment", {
        p_student_id: st.studentId,
        p_period_month: PERIOD,
        p_amount: p.amount ?? st.fee,
        p_mode: p.mode,
        p_paid_on: paidOnDaysAgo(p.daysAgo),
        p_notes: p.amount ? "Part payment — balance promised next week" : null,
      }),
      `payment for ${st.name}`,
    );
  }
  // recorded_by is auth.uid() inside the RPC (null for service role) → attribute to the warden
  check(await sb.from("fee_payments").update({ recorded_by: ids.warden }).eq("hostel_id", hostelId), "fees: recorded_by");
  log(`${payments.length} payments recorded for ${PERIOD} (2 partial, ${students.length - payments.length} unpaid)`);

  /* expenses (15, last 30 days) + revenues (10) — entered by the manager */
  section("Finance");
  const expenses: [number, string, number, string][] = [
    [0, "groceries", 3450, "Vegetables & dairy — weekly"],
    [0, "other", 600, "Newspaper & courier"],
    [1, "electricity", 8420, "Electricity bill"],
    [2, "groceries", 2780, "Rice, dal, cooking oil"],
    [3, "maintenance", 1500, "Plumber — 2nd floor bathroom"],
    [5, "water", 1900, "Water tanker × 2"],
    [6, "staff", 12000, "Cook salary"],
    [7, "groceries", 4100, "Monthly provisions"],
    [9, "other", 850, "Cleaning supplies"],
    [11, "maintenance", 2600, "Wi-Fi router replacement"],
    [14, "groceries", 3200, "Vegetables & dairy — weekly"],
    [17, "staff", 9000, "Housekeeping salary"],
    [21, "groceries", 3650, "Vegetables & dairy — weekly"],
    [24, "water", 950, "RO service"],
    [28, "electricity", 780, "Generator diesel"],
  ];
  check(
    await sb.from("expenses").insert(
      expenses.map(([d, category, amount, note]) => ({
        hostel_id: hostelId,
        date: iso(daysFromNow(-d)),
        category,
        amount,
        note,
        uploaded_by: ids.manager,
      })),
    ),
    "expenses",
  );
  const revenues: [number, string, number, string][] = [
    [0, "fees", 7000, "Fee — Aarav Sharma (UPI)"],
    [0, "mess", 1200, "Guest mess coupons"],
    [1, "fees", 6500, "Fee — Ishaan Verma (cash)"],
    [2, "fees", 7500, "Fee — Kavya Iyer (UPI)"],
    [3, "fees", 3000, "Part fee — Rohan Deshmukh"],
    [4, "mess", 800, "Extra meal coupons"],
    [6, "fees", 8000, "Fee — Sneha Patil (bank)"],
    [8, "other", 2500, "Laundry service"],
    [12, "fees", 7200, "Fee — Arjun Nair (UPI)"],
    [18, "other", 1500, "Room key deposit"],
  ];
  check(
    await sb.from("revenues").insert(
      revenues.map(([d, source, amount, note]) => ({
        hostel_id: hostelId,
        date: iso(daysFromNow(-d)),
        source,
        amount,
        note,
        uploaded_by: ids.manager,
      })),
    ),
    "revenues",
  );
  log(`${expenses.length} expenses + ${revenues.length} revenues`);

  /* complaints — insert (student = actor), then move status as the warden so
     complaint_events + notifications are produced by the DB triggers */
  section("Complaints");
  const complaintSeeds = [
    { s: 3, category: "wifi", title: "Wi-Fi keeps dropping in room 102", description: "Connection drops every evening after 8 pm; can't attend online classes.", daysAgo: 2, final: "open" as const },
    { s: 7, category: "food", title: "Dinner served cold twice this week", description: "Chapatis and dal were cold on Monday and Wednesday.", daysAgo: 4, final: "open" as const },
    { s: 4, category: "maintenance", title: "Bathroom tap leaking on 1st floor", description: "The tap near room 101 leaks continuously and the floor stays wet.", daysAgo: 9, final: "in_progress" as const },
    { s: 10, category: "cleaning", title: "Corridor on 2nd floor not cleaned", description: "Dust and litter near the stairs for the last three days.", daysAgo: 16, final: "resolved" as const, note: "Housekeeping schedule updated; corridor cleaned daily at 8 am." },
  ];
  for (const c of complaintSeeds) {
    const st = S(c.s);
    const createdAt = daysFromNow(-c.daysAgo).toISOString();
    const row = must(
      await sb
        .from("complaints")
        .insert({
          hostel_id: hostelId,
          student_id: st.studentId,
          category: c.category,
          title: c.title,
          description: c.description,
          updated_by: st.userId,
          created_at: createdAt,
        })
        .select("id")
        .single(),
      `complaint "${c.title}"`,
    ) as { id: string };
    // backdate the "raised" timeline event to match created_at
    check(await sb.from("complaint_events").update({ created_at: createdAt }).eq("complaint_id", row.id), "complaint event date");

    if (c.final !== "open") {
      check(await sb.from("complaints").update({ status: "in_progress", updated_by: ids.warden }).eq("id", row.id), "complaint → in_progress");
    }
    if (c.final === "resolved") {
      check(
        await sb.from("complaints").update({ status: "resolved", resolution_note: c.note, updated_by: ids.warden }).eq("id", row.id),
        "complaint → resolved",
      );
    }
  }
  log(`${complaintSeeds.length} complaints (2 open, 1 in progress, 1 resolved)`);

  /* announcements (owner) */
  section("Announcements, tasks, menu, leaves, visitors");
  check(
    await sb.from("announcements").insert([
      {
        hostel_id: hostelId,
        author_user_id: ids.owner,
        audience: "all",
        title: "Water supply maintenance on Sunday",
        body: "The overhead tank will be cleaned this Sunday between 10 am and 1 pm. Please store water in advance. Mess timings remain unchanged.",
        created_at: daysFromNow(-1).toISOString(),
      },
      {
        hostel_id: hostelId,
        author_user_id: ids.owner,
        audience: "students",
        title: "Monthly fee reminder",
        body: `Fees for ${PERIOD} are due by the 10th. Pay by UPI or at the warden's office. Late payments attract a ₹200 fine.`,
        created_at: daysFromNow(-3).toISOString(),
      },
    ]),
    "announcements",
  );

  /* tasks owner → manager (one done, one pending) */
  const doneTask = must(
    await sb
      .from("tasks")
      .insert({
        hostel_id: hostelId,
        assigned_to: ids.manager,
        created_by: ids.owner,
        title: "Submit last month's expense summary",
        description: "Export the expense CSV and share the category totals with the accountant.",
        due_date: iso(daysFromNow(-3)),
        created_at: daysFromNow(-8).toISOString(),
      })
      .select("id")
      .single(),
    "task 1",
  ) as { id: string };
  check(await sb.from("tasks").update({ status: "done" }).eq("id", doneTask.id), "task 1 → done");
  check(
    await sb.from("tasks").insert({
      hostel_id: hostelId,
      assigned_to: ids.manager,
      created_by: ids.owner,
      title: "Get quotes for a solar water heater",
      description: "Collect at least two vendor quotes for a 500 L rooftop unit and attach them here.",
      due_date: iso(daysFromNow(5)),
    }),
    "task 2",
  );

  /* weekly mess menu (7 days × 4 meals) */
  const menu: Record<string, [string, string, string, string]> = {
    mon: ["Poha, banana, tea", "Rice, dal tadka, aloo gobi, salad", "Samosa, chai", "Chapati, paneer butter masala, jeera rice"],
    tue: ["Idli, sambar, coconut chutney", "Rice, rajma, bhindi fry, curd", "Bread pakora, chai", "Chapati, mixed veg, dal fry"],
    wed: ["Upma, chutney, tea", "Rice, sambar, cabbage poriyal, papad", "Biscuits, coffee", "Veg pulao, raita, gulab jamun"],
    thu: ["Aloo paratha, curd, pickle", "Rice, chole, lauki sabzi, salad", "Vada pav, chai", "Chapati, egg curry / paneer bhurji, dal"],
    fri: ["Masala dosa, sambar, chutney", "Rice, kadhi, aloo matar, papad", "Bhel puri, chai", "Chapati, veg kolhapuri, curd rice"],
    sat: ["Chole bhature, tea", "Veg biryani, raita, salad", "Maggi, coffee", "Chapati, dal makhani, jeera aloo"],
    sun: ["Puri bhaji, sooji halwa, tea", "Rice, dal, chicken curry / paneer masala, salad", "Cake slice, chai", "Pav bhaji, ice cream"],
  };
  const meals = ["breakfast", "lunch", "snacks", "dinner"] as const;
  check(
    await sb.from("menus").insert(
      Object.entries(menu).flatMap(([day, items]) =>
        meals.map((meal, i) => ({ hostel_id: hostelId, day_of_week: day, meal, items: items[i], updated_by: ids.manager })),
      ),
    ),
    "menus",
  );

  /* leaves — 1 pending, 1 approved (insert pending → approve so the decision notification fires) */
  check(
    await sb.from("leaves").insert({
      hostel_id: hostelId,
      student_id: S(5).studentId,
      from_date: iso(daysFromNow(3)),
      to_date: iso(daysFromNow(6)),
      reason: "Cousin's wedding in Kolhapur",
    }),
    "leave 1",
  );
  const approvedLeave = must(
    await sb
      .from("leaves")
      .insert({
        hostel_id: hostelId,
        student_id: S(9).studentId,
        from_date: iso(daysFromNow(-12)),
        to_date: iso(daysFromNow(-9)),
        reason: "Family function at home",
        created_at: daysFromNow(-15).toISOString(),
      })
      .select("id")
      .single(),
    "leave 2",
  ) as { id: string };
  check(
    await sb
      .from("leaves")
      .update({ status: "approved", decided_by: ids.warden, decision_note: "Approved. Inform the warden on return." })
      .eq("id", approvedLeave.id),
    "leave 2 → approved",
  );

  /* visitors — 2 checked in today (still inside), 1 from yesterday already checked out */
  check(
    await sb.from("visitors").insert([
      { hostel_id: hostelId, student_id: S(1).studentId, visitor_name: "Rajesh Sharma", visitor_phone: "9811100001", relation: "Father", check_in_at: hoursAgo(0.5), logged_by: ids.warden },
      { hostel_id: hostelId, student_id: S(6).studentId, visitor_name: "Lakshmi Nair", visitor_phone: "9811100006", relation: "Mother", check_in_at: hoursAgo(1.5), logged_by: ids.warden },
      { hostel_id: hostelId, student_id: S(10).studentId, visitor_name: "Rahul Malhotra", visitor_phone: "9811100020", relation: "Brother", check_in_at: hoursAgo(24 + 6), check_out_at: hoursAgo(24 + 3.5), logged_by: ids.warden },
    ]),
    "visitors",
  );
  log("2 announcements, 2 tasks, 28 menu slots, 2 leaves, 3 visitors");
}

/* ─────────────────────────── output ─────────────────────────── */

function printCredentials(hostels: { name: string; id: string; state: string }[]) {
  const cols: (keyof Cred)[] = ["role", "name", "loginId", "password", "url"];
  const head: Record<keyof Cred, string> = { role: "Role", name: "Name", loginId: "Login ID", password: "Password", url: "URL" };
  const width = cols.map((c) => Math.max(head[c].length, ...creds.map((r) => r[c].length)));
  const line = (r: Record<keyof Cred, string>) => "  " + cols.map((c, i) => r[c].padEnd(width[i])).join("  ");

  console.log("\n══════════════════════════ DEMO CREDENTIALS ══════════════════════════");
  console.log(line(head));
  console.log("  " + width.map((w) => "─".repeat(w)).join("  "));
  for (const r of creds) console.log(line(r));
  console.log("\n  Students sign in with their phone number as the login ID.");
  if (hostels.length) {
    console.log("\n  Hostels:");
    for (const h of hostels) console.log(`    ${h.name.padEnd(20)} ${h.id}  (${h.state})`);
  }
  console.log("");
}

/* ─────────────────────────── main ─────────────────────────── */

async function main() {
  console.log(`HostelPro seed → ${SUPABASE_URL}${ADMIN_ONLY ? "  [--admin-only]" : ""}${FORCE ? "  [--force]" : ""}`);

  if (FORCE) await wipeDemoData();

  const superAdminId = await seedSuperAdmin();
  if (ADMIN_ONLY) {
    printCredentials([]);
    return;
  }

  /* ── Hostel 1: Sunrise Residency (active subscription) ── */
  section("Sunrise Residency");
  const owner1 = await createUser({ ...STAFF.owner1, password: PW.owner, role: "owner", fullName: STAFF.owner1.name, createdBy: superAdminId });
  const sunrise = await createHostel({
    ownerId: owner1,
    name: "Sunrise Residency",
    floors: 3,
    rooms: 12,
    address: "24, 5th Cross, Koramangala 6th Block, Bengaluru 560095",
    start: iso(daysFromNow(-60)),
    end: iso(daysFromNow(305)),
    amount: 24000,
    notes: "Annual plan — demo",
  });
  const manager1 = await createUser({ ...STAFF.manager1, password: PW.manager, role: "manager", fullName: STAFF.manager1.name, hostelId: sunrise, createdBy: owner1 });
  const warden1 = await createUser({ ...STAFF.warden1, password: PW.warden, role: "warden", fullName: STAFF.warden1.name, hostelId: sunrise, createdBy: owner1 });
  log(`owner, manager, warden created`);
  creds.push(
    { role: "Owner", name: STAFF.owner1.name, loginId: STAFF.owner1.email, password: PW.owner, url: `${APP_URL}/owner` },
    { role: "Manager", name: STAFF.manager1.name, loginId: STAFF.manager1.email, password: PW.manager, url: `${APP_URL}/manager` },
    { role: "Warden", name: STAFF.warden1.name, loginId: STAFF.warden1.email, password: PW.warden, url: `${APP_URL}/warden` },
  );

  const sunriseStudents = await registerStudents(sunrise, warden1, SUNRISE_STUDENTS);
  await seedSunriseData(sunrise, { owner: owner1, manager: manager1, warden: warden1 }, sunriseStudents);

  /* ── Hostel 2: Lakeview PG (EXPIRED subscription → read-only gate + isolation checks) ── */
  section("Lakeview PG");
  const owner2 = await createUser({ ...STAFF.owner2, password: PW.owner, role: "owner", fullName: STAFF.owner2.name, createdBy: superAdminId });
  // Created active so students can be registered through the RPC; expired right after.
  const lakeview = await createHostel({
    ownerId: owner2,
    name: "Lakeview PG",
    floors: 2,
    rooms: 6,
    address: "Plot 9, Hinjewadi Phase 1, Pune 411057",
    start: iso(daysFromNow(-368)),
    end: iso(daysFromNow(30)),
    amount: 18000,
    notes: "Annual plan — demo (expired)",
  });
  const warden2 = await createUser({ ...STAFF.warden2, password: PW.warden, role: "warden", fullName: STAFF.warden2.name, hostelId: lakeview, createdBy: owner2 });
  creds.push(
    { role: "Owner (expired)", name: STAFF.owner2.name, loginId: STAFF.owner2.email, password: PW.owner, url: `${APP_URL}/owner` },
    { role: "Warden (expired)", name: STAFF.warden2.name, loginId: STAFF.warden2.email, password: PW.warden, url: `${APP_URL}/warden` },
  );
  await registerStudents(lakeview, warden2, LAKEVIEW_STUDENTS);
  // Expire: end_date in the past → trigger recomputes status + flips hostels.status to 'readonly'
  check(await sb.from("subscriptions").update({ end_date: iso(daysFromNow(-3)) }).eq("hostel_id", lakeview), "expire Lakeview subscription");
  log("subscription expired 3 days ago → hostel is read-only");

  printCredentials([
    { name: "Sunrise Residency", id: sunrise, state: "active, 305 days left" },
    { name: "Lakeview PG", id: lakeview, state: "EXPIRED 3 days ago — read-only" },
  ]);
  console.log("✔ Seed complete.\n");
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  console.error(`\n✖ Seed failed: ${message}`);
  if (!FORCE && /Already seeded/.test(message)) {
    console.error("  Tip: `npx tsx db/seed.ts --force` wipes the previous demo hostels/accounts and reseeds.");
  }
  process.exit(1);
});

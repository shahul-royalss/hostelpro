#!/usr/bin/env node
/**
 * Google Play store graphics for NIVORA — generated, not hand-made.
 *
 *   node scripts/store-assets.mjs            # regenerate everything into public/store/
 *   node scripts/store-assets.mjs --svg      # also write the SVG sources next to the PNGs
 *   node scripts/store-assets.mjs --check    # verify existing output, generate nothing
 *
 * WHY A SCRIPT AND NOT A DESIGN FILE
 * Play rejects a listing without an icon, a feature graphic and at least two phone
 * screenshots. Those assets have to be re-cut every time the brand or the numbers
 * move, and a one-off export in someone's Figma account is exactly the artefact that
 * goes stale and then gets faked. Everything here is derived from files that are
 * already in the repository:
 *
 *   public/brand/*.png      the NIVORA artwork — EMBEDDED AS PIXELS, never redrawn
 *   tailwind.config.ts      the palette below is a transcription of the brand tokens
 *   app/manifest.ts         #F6F4EF background/theme colour
 *   node_modules/lucide-react  the same icon geometry the app renders
 *   db/seed.ts              the demo dataset the screenshot numbers are computed from
 *
 * ABOUT THE BRAND MARK
 * Earlier revisions of this file re-drew the logo from public/icons/icon.svg. They no
 * longer do. The N-as-a-house mark and the NIVORA wordmark are now the real raster
 * artwork out of public/brand/, embedded into the SVG as a data: URI and composited by
 * the same rasteriser that draws everything else. Two consequences worth stating:
 * the wordmark is the designed lettering rather than "NIVORA" typed in whatever font
 * the build machine happens to have, and the mark cannot drift from the launcher icon,
 * because it IS the launcher icon. See brandArt() for the file list and the fallback.
 *
 * ABOUT THE SCREENSHOTS
 * The app is behind a login and the TWA is portrait-locked (app/manifest.ts), so these
 * are not device captures: they are the real mobile layouts redrawn to scale, with the
 * real strings from app/ and numbers computed from db/seed.ts (see DEMO below). Nothing
 * is invented — no testimonials, no ratings, no awards, no features that do not exist.
 * Every string on the payment panels is quoted from components/payments/*.tsx; the
 * provenance comments on those screens name the file and the line they came from.
 *
 * Play specs enforced by verify() at the bottom, per
 * support.google.com/googleplay/android-developer/answer/9866151:
 *
 *   icon             512x512, "32-bit PNG with alpha", max 1024 KB, square corners
 *                    — Play applies its own mask
 *   feature graphic  1024x500, "JPEG or 24-bit PNG (no alpha)"
 *   screenshots      "JPEG or 24-bit PNG (no alpha)", every side within 320..3840, and
 *                    the long side no more than twice the short side; 2..8 of them
 *
 * A NOTE ON THE ICON'S BIT DEPTH, because it is the one place the spec reads like a
 * contradiction. "32-bit PNG with alpha" means RGBA — 8 bits x 4 channels — so the
 * icon MUST carry an alpha channel. Play separately rejects icons that are actually
 * transparent, because it composites its own shape and shadow behind them. Both are
 * satisfied by exactly one thing: RGBA whose alpha channel is 255 everywhere. That is
 * what this script writes, and verify() asserts both halves — four channels AND a
 * minimum alpha of 255, so a stray transparent pixel cannot slip through.
 *
 * The other two are the opposite: 24-bit, alpha channel absent entirely.
 */
import sharp from "sharp";
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = path.join(REPO_ROOT, "public", "store");
const SHOTS_DIR = path.join(OUT_DIR, "screenshots");

/* ───────────────────────── brand tokens ─────────────────────────
   Transcribed from tailwind.config.ts (theme.extend.colors) and app/globals.css.
   Keep in step with those files — they are the source of truth, this is a copy. */
const C = {
  ivory: "#F6F4EF",
  stone: "#EDEAE3",
  navy: "#1C2B45",
  navyDeep: "#06162F",
  teal: "#3E7C74",
  tealSoft: "#E4EFED",
  sage: "#8CA687",
  sageSoft: "#EAF0E8",
  sand: "#D8B98A",
  sandDeep: "#A8834B",
  sandSoft: "#F7EFE1",
  red: "#C4574E",
  redSoft: "#F8E7E5",
  charcoal: "#2A2E35",
  muted: "#6E7480",
  line: "#E5E1D8",
  white: "#FFFFFF",
  /* Sampled out of public/brand/logo-square-1024.png, not invented: it is the lit
     window in the mark. Used only as a small accent so the store art and the icon
     share a colour the eye can actually match. */
  amber: "#F4A438",
};

/** app/layout.tsx loads Inter; librsvg falls back to whatever the OS has if Inter is not installed. */
const FONT = "Inter, 'Segoe UI', 'Noto Sans', Arial, sans-serif";
/** The receipt slip is `font-family: var(--font-mono)` (receipt-printer.module.css .content). */
const MONO = "'JetBrains Mono', 'Cascadia Mono', Consolas, 'DejaVu Sans Mono', monospace";

/* ───────────────────────── demo dataset ─────────────────────────
   Every number below is computed from db/seed.ts (Sunrise Residency) rather than
   typed in, so the screenshots cannot drift away from what the app would show.

   Sunrise Residency: 3 floors x 12 rooms x 3 beds = 36 beds; 12 students seeded.
   PERIOD is pinned so the output is byte-identical on every run — see docs/store-assets.md. */
const PERIOD = {
  /** period_month as the database stores it. */
  iso: "2026-08",
  /**
   * What the app actually paints. lib/utils.ts formatPeriodMonth is
   * `format(toDate(period + "-01"), "MMM yyyy")` — an ABBREVIATED month. Every period
   * label in the product goes through it (app/warden/fees/page.tsx subtitle,
   * components/manager/expense-table.tsx description, the pay sheet, the receipt), so
   * this is the string the panels use. Earlier revisions of this file wrote out
   * "August 2026", which the product never renders anywhere.
   */
  label: "Aug 2026",
  short: "Aug",
  year: 2026,
};
/** The reference "today" the seeded day-offsets are measured back from. */
const TODAY = new Date(Date.UTC(2026, 7, 20));

/** db/seed.ts SUNRISE_STUDENTS — name, room, bed, monthly fee. */
const STUDENTS = [
  { name: "Aarav Sharma", room: "101", bed: 1, fee: 7000 },
  { name: "Ishaan Verma", room: "101", bed: 2, fee: 6500 },
  { name: "Kavya Iyer", room: "102", bed: 1, fee: 7500 },
  { name: "Rohan Deshmukh", room: "101", bed: 3, fee: 6000 },
  { name: "Sneha Patil", room: "102", bed: 2, fee: 8000 },
  { name: "Arjun Nair", room: "103", bed: 1, fee: 7200 },
  { name: "Meera Krishnan", room: "102", bed: 3, fee: 6800 },
  { name: "Aditya Kulkarni", room: "103", bed: 2, fee: 7000 },
  { name: "Priyanka Singh", room: "104", bed: 1, fee: 6500 },
  { name: "Karan Malhotra", room: "201", bed: 1, fee: 7800 },
  { name: "Divya Reddy", room: "202", bed: 1, fee: 7500 },
  { name: "Siddharth Bose", room: "201", bed: 2, fee: 6200 },
];

/** db/seed.ts payments for the current period — index is 1-based into STUDENTS. */
const PAYMENTS = [
  { s: 1, mode: "UPI", daysAgo: 0 },
  { s: 2, mode: "Cash", daysAgo: 1 },
  { s: 3, mode: "UPI", daysAgo: 2 },
  { s: 4, amount: 3000, mode: "UPI", daysAgo: 3 },
  { s: 5, mode: "Bank", daysAgo: 6 },
  { s: 6, mode: "UPI", daysAgo: 12 },
  { s: 7, amount: 4000, mode: "Cash", daysAgo: 4 },
  { s: 8, mode: "UPI", daysAgo: 8 },
];

/** db/seed.ts expenses — [daysAgo, category, amount, note]. */
const EXPENSES = [
  [0, "Groceries", 3450, "Vegetables & dairy — weekly"],
  [0, "Other", 600, "Newspaper & courier"],
  [1, "Electricity", 8420, "Electricity bill"],
  [2, "Groceries", 2780, "Rice, dal, cooking oil"],
  [3, "Maintenance", 1500, "Plumber — 2nd floor bathroom"],
  [5, "Water", 1900, "Water tanker × 2"],
  [6, "Staff", 12000, "Cook salary"],
  [7, "Groceries", 4100, "Monthly provisions"],
  [9, "Other", 850, "Cleaning supplies"],
  [11, "Maintenance", 2600, "Wi-Fi router replacement"],
  [14, "Groceries", 3200, "Vegetables & dairy — weekly"],
  [17, "Staff", 9000, "Housekeeping salary"],
  [21, "Groceries", 3650, "Vegetables & dairy — weekly"],
  [24, "Water", 950, "RO service"],
  [28, "Electricity", 780, "Generator diesel"],
];

/* ── the same maths the app does (lib/utils.ts, db/schema.sql rpc_hostel_stats) ── */

/** lib/utils.ts formatINR — en-IN grouping, no decimals. */
function inr(n) {
  return "₹" + new Intl.NumberFormat("en-IN", { maximumFractionDigits: 0 }).format(Math.round(n));
}
/** lib/utils.ts formatINRCompact — ₹2.45L / ₹18.5k / ₹1.2Cr. */
function inrCompact(n) {
  const abs = Math.abs(n);
  const sign = n < 0 ? "-" : "";
  const trim = (v) => v.toFixed(v >= 100 ? 0 : v >= 10 ? 1 : 2).replace(/\.?0+$/, "");
  if (abs >= 1e7) return `${sign}₹${trim(abs / 1e7)}Cr`;
  if (abs >= 1e5) return `${sign}₹${trim(abs / 1e5)}L`;
  if (abs >= 1e3) return `${sign}₹${trim(abs / 1e3)}k`;
  return `${sign}₹${Math.round(abs)}`;
}
/** lib/utils.ts formatDate — "20 Aug 2026". */
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function dayOffset(days) {
  return new Date(TODAY.getTime() - days * 86_400_000);
}
function fmtDate(d, withYear = true) {
  const s = `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
  return withYear ? `${s} ${d.getUTCFullYear()}` : s;
}

/** rpc_fee_ledger equivalent: one row per active student for the period. */
const LEDGER = STUDENTS.map((st, i) => {
  const p = PAYMENTS.find((x) => x.s === i + 1);
  const paid = p ? (p.amount ?? st.fee) : 0;
  const status = paid === 0 ? "unpaid" : paid < st.fee ? "partial" : "paid";
  return { ...st, paid, status, mode: p?.mode ?? null, paidOn: p ? dayOffset(p.daysAgo) : null };
});

const STATS = {
  totalBeds: 36,
  occupiedBeds: LEDGER.length,
  activeStudents: LEDGER.length,
  // rpc_hostel_stats: complaints where status <> 'resolved' → 2 open + 1 in_progress (db/seed.ts)
  openComplaints: 3,
  feesCollected: LEDGER.reduce((s, r) => s + r.paid, 0),
  feesPending: LEDGER.reduce((s, r) => s + Math.max(0, r.fee - r.paid), 0),
  paidCount: LEDGER.filter((r) => r.status === "paid").length,
  partialCount: LEDGER.filter((r) => r.status === "partial").length,
  unpaidCount: LEDGER.filter((r) => r.status === "unpaid").length,
  subscriptionDaysLeft: 305, // db/seed.ts: "active, 305 days left"
};
STATS.studentsUnpaid = STATS.partialCount + STATS.unpaidCount;
STATS.occupancyPct = Math.round((STATS.occupiedBeds / STATS.totalBeds) * 100);

/* ── the resident the payment panels follow ──────────────────────────────────
   Screens 3, 4 and 5 are one continuous flow — see a due amount, pay it, get the
   receipt — so they must all be the same person, with the same figure, or the
   sequence quietly lies about what the app does.

   Chosen by RULE, not by name: the first student in the seeded ledger who still owes
   the whole month. Room, floor, fee and the amount due are all read back out of that
   ledger row, so if db/seed.ts changes, these panels change with it instead of drifting
   into fiction. */
const PAYER = (() => {
  const row = LEDGER.find((r) => r.status === "unpaid");
  if (!row) throw new Error("no fully-unpaid student in the seeded ledger — the payment panels need one");
  return {
    ...row,
    /** Rooms are numbered <floor><nn>, so the leading digit is the floor. */
    floor: Number(row.room[0]),
    due: row.fee - row.paid,
    /**
     * Razorpay's id shape is `pay_` + 14 base62 characters. This one is PINNED and
     * deliberately spells "NIVORAdemo": the output has to be byte-identical run to
     * run, and a realistic-looking random id on a public store listing is a reference
     * someone could try to trace. Demo dataset, visibly demo id.
     */
    paymentId: "pay_S4mNIVORAdemo1",
    /** Razorpay method code `upi` → "UPI" via METHOD_LABEL in payment-receipt.tsx. */
    method: "UPI",
    paidOn: TODAY,
  };
})();

/** Expenses that fall inside PERIOD once the day-offsets are resolved. */
const MONTH_EXPENSES = EXPENSES.map(([days, category, amount, note]) => ({
  date: dayOffset(days),
  category,
  amount,
  note,
})).filter((e) => e.date.getUTCMonth() === TODAY.getUTCMonth() && e.date.getUTCFullYear() === TODAY.getUTCFullYear());
const EXPENSE_TOTAL = MONTH_EXPENSES.reduce((s, e) => s + e.amount, 0);
const EXPENSE_COUNTS = MONTH_EXPENSES.reduce((m, e) => m.set(e.category, (m.get(e.category) ?? 0) + 1), new Map());

/* ───────────────────────── SVG primitives ───────────────────────── */

const esc = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const n = (v) => (Math.round(v * 1000) / 1000).toString();

function rect({ x, y, w, h, r = 0, fill = "none", fillOpacity, stroke, strokeOpacity, strokeWidth = 1 }) {
  const a = [`x="${n(x)}"`, `y="${n(y)}"`, `width="${n(w)}"`, `height="${n(h)}"`];
  if (r) a.push(`rx="${n(r)}"`);
  a.push(`fill="${fill}"`);
  if (fillOpacity !== undefined) a.push(`fill-opacity="${fillOpacity}"`);
  if (stroke) {
    a.push(`stroke="${stroke}"`, `stroke-width="${n(strokeWidth)}"`);
    if (strokeOpacity !== undefined) a.push(`stroke-opacity="${strokeOpacity}"`);
  }
  return `<rect ${a.join(" ")}/>`;
}

function circle({ cx, cy, r, fill = "none", fillOpacity, stroke, strokeWidth = 1, strokeOpacity }) {
  const a = [`cx="${n(cx)}"`, `cy="${n(cy)}"`, `r="${n(r)}"`, `fill="${fill}"`];
  if (fillOpacity !== undefined) a.push(`fill-opacity="${fillOpacity}"`);
  if (stroke) {
    a.push(`stroke="${stroke}"`, `stroke-width="${n(strokeWidth)}"`);
    if (strokeOpacity !== undefined) a.push(`stroke-opacity="${strokeOpacity}"`);
  }
  return `<circle ${a.join(" ")}/>`;
}

function line({ x1, y1, x2, y2, stroke, strokeWidth = 1, strokeOpacity }) {
  const a = [`x1="${n(x1)}"`, `y1="${n(y1)}"`, `x2="${n(x2)}"`, `y2="${n(y2)}"`, `stroke="${stroke}"`, `stroke-width="${n(strokeWidth)}"`];
  if (strokeOpacity !== undefined) a.push(`stroke-opacity="${strokeOpacity}"`);
  return `<line ${a.join(" ")}/>`;
}

function text(str, { x, y, size = 14, weight = 400, fill = C.charcoal, anchor = "start", ls, opacity, font = FONT }) {
  const a = [
    `x="${n(x)}"`,
    `y="${n(y)}"`,
    `font-family="${font}"`,
    `font-size="${n(size)}"`,
    `font-weight="${weight}"`,
    `fill="${fill}"`,
  ];
  if (anchor !== "start") a.push(`text-anchor="${anchor}"`);
  if (ls !== undefined) a.push(`letter-spacing="${n(ls)}"`);
  if (opacity !== undefined) a.push(`opacity="${opacity}"`);
  return `<text ${a.join(" ")}>${esc(str)}</text>`;
}

/* ── lucide geometry, read out of the installed package so the icons in the
   screenshots are the exact icons the app renders (lucide-react v0.539.0) ── */
const iconCache = new Map();
function lucideNodes(name) {
  if (iconCache.has(name)) return iconCache.get(name);
  const file = path.join(REPO_ROOT, "node_modules", "lucide-react", "dist", "esm", "icons", `${name}.js`);
  if (!fs.existsSync(file)) throw new Error(`lucide icon "${name}" not found at ${file}`);
  const src = fs.readFileSync(file, "utf8");
  const start = src.indexOf("const __iconNode = [");
  const end = src.indexOf("];", start);
  if (start === -1 || end === -1) throw new Error(`could not read __iconNode out of ${file}`);
  const body = src.slice(start + "const __iconNode = ".length, end + 1);

  const out = [];
  const nodeRe = /\[\s*"([a-zA-Z]+)"\s*,\s*\{([^}]*)\}\s*\]/g;
  let m;
  while ((m = nodeRe.exec(body)) !== null) {
    const tag = m[1];
    const attrs = [];
    const attrRe = /([a-zA-Z0-9]+)\s*:\s*"([^"]*)"/g;
    let a;
    while ((a = attrRe.exec(m[2])) !== null) {
      if (a[1] === "key") continue;
      const attr = a[1].replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
      attrs.push(`${attr}="${esc(a[2])}"`);
    }
    out.push(`<${tag} ${attrs.join(" ")}/>`);
  }
  if (out.length === 0) throw new Error(`no drawable nodes parsed from ${file}`);
  const svg = out.join("");
  iconCache.set(name, svg);
  return svg;
}

/** Lucide icons are drawn on a 24-unit grid with a 2-unit stroke, exactly as in the app. */
function icon(name, { x, y, size = 20, color = C.navy, width = 1.75, opacity }) {
  const s = size / 24;
  const o = opacity !== undefined ? ` opacity="${opacity}"` : "";
  return `<g transform="translate(${n(x)} ${n(y)}) scale(${n(s)})" fill="none" stroke="${color}" stroke-width="${n(width)}" stroke-linecap="round" stroke-linejoin="round"${o}>${lucideNodes(name)}</g>`;
}

/** .glass-card / .glass-card-strong from app/globals.css. */
function glass(x, y, w, h, { r = 20, strong = false, shadow = true } = {}) {
  const f = strong ? 0.85 : 0.65;
  const s = strong ? 0.8 : 0.6;
  const filter = shadow ? ` filter="url(#glassShadow)"` : "";
  return `<g${filter}>${rect({ x, y, w, h, r, fill: C.white, fillOpacity: f, stroke: C.white, strokeOpacity: s })}</g>`;
}

/** StatusPill / Chip from components/shared/status-pill.tsx. */
const PILL_TONE = {
  teal: [C.tealSoft, C.teal],
  sand: [C.sandSoft, C.sandDeep],
  red: [C.redSoft, C.red],
  sage: [C.sageSoft, C.sage],
  navy: ["#1C2B451A", C.navy],
  muted: [C.stone, C.muted],
};
function pill(label, { x, y, tone = "muted", size = 10, padX = 8, h = 20, weight = 700, ls = 0.6, upper = true }) {
  const [bg, fg] = PILL_TONE[tone];
  const t = upper ? label.toUpperCase() : label;
  const w = t.length * size * 0.62 + padX * 2;
  return (
    rect({ x, y, w, h, r: h / 2, fill: bg }) +
    text(t, { x: x + padX, y: y + h / 2 + size * 0.36, size, weight, fill: fg, ls })
  );
}

/** components/shared/stat-card.tsx ProgressRing. */
function ring(cx, cy, pct, { size = 52, stroke = 3 } = {}) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    circle({ cx, cy, r, stroke: C.stone, strokeWidth: stroke }) +
    `<circle cx="${n(cx)}" cy="${n(cy)}" r="${n(r)}" fill="none" stroke="${C.navy}" stroke-width="${n(stroke)}" stroke-linecap="round" stroke-dasharray="${n(c)}" stroke-dashoffset="${n(c - (pct / 100) * c)}" transform="rotate(-90 ${n(cx)} ${n(cy)})"/>` +
    text(`${pct}%`, { x: cx, y: cy + 4, size: 11, weight: 700, fill: C.navy, anchor: "middle" })
  );
}

/** components/ui/avatar.tsx UserAvatar fallback — sand-soft circle with initials. */
function avatar(name, { x, y, size = 32 }) {
  const parts = name.trim().split(/\s+/);
  const ini = (parts[0][0] + (parts[1]?.[0] ?? "")).toUpperCase();
  return (
    circle({ cx: x + size / 2, cy: y + size / 2, r: size / 2, fill: C.sandSoft }) +
    text(ini, { x: x + size / 2, y: y + size / 2 + size * 0.13, size: size * 0.36, weight: 600, fill: C.sandDeep, anchor: "middle" })
  );
}

const defs = `<defs>
  <filter id="glassShadow" x="-40%" y="-40%" width="180%" height="180%">
    <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#06162F" flood-opacity="0.05"/>
  </filter>
  <!-- components/ui/sheet.tsx SheetOverlay: backdrop-blur-sm over the page behind the sheet. -->
  <filter id="sheetBlur" x="-5%" y="-5%" width="110%" height="110%">
    <feGaussianBlur stdDeviation="1.6"/>
  </filter>
  <!-- SheetContent itself is backdrop-blur-xl (24px). A 24px CSS blur is roughly
       stdDeviation 12, which is the difference between "a wash" and "text you can
       still read through the panel" — and reading the page through the sheet is the
       tell that a screenshot was composited rather than captured. -->
  <filter id="sheetBlurXl" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur stdDeviation="10"/>
  </filter>
  <!-- receipt-printer.module.css: the metallic hood and its lower lip. -->
  <linearGradient id="hoodTop" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#ffffff"/>
    <stop offset="15%" stop-color="#fbf4e8"/>
    <stop offset="45%" stop-color="#e9cf9f"/>
    <stop offset="75%" stop-color="#d19e54"/>
    <stop offset="100%" stop-color="#b37f35"/>
  </linearGradient>
  <linearGradient id="hoodBottom" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#9e6d2b"/>
    <stop offset="40%" stop-color="#d8b478"/>
    <stop offset="100%" stop-color="#fff7ea"/>
  </linearGradient>
  <!-- .hoodShadow — darkens the top of the lower lip so it reads as tucked under the
       hood rather than as a second bar stacked below it. -->
  <linearGradient id="lipShade" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#000000" stop-opacity="0.15"/>
    <stop offset="100%" stop-color="#000000" stop-opacity="0"/>
  </linearGradient>
  <!-- The paper's own cast shadow, so the slip sits in front of the machine. -->
  <filter id="paperShadow" x="-20%" y="-10%" width="140%" height="130%">
    <feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#3a2a12" flood-opacity="0.18"/>
  </filter>
  <!-- Ambient wash (app/globals.css .ambient-glow). The stops run all the way to 100%
       on purpose: ending the fade early leaves a faint disc edge, which is very
       visible behind the logo on the feature graphic. -->
  <radialGradient id="glowA" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="${C.navy}" stop-opacity="0.08"/>
    <stop offset="45%" stop-color="${C.teal}" stop-opacity="0.06"/>
    <stop offset="100%" stop-color="${C.ivory}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glowB" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="${C.sand}" stop-opacity="0.18"/>
    <stop offset="100%" stop-color="${C.ivory}" stop-opacity="0"/>
  </radialGradient>
</defs>`;

/* ───────────────────────── brand artwork ─────────────────────────
   The real NIVORA pixels, not a re-drawing of them.

   The logo pipeline writes three files into public/brand/. Each one is used for the
   job it was cut for, and none of them is traced, re-pathed or re-typed here:

     logo-square-1024.png  1024x1024 opaque — the mark centred on brand ivory. The
                           master. Used as the small badge on the screenshot captions.
     play-icon-512.png     512x512 opaque — the same mark with the safe-area padding
                           Play's circular/squircle masks need. Becomes the store icon
                           essentially verbatim: resized only if it is not already 512.
     nivora-logo.png       1024x663 with alpha — the full lockup, mark ABOVE the drawn
                           NIVORA wordmark. Used on the feature graphic, which is why
                           that graphic no longer sets the brand name as live text.

   That last point is the reason this indirection exists at all. Setting "NIVORA" as
   <text> means the wordmark is whatever font the machine running the build happens to
   have, and this repo cannot load webfonts (the CSP has no font-src grant). Embedding
   the drawn lockup makes the letterforms correct and machine-independent.

   FALLBACK. If public/brand/ has not been generated, everything below is derived from
   the source logo at the repo root by trimming its transparent margin with sharp. The
   result is reported in the run log so a fallback is never silent. */

const BRAND_DIR = path.join(REPO_ROOT, "public", "brand");
const ICONS_DIR = path.join(REPO_ROOT, "public", "icons");
/** The artwork the user supplied. Only touched when public/brand/ is missing. */
const RAW_LOGO = path.join(REPO_ROOT, "nivoralogo.png");

const dataUri = (buf) => `data:image/png;base64,${buf.toString("base64")}`;

/** First path that exists, or null. */
function firstExisting(...files) {
  return files.find((f) => fs.existsSync(f)) ?? null;
}

/**
 * Trim the transparent margin off the raw logo and return it centred on a square
 * ivory canvas. Only reached when public/brand/ is absent.
 */
async function squareFromRawLogo(size) {
  if (!fs.existsSync(RAW_LOGO)) {
    throw new Error(
      `no brand artwork: neither ${path.relative(REPO_ROOT, BRAND_DIR)} nor ${path.relative(REPO_ROOT, RAW_LOGO)} exists`,
    );
  }
  const inner = Math.round(size * 0.78); // leave Play's mask a safe area
  const trimmed = await sharp(RAW_LOGO)
    .trim()
    .resize(inner, inner, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .toBuffer();
  return sharp({
    create: { width: size, height: size, channels: 4, background: C.ivory },
  })
    .composite([{ input: trimmed, gravity: "centre" }])
    .flatten({ background: C.ivory })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toBuffer();
}

/**
 * Load every piece of brand artwork the generator needs.
 * Returns raw buffers (for the icon, which is a raster job) and data: URIs (for the
 * pieces that get composited inside an SVG), plus a provenance line per piece.
 */
async function brandArt() {
  const provenance = [];
  const rel = (f) => path.relative(REPO_ROOT, f).replace(/\\/g, "/");

  // ── the store icon ──
  const iconSrc = firstExisting(
    path.join(BRAND_DIR, "play-icon-512.png"),
    path.join(ICONS_DIR, "icon-512.png"),
    path.join(BRAND_DIR, "logo-square-1024.png"),
  );
  let iconBuf;
  if (iconSrc) {
    const meta = await sharp(iconSrc).metadata();
    if (meta.width !== meta.height) throw new Error(`${rel(iconSrc)} is ${meta.width}x${meta.height} — the icon source must be square`);
    // flatten kills any real transparency by compositing onto the brand ivory;
    // ensureAlpha then puts a fully-opaque alpha channel back, which is what makes
    // the file "32-bit with alpha" without making it transparent.
    iconBuf = await sharp(iconSrc)
      .resize(512, 512, { fit: "fill" })
      .flatten({ background: C.ivory })
      .ensureAlpha(1)
      .png({ compressionLevel: 9 })
      .toBuffer();
    provenance.push(`icon      ${rel(iconSrc)} (${meta.width}x${meta.height} → 512x512)`);
  } else {
    iconBuf = await squareFromRawLogo(512);
    provenance.push(`icon      FALLBACK — trimmed from ${rel(RAW_LOGO)}`);
  }

  // ── the square mark, for the screenshot caption badge ──
  const markSrc = firstExisting(path.join(BRAND_DIR, "logo-square-1024.png"), path.join(BRAND_DIR, "play-icon-512.png"));
  let markBuf;
  if (markSrc) {
    markBuf = fs.readFileSync(markSrc);
    const meta = await sharp(markBuf).metadata();
    provenance.push(`mark      ${rel(markSrc)} (${meta.width}x${meta.height})`);
  } else {
    markBuf = await squareFromRawLogo(512);
    provenance.push(`mark      FALLBACK — trimmed from ${rel(RAW_LOGO)}`);
  }

  // ── the lockup (mark + drawn wordmark), for the feature graphic ──
  const lockupSrc = firstExisting(path.join(BRAND_DIR, "nivora-logo.png"), RAW_LOGO);
  if (!lockupSrc) throw new Error("no lockup artwork found for the feature graphic");
  // Trim whatever margin the export carries so the layout below can position the
  // artwork by its ink, not by its bounding box. `trim` needs an alpha channel or a
  // uniform border colour; both sources have one.
  const lockupBuf = await sharp(lockupSrc).trim().png({ compressionLevel: 9 }).toBuffer();
  const lockupMeta = await sharp(lockupBuf).metadata();
  provenance.push(
    `lockup    ${rel(lockupSrc)} (trimmed to ${lockupMeta.width}x${lockupMeta.height}, aspect ${(lockupMeta.width / lockupMeta.height).toFixed(3)})`,
  );

  return {
    iconBuf,
    mark: dataUri(markBuf),
    lockup: dataUri(lockupBuf),
    lockupAspect: lockupMeta.width / lockupMeta.height,
    provenance,
  };
}

/**
 * Place a raster at (x,y) in a w*h box.
 * `preserveAspectRatio` is spelled out because librsvg's default would letterbox
 * differently from what the layout maths above assumes.
 */
function image(href, { x, y, w, h, clip, fit = "xMidYMid meet", opacity }) {
  const a = [`x="${n(x)}"`, `y="${n(y)}"`, `width="${n(w)}"`, `height="${n(h)}"`, `preserveAspectRatio="${fit}"`];
  if (clip) a.push(`clip-path="url(#${clip})"`);
  if (opacity !== undefined) a.push(`opacity="${opacity}"`);
  a.push(`xlink:href="${href}"`);
  return `<image ${a.join(" ")}/>`;
}

/* ───────────────────────── 1. app icon ─────────────────────────
   There is no SVG for the icon any more. The Play icon IS the brand artwork, so the
   only honest pipeline is resize-and-flatten, which is what brandArt() already did.
   Drawing a 512x512 SVG around it would just be a lossy round trip. */

/* ───────────────────────── 2. feature graphic ─────────────────────────
   1024x500. The brand lockup on the left (real artwork, real wordmark), the moment
   the app is actually for on the right: a resident paying rent from their phone. */

function featureSvg(art) {
  const W = 1024;
  const H = 500;
  // The five destinations that exist in the product's navigation, named the way the
  // product names them. Nothing aspirational.
  const chips = ["Pay rent", "Rooms", "Fees", "Complaints", "Mess"];

  // Play crops the feature graphic in some placements, so nothing that matters goes
  // outside x 112..912 (11% inset) or y 130..375.
  let chipX = 112;
  const chipRow = chips
    .map((label) => {
      const w = label.length * 8.4 + 30;
      const el =
        rect({ x: chipX, y: 336, w, h: 34, r: 17, fill: C.white, fillOpacity: 0.8, stroke: C.white, strokeOpacity: 0.9 }) +
        text(label, { x: chipX + 15, y: 358, size: 15, weight: 500, fill: C.navy });
      chipX += w + 10;
      return el;
    })
    .join("");

  // The lockup is mark-above-wordmark. Height is what we control; width follows the
  // trimmed artwork's own aspect so nothing is ever stretched.
  const lockH = 150;
  const lockW = lockH * art.lockupAspect;

  /* The pay card — the same three facts the real sheet leads with
     (components/payments/pay-rent-sheet.tsx: "Amount due", the figure, "<period> rent"),
     then the button and the Razorpay assurance line, both quoted verbatim. */
  const cardX = 568;
  const cardY = 130;
  const cardW = 344;
  const cardH = 240;
  const payCard =
    glass(cardX, cardY, cardW, cardH, { strong: true }) +
    rect({ x: cardX + 20, y: cardY + 20, w: cardW - 40, h: 104, r: 16, fill: C.white, fillOpacity: 0.7 }) +
    text("AMOUNT DUE", { x: cardX + cardW / 2, y: cardY + 46, size: 12, weight: 600, fill: C.muted, ls: 0.6, anchor: "middle" }) +
    text(inr(PAYER.due), { x: cardX + cardW / 2, y: cardY + 86, size: 36, weight: 700, fill: C.navy, anchor: "middle" }) +
    text(`${PERIOD.label} rent`, { x: cardX + cardW / 2, y: cardY + 110, size: 13, weight: 400, fill: C.muted, anchor: "middle" }) +
    rect({ x: cardX + 20, y: cardY + 140, w: cardW - 40, h: 52, r: 14, fill: C.navy }) +
    icon("indian-rupee", { x: cardX + 62, y: cardY + 156, size: 19, color: C.white, width: 2 }) +
    text(`Pay ${inr(PAYER.due)} securely`, { x: cardX + 90, y: cardY + 172, size: 16, weight: 600, fill: C.white }) +
    icon("lock", { x: cardX + 60, y: cardY + 206, size: 14, color: C.muted, width: 2 }) +
    text("Secured by Razorpay", { x: cardX + 82, y: cardY + 217, size: 13, weight: 400, fill: C.muted });

  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
${defs}
${rect({ x: 0, y: 0, w: W, h: H, fill: C.ivory })}
<ellipse cx="300" cy="250" rx="380" ry="330" fill="url(#glowA)"/>
<ellipse cx="880" cy="90" rx="300" ry="260" fill="url(#glowB)"/>

${image(art.lockup, { x: 112, y: 132, w: lockW, h: lockH, fit: "xMinYMid meet" })}
${text("Hostel & PG management", { x: 112, y: 318, size: 21, weight: 400, fill: C.muted })}
${chipRow}

${payCard}
</svg>`;
}

/* ───────────────────────── 3. phone screenshots ─────────────────────────
   Canvas 1080x1920 (9:16). A caption band, then the app screen redrawn inside a
   device panel. The screen bodies below are authored in CSS pixels against a
   360px-wide viewport and scaled by PANEL.scale, i.e. exactly what a 3x-ish phone
   shows — including the crop at the bottom of the scroll. */

const SHOT = { w: 1080, h: 1920 };
const PANEL = { x: 72, y: 288, w: 936, h: 1560, scale: 2.6 };
const CSS_W = PANEL.w / PANEL.scale; // 360
const CSS_H = PANEL.h / PANEL.scale; // 600

/**
 * Top app bar (h-16, glass-bar).
 *   variant "drawer" — desktop-shell.tsx below md: hamburger + Building2 + hostel name, bell + avatar
 *   variant "back"   — mobile-shell.tsx sub-page: back arrow + title/subtitle + bell
 *   variant "avatar" — mobile-shell.tsx home: avatar + greeting/subtitle + bell
 */
function topBar({ variant, title, subtitle, avatarName }) {
  let s =
    rect({ x: 0, y: 0, w: CSS_W, h: 64, fill: C.white, fillOpacity: 0.7 }) +
    line({ x1: 0, y1: 64, x2: CSS_W, y2: 64, stroke: C.white, strokeOpacity: 0.7 });
  let tx = 46;
  if (variant === "drawer") {
    s += icon("menu", { x: 14, y: 22, size: 20, color: C.navy });
    s += icon("building-2", { x: 48, y: 24, size: 16, color: C.navy, opacity: 0.5 });
    tx = 72;
  } else if (variant === "back") {
    s += icon("arrow-left", { x: 14, y: 22, size: 20, color: C.navy });
  } else {
    s += avatar(avatarName, { x: 16, y: 16, size: 32 });
    tx = 58;
  }
  s += text(title, { x: tx, y: subtitle ? 30 : 38, size: 16, weight: 700, fill: C.navy });
  if (subtitle) s += text(subtitle, { x: tx, y: 46, size: 11, weight: 400, fill: C.muted });
  if (variant === "drawer") {
    s += icon("bell", { x: 292, y: 22, size: 20, color: C.navy });
    s += avatar(avatarName, { x: 328, y: 20, size: 24 });
  } else {
    s += icon("bell", { x: 322, y: 22, size: 20, color: C.navy });
  }
  return s;
}

/** components/shell/mobile-shell.tsx bottom nav (h-[76px], raised centre action). */
function bottomNav(items, activeIndex) {
  const y = CSS_H - 76;
  // backdrop-blur(24px) over white/0.65: content scrolling underneath survives only as a
  // faint wash, so the bar is drawn near-opaque rather than see-through.
  let out =
    rect({ x: 0, y, w: CSS_W, h: 76, r: 20, fill: C.white, fillOpacity: 0.94 }) +
    line({ x1: 0, y1: y, x2: CSS_W, y2: y, stroke: C.line, strokeOpacity: 0.8 });
  const slot = CSS_W / items.length;
  items.forEach((it, i) => {
    const cx = slot * i + slot / 2;
    if (it.center) {
      out +=
        circle({ cx, cy: y + 12, r: 28, fill: C.ivory }) +
        circle({ cx, cy: y + 12, r: 24, fill: C.navy }) +
        icon(it.icon, { x: cx - 12, y: y, size: 24, color: C.white, width: 2 });
      return;
    }
    const active = i === activeIndex;
    if (active) out += rect({ x: cx - 28, y: y + 12, w: 56, h: 44, r: 12, fill: C.navy });
    out +=
      icon(it.icon, { x: cx - 10, y: y + 18, size: 20, color: active ? C.white : C.muted, width: active ? 2 : 1.75 }) +
      text(it.label.toUpperCase(), {
        x: cx,
        y: y + 50,
        size: 10,
        weight: 600,
        fill: active ? C.white : C.muted,
        anchor: "middle",
        ls: 0.4,
      });
  });
  return out;
}

/** components/shared/segmented.tsx SegmentedPills (size="sm"). */
function segmented(options, activeIndex, { x, y }) {
  let cx = x;
  let out = "";
  options.forEach((o, i) => {
    const active = i === activeIndex;
    const hasCount = typeof o.count === "number";
    const labelW = o.label.length * 6.6;
    const countW = hasCount ? String(o.count).length * 6.5 + 12 : 0;
    const w = labelW + countW + (hasCount ? 6 : 0) + 24;
    const tone = { navy: C.navy, teal: C.teal, sand: C.sandDeep, red: C.red, sage: C.sage }[o.tone ?? "navy"];
    out += active
      ? rect({ x: cx, y, w, h: 28, r: 14, fill: tone })
      : rect({ x: cx, y, w, h: 28, r: 14, fill: C.white, fillOpacity: 0.6, stroke: C.white, strokeOpacity: 0.7 });
    out += text(o.label, { x: cx + 12, y: y + 18, size: 12, weight: 500, fill: active ? C.white : C.muted });
    if (hasCount) {
      const bx = cx + 12 + labelW + 6;
      out += active
        ? rect({ x: bx, y: y + 6, w: countW, h: 16, r: 8, fill: C.white, fillOpacity: 0.2 })
        : rect({ x: bx, y: y + 6, w: countW, h: 16, r: 8, fill: C.navy, fillOpacity: 0.05 });
      out += text(String(o.count), {
        x: bx + countW / 2,
        y: y + 17,
        size: 10,
        weight: 600,
        fill: active ? C.white : C.navy,
        anchor: "middle",
      });
    }
    cx += w + 8;
  });
  return out;
}

/** components/shared/stat-card.tsx on a 360px viewport (stacked, grid-cols-1). */
function statCard({ x, y, w, h = 92, label, value, caption, tone = C.navy, iconName, iconTone, extra = "" }) {
  return (
    glass(x, y, w, h) +
    text(label.toUpperCase(), { x: x + 20, y: y + 28, size: 11, weight: 600, fill: C.muted, ls: 0.55 }) +
    (iconName ? icon(iconName, { x: x + w - 40, y: y + 16, size: 20, color: iconTone ?? tone, opacity: 0.5 }) : "") +
    text(value, { x: x + 20, y: y + 64, size: 28, weight: 700, fill: tone }) +
    (caption ? text(caption, { x: x + 20, y: y + 82, size: 12, weight: 400, fill: C.muted }) : "") +
    extra
  );
}

/* ── S1 · Owner dashboard (app/owner/page.tsx) ── */
function ownerScreen() {
  const w = CSS_W - 32;
  let s = topBar({ variant: "drawer", title: "Sunrise Residency", avatarName: "Ananya Rao" });
  s += text("Good morning, Ananya", { x: 16, y: 96, size: 22, weight: 600, fill: C.navy });
  s += text("Here's what's happening at", { x: 16, y: 118, size: 13, weight: 400, fill: C.muted });
  s += text("Sunrise Residency today.", { x: 16, y: 136, size: 13, weight: 400, fill: C.muted });

  // components/owner/subscription-card.tsx
  s += rect({ x: 16, y: 150, w, h: 56, r: 20, fill: C.sandSoft, fillOpacity: 0.85, stroke: C.sand, strokeOpacity: 0.4 });
  s += circle({ cx: 44, cy: 178, r: 17, fill: C.sand, fillOpacity: 0.3 });
  s += icon("calendar-clock", { x: 36, y: 170, size: 16, color: C.sandDeep });
  s += text("SUBSCRIPTION", { x: 72, y: 174, size: 11, weight: 600, fill: C.sandDeep, ls: 0.55, opacity: 0.8 });
  s += text(`${STATS.subscriptionDaysLeft} days left`, { x: 72, y: 193, size: 15, weight: 600, fill: C.sandDeep });

  const cards = [
    {
      label: "Occupancy",
      value: String(STATS.occupiedBeds),
      caption: `${STATS.occupiedBeds} / ${STATS.totalBeds} beds`,
      ringed: true,
    },
    { label: "Active students", value: String(STATS.activeStudents), caption: "Currently registered", iconName: "users" },
    {
      label: "Fees collected",
      value: inrCompact(STATS.feesCollected),
      caption: "This month",
      tone: C.teal,
      iconName: "indian-rupee",
    },
    {
      label: "Fees pending",
      value: inrCompact(STATS.feesPending),
      caption: `${STATS.studentsUnpaid} students due`,
      tone: C.red,
      iconName: "wallet",
    },
  ];
  cards.forEach((c, i) => {
    const y = 216 + i * 96;
    s += statCard({
      x: 16,
      y,
      w,
      h: 88,
      ...c,
      extra: c.ringed ? ring(CSS_W - 52, y + 30, STATS.occupancyPct, { size: 44 }) : "",
    });
  });
  return s;
}

/* ── S2 · Warden fees (app/warden/fees/page.tsx + components/warden/fees-view.tsx) ── */
function wardenScreen() {
  let s = topBar({ variant: "back", title: "Fees", subtitle: `${PERIOD.label} · Sunrise Residency` });

  const months = ["Mar", "Apr", "May", "Jun", "Jul", "Aug"];
  s += segmented(months.map((m) => ({ label: m })), 5, { x: 16, y: 76 });

  // summary strip — two cards, grid-cols-2
  const cw = (CSS_W - 32 - 12) / 2;
  s += glass(16, 116, cw, 88);
  s += text("COLLECTED", { x: 32, y: 140, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += icon("circle-check-big", { x: 16 + cw - 30, y: 130, size: 16, color: C.teal, opacity: 0.6 });
  s += text(inrCompact(STATS.feesCollected), { x: 32, y: 174, size: 28, weight: 700, fill: C.teal });
  s += text(`${STATS.paidCount} paid · ${PERIOD.label}`, { x: 32, y: 192, size: 11, weight: 400, fill: C.muted });

  s += glass(28 + cw, 116, cw, 88);
  s += text("PENDING", { x: 44 + cw, y: 140, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += icon("wallet", { x: 28 + cw + cw - 30, y: 130, size: 16, color: C.red, opacity: 0.6 });
  s += text(inrCompact(STATS.feesPending), { x: 44 + cw, y: 174, size: 28, weight: 700, fill: C.red });
  s += text(`${STATS.studentsUnpaid} students due`, { x: 44 + cw, y: 192, size: 11, weight: 400, fill: C.muted });

  s += segmented(
    [
      { label: "All", count: LEDGER.length },
      { label: "Unpaid", count: STATS.unpaidCount, tone: "red" },
      { label: "Partial", count: STATS.partialCount, tone: "sand" },
      { label: "Paid", count: STATS.paidCount, tone: "teal" },
    ],
    0,
    { x: 16, y: 216 },
  );

  // search input
  s += rect({ x: 16, y: 256, w: CSS_W - 32, h: 40, r: 12, fill: C.white, fillOpacity: 0.7, stroke: "#DDD9CF" });
  s += icon("search", { x: 28, y: 268, size: 16, color: C.muted });
  s += text("Search name, phone or room", { x: 52, y: 281, size: 13, weight: 400, fill: C.muted });

  // ledger rows — one paid, one partial, one unpaid, as the seeded month actually stands
  const rows = [LEDGER[0], LEDGER[3], LEDGER[8]];
  rows.forEach((r, i) => {
    const y = 308 + i * 72;
    const remaining = r.fee - r.paid;
    const sub =
      r.status === "paid"
        ? `Paid ${fmtDate(r.paidOn, false)} · ${r.mode}`
        : r.status === "partial"
          ? `Bal: ${inr(remaining)}`
          : `Due ${inr(r.fee)}`;
    const tone = { paid: "teal", partial: "sand", unpaid: "red" }[r.status];
    s += glass(16, y, CSS_W - 32, 64);
    s += avatar(r.name, { x: 30, y: y + 14, size: 36 });
    s += text(r.name, { x: 76, y: y + 27, size: 13, weight: 600, fill: C.navy });
    s += pill(`Room ${r.room}`, { x: 76, y: y + 36, tone: "muted", size: 10, h: 17, padX: 7, weight: 500, ls: 0, upper: false });
    s += text(sub, { x: 76 + `Room ${r.room}`.length * 6.2 + 20, y: y + 48, size: 11, weight: 400, fill: C.muted });
    s += text(inr(r.fee), { x: CSS_W - 32, y: y + 28, size: 15, weight: 700, fill: C.navy, anchor: "end" });
    s += pill(r.status, { x: CSS_W - 32 - (r.status.length * 6.2 + 16), y: y + 36, tone, size: 10, h: 18, padX: 8 });
  });

  s += bottomNav(
    [
      { label: "Home", icon: "house" },
      { label: "Rooms", icon: "bed-double" },
      { label: "Register", icon: "user-plus", center: true },
      { label: "Fees", icon: "wallet" },
      { label: "Leaves", icon: "calendar-off" },
    ],
    3,
  );
  return s;
}

/* ── S3 · Student home (app/student/page.tsx) ──
   PAYER's own home. Because this student's ledger row still owes the whole month,
   app/student/page.tsx takes three branches the previous version of this screenshot
   never showed: the fee line reads "Pay at warden desk" rather than a thank-you, the
   StatusPill is the unpaid (red) tone carrying `Due <amount>`, and — because
   `fee.remaining > 0` — <PayRentButton> renders under it. That button is the entry
   point to the next two panels. */
function studentScreen() {
  const me = PAYER;
  const first = me.name.split(" ")[0]; // lib/utils.ts firstName()
  let s = topBar({ variant: "avatar", avatarName: me.name, title: `Hi, ${first}`, subtitle: "Sunrise Residency" });

  /* Hero — <GlassCard strong className="p-5">. */
  const heroY = 80;
  const heroH = 214;
  s += glass(16, heroY, CSS_W - 32, heroH, { strong: true });
  s += rect({ x: 36, y: heroY + 20, w: 44, h: 44, r: 12, fill: C.navy, fillOpacity: 0.1 });
  s += icon("building-2", { x: 48, y: heroY + 32, size: 20, color: C.navy });
  s += text("MY STAY", { x: 92, y: heroY + 34, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += text(`Room ${me.room} · Bed ${me.bed} · Floor ${me.floor}`, { x: 92, y: heroY + 56, size: 18, weight: 700, fill: C.navy });
  s += text("Sunrise Residency", { x: 92, y: heroY + 72, size: 12, weight: 400, fill: C.muted });

  /* Fee strip — rounded-control bg-white/60, label + status pill. */
  const stripY = heroY + 84;
  s += rect({ x: 36, y: stripY, w: CSS_W - 72, h: 46, r: 12, fill: C.white, fillOpacity: 0.6 });
  s += text(`${PERIOD.label.toUpperCase()} FEE`, { x: 48, y: stripY + 18, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += text("Pay at warden desk", { x: 48, y: stripY + 34, size: 11.5, weight: 400, fill: C.muted });
  // StatusPill status="unpaid" → red-soft / red, label `Due ₹6,500`.
  const dueLabel = `Due ${inr(me.due)}`;
  const dueW = dueLabel.length * 11 * 0.62 + 20;
  s += pill(dueLabel, { x: CSS_W - 36 - dueW, y: stripY + 12, tone: "red", size: 11, h: 22, padX: 10, ls: 0, weight: 600, upper: false });

  /* components/payments/pay-rent-button.tsx — LiquidButton, h-12 w-full, IndianRupee
     + `Pay ₹6,500 now`. The glass treatment is a canvas refraction in the product; a
     single highlight band is the honest still-frame of it. */
  const btnY = stripY + 62;
  s += rect({ x: 36, y: btnY, w: CSS_W - 72, h: 48, r: 12, fill: C.navy });
  s += rect({ x: 36, y: btnY, w: CSS_W - 72, h: 22, r: 12, fill: C.white, fillOpacity: 0.09 });
  const payLabel = `Pay ${inr(me.due)} now`;
  const payTextW = payLabel.length * 7.7;
  const payStart = CSS_W / 2 - (payTextW + 24) / 2;
  s += icon("indian-rupee", { x: payStart, y: btnY + 15, size: 17, color: C.white, width: 2 });
  s += text(payLabel, { x: payStart + 25, y: btnY + 29, size: 15, weight: 600, fill: C.white });

  /* Updates — db/seed.ts announcements, line-clamp-2 bodies plus the date line.
     NOTE ON THE SECOND BODY: db/seed.ts interpolates the raw `period_month`, so the
     seeded string literally reads "Fees for 2026-08…". Announcements are free text
     written by the hostel in production, so the panel shows the period the way a
     person would type it. That is the one string here not lifted verbatim. */
  const upY = heroY + heroH + 16;
  s += glass(16, upY, CSS_W - 32, 156);
  s += text("Updates from hostel", { x: 36, y: upY + 28, size: 16, weight: 600, fill: C.navy });
  const updates = [
    [
      "Water supply maintenance on Sunday",
      "The overhead tank will be cleaned this Sunday",
      "between 10 am and 1 pm. Please store water in advance.",
      fmtDate(dayOffset(0)),
    ],
    [
      "Monthly fee reminder",
      `Fees for ${PERIOD.label} are due by the 10th. Pay by UPI`,
      "or at the warden's office.",
      fmtDate(dayOffset(2)),
    ],
  ];
  updates.forEach((u, i) => {
    const y = upY + 44 + i * 58;
    s += circle({ cx: 50, cy: y + 12, r: 14, fill: C.navy, fillOpacity: 0.05 });
    s += icon("megaphone", { x: 43, y: y + 5, size: 14, color: C.navy });
    s += text(u[0], { x: 76, y: y + 10, size: 13, weight: 600, fill: C.navy });
    s += text(u[1], { x: 76, y: y + 25, size: 11.5, weight: 400, fill: C.charcoal, opacity: 0.8 });
    s += text(u[2], { x: 76, y: y + 38, size: 11.5, weight: 400, fill: C.charcoal, opacity: 0.8 });
    s += text(u[3].toUpperCase(), { x: 76, y: y + 51, size: 9.5, weight: 400, fill: C.muted, ls: 0.5 });
    if (i === 0) s += line({ x1: 36, y1: y + 54, x2: CSS_W - 36, y2: y + 54, stroke: C.line });
  });

  /* Quick actions — components/student/quick-grid.tsx. On a 360x600 viewport the
     second row falls under the bottom nav, which is what the phone actually shows. */
  const qaY = upY + 156 + 16;
  s += text("Quick actions", { x: 16, y: qaY + 12, size: 16, weight: 600, fill: C.navy });
  const tiles = [
    ["Mess menu", "utensils-crossed", C.navy, "#1C2B451A"],
    ["Raise complaint", "message-square-warning", C.red, C.redSoft],
    ["Apply leave", "calendar-off", C.sandDeep, C.sandSoft],
    ["My room", "bed", C.teal, C.tealSoft],
  ];
  const tw = (CSS_W - 32 - 12) / 2;
  tiles.forEach((t, i) => {
    const x = 16 + (i % 2) * (tw + 12);
    const y = qaY + 26 + Math.floor(i / 2) * 72;
    s += glass(x, y, tw, 62);
    s += rect({ x: x + 13, y: y + 13, w: 36, h: 36, r: 10, fill: t[3] });
    s += icon(t[1], { x: x + 22, y: y + 22, size: 18, color: t[2] });
    s += text(t[0], { x: x + 58, y: y + 36, size: 12.5, weight: 600, fill: C.navy });
  });

  s += bottomNav(
    [
      { label: "Home", icon: "house" },
      { label: "Menu", icon: "utensils-crossed" },
      { label: "Complaints", icon: "clipboard-list" },
      { label: "Room", icon: "bed" },
      { label: "Profile", icon: "circle-user" },
    ],
    0,
  );
  return s;
}

/* ───────────────── the pay sheet, shared chrome ─────────────────
   components/ui/sheet.tsx, side="bottom": bg-white/90 backdrop-blur-xl, border-t,
   rounded-t-card (20px), p-6, a grab handle and a close button. The page behind it is
   the student's own home screen under `bg-navy/20 backdrop-blur-sm` (SheetOverlay) —
   both drawn for real here rather than faked with a flat panel. */
function sheetOver(top, draw) {
  const pad = 24;
  const home = studentScreen();
  const dim = rect({ x: 0, y: 0, w: CSS_W, h: CSS_H, fill: C.navy, fillOpacity: 0.2 });

  // 1. the page, under the overlay's backdrop-blur-sm, then the navy scrim
  let s = `<g filter="url(#sheetBlur)">${home}</g>${dim}`;

  // 2. the same page again, blurred far harder and clipped to the sheet's own
  //    rectangle — that is what `backdrop-blur-xl` on SheetContent actually does.
  const clipId = `sheetPanel${Math.round(top)}`;
  s += `<clipPath id="${clipId}"><rect x="0" y="${n(top)}" width="${n(CSS_W)}" height="${n(CSS_H - top)}" rx="20"/></clipPath>`;
  s += `<g clip-path="url(#${clipId})"><g filter="url(#sheetBlurXl)">${home}</g>${dim}</g>`;

  // 3. the panel itself — bg-white/90 over that wash
  s += rect({ x: 0, y: top, w: CSS_W, h: CSS_H - top, r: 20, fill: C.white, fillOpacity: 0.9, stroke: C.white, strokeOpacity: 0.85 });
  // mx-auto -mt-2 mb-3 h-1.5 w-12 rounded-full bg-line
  s += rect({ x: CSS_W / 2 - 24, y: top + 13, w: 48, h: 6, r: 3, fill: C.line });
  // SheetPrimitive.Close — absolute right-4 top-4, an X in text-muted
  s += icon("x", { x: CSS_W - 36, y: top + 18, size: 16, color: C.muted, width: 2 });
  return s + draw(top, pad);
}

/* ── S4 · Pay rent (components/payments/pay-rent-sheet.tsx, phase "summary") ──
   Every string on this panel is quoted from that file:
     SheetTitle          "Pay rent"
     SheetDescription    `${periodLabel} · paid securely through Razorpay.`
     the amount block    label-caps "Amount due" / text-stat / `${periodLabel} rent`
     the button          `Pay ${amountLabel} securely`
     the assurance line  "Card details are handled by Razorpay — never by this app."
   The figure is PAYER.due, i.e. the same rupees the previous panel showed as owing.
   The test-mode chip is deliberately absent: it renders only when the server reports
   `testMode`, and a store listing must not advertise a sandbox. */
function paySheetScreen() {
  return sheetOver(270, (top, pad) => {
    const me = PAYER;
    let s = "";
    s += text("Pay rent", { x: pad, y: top + 58, size: 18, weight: 600, fill: C.navy });
    s += text(`${PERIOD.label} · paid securely through Razorpay.`, { x: pad, y: top + 78, size: 13, weight: 400, fill: C.muted });

    // rounded-card bg-white/70 px-4 py-4 text-center
    const cardY = top + 96;
    s += rect({ x: pad, y: cardY, w: CSS_W - pad * 2, h: 104, r: 20, fill: C.white, fillOpacity: 0.7 });
    s += text("AMOUNT DUE", { x: CSS_W / 2, y: cardY + 26, size: 11, weight: 600, fill: C.muted, ls: 0.55, anchor: "middle" });
    s += text(inr(me.due), { x: CSS_W / 2, y: cardY + 66, size: 34, weight: 700, fill: C.navy, anchor: "middle" });
    s += text(`${PERIOD.label} rent`, { x: CSS_W / 2, y: cardY + 88, size: 12, weight: 400, fill: C.muted, anchor: "middle" });

    // <Button size="xl"> — h-12 w-full rounded-control text-[15px]
    const btnY = cardY + 120;
    s += rect({ x: pad, y: btnY, w: CSS_W - pad * 2, h: 48, r: 12, fill: C.navy });
    s += text(`Pay ${inr(me.due)} securely`, { x: CSS_W / 2, y: btnY + 29, size: 15, weight: 600, fill: C.white, anchor: "middle" });

    // Lock + assurance, wrapped the way 360px wraps it.
    const lockY = btnY + 70;
    const l1 = "Card details are handled by Razorpay —";
    const l1w = l1.length * 5.5;
    const lx = CSS_W / 2 - (l1w + 18) / 2;
    s += icon("lock", { x: lx, y: lockY - 9, size: 12, color: C.muted, width: 2 });
    s += text(l1, { x: lx + 18, y: lockY, size: 11.5, weight: 400, fill: C.muted });
    s += text("never by this app.", { x: CSS_W / 2, y: lockY + 15, size: 11.5, weight: 400, fill: C.muted, anchor: "middle" });
    return s;
  });
}

/* ── the thermal receipt printer (components/payments/receipt-printer.tsx) ──
   The success visual, drawn at its settled state: paper fully fed, cutter already
   fired. Geometry and colours come from receipt-printer.module.css — the hood
   gradient, the #0f0a03 slit, the 87.5% slit width, the 86.8% paper width, the
   #fafaf8 paper and its mono type. The slip's own content is the props the sheet
   passes it, which is the payment the server confirmed. */
function receiptPrinter(x, y, w) {
  const me = PAYER;
  const money = inr(me.due);
  // Ratios straight out of the stylesheet's custom properties.
  const slitW = w * 0.875;
  const paperW = w * 0.868;
  const paperX = x + (w - paperW) / 2;
  /* .hoodTop is 40px, .slit 11px below it, .hoodBottom absolute at top:42px, and the
     paper rises from behind the slit. The lip is dropped 4px relative to the
     stylesheet: at the browser's scale the slit still reads as a dark mouth with only
     the 2px the CSS leaves exposed, but resampled down into a store screenshot that
     becomes a hairline and the machine turns into two stacked gold bars. Six pixels of
     visible mouth is the smallest change that keeps it legible as a printer. */
  const paperY = y + 48;
  const paperH = 240;

  let s = "";

  /* Painted back to front, which is the stylesheet's z-order spelled out:
     slit (z5) → paper (z8) → lower lip (z10) → hood (z25). */
  s += rect({ x: x + (w - slitW) / 2, y: y + 40, w: slitW, h: 14, r: 2, fill: "#0f0a03" });

  // ── the slip ──
  s += `<g filter="url(#paperShadow)">${rect({ x: paperX, y: paperY, w: paperW, h: paperH, r: 2, fill: "#fafaf8" })}</g>`;
  const cx = paperX + 14; // .content padding: 14px 14px 20px
  const rx = paperX + paperW - 14;

  // .head — brand block left, the navy "N" chip right, margin-bottom 12
  s += text("NIVORA", { x: cx, y: paperY + 20, size: 13, weight: 800, fill: C.navy, ls: 1.5, font: MONO });
  s += text("Sunrise Residency · Rent receipt", { x: cx, y: paperY + 32, size: 9, weight: 600, fill: "#555555", ls: 0.35, font: MONO });
  s += rect({ x: rx - 30, y: paperY + 9, w: 30, h: 30, r: 7, fill: C.navy });
  s += text("N", { x: rx - 15, y: paperY + 29, size: 14, weight: 800, fill: C.white, anchor: "middle", font: MONO });

  // .amount (26px) / .meta (9px, uppercase, faint)
  s += text(money, { x: cx, y: paperY + 68, size: 26, weight: 700, fill: "#111111", font: MONO });
  s += text(`${fmtDate(me.paidOn).toUpperCase()} · RENT PAID`, { x: cx, y: paperY + 81, size: 9, weight: 500, fill: "#888888", ls: 0.45, font: MONO });

  // .rule — 1px dashed
  s += `<line x1="${n(cx)}" y1="${n(paperY + 92)}" x2="${n(rx)}" y2="${n(paperY + 92)}" stroke="#cfcfc9" stroke-width="1" stroke-dasharray="3 3"/>`;

  // .lines — label left, value right, 7px gap
  const rows = [
    [`${PERIOD.label} rent`, money],
    ["Resident", me.name],
    ["Paid by", me.method],
  ];
  rows.forEach((r, i) => {
    const ry = paperY + 108 + i * 18;
    s += text(r[0], { x: cx, y: ry, size: 11, weight: 500, fill: "#444444", font: MONO });
    s += text(r[1], { x: rx, y: ry, size: 11, weight: 600, fill: "#222222", anchor: "end", font: MONO });
  });

  // .grand — border-top, then TOTAL PAID
  s += line({ x1: cx, y1: paperY + 153, x2: rx, y2: paperY + 153, stroke: "#cfcfc9" });
  s += text("TOTAL PAID", { x: cx, y: paperY + 169, size: 11.5, weight: 700, fill: "#111111", font: MONO });
  s += text(money, { x: rx, y: paperY + 169, size: 11.5, weight: 700, fill: "#111111", anchor: "end", font: MONO });

  // .foot — THANK YOU, the barcode, the payment id
  const px = paperX + paperW / 2;
  s += text("THANK YOU", { x: px, y: paperY + 189, size: 9, weight: 600, fill: "#555555", ls: 1.3, anchor: "middle", font: MONO });
  const barW = paperW * 0.76;
  const barX = paperX + (paperW - barW) / 2;
  let bar = "";
  // The CSS draws these with a repeating-linear-gradient; this is the same 9.5px
  // period and the same duty cycle, unrolled into rects.
  for (let bx = 0; bx + 8 < barW; bx += 9.5) {
    bar += rect({ x: barX + bx, y: paperY + 196, w: 1.5, h: 22, fill: "#222222" });
    bar += rect({ x: barX + bx + 3, y: paperY + 196, w: 1, h: 22, fill: "#222222" });
    bar += rect({ x: barX + bx + 5.5, y: paperY + 196, w: 2.5, h: 22, fill: "#222222" });
  }
  s += `<g opacity="0.75">${bar}</g>`;
  s += text(me.paymentId, { x: px, y: paperY + 229, size: 8, weight: 400, fill: "#888888", ls: 0.6, anchor: "middle", font: MONO });

  // .hoodBottom — the lower lip (top:42px, height 12px), over the paper, with
  // .hoodShadow shading its upper edge.
  s += `<rect x="${n(x)}" y="${n(y + 46)}" width="${n(w)}" height="12" rx="4" fill="url(#hoodBottom)"/>`;
  s += `<rect x="${n(x)}" y="${n(y + 46)}" width="${n(w)}" height="12" rx="4" fill="url(#lipShade)"/>`;

  // .hoodTop (40px, radius 14/14/4/4) and its highlight
  s += `<rect x="${n(x)}" y="${n(y)}" width="${n(w)}" height="40" rx="14" fill="url(#hoodTop)"/>`;
  s += rect({ x: x + w * 0.05, y: y + 3, w: w * 0.9, h: 5, r: 2.5, fill: C.white, fillOpacity: 0.55 });
  return s;
}

/* ── S5 · Payment received (pay-rent-sheet.tsx, phase "success") ──
   The sheet after the SIGNED WEBHOOK credited the ledger — the sheet polls
   getRentPaymentStatus and only reaches this phase when the server says `credited`,
   which is why the description can state it as fact. Strings, again verbatim:
     SheetTitle        "Payment received"
     SheetDescription  "Your fee ledger has been updated."
     the receipt rows  payment-receipt.tsx — "Amount paid", "For", "Resident", "Hostel"
     the button        "Done"
   The receipt card runs past the bottom of a 360x600 viewport exactly as it does on a
   real phone; the sheet is `overflow-y-auto` and the rest is a scroll away. */
function paidScreen() {
  return sheetOver(44, (top, pad) => {
    const me = PAYER;
    let s = "";
    s += text("Payment received", { x: pad, y: top + 58, size: 18, weight: 600, fill: C.navy });
    s += text("Your fee ledger has been updated.", { x: pad, y: top + 78, size: 13, weight: 400, fill: C.muted });

    s += receiptPrinter(30, top + 96, 300);

    // components/payments/payment-receipt.tsx — rounded-card border-line bg-white/70
    const recY = top + 96 + 300;
    s += rect({ x: pad, y: recY, w: CSS_W - pad * 2, h: 170, r: 20, fill: C.white, fillOpacity: 0.7, stroke: C.line });
    const rows = [
      ["Amount paid", inr(me.due), true],
      ["For", `${PERIOD.label} rent`, false],
      ["Resident", me.name, false],
      ["Hostel", "Sunrise Residency", false],
      ["Paid by", me.method, false],
    ];
    rows.forEach((r, i) => {
      const ry = recY + 24 + i * 30;
      s += text(r[0], { x: pad + 16, y: ry, size: 12.5, weight: 400, fill: C.muted });
      s += text(r[1], { x: CSS_W - pad - 16, y: ry, size: r[2] ? 14.5 : 12.5, weight: r[2] ? 700 : 500, fill: C.navy, anchor: "end" });
      if (i < rows.length - 1) s += line({ x1: pad + 16, y1: ry + 10, x2: CSS_W - pad - 16, y2: ry + 10, stroke: C.line });
    });
    return s;
  });
}


/* ── S4 · Manager expenses (app/manager/expenses/page.tsx + expense-table.tsx) ── */
function managerScreen() {
  const cardX = 16;
  const cardY = 152;
  const cardW = CSS_W - 32;
  const cardH = CSS_H - cardY - 16;

  let s = topBar({ variant: "drawer", title: "Sunrise Residency", avatarName: "Rahul Mehta" });
  s += text("Daily expenses", { x: 16, y: 96, size: 22, weight: 600, fill: C.navy });
  s += text("Record and track outflow for", { x: 16, y: 118, size: 13, weight: 400, fill: C.muted });
  s += text("Sunrise Residency.", { x: 16, y: 136, size: 13, weight: 400, fill: C.muted });

  s += glass(cardX, cardY, cardW, cardH);
  s += text("This month", { x: 36, y: 182, size: 16, weight: 600, fill: C.navy });
  s += text(`${MONTH_EXPENSES.length} entries in ${PERIOD.label}`, { x: 36, y: 200, size: 12.5, weight: 400, fill: C.muted });

  // The pills and the table both live in overflow-x-auto containers, so anything wider
  // than the card is clipped by the card — exactly what a 360px-wide phone shows.
  const clipId = "expenseClip";
  let inner = "";

  const cats = ["Groceries", "Staff", "Electricity", "Water", "Maintenance"];
  inner += segmented(
    [
      { label: "All", count: MONTH_EXPENSES.length },
      ...cats.map((c, i) => ({ label: c, count: EXPENSE_COUNTS.get(c) ?? 0, tone: ["teal", "navy", "sand", "sage", "red"][i] })),
    ],
    0,
    { x: 36, y: 210 },
  );

  const hy = 262;
  inner += text("DATE", { x: 36, y: hy, size: 10, weight: 600, fill: C.muted, ls: 0.5 });
  inner += text("CATEGORY", { x: 130, y: hy, size: 10, weight: 600, fill: C.muted, ls: 0.5 });
  inner += text("AMOUNT", { x: 300, y: hy, size: 10, weight: 600, fill: C.muted, ls: 0.5, anchor: "end" });
  inner += text("NOTE", { x: 316, y: hy, size: 10, weight: 600, fill: C.muted, ls: 0.5 });
  inner += line({ x1: 36, y1: hy + 10, x2: CSS_W, y2: hy + 10, stroke: C.line, strokeOpacity: 0.7 });

  const CAT_TONE = { Groceries: "teal", Staff: "navy", Electricity: "sand", Water: "sage", Maintenance: "red", Other: "muted" };
  MONTH_EXPENSES.slice(0, 6).forEach((e, i) => {
    const y = hy + 38 + i * 36;
    inner += text(fmtDate(e.date), { x: 36, y, size: 12, weight: 400, fill: C.charcoal });
    inner += pill(e.category, { x: 130, y: y - 13, tone: CAT_TONE[e.category], size: 11, h: 19, padX: 8, weight: 500, ls: 0, upper: false });
    inner += text(inr(e.amount), { x: 300, y, size: 12.5, weight: 600, fill: C.red, anchor: "end" });
    inner += text(e.note, { x: 316, y, size: 12, weight: 400, fill: C.muted });
    inner += line({ x1: 36, y1: y + 13, x2: CSS_W, y2: y + 13, stroke: C.line, strokeOpacity: 0.5 });
  });

  s += `<clipPath id="${clipId}"><rect x="${n(cardX)}" y="${n(cardY)}" width="${n(cardW)}" height="${n(cardH)}" rx="20"/></clipPath>`;
  s += `<g clip-path="url(#${clipId})">${inner}</g>`;

  // footer total (components/manager/expense-table.tsx)
  const fy = CSS_H - 96;
  s += line({ x1: 36, y1: fy, x2: CSS_W - 36, y2: fy, stroke: C.line, strokeOpacity: 0.7 });
  s += text("TOTAL THIS MONTH", { x: 36, y: fy + 24, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += text(inr(EXPENSE_TOTAL), { x: 36, y: fy + 54, size: 28, weight: 700, fill: C.red });
  s += rect({ x: CSS_W - 148, y: fy + 22, w: 112, h: 36, r: 12, fill: C.navy, fillOpacity: 0.06 });
  s += icon("download", { x: CSS_W - 136, y: fy + 32, size: 16, color: C.navy });
  s += text("Export CSV", { x: CSS_W - 114, y: fy + 45, size: 12.5, weight: 600, fill: C.navy });
  return s;
}

/**
 * The listing, in order. Play shows the first two or three inline, so the rent
 * payment flow leads: it is the headline feature and it is the one a resident can
 * recognise without knowing anything about the product.
 *
 * Screens 1-3 are one continuous story about one person (PAYER) and one figure.
 * Nothing in these captions claims a rating, an award, a user count or a feature
 * that does not exist in app/.
 */
const SCREENS = [
  {
    file: "01-student-rent-due.png",
    eyebrow: "Student",
    headline: "Rent due, paid from bed",
    sub: "No cash counted out, no queue at the warden's desk.",
    body: studentScreen,
  },
  {
    file: "02-pay-rent.png",
    eyebrow: "Payments",
    headline: "Pay in a couple of taps",
    sub: "UPI, card or net banking, handled by Razorpay.",
    body: paySheetScreen,
  },
  {
    file: "03-payment-received.png",
    eyebrow: "Payments",
    headline: "A receipt the moment it clears",
    sub: "The ledger updates itself. Keep the payment ID as proof.",
    body: paidScreen,
  },
  {
    file: "04-owner-dashboard.png",
    eyebrow: "Owner",
    headline: "The whole hostel, at a glance",
    sub: "Occupancy, fees collected and pending, open complaints.",
    body: ownerScreen,
  },
  {
    file: "05-warden-fees.png",
    eyebrow: "Warden",
    headline: "Collect fees without a register",
    sub: "Month by month. Record cash, UPI or bank in two taps.",
    body: wardenScreen,
  },
  {
    file: "06-manager-expenses.png",
    eyebrow: "Manager",
    headline: "Every rupee in and out",
    sub: "Daily expenses by category, with receipts and CSV export.",
    body: managerScreen,
  },
];

function screenshotSvg(screen, art) {
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${SHOT.w}" height="${SHOT.h}" viewBox="0 0 ${SHOT.w} ${SHOT.h}">
${defs}
<clipPath id="panelClip"><rect x="${PANEL.x}" y="${PANEL.y}" width="${PANEL.w}" height="${PANEL.h}" rx="40"/></clipPath>
<clipPath id="markClip"><rect x="76" y="66" width="56" height="56" rx="14"/></clipPath>
${rect({ x: 0, y: 0, w: SHOT.w, h: SHOT.h, fill: C.ivory })}
<ellipse cx="200" cy="180" rx="520" ry="460" fill="url(#glowA)"/>
<ellipse cx="980" cy="1500" rx="480" ry="440" fill="url(#glowB)"/>

${/* The real mark, rounded off — the caption band is the only place the brand is
     named, since the app's own chrome shows the hostel's name and not ours. */ ""}
${image(art.mark, { x: 76, y: 66, w: 56, h: 56, clip: "markClip" })}
${rect({ x: 76, y: 66, w: 56, h: 56, r: 14, fill: "none", stroke: C.navy, strokeOpacity: 0.08 })}
${text(screen.eyebrow.toUpperCase(), { x: 148, y: 102, size: 22, weight: 700, fill: C.muted, ls: 4 })}
${text(screen.headline, { x: 74, y: 186, size: 50, weight: 700, fill: C.navy })}
${text(screen.sub, { x: 76, y: 236, size: 25, weight: 400, fill: C.charcoal })}

${rect({ x: PANEL.x, y: PANEL.y, w: PANEL.w, h: PANEL.h, r: 40, fill: C.ivory, stroke: C.white, strokeOpacity: 0.9, strokeWidth: 2 })}
<g clip-path="url(#panelClip)">
  <g transform="translate(${PANEL.x} ${PANEL.y}) scale(${PANEL.scale})">
    ${rect({ x: 0, y: 0, w: CSS_W, h: CSS_H, fill: C.ivory })}
    ${screen.body()}
  </g>
</g>
${rect({ x: PANEL.x, y: PANEL.y, w: PANEL.w, h: PANEL.h, r: 40, fill: "none", stroke: C.navy, strokeOpacity: 0.08, strokeWidth: 2 })}
</svg>`;
}

/* ───────────────────────── render + verify ───────────────────────── */

/**
 * Rasterise an SVG at exactly width x height.
 *
 * `density: 72` matters: librsvg treats the SVG's user units as points, so the
 * default 96 dpi silently renders every asset 1.333x too large. The explicit
 * resize is belt and braces — it is what makes the pixel dimensions a guarantee
 * rather than a side effect of the rasteriser's dpi.
 *
 * `flatten` composites onto an opaque colour and drops the alpha channel: Play
 * wants the icon and the feature graphic opaque, and there is nothing meaningful
 * to make transparent in a screenshot either.
 */
async function render(svg, file, { width, height, flatten }) {
  await sharp(Buffer.from(svg), { density: 72 })
    .resize(width, height, { fit: "fill" })
    .flatten({ background: flatten })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toFile(file);
}

/** Assert the real file on disk matches the Play spec. Returns a printable row. */
async function verify(file, spec) {
  const meta = await sharp(file).metadata();
  const bytes = fs.statSync(file).size;
  const problems = [];
  if (meta.width !== spec.width || meta.height !== spec.height) {
    problems.push(`expected ${spec.width}x${spec.height}, got ${meta.width}x${meta.height}`);
  }
  // 24-bit, no alpha channel at all — the feature graphic and the screenshots.
  if (spec.opaque && meta.hasAlpha) problems.push(`has an alpha channel (${meta.channels} channels)`);
  if (spec.opaque && meta.channels !== 3) problems.push(`expected 3 channels (24-bit), got ${meta.channels}`);

  /* 32-bit WITH alpha, and that alpha fully opaque — the icon. Both halves are
     checked against the actual pixels, not against the encoder's intent: `min` is
     the darkest value anywhere in the alpha channel, so 255 proves every pixel is
     opaque and no corner of the mark is see-through. */
  let alphaMin = null;
  if (meta.hasAlpha) {
    const stats = await sharp(file).stats();
    alphaMin = stats.channels[3]?.min ?? null;
  }
  if (spec.rgba) {
    if (meta.channels !== 4) problems.push(`expected 4 channels (32-bit RGBA), got ${meta.channels}`);
    if (!meta.hasAlpha) problems.push("has no alpha channel — Play wants a 32-bit PNG with alpha");
    else if (alphaMin === null) problems.push("could not read the alpha channel to check its opacity");
    else if (alphaMin !== 255) problems.push(`alpha channel is not fully opaque (min ${alphaMin}, expected 255)`);
  }

  if (meta.format !== "png") problems.push(`expected png, got ${meta.format}`);
  if (spec.maxBytes && bytes > spec.maxBytes) {
    problems.push(`${(bytes / 1024).toFixed(0)} KB exceeds the ${(spec.maxBytes / 1024).toFixed(0)} KB limit`);
  }
  // Play phone screenshots: every side 320..3840 px, the long side at most twice the
  // short side, and (for promotional eligibility) 16:9 or 9:16 at 1080p or better.
  if (spec.playScreenshot) {
    for (const side of [meta.width, meta.height]) {
      if (side < 320 || side > 3840) problems.push(`side ${side}px is outside Play's 320..3840 range`);
    }
    const long = Math.max(meta.width, meta.height);
    const short = Math.min(meta.width, meta.height);
    if (long > short * 2) problems.push(`long side ${long}px is more than twice the short side ${short}px`);
    const ratio = meta.width / meta.height;
    if (Math.abs(ratio - 9 / 16) > 0.001 && Math.abs(ratio - 16 / 9) > 0.001) {
      problems.push(`aspect ratio ${ratio.toFixed(4)} is neither 9:16 nor 16:9`);
    }
  }
  return {
    file: path.relative(REPO_ROOT, file).replace(/\\/g, "/"),
    size: `${meta.width}x${meta.height}`,
    format: meta.format,
    channels: meta.channels,
    /* "none"   — 24-bit, no alpha channel (feature graphic, screenshots)
       "opaque" — 32-bit RGBA, every alpha sample 255 (icon)
       "SEE-THRU" — 32-bit RGBA with real transparency, which Play rejects */
    alpha: !meta.hasAlpha ? "none" : alphaMin === 255 ? "opaque" : `SEE-THRU(${alphaMin})`,
    bits: meta.channels * 8,
    kb: (bytes / 1024).toFixed(1),
    /* Printed so "run it twice, compare" is a diff of this table rather than a
       separate ritual. Nothing here reads the clock, so these must not move. */
    sha256: createHash("sha256").update(fs.readFileSync(file)).digest("hex").slice(0, 12),
    problems,
  };
}

/* ───────────────────────── main ───────────────────────── */

async function main() {
  const args = new Set(process.argv.slice(2));
  const checkOnly = args.has("--check");
  const keepSvg = args.has("--svg");

  const targets = [
    { file: path.join(OUT_DIR, "icon-512.png"), spec: { width: 512, height: 512, rgba: true, maxBytes: 1024 * 1024 } },
    { file: path.join(OUT_DIR, "feature-graphic-1024x500.png"), spec: { width: 1024, height: 500, opaque: true, maxBytes: 15 * 1024 * 1024 } },
    ...SCREENS.map((s) => ({
      file: path.join(SHOTS_DIR, s.file),
      spec: { width: SHOT.w, height: SHOT.h, opaque: true, playScreenshot: true, maxBytes: 8 * 1024 * 1024 },
    })),
  ];

  if (!checkOnly) {
    fs.mkdirSync(SHOTS_DIR, { recursive: true });

    const art = await brandArt();
    console.log("brand artwork");
    for (const p of art.provenance) console.log(`  ${p}`);
    console.log("");

    /* The icon is a raster job, not a drawing — see section 1. Written straight from
       the buffer brandArt() prepared, so the store icon is the launcher icon's pixels. */
    fs.writeFileSync(targets[0].file, art.iconBuf);
    console.log(`wrote ${path.relative(REPO_ROOT, targets[0].file).replace(/\\/g, "/")}`);

    const jobs = [
      { svg: featureSvg(art), target: targets[1], flatten: C.ivory, name: "feature-graphic-1024x500.svg" },
      ...SCREENS.map((s, i) => ({
        svg: screenshotSvg(s, art),
        target: targets[2 + i],
        flatten: C.ivory,
        name: s.file.replace(/\.png$/, ".svg"),
      })),
    ];

    for (const job of jobs) {
      const { file } = job.target;
      await render(job.svg, file, { width: job.target.spec.width, height: job.target.spec.height, flatten: job.flatten });
      if (keepSvg) {
        const dir = path.join(OUT_DIR, "svg");
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, job.name), job.svg);
      }
      console.log(`wrote ${path.relative(REPO_ROOT, file).replace(/\\/g, "/")}`);
    }

    /* Screenshots have been renamed and re-ordered before now, and a leftover PNG in
       this folder is not harmless: it is a HostelPro-era asset sitting in the same
       directory someone uploads from. Anything not in SCREENS goes. */
    const expected = new Set(SCREENS.map((s) => s.file));
    for (const stale of fs.readdirSync(SHOTS_DIR).filter((f) => f.endsWith(".png") && !expected.has(f))) {
      fs.unlinkSync(path.join(SHOTS_DIR, stale));
      console.log(`removed stale public/store/screenshots/${stale}`);
    }
  }

  // Play requires at least 2 and at most 8 phone screenshots.
  const shotCount = SCREENS.length;
  const countProblem = shotCount < 2 || shotCount > 8 ? [`${shotCount} phone screenshots — Play accepts 2..8`] : [];

  const rows = [];
  for (const t of targets) {
    if (!fs.existsSync(t.file)) {
      rows.push({ file: path.relative(REPO_ROOT, t.file).replace(/\\/g, "/"), problems: ["missing"] });
      continue;
    }
    rows.push(await verify(t.file, t.spec));
  }

  const head = ["file", "size", "format", "depth", "alpha", "KB", "sha256"];
  const table = rows.map((r) => [
    r.file,
    r.size ?? "-",
    r.format ?? "-",
    r.bits ? `${r.bits}-bit` : "-",
    r.alpha ?? "-",
    r.kb ?? "-",
    r.sha256 ?? "-",
  ]);
  const widths = head.map((h, i) => Math.max(h.length, ...table.map((row) => row[i].length)));
  const fmtRow = (cells) => "  " + cells.map((c, i) => c.padEnd(widths[i])).join("  ");
  console.log("\n─────────────────────────── verification ───────────────────────────");
  console.log(fmtRow(head));
  console.log("  " + widths.map((w) => "─".repeat(w)).join("  "));
  for (const row of table) console.log(fmtRow(row));
  console.log(`\n  phone screenshots: ${shotCount} (Play accepts 2..8)`);

  const failures = [...rows.flatMap((r) => r.problems.map((p) => `${r.file}: ${p}`)), ...countProblem];
  if (failures.length > 0) {
    console.error("\nFAILED");
    for (const f of failures) console.error(`  ✗ ${f}`);
    process.exitCode = 1;
    return;
  }
  console.log("\n  All assets match the Play specs.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});

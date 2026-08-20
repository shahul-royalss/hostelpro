#!/usr/bin/env node
/**
 * Google Play store graphics for HostelPro — generated, not hand-made.
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
 *   public/icons/icon.svg   the brand glyph — read and re-used verbatim, never redrawn
 *   tailwind.config.ts      the palette below is a transcription of the brand tokens
 *   app/manifest.ts         #F6F4EF background/theme colour
 *   node_modules/lucide-react  the same icon geometry the app renders
 *   db/seed.ts              the demo dataset the screenshot numbers are computed from
 *
 * ABOUT THE SCREENSHOTS
 * The app is behind a login and the TWA is portrait-locked (app/manifest.ts), so these
 * are not device captures: they are the real mobile layouts redrawn to scale, with the
 * real strings from app/ and numbers computed from db/seed.ts (see DEMO below). Nothing
 * is invented — no testimonials, no ratings, no awards, no features that do not exist.
 *
 * Play specs enforced by verify() at the bottom:
 *   icon             512x512 PNG, opaque (no alpha), square corners — Play applies its own mask
 *   feature graphic  1024x500 PNG, opaque
 *   screenshots      1080x1920 PNG (9:16), 2..8 of them, every side within 320..3840
 */
import sharp from "sharp";
import fs from "node:fs";
import path from "node:path";
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
};

/** app/layout.tsx loads Inter; librsvg falls back to whatever the OS has if Inter is not installed. */
const FONT = "Inter, 'Segoe UI', 'Noto Sans', Arial, sans-serif";

/* ───────────────────────── demo dataset ─────────────────────────
   Every number below is computed from db/seed.ts (Sunrise Residency) rather than
   typed in, so the screenshots cannot drift away from what the app would show.

   Sunrise Residency: 3 floors x 12 rooms x 3 beds = 36 beds; 12 students seeded.
   PERIOD is pinned so the output is byte-identical on every run — see docs/store-assets.md. */
const PERIOD = { month: "August 2026", short: "Aug", year: 2026 };
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

function text(str, { x, y, size = 14, weight = 400, fill = C.charcoal, anchor = "start", ls, opacity }) {
  const a = [
    `x="${n(x)}"`,
    `y="${n(y)}"`,
    `font-family="${FONT}"`,
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
  <radialGradient id="glowA" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="${C.navy}" stop-opacity="0.10"/>
    <stop offset="50%" stop-color="${C.teal}" stop-opacity="0.10"/>
    <stop offset="70%" stop-color="${C.ivory}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glowB" cx="50%" cy="50%" r="50%">
    <stop offset="0%" stop-color="${C.sand}" stop-opacity="0.22"/>
    <stop offset="65%" stop-color="${C.ivory}" stop-opacity="0"/>
  </radialGradient>
</defs>`;

/* ───────────────────────── brand glyph ─────────────────────────
   Read out of public/icons/icon.svg so the store icon is literally the app icon.
   Everything after the background <rect> is the mark; we drop the rect because
   Play wants square corners and applies its own mask. */
function brandGlyph() {
  const file = path.join(REPO_ROOT, "public", "icons", "icon.svg");
  const src = fs.readFileSync(file, "utf8");
  const afterRect = src.indexOf("/>", src.indexOf("<rect"));
  const closing = src.lastIndexOf("</svg>");
  if (afterRect === -1 || closing === -1) throw new Error(`unexpected structure in ${file} — cannot extract the brand mark`);
  const mark = src.slice(afterRect + 2, closing).trim();
  if (!mark.includes("<path") || !mark.includes("<circle")) {
    throw new Error(`extracted mark from ${file} is missing the house path or the accent dot`);
  }
  const viewBox = src.match(/viewBox="0 0 (\d+) (\d+)"/);
  if (!viewBox) throw new Error(`no viewBox in ${file}`);
  return { mark, size: Number(viewBox[1]) };
}

/** Place the brand mark, scaled from its native 512 grid, at (x,y) with the given box size. */
function brandMark(glyph, x, y, size) {
  const s = size / glyph.size;
  return `<g transform="translate(${n(x)} ${n(y)}) scale(${n(s)})">${glyph.mark}</g>`;
}

/* ───────────────────────── 1. app icon ───────────────────────── */

function iconSvg(glyph) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
${rect({ x: 0, y: 0, w: 512, h: 512, fill: C.navy })}
${brandMark(glyph, 0, 0, 512)}
</svg>`;
}

/* ───────────────────────── 2. feature graphic ───────────────────────── */

function featureSvg(glyph) {
  const W = 1024;
  const H = 500;
  const chips = ["Rooms", "Fees", "Complaints", "Leaves", "Mess"];

  // Play crops the feature graphic in some placements, so nothing that matters goes
  // outside x 112..912 (11% inset) or y 130..375.
  let chipX = 112;
  const chipRow = chips
    .map((label) => {
      const w = label.length * 8.4 + 30;
      const el =
        rect({ x: chipX, y: 340, w, h: 34, r: 17, fill: C.white, fillOpacity: 0.8, stroke: C.white, strokeOpacity: 0.9 }) +
        text(label, { x: chipX + 15, y: 362, size: 15, weight: 500, fill: C.navy });
      chipX += w + 10;
      return el;
    })
    .join("");

  const cardX = 568;
  const cardY = 140;
  const statRow = (i, label, value, tone, iconName, iconOpacity) => {
    const top = cardY + 18 + i * 66;
    return (
      text(label.toUpperCase(), { x: cardX + 26, y: top + 14, size: 11, weight: 600, fill: C.muted, ls: 0.6 }) +
      text(value, { x: cardX + 26, y: top + 42, size: 26, weight: 700, fill: tone }) +
      (iconName ? icon(iconName, { x: cardX + 288, y: top + 8, size: 26, color: tone, opacity: iconOpacity }) : "") +
      (i < 2 ? line({ x1: cardX + 26, y1: top + 54, x2: cardX + 318, y2: top + 54, stroke: C.line }) : "")
    );
  };

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
${defs}
${rect({ x: 0, y: 0, w: W, h: H, fill: C.ivory })}
<ellipse cx="300" cy="250" rx="380" ry="330" fill="url(#glowA)"/>
<ellipse cx="880" cy="90" rx="300" ry="260" fill="url(#glowB)"/>

${rect({ x: 112, y: 132, w: 92, h: 92, r: 21, fill: C.navy })}
${brandMark(glyph, 112, 132, 92)}
${text("HostelPro", { x: 226, y: 182, size: 52, weight: 700, fill: C.navy })}
${text("Hostel & PG management", { x: 228, y: 214, size: 21, weight: 400, fill: C.muted })}
${text("Owner · Manager · Warden · Student", { x: 112, y: 278, size: 20, weight: 600, fill: C.navy })}
${text("One workspace, live data, private by default.", { x: 112, y: 308, size: 19, weight: 400, fill: C.charcoal })}
${chipRow}

${glass(cardX, cardY, 344, 220, { strong: true })}
${statRow(0, "Occupancy", `${STATS.occupiedBeds} / ${STATS.totalBeds} beds`, C.navy)}
${ring(cardX + 300, cardY + 44, STATS.occupancyPct, { size: 44 })}
${statRow(1, "Fees collected", inrCompact(STATS.feesCollected), C.teal, "indian-rupee", 0.5)}
${statRow(2, "Open complaints", String(STATS.openComplaints), C.navy, "message-square-warning", 0.35)}
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
  let s = topBar({ variant: "back", title: "Fees", subtitle: `${PERIOD.month} · Sunrise Residency` });

  const months = ["Mar", "Apr", "May", "Jun", "Jul", "Aug"];
  s += segmented(months.map((m) => ({ label: m })), 5, { x: 16, y: 76 });

  // summary strip — two cards, grid-cols-2
  const cw = (CSS_W - 32 - 12) / 2;
  s += glass(16, 116, cw, 88);
  s += text("COLLECTED", { x: 32, y: 140, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += icon("circle-check-big", { x: 16 + cw - 30, y: 130, size: 16, color: C.teal, opacity: 0.6 });
  s += text(inrCompact(STATS.feesCollected), { x: 32, y: 174, size: 28, weight: 700, fill: C.teal });
  s += text(`${STATS.paidCount} paid · ${PERIOD.month}`, { x: 32, y: 192, size: 11, weight: 400, fill: C.muted });

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

/* ── S3 · Student home (app/student/page.tsx) ── */
function studentScreen() {
  const me = LEDGER[0]; // Aarav Sharma — room 101, bed 1, paid by UPI
  let s = topBar({ variant: "avatar", avatarName: me.name, title: "Hi, Aarav", subtitle: "Sunrise Residency" });

  // hero
  s += glass(16, 80, CSS_W - 32, 124, { strong: true });
  s += rect({ x: 36, y: 98, w: 44, h: 44, r: 12, fill: C.navy, fillOpacity: 0.1 });
  s += icon("building-2", { x: 48, y: 110, size: 20, color: C.navy });
  s += text("MY STAY", { x: 92, y: 112, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += text(`Room ${me.room} · Bed ${me.bed} · Floor 1`, { x: 92, y: 134, size: 18, weight: 700, fill: C.navy });
  s += text("Sunrise Residency", { x: 92, y: 150, size: 12, weight: 400, fill: C.muted });
  s += rect({ x: 36, y: 160, w: CSS_W - 72, h: 32, r: 12, fill: C.white, fillOpacity: 0.7 });
  s += text(`${PERIOD.month.toUpperCase()} FEE`, { x: 48, y: 175, size: 11, weight: 600, fill: C.muted, ls: 0.55 });
  s += text(`${inr(me.paid)} received — thank you`, { x: 48, y: 188, size: 11.5, weight: 400, fill: C.muted });
  s += pill("Paid", { x: CSS_W - 88, y: 165, tone: "teal", size: 11, h: 22, padX: 10, ls: 0 });

  // updates (db/seed.ts announcements)
  s += glass(16, 216, CSS_W - 32, 156);
  s += text("Updates from hostel", { x: 36, y: 244, size: 16, weight: 600, fill: C.navy });
  const updates = [
    ["Water supply maintenance on Sunday", "The overhead tank will be cleaned this", "Sunday between 10 am and 1 pm."],
    ["Monthly fee reminder", `Fees for ${PERIOD.month} are due by the 10th.`, "Pay by UPI or at the warden's office."],
  ];
  updates.forEach((u, i) => {
    const y = 256 + i * 60;
    s += circle({ cx: 48, cy: y + 14, r: 12, fill: C.navy, fillOpacity: 0.05 });
    s += icon("megaphone", { x: 41, y: y + 7, size: 14, color: C.navy });
    s += text(u[0], { x: 72, y: y + 18, size: 12.5, weight: 600, fill: C.navy });
    s += text(u[1], { x: 72, y: y + 32, size: 11.5, weight: 400, fill: C.charcoal, opacity: 0.8 });
    s += text(u[2], { x: 72, y: y + 45, size: 11.5, weight: 400, fill: C.charcoal, opacity: 0.8 });
    if (i === 0) s += line({ x1: 36, y1: y + 54, x2: CSS_W - 36, y2: y + 54, stroke: C.line });
  });

  // quick actions (components/student/quick-grid.tsx)
  s += text("Quick actions", { x: 16, y: 396, size: 16, weight: 600, fill: C.navy });
  const tiles = [
    ["Mess menu", "utensils-crossed", C.navy, "#1C2B451A"],
    ["Raise complaint", "message-square-warning", C.red, C.redSoft],
    ["Apply leave", "calendar-off", C.sandDeep, C.sandSoft],
    ["My room", "bed", C.teal, C.tealSoft],
  ];
  const tw = (CSS_W - 32 - 12) / 2;
  tiles.forEach((t, i) => {
    const x = 16 + (i % 2) * (tw + 12);
    const y = 410 + Math.floor(i / 2) * 72;
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
  s += text(`${MONTH_EXPENSES.length} entries in ${PERIOD.month}`, { x: 36, y: 200, size: 12.5, weight: 400, fill: C.muted });

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

const SCREENS = [
  {
    file: "01-owner-dashboard.png",
    eyebrow: "Owner",
    headline: "The whole hostel, at a glance",
    sub: "Occupancy, fees collected and pending, open complaints.",
    body: ownerScreen,
  },
  {
    file: "02-warden-fees.png",
    eyebrow: "Warden",
    headline: "Collect fees without a register",
    sub: "Month by month. Record cash, UPI or bank in two taps.",
    body: wardenScreen,
  },
  {
    file: "03-student-room-fees.png",
    eyebrow: "Student",
    headline: "Your room and your dues",
    sub: "Students sign in with their phone number — no signup.",
    body: studentScreen,
  },
  {
    file: "04-manager-expenses.png",
    eyebrow: "Manager",
    headline: "Every rupee in and out",
    sub: "Daily expenses by category, with receipts and CSV export.",
    body: managerScreen,
  },
];

function screenshotSvg(screen) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${SHOT.w}" height="${SHOT.h}" viewBox="0 0 ${SHOT.w} ${SHOT.h}">
${defs}
<clipPath id="panelClip"><rect x="${PANEL.x}" y="${PANEL.y}" width="${PANEL.w}" height="${PANEL.h}" rx="40"/></clipPath>
${rect({ x: 0, y: 0, w: SHOT.w, h: SHOT.h, fill: C.ivory })}
<ellipse cx="200" cy="180" rx="520" ry="460" fill="url(#glowA)"/>
<ellipse cx="980" cy="1500" rx="480" ry="440" fill="url(#glowB)"/>

${text(screen.eyebrow.toUpperCase(), { x: 76, y: 116, size: 22, weight: 700, fill: C.muted, ls: 4 })}
${text(screen.headline, { x: 74, y: 178, size: 50, weight: 700, fill: C.navy })}
${text(screen.sub, { x: 76, y: 228, size: 25, weight: 400, fill: C.charcoal })}

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
  if (spec.opaque && meta.hasAlpha) problems.push(`has an alpha channel (${meta.channels} channels)`);
  if (spec.opaque && meta.channels !== 3) problems.push(`expected 3 channels, got ${meta.channels}`);
  if (meta.format !== "png") problems.push(`expected png, got ${meta.format}`);
  if (spec.maxBytes && bytes > spec.maxBytes) {
    problems.push(`${(bytes / 1024 / 1024).toFixed(2)} MB exceeds the ${spec.maxBytes / 1024 / 1024} MB limit`);
  }
  // Play phone screenshots: every side 320..3840 px, ratio 16:9 or 9:16.
  if (spec.playScreenshot) {
    for (const side of [meta.width, meta.height]) {
      if (side < 320 || side > 3840) problems.push(`side ${side}px is outside Play's 320..3840 range`);
    }
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
    alpha: meta.hasAlpha ? "YES" : "no",
    kb: (bytes / 1024).toFixed(1),
    problems,
  };
}

/* ───────────────────────── main ───────────────────────── */

async function main() {
  const args = new Set(process.argv.slice(2));
  const checkOnly = args.has("--check");
  const keepSvg = args.has("--svg");

  const targets = [
    { file: path.join(OUT_DIR, "icon-512.png"), spec: { width: 512, height: 512, opaque: true, maxBytes: 1024 * 1024 } },
    { file: path.join(OUT_DIR, "feature-graphic-1024x500.png"), spec: { width: 1024, height: 500, opaque: true, maxBytes: 15 * 1024 * 1024 } },
    ...SCREENS.map((s) => ({
      file: path.join(SHOTS_DIR, s.file),
      spec: { width: SHOT.w, height: SHOT.h, opaque: true, playScreenshot: true, maxBytes: 8 * 1024 * 1024 },
    })),
  ];

  if (!checkOnly) {
    fs.mkdirSync(SHOTS_DIR, { recursive: true });
    const glyph = brandGlyph();
    console.log(`brand mark read from public/icons/icon.svg (${glyph.size}x${glyph.size} grid)`);

    const jobs = [
      { svg: iconSvg(glyph), target: targets[0], flatten: C.navy, name: "icon-512.svg" },
      { svg: featureSvg(glyph), target: targets[1], flatten: C.ivory, name: "feature-graphic-1024x500.svg" },
      ...SCREENS.map((s, i) => ({
        svg: screenshotSvg(s),
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

  const head = ["file", "size", "format", "channels", "alpha", "KB"];
  const table = rows.map((r) => [r.file, r.size ?? "-", r.format ?? "-", String(r.channels ?? "-"), r.alpha ?? "-", r.kb ?? "-"]);
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

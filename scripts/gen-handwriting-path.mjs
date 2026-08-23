#!/usr/bin/env node
/**
 * Handwriting path generator — BUILD/DEV TIME ONLY.
 *
 *   node scripts/gen-handwriting-path.mjs            # download (cached) + generate
 *   node scripts/gen-handwriting-path.mjs --font X   # use a local .ttf/.otf instead
 *   node scripts/gen-handwriting-path.mjs --check    # regenerate into memory and diff
 *
 * WHY THIS EXISTS
 * ---------------
 * The component this feeds (components/ui/handwriting-svg.tsx) used to fetch a TTF from
 * raw.githubusercontent.com in the browser and parse it with opentype.js on every mount.
 * That was broken twice over in this codebase:
 *
 *   1. CSP. lib/security-headers.ts pins `connect-src` to 'self' + the Supabase origin.
 *      A runtime fetch to raw.githubusercontent.com is blocked outright — the component
 *      would render nothing in production and only "work" with the policy loosened.
 *   2. Weight. opentype.js is ~3.6 MB unpacked. Shipping a font parser to the browser to
 *      draw six letters that never change is a First Load JS regression for zero benefit.
 *
 * So the font parsing moved here, to a script that runs on a developer machine. opentype.js
 * stays a devDependency, the font never reaches the browser, and the app imports plain
 * strings from lib/handwriting-paths.ts (committed). No CSP change was needed.
 *
 * The font is downloaded to a cache under node_modules/.cache/, which is already gitignored
 * by the `/node_modules` rule — no .gitignore edit required, and no font binary in the repo.
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import * as opentypeNs from "opentype.js";

// opentype.js 2.x ships a CJS bundle with an interop `default`; unwrap whichever we get.
const opentype = opentypeNs.default ?? opentypeNs;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CACHE_DIR = path.join(ROOT, "node_modules", ".cache", "handwriting-font");
const OUT_FILE = path.join(ROOT, "lib", "handwriting-paths.ts");

/**
 * Caveat, SIL Open Font License 1.1 (github.com/google/fonts/blob/main/ofl/caveat/OFL.txt).
 *
 * The URL is pinned to a commit, not to `main`, and the bytes are checked against a digest.
 * A pinned+hashed build-time download is reproducible; an unpinned one silently changes the
 * committed output whenever upstream re-releases the font. If this digest ever fails, that is
 * a deliberate re-pin decision for a human, not something to --force past.
 */
const FONT = {
  name: "Caveat",
  license: "OFL-1.1",
  commit: "a85fc09e44c70c7159761adfdc9d5dd007792c15",
  url: "https://raw.githubusercontent.com/google/fonts/a85fc09e44c70c7159761adfdc9d5dd007792c15/ofl/caveat/Caveat%5Bwght%5D.ttf",
  sha256: "0bdb6b660482d31531b3945849fba5916b3ef8695da7024a9e6b9ee3c4157988",
  file: "Caveat-wght.ttf",
};

/**
 * The strings the app actually needs. Keep this list short — every entry becomes path data
 * in the client bundle, so adding one has a real byte cost (see the size report on stdout).
 */
const ENTRIES = [
  { key: "nivora", text: "NIVORA", note: "product wordmark" },
  { key: "welcome", text: "Welcome", note: "auth / onboarding greeting" },
];

/** Em size the outlines are generated at. Bigger = finer detail after rounding. */
const FONT_SIZE = 100;
/** Padding around the glyph bounding box, so a stroked render is not clipped by the viewBox. */
const PAD = 4;
/** Coordinate decimals. 1 is visually indistinguishable at these sizes and ~25% smaller than 2. */
const DECIMALS = 1;

const args = new Set(process.argv.slice(2));
const flagValue = (name) => {
  const i = process.argv.indexOf(name);
  return i !== -1 ? process.argv[i + 1] : undefined;
};

function sha256(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

async function loadFontBytes() {
  const local = flagValue("--font");
  if (local) {
    const buf = fs.readFileSync(path.resolve(local));
    console.log(`  font: ${local} (${buf.length} bytes, sha256 ${sha256(buf).slice(0, 16)}…)`);
    return buf;
  }

  const cached = path.join(CACHE_DIR, FONT.file);
  if (fs.existsSync(cached)) {
    const buf = fs.readFileSync(cached);
    if (sha256(buf) === FONT.sha256) {
      console.log(`  font: cache hit ${path.relative(ROOT, cached)} (${buf.length} bytes)`);
      return buf;
    }
    console.log("  font: cached copy failed its digest — re-downloading");
  }

  console.log(`  font: downloading ${FONT.name} @ ${FONT.commit.slice(0, 10)} …`);
  const res = await fetch(FONT.url, { redirect: "follow" });
  if (!res.ok) throw new Error(`font download failed: HTTP ${res.status} ${res.statusText}`);
  const buf = Buffer.from(await res.arrayBuffer());

  const got = sha256(buf);
  if (got !== FONT.sha256) {
    throw new Error(
      `font digest mismatch\n  expected ${FONT.sha256}\n  actual   ${got}\n` +
        "Refusing to generate from unverified bytes. Re-pin FONT.commit/sha256 deliberately.",
    );
  }

  fs.mkdirSync(CACHE_DIR, { recursive: true });
  fs.writeFileSync(cached, buf);
  console.log(`  font: cached to ${path.relative(ROOT, cached)} (${buf.length} bytes)`);
  return buf;
}

/** Node Buffer -> the exact ArrayBuffer slice opentype.parse expects. */
function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function buildEntry(font, text) {
  // Pass 1 at the origin tells us where the outlines actually land (y is a baseline, so the
  // box straddles it), pass 2 re-renders shifted so the box sits at PAD,PAD inside a viewBox.
  const probe = font.getPath(text, 0, 0, FONT_SIZE, { kerning: true }).getBoundingBox();
  const dx = PAD - probe.x1;
  const dy = PAD - probe.y1;

  const glyphPath = font.getPath(text, dx, dy, FONT_SIZE, { kerning: true });
  const box = glyphPath.getBoundingBox();
  const width = round(box.x2 + PAD);
  const height = round(box.y2 + PAD);

  return {
    text,
    d: glyphPath.toPathData(DECIMALS),
    width,
    height,
    viewBox: `0 0 ${width} ${height}`,
  };
}

function round(n) {
  return Number(n.toFixed(DECIMALS));
}

function render(entries) {
  const body = entries
    .map(
      ({ key, note, value }) =>
        `  /** ${escapeComment(value.text)} — ${note} */\n` +
        `  ${key}: {\n` +
        `    text: ${JSON.stringify(value.text)},\n` +
        `    width: ${value.width},\n` +
        `    height: ${value.height},\n` +
        `    viewBox: ${JSON.stringify(value.viewBox)},\n` +
        `    d: ${JSON.stringify(value.d)},\n` +
        `  },`,
    )
    .join("\n");

  return `/**
 * GENERATED FILE — do not edit by hand.
 * Regenerate with: node scripts/gen-handwriting-path.mjs
 *
 * SVG outlines for a handful of fixed strings, traced from ${FONT.name} (${FONT.license})
 * at build time so the browser never downloads a font binary and never loads opentype.js.
 * These are plain strings: no runtime parsing, no network request, nothing for the CSP to
 * block. Rendered by components/ui/handwriting-svg.tsx.
 *
 * Font: ${FONT.name}, ${FONT.license}, google/fonts @ ${FONT.commit}
 * Traced at em size ${FONT_SIZE}, ${DECIMALS} decimal place(s), ${PAD}px padding.
 */

export interface HandwritingPath {
  /** The literal text these outlines spell — use it as the accessible name. */
  readonly text: string;
  /** Intrinsic width of the artwork, in viewBox units. */
  readonly width: number;
  /** Intrinsic height of the artwork, in viewBox units. */
  readonly height: number;
  /** Ready-made \`viewBox\` attribute for the wrapping \`<svg>\`. */
  readonly viewBox: string;
  /** Glyph outline path data for a single \`<path d="…">\`. */
  readonly d: string;
}

export const HANDWRITING_PATHS = {
${body}
} as const satisfies Record<string, HandwritingPath>;

export type HandwritingPathKey = keyof typeof HANDWRITING_PATHS;
`;
}

function escapeComment(s) {
  return s.replace(/\*\//g, "*\\/");
}

async function main() {
  console.log("\nhandwriting paths\n");
  const bytes = await loadFontBytes();
  const font = opentype.parse(toArrayBuffer(bytes));
  console.log(`  parsed: ${font.names.fontFamily?.en ?? FONT.name}, unitsPerEm ${font.unitsPerEm}\n`);

  const entries = ENTRIES.map((e) => ({ ...e, value: buildEntry(font, e.text) }));
  for (const { key, value } of entries) {
    console.log(
      `  ${key.padEnd(10)} "${value.text}"  ${value.d.length} chars of path data  ` +
        `viewBox ${value.viewBox}`,
    );
  }

  const source = render(entries);
  const total = Buffer.byteLength(source, "utf8");
  console.log(`\n  ${path.relative(ROOT, OUT_FILE)}  ${total} bytes total\n`);

  if (args.has("--check")) {
    const existing = fs.existsSync(OUT_FILE) ? fs.readFileSync(OUT_FILE, "utf8") : "";
    if (existing !== source) {
      console.error("  x out of date — run without --check to regenerate\n");
      process.exit(1);
    }
    console.log("  . up to date\n");
    return;
  }

  fs.mkdirSync(path.dirname(OUT_FILE), { recursive: true });
  fs.writeFileSync(OUT_FILE, source, "utf8");
  console.log("  . written\n");
}

main().catch((err) => {
  console.error(`\n  x ${err.message}\n`);
  process.exit(1);
});

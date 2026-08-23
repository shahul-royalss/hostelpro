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

/**
 * Lay a string out one glyph at a time.
 *
 * font.getPath(string) is the obvious call and it is the one that was here first, but on this
 * font it emits literal "NaN" into the path data — 11 of them in "Welcome", none in "NIVORA".
 * It is not the outlines and it is not kerning: every glyph renders cleanly on its own AND at
 * its accumulated x position, every advanceWidth is finite, and the NaN count is identical with
 * kerning on and off. The fault is inside opentype.js's own string-layout pass for this variable
 * font (Caveat[wght]), which is a family it does not fully support.
 *
 * Composing the glyphs ourselves sidesteps that layer entirely while producing the same result,
 * kerning included — getKerningValue() returns correct finite values here.
 */
/**
 * Serialise a Path ourselves instead of calling opentype's toPathData().
 *
 * The composed path holds 582 commands with ZERO non-finite numbers — verified by walking every
 * x/y/x1/y1/x2/y2 — and toPathData() still returns a string containing 11 "NaN". It only does so
 * once the glyphs carry an x offset; at the origin the same call is clean. So the fault is in
 * that serialiser's own shorthand/rounding pass, not in the geometry we hand it.
 *
 * Writing the string here is a dozen lines, is exact, and removes a dependency on the one
 * opentype.js function that demonstrably cannot round-trip this font.
 */
function serialisePath(commands, decimals) {
  const n = (v) => {
    if (!Number.isFinite(v)) throw new Error(`non-finite coordinate reached the serialiser: ${v}`);
    // Number() drops the trailing zeros toFixed() adds, so 12.0 emits as "12".
    return String(Number(v.toFixed(decimals)));
  };
  const out = [];
  for (const c of commands) {
    switch (c.type) {
      case "M": out.push(`M${n(c.x)} ${n(c.y)}`); break;
      case "L": out.push(`L${n(c.x)} ${n(c.y)}`); break;
      case "Q": out.push(`Q${n(c.x1)} ${n(c.y1)} ${n(c.x)} ${n(c.y)}`); break;
      case "C": out.push(`C${n(c.x1)} ${n(c.y1)} ${n(c.x2)} ${n(c.y2)} ${n(c.x)} ${n(c.y)}`); break;
      case "Z": out.push("Z"); break;
      default: throw new Error(`unhandled path command: ${c.type}`);
    }
  }
  return out.join("");
}

function layout(font, text, x, y) {
  const path = new opentype.Path();
  let penX = x;
  const scale = FONT_SIZE / font.unitsPerEm;
  const glyphs = [...text].map((c) => font.charToGlyph(c));

  glyphs.forEach((glyph, i) => {
    // Render at the ORIGIN and translate the commands ourselves.
    //
    // glyph.getPath(penX, ...) is the natural call, and it is what produced 11-13 literal
    // "NaN" coordinates in "Welcome" while leaving "NIVORA" untouched. It is not the outlines
    // (every glyph is clean alone), not kerning (identical with it off, and every pair value is
    // finite) and not the position (m is clean at 197.7 when asked directly). It only appears
    // through opentype.js's own positioning pass on this variable font, which is a family it
    // does not fully support. At x=0,y=0 that pass has nothing to do, so it cannot go wrong —
    // and an offset is arithmetic we can do exactly.
    const glyphPath = glyph.getPath(0, 0, FONT_SIZE);
    for (const cmd of glyphPath.commands) {
      if (cmd.x !== undefined) { cmd.x += penX; cmd.y += y; }
      if (cmd.x1 !== undefined) { cmd.x1 += penX; cmd.y1 += y; }
      if (cmd.x2 !== undefined) { cmd.x2 += penX; cmd.y2 += y; }
    }
    path.extend(glyphPath);

    penX += glyph.advanceWidth * scale;
    const next = glyphs[i + 1];
    if (next) {
      const kern = font.getKerningValue(glyph, next);
      if (Number.isFinite(kern)) penX += kern * scale;
    }
  });
  return path;
}

function buildEntry(font, text) {
  // Pass 1 at the origin tells us where the outlines actually land (y is a baseline, so the
  // box straddles it), pass 2 re-renders shifted so the box sits at PAD,PAD inside a viewBox.
  const probe = layout(font, text, 0, 0).getBoundingBox();
  const dx = PAD - probe.x1;
  const dy = PAD - probe.y1;

  const glyphPath = layout(font, text, dx, dy);
  const box = glyphPath.getBoundingBox();
  const width = round(box.x2 + PAD);
  const height = round(box.y2 + PAD);

  const d = serialisePath(glyphPath.commands, DECIMALS);

  // A path is a string, so a broken coordinate does not throw — it serialises the literal
  // text "NaN" into the d attribute and the browser silently drops that subpath. The first
  // generated "Welcome" shipped with 13 of them. Refuse to emit rather than write a mark
  // that renders wrong; a build that fails here is far cheaper than one that does not.
  if (!Number.isFinite(width) || !Number.isFinite(height) || /NaN|Infinity|undefined/.test(d)) {
    const bad = (d.match(/NaN|Infinity|undefined/g) ?? []).length;
    throw new Error(
      `Path for ${JSON.stringify(text)} is not renderable: ${bad} invalid coordinate(s), ` +
        `width=${width} height=${height}.
` +
        `  This is usually a glyph whose contour opentype.js could not resolve at this em size. ` +
        `Try a different FONT_SIZE, or a font that has every glyph in the string.`,
    );
  }

  return { text, d, width, height, viewBox: `0 0 ${width} ${height}` };
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

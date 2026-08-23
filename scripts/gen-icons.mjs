#!/usr/bin/env node
/**
 * NIVORA app icons — every size the web app and the Android wrapper need, cut from
 * one source file so a brand change is one re-run and not an afternoon in an image editor.
 *
 *   node scripts/gen-icons.mjs           # regenerate everything
 *   node scripts/gen-icons.mjs --check   # verify what is on disk, write nothing
 *   node scripts/gen-icons.mjs --quiet   # no measurement tables, just the summary
 *
 * THE SOURCE AND WHY IT NEEDS WORK
 * nivoralogo.png is 1536x1024 (3:2) RGBA. 90.7% of it is fully transparent padding and
 * it is a *vertical lockup*: the N-house mark on top, the "NIVORA" wordmark underneath.
 * Three things follow from that, and this script does all three rather than pretending
 * the file is already an icon:
 *
 *   1. TRIM.  Padding is stripped with sharp's .trim() before anything is scaled, so the
 *      mark fills its square instead of sitting small in the middle of dead space.
 *   2. SPLIT. The wordmark is dropped for icons. At 48px "NIVORA" is four grey smudges;
 *      the mark alone stays legible. The split is *measured* (the longest run of fully
 *      transparent rows inside the trimmed art), not hardcoded, and asserted — see
 *      splitLockup(). The full lockup is still exported, for in-app use, as
 *      public/brand/nivora-logo.png.
 *   3. FLATTEN. Google Play rejects a 512x512 icon that carries an alpha channel, so the
 *      Play master is composited onto a solid plate and written as 3-channel RGB.
 *
 * WHY THE PLATE IS IVORY AND NOT NAVY
 * The old placeholder mark (public/icons/icon.svg) was a white house on navy, so the
 * launcher plate was navy (#1C2B45). The real logo is the other way round: a dark navy
 * gradient mark whose measured ink is around #0B1D33. On the old navy plate it is very
 * nearly invisible. The plate is therefore #F6F4EF — the same ivory as background_color
 * in app/manifest.ts and --brand-ivory in tailwind.config.ts — which is also the ground
 * the logo was drawn for. android/app/src/main/res/values/colors.xml carries the matching
 * change to ic_launcher_background (that colour is referenced by nothing except the two
 * adaptive-icon XMLs).
 *
 * SAFE ZONES ARE MEASURED, NOT GUESSED
 * An Android adaptive icon is a 108dp canvas of which only the centre 66dp circle is
 * guaranteed to survive the OEM mask; a maskable web icon only guarantees the centre 80%.
 * Rather than picking a scale factor by eye, fitToSafeZone() binary-searches the largest
 * mark size that still keeps INK_TARGET (99.5%) of the mark's alpha mass inside that
 * circle, and the achieved figure is printed in the table. Nothing important gets cropped.
 *
 * DETERMINISM
 * Same input, same bytes out — no timestamps, no metadata, fixed resampling kernel and
 * fixed compression settings. `node scripts/gen-icons.mjs && sha256sum <outputs>` twice
 * gives identical digests, which is what makes --check meaningful in CI.
 */
import sharp from "sharp";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC = path.join(REPO_ROOT, "nivoralogo.png");

const ICONS_DIR = path.join(REPO_ROOT, "public", "icons");
const BRAND_DIR = path.join(REPO_ROOT, "public", "brand");
const RES_DIR = path.join(REPO_ROOT, "android", "app", "src", "main", "res");

const CHECK = process.argv.includes("--check");
const QUIET = process.argv.includes("--quiet");

/* ───────────────────────── brand tokens ─────────────────────────
   Transcribed from app/manifest.ts (background_color / theme_color) and
   tailwind.config.ts (--brand-ivory). Those files are the source of truth. */
const IVORY = "#F6F4EF";

/** Alpha below this counts as padding. Chosen above the source's dithered glow
 *  fringe (which sits at alpha 1..4) and far below the mark itself (alpha ~253). */
const TRIM_ALPHA = 10;

/** Fraction of the mark's alpha mass that must survive a mask for a fit to be accepted. */
const INK_TARGET = 0.995;

/** Resampling is pinned so output bytes do not move between sharp/libvips builds. */
const RESIZE = { kernel: "lanczos3", fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } };

/**
 * Two encoder profiles, because the two audiences want different files.
 *
 * PNG_INDEXED — 256-colour quantised. The art is a two-tone navy gradient on a flat
 * plate, so 256 colours is effectively lossless: measured against the truecolour render
 * composited onto #F6F4EF, mean error is 0.15/255 and only 0.008% of subpixels move by
 * more than 8. It is ~2.8x smaller, which is 500 kB off the repo and off the APK.
 * (`effort` is a palette-mode setting in sharp — with `palette:false` it is ignored,
 * which is exactly the trap that made the first cut of these files 3x too big.)
 *
 * PNG_TRUECOLOR — Play asks for a "32-bit PNG" for the store icon, so the masters that
 * feed the listing are left unquantised rather than shipped as an indexed image that a
 * reviewer's tooling might reject.
 */
const PNG_INDEXED = { compressionLevel: 9, effort: 10, palette: true, colours: 256, dither: 1.0 };
const PNG_TRUECOLOR = { compressionLevel: 9, palette: false };
/** Intermediates stay unquantised so nothing is quantised twice. */
const PNG_WORK = { compressionLevel: 0, palette: false };

const log = (...a) => { if (!QUIET) console.log(...a); };

/* ───────────────────────── geometry helpers ───────────────────────── */

/** Tight bounding box of pixels with alpha > threshold, measured on raw RGBA. */
function alphaBBox(data, width, height, threshold) {
  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (data[(y * width + x) * 4 + 3] > threshold) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) throw new Error("alphaBBox: the image is entirely transparent");
  return { left: x0, top: y0, width: x1 - x0 + 1, height: y1 - y0 + 1 };
}

/**
 * Split the trimmed lockup into the mark (top) and the wordmark (bottom) at the longest
 * run of rows that carry no ink at all. Throws rather than guessing if the art stops
 * looking like a two-part vertical lockup — a silently mis-cropped icon is worse than
 * a failed build.
 */
function splitLockup(data, width, height) {
  const rowMax = new Array(height).fill(0);
  for (let y = 0; y < height; y += 1) {
    let m = 0;
    for (let x = 0; x < width; x += 1) {
      const a = data[(y * width + x) * 4 + 3];
      if (a > m) m = a;
    }
    rowMax[y] = m;
  }
  let best = null;
  let run = null;
  for (let y = 0; y < height; y += 1) {
    if (rowMax[y] <= TRIM_ALPHA) {
      if (!run) run = { y0: y };
    } else if (run) {
      run.y1 = y - 1;
      if (!best || run.y1 - run.y0 > best.y1 - best.y0) best = run;
      run = null;
    }
  }
  if (!best) throw new Error("splitLockup: no blank band found — the source is not a stacked lockup");

  const gap = best.y1 - best.y0 + 1;
  const mark = alphaBBox(data.subarray(0, best.y0 * width * 4), width, best.y0, TRIM_ALPHA);
  const wordHeight = height - (best.y1 + 1);
  const wordRaw = alphaBBox(data.subarray((best.y1 + 1) * width * 4), width, wordHeight, TRIM_ALPHA);
  const word = { ...wordRaw, top: wordRaw.top + best.y1 + 1 };

  const markAspect = mark.width / mark.height;
  const wordAspect = word.width / word.height;
  if (markAspect < 0.8 || markAspect > 1.4) {
    throw new Error(`splitLockup: top band aspect ${markAspect.toFixed(2)} is not the near-square mark`);
  }
  if (wordAspect < 4) {
    throw new Error(`splitLockup: bottom band aspect ${wordAspect.toFixed(2)} is not the wide wordmark`);
  }
  return { mark, word, gap };
}

/** Fraction of an RGBA buffer's alpha mass falling inside a centred circle. */
function inkInsideCircle(data, size, radius) {
  const c = (size - 1) / 2;
  let inside = 0;
  let total = 0;
  const r2 = radius * radius;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const a = data[(y * size + x) * 4 + 3];
      if (!a) continue;
      total += a;
      const dx = x - c;
      const dy = y - c;
      if (dx * dx + dy * dy <= r2) inside += a;
    }
  }
  return total === 0 ? 0 : inside / total;
}

/**
 * Largest mark width (as a fraction of the canvas) that still keeps INK_TARGET of the
 * mark's ink inside a centred safe circle of the given radius fraction. Deterministic
 * binary search — fixed bounds, fixed iteration count.
 */
async function fitToSafeZone(markPng, safeRadiusFrac) {
  const PROBE = 256;
  const radius = safeRadiusFrac * PROBE;
  const probe = async (frac) => {
    const w = Math.max(2, Math.round(PROBE * frac));
    const buf = await sharp({ create: { width: PROBE, height: PROBE, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite([{ input: await sharp(markPng).resize(w, w, RESIZE).png(PNG_WORK).toBuffer(), gravity: "centre" }])
      .raw()
      .toBuffer();
    return inkInsideCircle(buf, PROBE, radius);
  };
  let lo = 0.20;
  let hi = 1.00;
  for (let i = 0; i < 18; i += 1) {
    const mid = (lo + hi) / 2;
    // Sequential by definition: each probe decides where the next one looks.
    if (await probe(mid) >= INK_TARGET) lo = mid; else hi = mid;
  }
  return { frac: Math.round(lo * 1000) / 1000, ink: await probe(lo) };
}

/* ───────────────────────── composition ───────────────────────── */

/** An `<svg>` rounded rectangle used as the icon plate. r=0 gives a full-bleed square. */
function plate(size, radius, fill) {
  const r = Math.round(radius);
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
      `<rect width="${size}" height="${size}" rx="${r}" ry="${r}" fill="${fill}"/></svg>`,
  );
}

/** A circular plate, for the pre-API-26 round launcher icon. */
function disc(size, fill) {
  const c = size / 2;
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}">` +
      `<circle cx="${c}" cy="${c}" r="${c}" fill="${fill}"/></svg>`,
  );
}

/**
 * Centre the mark on a canvas.
 *  shape "square" | "rounded" | "circle" | "none" (transparent, no plate)
 *  opaque   drop the alpha channel entirely (Play, iOS)
 */
async function compose(markPng, { size, markFrac, shape, fill = IVORY, opaque = false, truecolor = false }) {
  const w = Math.max(1, Math.round(size * markFrac));
  const mark = await sharp(markPng).resize(w, w, RESIZE).png(PNG_WORK).toBuffer();

  const layers = [];
  if (shape === "rounded") layers.push({ input: plate(size, size * 0.2237, fill) });
  else if (shape === "square") layers.push({ input: plate(size, 0, fill) });
  else if (shape === "circle") layers.push({ input: disc(size, fill) });
  layers.push({ input: mark, gravity: "centre" });

  let img = sharp({ create: { width: size, height: size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(layers);
  // .flatten() alone composites the pixels onto the plate but still writes a 32-bit RGBA
  // PNG with a fully-opaque alpha channel. Play rejects the *channel*, not just visible
  // transparency, so the alpha band has to be dropped as well.
  if (opaque) img = img.flatten({ background: fill }).removeAlpha();
  return img.png(truecolor ? PNG_TRUECOLOR : PNG_INDEXED).toBuffer();
}

/** White silhouette from the mark's alpha — Android 13 themed icons tint this themselves. */
async function monochrome(markPng, size, markFrac) {
  const w = Math.max(1, Math.round(size * markFrac));
  const { data, info } = await sharp(markPng).resize(w, w, RESIZE).raw().toBuffer({ resolveWithObject: true });
  const out = Buffer.alloc(data.length);
  for (let i = 0; i < data.length; i += 4) {
    out[i] = 255;
    out[i + 1] = 255;
    out[i + 2] = 255;
    out[i + 3] = data[i + 3];
  }
  const white = await sharp(out, { raw: { width: info.width, height: info.height, channels: 4 } }).png(PNG_WORK).toBuffer();
  return sharp({ create: { width: size, height: size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: white, gravity: "centre" }])
    .png(PNG_INDEXED)
    .toBuffer();
}

/**
 * Minimal .ico container holding PNG-compressed frames (the Vista+ form, understood by
 * every browser in support). sharp cannot write .ico, and pulling a dependency in for
 * 22 bytes of header per frame is not a trade worth making.
 */
function ico(frames) {
  const dir = Buffer.alloc(6 + frames.length * 16);
  dir.writeUInt16LE(0, 0);
  dir.writeUInt16LE(1, 2);
  dir.writeUInt16LE(frames.length, 4);
  let offset = dir.length;
  frames.forEach(({ size, png }, i) => {
    const e = 6 + i * 16;
    dir.writeUInt8(size >= 256 ? 0 : size, e);
    dir.writeUInt8(size >= 256 ? 0 : size, e + 1);
    dir.writeUInt8(0, e + 2);
    dir.writeUInt8(0, e + 3);
    dir.writeUInt16LE(1, e + 4);
    dir.writeUInt16LE(32, e + 6);
    dir.writeUInt32LE(png.length, e + 8);
    dir.writeUInt32LE(offset, e + 12);
    offset += png.length;
  });
  return Buffer.concat([dir, ...frames.map((f) => f.png)]);
}

/* ───────────────────────── writing + verification ───────────────────────── */

const written = [];

function emit(absPath, buf) {
  const rel = path.relative(REPO_ROOT, absPath).split(path.sep).join("/");
  const sha = crypto.createHash("sha256").update(buf).digest("hex");
  if (CHECK) {
    if (!fs.existsSync(absPath)) throw new Error(`--check: missing ${rel}`);
    const have = crypto.createHash("sha256").update(fs.readFileSync(absPath)).digest("hex");
    if (have !== sha) throw new Error(`--check: ${rel} does not match a fresh render`);
  } else {
    fs.mkdirSync(path.dirname(absPath), { recursive: true });
    fs.writeFileSync(absPath, buf);
  }
  written.push({ rel, bytes: buf.length, sha });
  return absPath;
}

/** Re-open every output with sharp and report what is actually on disk. */
async function verify(expectations) {
  const rows = [];
  const failures = [];
  for (const exp of expectations) {
    const abs = path.join(REPO_ROOT, exp.rel);
    // Sequential so the printed table keeps the declared order.
    const meta = await sharp(abs).metadata();
    const bytes = fs.statSync(abs).size;
    const row = {
      file: exp.rel,
      dims: `${meta.width}x${meta.height}`,
      ch: meta.channels,
      alpha: meta.hasAlpha ? "yes" : "NO",
      png: meta.isPalette ? "indexed" : "truecolor",
      kb: (bytes / 1024).toFixed(1),
    };
    rows.push(row);
    if (meta.width !== exp.w || meta.height !== exp.h) {
      failures.push(`${exp.rel}: expected ${exp.w}x${exp.h}, found ${meta.width}x${meta.height}`);
    }
    if (exp.alpha === false && meta.hasAlpha) failures.push(`${exp.rel}: MUST NOT have an alpha channel`);
    if (exp.alpha === true && !meta.hasAlpha) failures.push(`${exp.rel}: must keep its alpha channel`);
    if (exp.channels && meta.channels !== exp.channels) {
      failures.push(`${exp.rel}: expected ${exp.channels} channels, found ${meta.channels}`);
    }
  }
  return { rows, failures };
}

function table(rows) {
  const cols = Object.keys(rows[0]);
  const w = cols.map((c) => Math.max(c.length, ...rows.map((r) => String(r[c]).length)));
  const line = (cells) => "  " + cells.map((c, i) => String(c).padEnd(w[i])).join("  ");
  log(line(cols));
  log("  " + w.map((n) => "-".repeat(n)).join("  "));
  rows.forEach((r) => log(line(cols.map((c) => r[c]))));
}

/* ───────────────────────── main ───────────────────────── */

async function main() {
  if (!fs.existsSync(SRC)) throw new Error(`source logo not found: ${SRC}`);

  const srcMeta = await sharp(SRC).metadata();
  log(`source  nivoralogo.png  ${srcMeta.width}x${srcMeta.height}  ${srcMeta.channels}ch  alpha=${srcMeta.hasAlpha}`);
  if (!srcMeta.hasAlpha) throw new Error("source logo has no alpha channel — the trim step assumes one");

  /* 1. trim the transparent padding off the lockup */
  const trimmed = await sharp(SRC).trim({ threshold: TRIM_ALPHA }).png(PNG_WORK).toBuffer({ resolveWithObject: true });
  const t = trimmed.info;
  log(
    `trim    sharp .trim({threshold:${TRIM_ALPHA}}) -> ${t.width}x${t.height} ` +
      `at (${-t.trimOffsetLeft},${-t.trimOffsetTop})  ` +
      `dropped ${(100 - (t.width * t.height * 100) / (srcMeta.width * srcMeta.height)).toFixed(1)}% of the canvas`,
  );

  /* 2. split mark from wordmark */
  const raw = await sharp(trimmed.data).raw().toBuffer();
  const { mark, word, gap } = splitLockup(raw, t.width, t.height);
  log(
    `split   blank band ${gap}px  ->  mark ${mark.width}x${mark.height} (aspect ${(mark.width / mark.height).toFixed(3)})` +
      `  wordmark ${word.width}x${word.height} (aspect ${(word.width / word.height).toFixed(2)}, dropped from icons)`,
  );

  /* Square the mark by padding, never by stretching. */
  const side = Math.max(mark.width, mark.height);
  const markSquare = await sharp(trimmed.data)
    .extract({ left: mark.left, top: mark.top, width: mark.width, height: mark.height })
    .extend({
      top: Math.floor((side - mark.height) / 2),
      bottom: Math.ceil((side - mark.height) / 2),
      left: Math.floor((side - mark.width) / 2),
      right: Math.ceil((side - mark.width) / 2),
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png(PNG_WORK)
    .toBuffer();
  log(`square  padded ${mark.width}x${mark.height} -> ${side}x${side} (no stretching; native mark resolution is ${side}px)`);

  /* 3. measured safe-zone fits */
  const adaptive = await fitToSafeZone(markSquare, 33 / 108); // Android: centre 66dp of 108dp
  const maskable = await fitToSafeZone(markSquare, 0.40); // web maskable: centre 80%
  const round = await fitToSafeZone(markSquare, 0.40); // inside a circular plate, with margin
  log(
    `safezone adaptive-icon ${(adaptive.frac * 100).toFixed(1)}% of canvas (${(adaptive.ink * 100).toFixed(2)}% of ink inside the 66dp circle)  |  ` +
      `maskable ${(maskable.frac * 100).toFixed(1)}% (${(maskable.ink * 100).toFixed(2)}% inside the 80% circle)  |  ` +
      `round plate ${(round.frac * 100).toFixed(1)}%`,
  );

  const expectations = [];
  const add = (abs, exp) => expectations.push({ rel: path.relative(REPO_ROOT, abs).split(path.sep).join("/"), ...exp });

  /* ── public/brand ── */

  // Full lockup, trimmed and rescaled, transparent — for in-app use.
  const LOCKUP_W = 1024;
  const lockup = await sharp(trimmed.data)
    .resize(LOCKUP_W, null, { kernel: "lanczos3" })
    .png(PNG_INDEXED)
    .toBuffer();
  const lockupMeta = await sharp(lockup).metadata();
  add(emit(path.join(BRAND_DIR, "nivora-logo.png"), lockup), { w: LOCKUP_W, h: lockupMeta.height, alpha: true });

  // Square, opaque master for scripts/store-assets.mjs (owned by the store-assets pass).
  const MASTER_FRAC = 0.72;
  add(emit(path.join(BRAND_DIR, "logo-square-1024.png"), await compose(markSquare, { size: 1024, markFrac: MASTER_FRAC, shape: "square", opaque: true, truecolor: true })), { w: 1024, h: 1024, alpha: false, channels: 3 });

  // The Play icon itself, to Play's spec, so the deliverable is testable without
  // writing into public/store/ (a different pass owns that directory).
  add(emit(path.join(BRAND_DIR, "play-icon-512.png"), await compose(markSquare, { size: 512, markFrac: MASTER_FRAC, shape: "square", opaque: true, truecolor: true })), { w: 512, h: 512, alpha: false, channels: 3 });

  /* ── public/icons ── filenames are fixed by app/manifest.ts and app/layout.tsx ── */

  // purpose "any": a normal rounded-square app icon.
  add(emit(path.join(ICONS_DIR, "icon-192.png"), await compose(markSquare, { size: 192, markFrac: 0.62, shape: "rounded" })), { w: 192, h: 192, alpha: true });

  // purpose "maskable": must be full-bleed, so square corners and no transparency,
  // with the mark inside the guaranteed centre 80%.
  add(emit(path.join(ICONS_DIR, "icon-512.png"), await compose(markSquare, { size: 512, markFrac: maskable.frac, shape: "square", opaque: true })), { w: 512, h: 512, alpha: false, channels: 3 });

  // iOS composites onto black wherever an apple-touch-icon is transparent, and applies
  // its own squircle — so this one is opaque with square corners too.
  add(emit(path.join(ICONS_DIR, "apple-touch-icon.png"), await compose(markSquare, { size: 180, markFrac: 0.62, shape: "square", opaque: true })), { w: 180, h: 180, alpha: false, channels: 3 });

  // Browser tab icon. Slightly chunkier than icon-192 because 16px eats fine detail.
  const icoFrames = [];
  for (const size of [16, 32, 48]) {
    icoFrames.push({ size, png: await compose(markSquare, { size, markFrac: 0.72, shape: "rounded" }) });
  }
  emit(path.join(ICONS_DIR, "favicon.ico"), ico(icoFrames));

  /* ── android launcher icons ──
     Names must match what mipmap-anydpi-v26/*.xml and AndroidManifest.xml already
     reference: ic_launcher, ic_launcher_round, ic_launcher_foreground,
     ic_launcher_monochrome. */
  const DENSITIES = [
    { dir: "mdpi", legacy: 48, adaptive: 108 },
    { dir: "hdpi", legacy: 72, adaptive: 162 },
    { dir: "xhdpi", legacy: 96, adaptive: 216 },
    { dir: "xxhdpi", legacy: 144, adaptive: 324 },
    { dir: "xxxhdpi", legacy: 192, adaptive: 432 },
  ];

  for (const d of DENSITIES) {
    /* One density at a time keeps peak memory flat. */
    add(emit(path.join(RES_DIR, `mipmap-${d.dir}`, "ic_launcher.png"), await compose(markSquare, { size: d.legacy, markFrac: 0.64, shape: "rounded" })), { w: d.legacy, h: d.legacy, alpha: true });
    add(emit(path.join(RES_DIR, `mipmap-${d.dir}`, "ic_launcher_round.png"), await compose(markSquare, { size: d.legacy, markFrac: round.frac, shape: "circle" })), { w: d.legacy, h: d.legacy, alpha: true });
    add(emit(path.join(RES_DIR, `drawable-${d.dir}`, "ic_launcher_foreground.png"), await compose(markSquare, { size: d.adaptive, markFrac: adaptive.frac, shape: "none" })), { w: d.adaptive, h: d.adaptive, alpha: true });
    add(emit(path.join(RES_DIR, `drawable-${d.dir}`, "ic_launcher_monochrome.png"), await monochrome(markSquare, d.adaptive, adaptive.frac)), { w: d.adaptive, h: d.adaptive, alpha: true });
  }

  /* 4. verify what landed on disk */
  if (!CHECK) {
    log("");
    const { rows, failures } = await verify(expectations);
    table(rows);
    const play = await sharp(path.join(BRAND_DIR, "play-icon-512.png")).stats();
    const master = await sharp(path.join(BRAND_DIR, "logo-square-1024.png")).stats();
    log("");
    log(`assert  play-icon-512.png     isOpaque=${play.isOpaque} (Play rejects alpha)`);
    log(`assert  logo-square-1024.png  isOpaque=${master.isOpaque}`);
    if (!play.isOpaque || !master.isOpaque) failures.push("a Play asset still carries transparency");
    if (failures.length) {
      failures.forEach((f) => console.error(`FAIL  ${f}`));
      process.exitCode = 1;
      return;
    }
  }

  const total = written.reduce((n, f) => n + f.bytes, 0);
  console.log("");
  console.log(`${CHECK ? "checked" : "wrote"} ${written.length} files, ${(total / 1024).toFixed(1)} kB total`);
}

main().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});

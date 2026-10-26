#!/usr/bin/env node
/**
 * Apnivaas brand assets — the app icons for every platform, the transparent masters they are
 * cut from, and the launch animation — from the two files the owner supplied, so a brand change
 * is one re-run and not an afternoon in an image editor.
 *
 *   node scripts/gen-icons.mjs                    # every icon, from the committed masters
 *   node scripts/gen-icons.mjs --check            # verify the icons on disk, write nothing
 *   node scripts/gen-icons.mjs --cut              # ALSO re-cut the masters from Apnivaas_8K_UHD.png
 *   node scripts/gen-icons.mjs --splash --ffmpeg=<path to ffmpeg>
 *                                                 # ALSO rebuild the launch animation from the mp4
 *   node scripts/gen-icons.mjs --quiet            # no measurement tables, just the summary
 *
 * ── THE TWO SOURCES, AND WHY NEITHER IS USABLE AS IT STANDS ──────────────────────────────────
 *
 * Apnivaas_8K_UHD.png (repo root) is 7680x7680 RGBA, but its alpha is 255 EVERYWHERE. It is an
 * app-icon mockup, not a master: a near-white page (#FEFEFE) with a baked-in rounded tile
 * (#FEFCF9), a drop shadow, the green A-house mark and the "Apnivaas" wordmark under it. Fed
 * straight into an icon pipeline it gives a double-masked Android icon, a shadowed iOS icon and a
 * wordmark that is four smudges at 48px. And a square crop centred on the mark pulls in the top
 * of the wordmark, so the mark has to be LIFTED onto a new canvas, never cropped.
 *
 * So `--cut` lifts it, by colour distance from the tile: alpha ramps from 0 to 1 as the summed
 * channel distance from #FEFCF9 goes from 12 to 55 (the tile itself drifts by up to 9 between
 * its top and its bottom, which is why the floor is 12), and each partly covered edge pixel has
 * the tile colour taken back OUT of it, so the mark keeps no pale fringe on a dark or beige
 * ground. The result is committed as two transparent masters under apnivaas_app/assets/brand/:
 *
 *   apnivaas_mark.png    the A-house alone, 2048px wide, trimmed to its ink
 *   apnivaas_lockup.png  the mark above the wordmark, exactly as the artwork sets them, 2048 wide
 *
 * Everything else is made from those two files, so the 7.6 MB mockup only has to be present
 * when the cut itself is redone. (The masters are NOT declared in pubspec.yaml and so do not
 * ship in the app; only the two launch WebPs do.)
 *
 * "Logo animation.mp4" (repo root) is 6.0s of 1080x1920 portrait H.264 with a stereo AAC sound
 * effect and a Gemini sparkle watermark in the bottom-right corner. `--splash` turns it into
 * what the app plays on a cold start — see makeSplash() for every number and why.
 *
 * ── WHERE THE OUTPUT GOES ────────────────────────────────────────────────────────────────────
 *
 *   apnivaas_app/android/app/src/main/res   launcher, round, adaptive foreground + monochrome,
 *                                         and the status-bar notification icon
 *   apnivaas_app/ios/.../AppIcon.appiconset the single 1024 universal icon (Xcode derives the rest)
 *   public/icons + app/favicon.ico        the website's PWA icons and favicon
 *   public/brand                          the square store masters, and the lockup the
 *                                         website's sign-in card shows
 *
 * This used to write its launcher icons into a separate web-wrapper project (removed on
 * 2026-10-14), and the Flutter and iOS copies were then copied across by hand, which is exactly
 * how an app ends up shipping a new name with the old icon. It writes the app the Play listing
 * actually serves.
 *
 * ── SAFE ZONES ARE MEASURED, NOT GUESSED ─────────────────────────────────────────────────────
 *
 * An Android adaptive icon is a 108dp canvas of which only the centre 66dp circle is guaranteed
 * to survive the launcher's mask; a maskable web icon only guarantees the centre 80%. fitInCircle()
 * binary-searches the widest mark that puts NO visible pixel (alpha above 8) outside that circle
 * — strictly, not "99.5% of the ink", because the mark is wider than it is tall and the 0.5% that
 * escaped under the old rule was the tips of both feet of the A. The adaptive layer is also held
 * at or under half the canvas width, which is what the safe circle allows for this shape anyway.
 *
 * ── DETERMINISM ──────────────────────────────────────────────────────────────────────────────
 *
 * Same input, same bytes out — no timestamps, no metadata, a fixed resampling kernel and fixed
 * compression settings. Running it twice gives identical digests, which is what makes --check
 * meaningful. (--splash is the exception that proves the rule: it depends on an external ffmpeg
 * build, so --check never re-renders the animation; the Dart test reads the WebP's own bytes.)
 */
import sharp from "sharp";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** The owner's artwork. Only read by --cut (the animation is read by scripts/gen-splash.mjs). */
const SRC_ART = path.join(REPO_ROOT, "Apnivaas_8K_UHD.png");

const APP = path.join(REPO_ROOT, "apnivaas_app");
const APP_BRAND = path.join(APP, "assets", "brand");
const MARK_MASTER = path.join(APP_BRAND, "apnivaas_mark.png");
const LOCKUP_MASTER = path.join(APP_BRAND, "apnivaas_lockup.png");

const RES_DIR = path.join(APP, "android", "app", "src", "main", "res");
const IOS_ICON = path.join(APP, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset", "Icon-App-1024x1024@1x.png");

const ICONS_DIR = path.join(REPO_ROOT, "public", "icons");
const BRAND_DIR = path.join(REPO_ROOT, "public", "brand");
const NEXT_FAVICON = path.join(REPO_ROOT, "app", "favicon.ico");

const ARGS = process.argv.slice(2);
const CHECK = ARGS.includes("--check");
const QUIET = ARGS.includes("--quiet");
const CUT = ARGS.includes("--cut");
const MAKE_SPLASH = ARGS.includes("--splash");
const FFMPEG = (ARGS.find((a) => a.startsWith("--ffmpeg=")) ?? "").slice("--ffmpeg=".length) || process.env.FFMPEG || "ffmpeg";

/* ───────────────────────── brand tokens ───────────────────────── */

/**
 * THE PLATE. The artwork's own tile colour, measured off the mockup (its median between the mark
 * and the wordmark is #FDFBF8, and #FEFCF9 at the top of the tile). Every icon that needs a solid
 * ground uses it — legacy launcher plates, iOS, the maskable web icon, the Play icon — and
 * values/colors.xml carries it as ic_launcher_background for the adaptive icon. A warm white
 * rather than the splash beige: on a launcher grid of white and pale icons the beige read as
 * "dirty", and #FEFCF9 is what the mark was drawn on.
 */
const PLATE = "#FEFCF9";
const PLATE_RGB = [254, 252, 249];

/** The colour-distance ramp of the cut. See the header for why 12, and 55 is the first value at
 *  which every pixel of the anti-aliased edge of the mark has been counted as fully opaque. */
const CUT_LO = 12;
const CUT_HI = 55;

/** Alpha above this is "visible" for the strict safe-zone fit. */
const VISIBLE_ALPHA = 8;

/** Resampling is pinned so output bytes do not move between sharp/libvips builds. */
const RESIZE = { kernel: "lanczos3", fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } };

/**
 * Two encoder profiles, because the two audiences want different files.
 *
 * PNG_INDEXED — 256-colour quantised, dithered. The launcher icons are a green gradient on a flat
 * plate and are never shown larger than they are encoded, so a palette is visually lossless at
 * these sizes and roughly a third of the bytes, which comes straight off the APK. (`effort` is a
 * palette-mode setting in sharp — with `palette:false` it is ignored.)
 *
 * PNG_TRUECOLOR — the masters and every file a store or Xcode ingests. Play asks for a "32-bit
 * PNG" icon, and a master that has already been quantised would be quantised again downstream.
 */
const PNG_INDEXED = { compressionLevel: 9, effort: 10, palette: true, colours: 256, dither: 1.0 };
const PNG_TRUECOLOR = { compressionLevel: 9, palette: false };
/** Intermediates stay unquantised so nothing is quantised twice. */
const PNG_WORK = { compressionLevel: 0, palette: false };

const log = (...a) => { if (!QUIET) console.log(...a); };
const rel = (abs) => path.relative(REPO_ROOT, abs).split(path.sep).join("/");
const hex = ([r, g, b]) => `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase()}`;

/* ───────────────────────── writing + verification ───────────────────────── */

const written = [];

function emit(absPath, buf) {
  const sha = crypto.createHash("sha256").update(buf).digest("hex");
  if (CHECK) {
    if (!fs.existsSync(absPath)) throw new Error(`--check: missing ${rel(absPath)}`);
    const have = crypto.createHash("sha256").update(fs.readFileSync(absPath)).digest("hex");
    if (have !== sha) throw new Error(`--check: ${rel(absPath)} does not match a fresh render`);
  } else {
    fs.mkdirSync(path.dirname(absPath), { recursive: true });
    fs.writeFileSync(absPath, buf);
  }
  written.push({ rel: rel(absPath), bytes: buf.length, sha });
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
    rows.push({
      file: exp.rel,
      dims: `${meta.width}x${meta.height}`,
      ch: meta.channels,
      alpha: meta.hasAlpha ? "yes" : "NO",
      png: meta.isPalette ? "indexed" : "truecolor",
      kb: (bytes / 1024).toFixed(1),
    });
    if (meta.width !== exp.w || meta.height !== exp.h) {
      failures.push(`${exp.rel}: expected ${exp.w}x${exp.h}, found ${meta.width}x${meta.height}`);
    }
    if (exp.alpha === false && meta.hasAlpha) failures.push(`${exp.rel}: MUST NOT have an alpha channel`);
    if (exp.alpha === true && !meta.hasAlpha) failures.push(`${exp.rel}: must keep its alpha channel`);
    if (exp.channels && meta.channels !== exp.channels) {
      failures.push(`${exp.rel}: expected ${exp.channels} channels, found ${meta.channels}`);
    }
    if (exp.whiteOnly) {
      // A status-bar icon is drawn from its ALPHA alone; any colour in it is a sign the wrong
      // layer was written, and Android would show the colour as white anyway.
      const { data, info } = await sharp(abs).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      for (let i = 0; i < data.length; i += info.channels) {
        if (data[i + 3] > 0 && (data[i] !== 255 || data[i + 1] !== 255 || data[i + 2] !== 255)) {
          failures.push(`${exp.rel}: a visible pixel is not white`);
          break;
        }
      }
    }
  }
  return { rows, failures };
}

function table(rows) {
  if (!rows.length) return;
  const cols = Object.keys(rows[0]);
  const w = cols.map((c) => Math.max(c.length, ...rows.map((r) => String(r[c]).length)));
  const line = (cells) => "  " + cells.map((c, i) => String(c).padEnd(w[i])).join("  ");
  log(line(cols));
  log("  " + w.map((n) => "-".repeat(n)).join("  "));
  rows.forEach((r) => log(line(cols.map((c) => r[c]))));
}

/* ───────────────────────── geometry helpers ───────────────────────── */

/** Tight bounding box of pixels with alpha > threshold, measured on raw RGBA. */
function alphaBBox(data, width, height, threshold, y0 = 0, y1 = height) {
  let bx0 = width, by0 = height, bx1 = -1, by1 = -1;
  for (let y = y0; y < y1; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (data[(y * width + x) * 4 + 3] > threshold) {
        if (x < bx0) bx0 = x;
        if (x > bx1) bx1 = x;
        if (y < by0) by0 = y;
        if (y > by1) by1 = y;
      }
    }
  }
  if (bx1 < 0) throw new Error("alphaBBox: no visible pixels in the band");
  return { left: bx0, top: by0, width: bx1 - bx0 + 1, height: by1 - by0 + 1 };
}

/** Whether any visible pixel of a square RGBA buffer lies outside a centred circle. */
function escapesCircle(data, size, radius) {
  const c = (size - 1) / 2;
  const r2 = radius * radius;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      if (data[(y * size + x) * 4 + 3] <= VISIBLE_ALPHA) continue;
      const dx = x - c;
      const dy = y - c;
      if (dx * dx + dy * dy > r2) return true;
    }
  }
  return false;
}

/**
 * The widest mark (as a fraction of the canvas width) whose every visible pixel stays inside a
 * centred circle of the given radius fraction, capped at `max`. Deterministic binary search —
 * fixed bounds, fixed iteration count.
 *
 * Probed at EVERY size the layer is drawn at, not just the largest. The A-house's feet sit at
 * the bottom corners of its box, which is exactly where a circle is tightest, so at 50% of the
 * canvas the mark is within a pixel of the 66dp circle — and whether that pixel lands inside
 * depends on how each density's resample rounds. Probing only 432px passed a fraction that put
 * ink outside the circle at 324px (xxhdpi).
 */
async function fitInCircle(markPng, radiusFrac, max = 1, sizes = [432]) {
  const probe = async (frac) => {
    for (const size of sizes) {
      // Sequential: the first size that fails decides, and the rest need not be drawn.
      const layer = await placeMark(markPng, size, frac);
      const raw = await sharp(layer).raw().toBuffer();
      if (escapesCircle(raw, size, radiusFrac * size)) return false;
    }
    return true;
  };
  let lo = 0.2;
  let hi = max;
  if (await probe(hi)) return hi;
  for (let i = 0; i < 16; i += 1) {
    const mid = (lo + hi) / 2;
    // Sequential by definition: each probe decides where the next one looks.
    if (await probe(mid)) lo = mid; else hi = mid;
  }
  return Math.floor(lo * 1000) / 1000;
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
 * The mark, `frac` of the canvas WIDE and centred, on a transparent square canvas. Width rather
 * than the longer side because the A-house is wider than it is tall (about 1.38:1), so every
 * fraction in this file is a horizontal one and the height follows from the artwork.
 */
async function placeMark(markPng, size, frac) {
  const meta = await sharp(markPng).metadata();
  const w = Math.max(1, Math.round(size * frac));
  const h = Math.max(1, Math.round((w * meta.height) / meta.width));
  const mark = await sharp(markPng).resize(w, h, RESIZE).png(PNG_WORK).toBuffer();
  return sharp({ create: { width: size, height: size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite([{ input: mark, left: Math.floor((size - w) / 2), top: Math.floor((size - h) / 2) }])
    .png(PNG_WORK)
    .toBuffer();
}

/**
 * Centre the mark on a canvas.
 *  shape    "square" | "rounded" | "circle" | "none" (transparent, no plate)
 *  opaque   drop the alpha channel entirely (iOS, the maskable icon, the store masters)
 */
async function compose(markPng, { size, frac, shape, fill = PLATE, opaque = false, truecolor = false }) {
  const layers = [];
  if (shape === "rounded") layers.push({ input: plate(size, size * 0.2237, fill) });
  else if (shape === "square") layers.push({ input: plate(size, 0, fill) });
  else if (shape === "circle") layers.push({ input: disc(size, fill) });
  layers.push({ input: await placeMark(markPng, size, frac) });

  let img = sharp({ create: { width: size, height: size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(layers);
  // .flatten() alone composites the pixels onto the plate but still writes a 32-bit RGBA PNG
  // with a fully-opaque alpha channel. Apple and Play reject the CHANNEL, not just visible
  // transparency, so the alpha band has to be dropped as well.
  if (opaque) img = img.flatten({ background: fill }).removeAlpha();
  return img.png(truecolor ? PNG_TRUECOLOR : PNG_INDEXED).toBuffer();
}

/**
 * White silhouette from the mark's alpha. Two jobs: the Android 13 themed-icon layer (the
 * launcher tints it itself) and the status-bar notification icon (Android draws ONLY the alpha
 * of a small icon, so a coloured or opaque one becomes a solid white blob — which is exactly what
 * `@mipmap/ic_launcher` used to do there).
 */
async function silhouette(markPng, size, frac) {
  const layer = await placeMark(markPng, size, frac);
  const { data, info } = await sharp(layer).raw().toBuffer({ resolveWithObject: true });
  const out = Buffer.alloc(data.length);
  for (let i = 0; i < data.length; i += 4) {
    const a = data[i + 3];
    // Colour only where there is coverage: a fully transparent pixel stays (0,0,0,0) so the
    // palette has one less entry and verify() can insist every VISIBLE pixel is white.
    out[i] = a ? 255 : 0;
    out[i + 1] = a ? 255 : 0;
    out[i + 2] = a ? 255 : 0;
    out[i + 3] = a;
  }
  return sharp(out, { raw: { width: info.width, height: info.height, channels: 4 } }).png(PNG_INDEXED).toBuffer();
}

/**
 * Minimal .ico container holding PNG-compressed frames (the Vista+ form, understood by every
 * browser in support). sharp cannot write .ico, and pulling a dependency in for 22 bytes of
 * header per frame is not a trade worth making.
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

/* ───────────────────────── 1. the cut (--cut) ───────────────────────── */

/**
 * Where the lockup sits in the 7680px mockup, measured once by scanning for non-tile pixels and
 * padded by 48px on every side. Far inside the tile (whose edges are at 619 and 7048), so the
 * tile's rounded corners and its drop shadow never enter the region being cut.
 */
const LOCKUP_REGION = { left: 1431, top: 1586, width: 4829, height: 4414 };

/** The mark's master width. The mockup is an upscale whose real detail is about 1.5-2K, so
 *  2048 keeps everything it has without inventing resolution, and covers the 1024 iOS icon. */
const MASTER_W = 2048;

async function cutMasters() {
  if (!fs.existsSync(SRC_ART)) throw new Error(`--cut needs the artwork at ${rel(SRC_ART)}`);
  const meta = await sharp(SRC_ART).metadata();
  log(`source  ${rel(SRC_ART)}  ${meta.width}x${meta.height}  ${meta.channels}ch`);
  if (meta.width !== 7680 || meta.height !== 7680) {
    throw new Error(`the artwork is ${meta.width}x${meta.height}; LOCKUP_REGION was measured on the 7680px file`);
  }

  const { data, info } = await sharp(SRC_ART)
    .extract(LOCKUP_REGION)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width: W, height: H } = info;
  const out = Buffer.alloc(W * H * 4);
  let partial = 0;
  let opaque = 0;
  for (let p = 0, q = 0; p < data.length; p += 3, q += 4) {
    const r = data[p];
    const g = data[p + 1];
    const b = data[p + 2];
    const d = Math.abs(r - PLATE_RGB[0]) + Math.abs(g - PLATE_RGB[1]) + Math.abs(b - PLATE_RGB[2]);
    const a = Math.min(1, Math.max(0, (d - CUT_LO) / (CUT_HI - CUT_LO)));
    if (a === 0) continue;
    if (a < 1) partial += 1; else opaque += 1;
    // Take the tile back out of the edge: p = a*c + (1-a)*tile  =>  c = tile + (p - tile)/a.
    out[q] = Math.round(Math.min(255, Math.max(0, PLATE_RGB[0] + (r - PLATE_RGB[0]) / a)));
    out[q + 1] = Math.round(Math.min(255, Math.max(0, PLATE_RGB[1] + (g - PLATE_RGB[1]) / a)));
    out[q + 2] = Math.round(Math.min(255, Math.max(0, PLATE_RGB[2] + (b - PLATE_RGB[2]) / a)));
    out[q + 3] = Math.round(a * 255);
  }
  log(`cut     ${W}x${H} region: ${opaque} opaque, ${partial} edge pixels (${((100 * partial) / (opaque + partial)).toFixed(2)}% of the ink)`);

  // SPLIT the lockup at the widest band of empty rows: the mark above, the wordmark below.
  // Measured, never hardcoded, and asserted — a silently mis-cropped icon is worse than a failed
  // build.
  const rowEmpty = new Array(H).fill(true);
  for (let y = 0; y < H; y += 1) {
    for (let x = 0; x < W; x += 1) {
      if (out[(y * W + x) * 4 + 3] > VISIBLE_ALPHA) { rowEmpty[y] = false; break; }
    }
  }
  let best = null;
  let start = null;
  const all = alphaBBox(out, W, H, VISIBLE_ALPHA);
  for (let y = all.top; y <= all.top + all.height; y += 1) {
    if (y < H && rowEmpty[y]) {
      if (start === null) start = y;
    } else if (start !== null) {
      if (!best || y - start > best.end - best.start) best = { start, end: y };
      start = null;
    }
  }
  if (!best) throw new Error("no empty band between the mark and the wordmark — has the artwork changed?");
  const mark = alphaBBox(out, W, H, VISIBLE_ALPHA, 0, best.start);
  const word = alphaBBox(out, W, H, VISIBLE_ALPHA, best.end, H);
  const markAspect = mark.width / mark.height;
  const wordAspect = word.width / word.height;
  log(
    `split   gap ${best.end - best.start}px  mark ${mark.width}x${mark.height} (aspect ${markAspect.toFixed(3)})` +
      `  wordmark ${word.width}x${word.height} (aspect ${wordAspect.toFixed(2)})`,
  );
  if (markAspect < 1.2 || markAspect > 1.6) throw new Error(`the top band (aspect ${markAspect.toFixed(2)}) is not the A-house mark`);
  if (wordAspect < 3.5) throw new Error(`the bottom band (aspect ${wordAspect.toFixed(2)}) is not the wordmark`);

  const cut = sharp(out, { raw: { width: W, height: H, channels: 4 } });
  const cutPng = await cut.png(PNG_WORK).toBuffer();

  const markPng = await sharp(cutPng)
    .extract(mark)
    .resize(MASTER_W, null, { kernel: "lanczos3" })
    .png(PNG_TRUECOLOR)
    .toBuffer();
  emit(MARK_MASTER, markPng);

  const lockup = {
    left: Math.min(mark.left, word.left),
    top: mark.top,
    width: Math.max(mark.left + mark.width, word.left + word.width) - Math.min(mark.left, word.left),
    height: word.top + word.height - mark.top,
  };
  const lockupPng = await sharp(cutPng)
    .extract(lockup)
    .resize(MASTER_W, null, { kernel: "lanczos3" })
    .png(PNG_TRUECOLOR)
    .toBuffer();
  emit(LOCKUP_MASTER, lockupPng);
  log(`masters ${rel(MARK_MASTER)}, ${rel(LOCKUP_MASTER)}`);
}

/* ───────────────────────── 2. the launch animation (--splash) ───────────────────────── */

/** Built by scripts/gen-splash.mjs, which keys the logo out of the video onto transparency; see
 *  its header for every number and why. --splash only runs it before the icons. */
async function makeSplash() {
  const { makeSplash: build } = await import("./gen-splash.mjs");
  await build({ ffmpeg: FFMPEG, log });
}

/* ───────────────────────── 3. every icon (default) ───────────────────────── */

/**
 * The 16px favicon frame without the four window squares. At 16px they are a single grey pixel
 * in the middle of the A that reads as dirt, not a window; the A alone is the more legible mark.
 * Found by colour (the windows are the only grey-green in the artwork, #7C9786) and blanked with
 * a margin for their soft halo.
 */
async function markWithoutWindows(markPng) {
  const { data, info } = await sharp(markPng).raw().toBuffer({ resolveWithObject: true });
  const { width: W, height: H } = info;
  const WINDOW = [124, 151, 134];
  let x0 = W, y0 = H, x1 = -1, y1 = -1;
  // Only the middle of the mark, where the house's opening is — the ribbons never come in here.
  for (let y = Math.floor(H * 0.35); y < Math.floor(H * 0.95); y += 1) {
    for (let x = Math.floor(W * 0.3); x < Math.floor(W * 0.7); x += 1) {
      const i = (y * W + x) * 4;
      if (data[i + 3] < 200) continue;
      const d = Math.abs(data[i] - WINDOW[0]) + Math.abs(data[i + 1] - WINDOW[1]) + Math.abs(data[i + 2] - WINDOW[2]);
      if (d < 36) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) throw new Error("could not find the window squares in the mark");
  const pad = Math.round(W * 0.012);
  const out = Buffer.from(data);
  for (let y = Math.max(0, y0 - pad); y <= Math.min(H - 1, y1 + pad); y += 1) {
    for (let x = Math.max(0, x0 - pad); x <= Math.min(W - 1, x1 + pad); x += 1) {
      out[(y * W + x) * 4 + 3] = 0;
    }
  }
  log(`windows found at (${x0},${y0})-(${x1},${y1}) of the ${W}x${H} mark; blanked for the 16px favicon`);
  return sharp(out, { raw: { width: W, height: H, channels: 4 } }).png(PNG_WORK).toBuffer();
}

async function makeIcons() {
  for (const f of [MARK_MASTER, LOCKUP_MASTER]) {
    if (!fs.existsSync(f)) throw new Error(`missing master ${rel(f)} — run with --cut first`);
  }
  const markPng = fs.readFileSync(MARK_MASTER);
  const lockupPng = fs.readFileSync(LOCKUP_MASTER);
  const markMeta = await sharp(markPng).metadata();
  log(`master  ${rel(MARK_MASTER)}  ${markMeta.width}x${markMeta.height}  aspect ${(markMeta.width / markMeta.height).toFixed(3)}`);

  /* Measured safe-zone fits. */
  // Each probed at the sizes it is actually written at (see fitInCircle for why).
  const adaptive = await fitInCircle(markPng, 33 / 108, 0.5, [108, 162, 216, 324, 432]); // Android: centre 66dp of 108dp
  const maskable = await fitInCircle(markPng, 0.4, 1, [512]); // web maskable: centre 80%
  const round = await fitInCircle(markPng, 0.4, 1, [48, 72, 96, 144, 192]); // inside the round plate, with a margin
  log(`safe    adaptive ${(adaptive * 100).toFixed(1)}% of the canvas width  |  maskable ${(maskable * 100).toFixed(1)}%  |  round plate ${(round * 100).toFixed(1)}%`);

  const expectations = [];
  const add = (abs, exp) => expectations.push({ rel: rel(abs), ...exp });

  /* ── public/brand ── */

  // The lockup for the website's sign-in card (components/auth/auth-card.tsx), transparent.
  const lockupWeb = await sharp(lockupPng).resize(1024, null, { kernel: "lanczos3" }).png(PNG_INDEXED).toBuffer();
  const lockupWebMeta = await sharp(lockupWeb).metadata();
  add(emit(path.join(BRAND_DIR, "apnivaas-lockup.png"), lockupWeb), { w: 1024, h: lockupWebMeta.height, alpha: true });

  // Square, opaque masters: the caption badge and the Play icon.
  // 66% wide keeps the mark inside the rounded square Play and the stores crop to.
  add(emit(path.join(BRAND_DIR, "logo-square-1024.png"), await compose(markPng, { size: 1024, frac: 0.66, shape: "square", opaque: true, truecolor: true })), { w: 1024, h: 1024, alpha: false, channels: 3 });
  add(emit(path.join(BRAND_DIR, "play-icon-512.png"), await compose(markPng, { size: 512, frac: 0.66, shape: "square", opaque: true, truecolor: true })), { w: 512, h: 512, alpha: false, channels: 3 });

  /* ── iOS ── one 1024 universal icon, RGB with NO alpha channel (App Store Connect rejects
     one), square corners (iOS applies its own mask) and no baked shadow. */
  add(emit(IOS_ICON, await compose(markPng, { size: 1024, frac: 0.66, shape: "square", opaque: true, truecolor: true })), { w: 1024, h: 1024, alpha: false, channels: 3 });

  /* ── public/icons ── filenames are fixed by app/manifest.ts and app/layout.tsx ── */

  // purpose "any": a normal rounded-square app icon.
  add(emit(path.join(ICONS_DIR, "icon-192.png"), await compose(markPng, { size: 192, frac: 0.66, shape: "rounded" })), { w: 192, h: 192, alpha: true });
  // purpose "maskable": full-bleed, square corners, no transparency, mark inside the centre 80%.
  add(emit(path.join(ICONS_DIR, "icon-512.png"), await compose(markPng, { size: 512, frac: maskable, shape: "square", opaque: true })), { w: 512, h: 512, alpha: false, channels: 3 });
  // iOS composites onto black wherever an apple-touch-icon is transparent, and applies its own
  // squircle — so this one is opaque with square corners too.
  add(emit(path.join(ICONS_DIR, "apple-touch-icon.png"), await compose(markPng, { size: 180, frac: 0.66, shape: "square", opaque: true })), { w: 180, h: 180, alpha: false, channels: 3 });

  // Browser tab icon. Chunkier than the app icons because 16px eats fine detail, and the 16px
  // frame drops the windows (see markWithoutWindows).
  const simple = await markWithoutWindows(markPng);
  const icoBuf = ico([
    { size: 16, png: await compose(simple, { size: 16, frac: 0.86, shape: "rounded" }) },
    { size: 32, png: await compose(markPng, { size: 32, frac: 0.8, shape: "rounded" }) },
    { size: 48, png: await compose(markPng, { size: 48, frac: 0.76, shape: "rounded" }) },
  ]);
  // Two byte-identical copies: Next serves app/favicon.ico at /favicon.ico, and public/icons
  // holds the one the manifest and older links point at.
  emit(path.join(ICONS_DIR, "favicon.ico"), icoBuf);
  emit(NEXT_FAVICON, icoBuf);

  /* ── Android ──
     Names must match what mipmap-anydpi-v26/*.xml and AndroidManifest.xml reference:
     ic_launcher, ic_launcher_round, ic_launcher_foreground, ic_launcher_monochrome, and the
     notification icon ic_stat_apnivaas (push_service.dart and the FCM default meta-data). */
  const DENSITIES = [
    { dir: "mdpi", legacy: 48, adaptive: 108, stat: 24 },
    { dir: "hdpi", legacy: 72, adaptive: 162, stat: 36 },
    { dir: "xhdpi", legacy: 96, adaptive: 216, stat: 48 },
    { dir: "xxhdpi", legacy: 144, adaptive: 324, stat: 72 },
    { dir: "xxxhdpi", legacy: 192, adaptive: 432, stat: 96 },
  ];
  for (const d of DENSITIES) {
    /* One density at a time keeps peak memory flat. minSdk is 24, so the legacy pair is still
       what API 24-25 launchers draw, plate and all. */
    add(emit(path.join(RES_DIR, `mipmap-${d.dir}`, "ic_launcher.png"), await compose(markPng, { size: d.legacy, frac: 0.66, shape: "rounded" })), { w: d.legacy, h: d.legacy, alpha: true });
    add(emit(path.join(RES_DIR, `mipmap-${d.dir}`, "ic_launcher_round.png"), await compose(markPng, { size: d.legacy, frac: round, shape: "circle" })), { w: d.legacy, h: d.legacy, alpha: true });
    add(emit(path.join(RES_DIR, `drawable-${d.dir}`, "ic_launcher_foreground.png"), await compose(markPng, { size: d.adaptive, frac: adaptive, shape: "none" })), { w: d.adaptive, h: d.adaptive, alpha: true });
    add(emit(path.join(RES_DIR, `drawable-${d.dir}`, "ic_launcher_monochrome.png"), await silhouette(markPng, d.adaptive, adaptive)), { w: d.adaptive, h: d.adaptive, alpha: true, whiteOnly: true });
    // 24dp with a 1dp margin each side: 22/24 of the width.
    add(emit(path.join(RES_DIR, `drawable-${d.dir}`, "ic_stat_apnivaas.png"), await silhouette(markPng, d.stat, 22 / 24)), { w: d.stat, h: d.stat, alpha: true, whiteOnly: true });
  }

  /* Re-open what landed and check it against what was asked for. */
  if (!CHECK) {
    log("");
    const { rows, failures } = await verify(expectations);
    table(rows);
    for (const f of ["play-icon-512.png", "logo-square-1024.png"]) {
      const stats = await sharp(path.join(BRAND_DIR, f)).stats();
      log(`assert  ${f.padEnd(22)} isOpaque=${stats.isOpaque} (Play rejects alpha)`);
      if (!stats.isOpaque) failures.push(`${f} still carries transparency`);
    }
    // The adaptive foreground must sit inside the 66dp circle at every density, not just the probe.
    for (const d of DENSITIES) {
      const file = path.join(RES_DIR, `drawable-${d.dir}`, "ic_launcher_foreground.png");
      const raw = await sharp(file).ensureAlpha().raw().toBuffer();
      if (escapesCircle(raw, d.adaptive, (33 / 108) * d.adaptive + 0.5)) failures.push(`${rel(file)}: ink outside the 66dp safe circle`);
    }
    if (failures.length) {
      failures.forEach((f) => console.error(`FAIL  ${f}`));
      process.exitCode = 1;
    }
  }
}

/* ───────────────────────── main ───────────────────────── */

async function main() {
  if (CUT) await cutMasters();
  if (MAKE_SPLASH) await makeSplash();
  await makeIcons();
  if (process.exitCode) return;
  const total = written.reduce((n, f) => n + f.bytes, 0);
  console.log("");
  console.log(`${CHECK ? "checked" : "wrote"} ${written.length} files, ${(total / 1024).toFixed(1)} kB total`);
}

main().catch((err) => {
  console.error(err.message);
  process.exitCode = 1;
});

#!/usr/bin/env node
/**
 * THE APNIVAAS LAUNCH ANIMATION — apnivaas_app/assets/brand/apnivaas_splash.webp and the still it
 * settles on, apnivaas_splash_still.webp, rebuilt from the owner's "Logo animation.mp4".
 *
 * USAGE (from the repo root; needs ffmpeg and the npm "sharp" the website already depends on):
 *
 *   node scripts/gen-splash.mjs --ffmpeg=<path to ffmpeg>          # the two WebPs, nothing else
 *   node scripts/gen-splash.mjs --ffmpeg=<...> --preview=<dir>     # also every decoded frame and
 *                                                                  # the still, flattened on the
 *                                                                  # ground, as PNGs to look at
 *   node scripts/gen-icons.mjs --splash --ffmpeg=<...>             # the same, then every icon
 *
 * ffmpeg may also come from $FFMPEG or PATH (on this machine winget's Gyan.FFmpeg build). A run
 * takes about five minutes: ~1.5 to key 95 source frames at 1080px, the rest in the WebP encoder.
 * It overwrites both files only after it has decoded the result and found every frame's outer
 * 8px fully transparent. --size=<px> and --quality=<n> exist for budget experiments only; the
 * SPLASH and KEY constants below are what ships. The ground colour is read from splash_ground in
 * android/.../values/colors.xml, the same colour lib/core/boot/splash_gate.dart (kSplashGround)
 * paints behind the image, and test/splash_opening_test.dart keeps those copies equal. After a
 * run: flutter test test/splash_asset_bytes_test.dart test/splash_opening_test.dart.
 *
 * lib/core/boot/splash_gate.dart holds the matching constants (60 frames, 32ms each, played once)
 * and test/splash_asset_bytes_test.dart reads the WebP's own RIFF chunks to keep the two in step.
 *
 * ── WHAT WAS WRONG WITH THE FIRST VERSION ────────────────────────────────────────────────────
 *
 * The video came out of an AI video tool, and everything behind the logo in it is noise that the
 * first version shipped as picture. Measured off the source and the decoded WebP:
 *
 *   - The ground is not a ground. Diagonal light streaks (red 224-242) drift with a slow camera
 *     move, and the whole frame dims by 2-4 levels and recovers around the light flash (frames
 *     8 and 22). On a flat phone screen that reads as the background breathing.
 *   - H.264 at 1.6 Mbit/s left 16px macroblocks in every soft shadow, and its 4:2:0 chroma is
 *     quantised in blocks, so the shadows were blotchy squares of brown and green.
 *   - Lossy WebP at quality 74 made both worse. Its animation encoder treats a pixel that moved by
 *     five levels or less as unchanged and keeps the OLD value, so the slowly drifting streaks
 *     froze and then caught up in rectangles: the "disturbance". Contrast-stretched, the shipped
 *     frames show block mosaics under the wordmark and stale traces of the light flash on frames
 *     long after it had gone.
 *   - The edge of the frame was blended into a flat beige from 80% of the half-width outwards,
 *     so the untouched centre showed as a faint lighter disc around the logo.
 *   - 720px frames were drawn at up to 300dp, i.e. stretched by up to 1.25x on a 3x phone.
 *
 * ── WHAT THIS DOES INSTEAD ──────────────────────────────────────────────────────────────────
 *
 * It keeps the owner's animation — the ribbon, the glass windows, the wordmark, the light — and
 * throws away everything the AI tool put around it. Each source frame is KEYED: the logo is lifted
 * off the video's ground onto TRANSPARENCY, and the app paints the ground. Nothing in the file is
 * ground any more, so the seam between the image and the screen around it cannot exist, whatever
 * the encoder does to a flat colour, and the WebP's own border is asserted transparent on every
 * frame after encoding.
 *
 *   1. A clean plate per frame: the ground's slow light streaks, fitted (normalised Gaussian) to
 *      the pixels that are confidently ground, and interpolated under the logo.
 *   2. Against that plate each pixel is scored as logo by three cues that ground, streaks, noise
 *      and SHADOWS do not have: green (chroma tilted to green), light (brighter than the plate:
 *      glows, the flash, the glass) and ink (darker than 68% of the plate — the darkest shadow in
 *      the video is 70%). The cues are taken from slightly blurred frames, chroma at 3px, so the
 *      H.264 block grid does not become a block grid in the matte.
 *   3. Where the score is strong (the ribbon, the letters, the bright lines) the source pixel is
 *      kept exactly. Where it is soft (glow halos, the green light the glass throws) the signal
 *      is smoothed at 5px over soft pixels only — glows have no fine detail, macroblocks do.
 *   4. The wordmark materialises as a pale grey ghost that no colour cue sees whole, so it is
 *      matted once from the finished frame and faded in over frames 66-72: no letter appears in
 *      pieces.
 *   5. The video's own shadows are noise, so they go, and a clean shadow is cast from the matte
 *      in the video's lighting (down and to the left, a near contact shadow and a long soft one)
 *      so the mark still sits on the surface. It moves with the ribbon by construction.
 *   6. A light that crosses the whole frame (the flash at frames 14-25) fades out between 15% and
 *      3% of the half-width from the border instead of being cut off at it, and nothing at all
 *      is drawn in the outer 3%.
 *
 * Partially covered pixels are re-coloured against the plate rather than cut out, so the logo
 * keeps its anti-aliased edge without a fringe of the old ground (the plate and the app ground
 * differ by at most a few levels, so the correction is small and errors in it are smaller).
 *
 * TIMING IS UNCHANGED: source frames 6-100 (the first quarter-second is empty ground the native
 * launch window has already shown; by frame 100 the wordmark is in), twice as fast, 60 frames of
 * 32ms. 32ms is two vsyncs at 60Hz, three at 90 and four at 120, so the file plays at the same
 * 30fps on every display (42ms would be three vsyncs at 60Hz and run past the gate's cap).
 * Covering 94 source frames in 60 is a step of 1.59 frames; each output frame now AVERAGES the
 * source over its own time slot (a 360-degree shutter) instead of blending the two nearest
 * frames by distance, which alternated sharp frames with double exposures and stuttered. The
 * last frame is source frame 100 exactly, the same picture as the still.
 *
 * 900px, NOT 720. The slot is min(80% of the width, 300dp), which is 800-900px on the 2.6-3x
 * phones most people have, so 900 is drawn at or under its own size: no stretch. The engine holds
 * the current and next decoded frames (3.2 MB each), and only the rectangle that changed is
 * decoded per frame.
 *
 * QUALITY 87, ALPHA LOSSLESS. With nothing behind the logo there is nothing for the encoder to
 * smear: the flat ground is the app's own paint, not pixels. 90 measured 2.26 MB for no visible
 * gain over 87 (2.09 MB); the still is encoded at 95, it is one frame (65 KB).
 */
import sharp from "sharp";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SRC_VIDEO = path.join(REPO_ROOT, "Logo animation.mp4");
const APP = path.join(REPO_ROOT, "apnivaas_app");
const APP_BRAND = path.join(APP, "assets", "brand");
const SPLASH_ANIM = path.join(APP_BRAND, "apnivaas_splash.webp");
const SPLASH_STILL = path.join(APP_BRAND, "apnivaas_splash_still.webp");
const COLORS_XML = path.join(APP, "android", "app", "src", "main", "res", "values", "colors.xml");

export const SPLASH = {
  /** A square out of the 9:16 frame. Every frame's logo lives in rows 572-1312, so this keeps all
   *  of it and drops the watermark in the corner (863-935, 1702-1776). Keyed at this, full,
   *  resolution and only then scaled. */
  crop: { x: 0, y: 400, size: 1080 },
  size: 900,
  firstSource: 6,
  lastSource: 100,
  frames: 60,
  frameMs: 32,
  quality: 87,
  stillQuality: 95,
};

/** The keyer's thresholds. Ratios are pixel / plate, so they hold across the streaks. The ground's
 *  own noise reaches green ±0.011 and light +0.016, so every floor here sits well above it. */
const KEY = {
  green: [0.02, 0.06],
  light: [0.03, 0.09],
  ink: [0.32, 0.55], // 1 - ratio: the darkest shadow is at 0.30
  coreGreen: [0.06, 0.12],
  coreLight: [0.04, 0.08],
  coreInk: [0.40, 0.55],
  softSigma: 5,
  edge: [0.03, 0.15], // of the half-width from the border: nothing at all in the outer 3%
  wordmark: { rows: [715, 935], from: 66, to: 72, ink: [0.30, 0.55] },
  shadows: [
    { dx: -14, dy: 18, sigma: 12, strength: 0.22 },
    { dx: -46, dy: 60, sigma: 40, strength: 0.1 },
  ],
};

const N = SPLASH.crop.size;
const PIX = N * N;

/** Alpha reaches 1 where the blurred coverage of the ground is 1/32 (about 7 levels of shadow, under
 *  a level of glow): a broad flat-topped support, which compresses better and has no ragged rim. */
const ALPHA_GAIN = 32;

/* ───────────────────────── image primitives on Float32 planes ───────────────────────── */

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
function smoothstep(edges, x) {
  const t = clamp01((x - edges[0]) / (edges[1] - edges[0]));
  return t * t * (3 - 2 * t);
}

function gaussExact(src, w, h, sigma) {
  const r = Math.ceil(3 * sigma);
  const k = new Float32Array(2 * r + 1);
  let s = 0;
  for (let i = -r; i <= r; i += 1) s += (k[i + r] = Math.exp(-(i * i) / (2 * sigma * sigma)));
  for (let i = 0; i < k.length; i += 1) k[i] /= s;
  const tmp = new Float32Array(w * h);
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y += 1) {
    const o = y * w;
    for (let x = 0; x < w; x += 1) {
      let acc = 0;
      for (let i = -r; i <= r; i += 1) {
        const xx = x + i;
        acc += src[o + (xx < 0 ? 0 : xx >= w ? w - 1 : xx)] * k[i + r];
      }
      tmp[o + x] = acc;
    }
  }
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      let acc = 0;
      for (let i = -r; i <= r; i += 1) {
        const yy = y + i;
        acc += tmp[(yy < 0 ? 0 : yy >= h ? h - 1 : yy) * w + x] * k[i + r];
      }
      out[y * w + x] = acc;
    }
  }
  return out;
}

function boxH(src, dst, w, h, r) {
  const norm = 1 / (2 * r + 1);
  for (let y = 0; y < h; y += 1) {
    const o = y * w;
    let acc = 0;
    for (let i = -r; i <= r; i += 1) acc += src[o + (i < 0 ? 0 : i >= w ? w - 1 : i)];
    for (let x = 0; x < w; x += 1) {
      dst[o + x] = acc * norm;
      const add = x + r + 1;
      const sub = x - r;
      acc += src[o + (add >= w ? w - 1 : add)] - src[o + (sub < 0 ? 0 : sub)];
    }
  }
}

function boxV(src, dst, w, h, r) {
  const norm = 1 / (2 * r + 1);
  const acc = new Float64Array(w);
  for (let i = -r; i <= r; i += 1) {
    const o = (i < 0 ? 0 : i >= h ? h - 1 : i) * w;
    for (let x = 0; x < w; x += 1) acc[x] += src[o + x];
  }
  for (let y = 0; y < h; y += 1) {
    const o = y * w;
    const add = (y + r + 1 >= h ? h - 1 : y + r + 1) * w;
    const sub = (y - r < 0 ? 0 : y - r) * w;
    for (let x = 0; x < w; x += 1) {
      dst[o + x] = acc[x] * norm;
      acc[x] += src[add + x] - src[sub + x];
    }
  }
}

/** Gaussian blur: exact below sigma 2, three box passes (Kutskir) above it. */
function blur(src, w, h, sigma) {
  if (sigma < 2) return gaussExact(src, w, h, sigma);
  const n = 3;
  let wl = Math.floor(Math.sqrt((12 * sigma * sigma) / n + 1));
  if (wl % 2 === 0) wl -= 1;
  const m = Math.round((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4));
  const a = Float32Array.from(src);
  const t = new Float32Array(w * h);
  for (let i = 0; i < n; i += 1) {
    const r = ((i < m ? wl : wl + 2) - 1) >> 1;
    boxH(a, t, w, h, r);
    boxV(t, a, w, h, r);
  }
  return a;
}

function maxFilter(src, w, h, size) {
  const r = (size - 1) >> 1;
  const t = new Float32Array(w * h);
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y += 1) {
    const o = y * w;
    for (let x = 0; x < w; x += 1) {
      let m = -Infinity;
      const x1 = Math.min(w - 1, x + r);
      for (let i = Math.max(0, x - r); i <= x1; i += 1) if (src[o + i] > m) m = src[o + i];
      t[o + x] = m;
    }
  }
  for (let y = 0; y < h; y += 1) {
    const y0 = Math.max(0, y - r);
    const y1 = Math.min(h - 1, y + r);
    for (let x = 0; x < w; x += 1) {
      let m = -Infinity;
      for (let j = y0; j <= y1; j += 1) {
        const v = t[j * w + x];
        if (v > m) m = v;
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

function median(values, lo, hi, bins) {
  const hist = new Uint32Array(bins);
  const sc = bins / (hi - lo);
  for (let i = 0; i < values.length; i += 1) {
    const b = Math.floor((values[i] - lo) * sc);
    hist[b < 0 ? 0 : b >= bins ? bins - 1 : b] += 1;
  }
  const half = values.length / 2;
  let acc = 0;
  for (let b = 0; b < bins; b += 1) {
    acc += hist[b];
    if (acc >= half) return lo + (b + 0.5) / sc;
  }
  return hi;
}

/** Dilate a soft mask by 2px and soften its edge, so a matte always covers its anti-aliasing. */
function soften(x) {
  const out = gaussExact(maxFilter(x, N, N, 5), N, N, 1);
  for (let p = 0; p < PIX; p += 1) out[p] = clamp01(out[p]);
  return out;
}

/* ───────────────────────── the keyer ───────────────────────── */

/**
 * The clean plate: what the video's ground would be at every pixel if the logo were not there.
 * Fitted to confidently-ground pixels (chroma within 0.012 of the frame's median chroma, luma
 * within -8/+12 of its median, eroded 6px), at 1/8 resolution because it is smooth by nature.
 */
function plate(F) {
  const [R, Gc, B] = F;
  const lum = new Float32Array(PIX);
  const cr = new Float32Array(PIX);
  const cg = new Float32Array(PIX);
  const cb = new Float32Array(PIX);
  for (let p = 0; p < PIX; p += 1) {
    const s = R[p] + Gc[p] + B[p];
    lum[p] = s / 3;
    cr[p] = R[p] / (s + 1e-3);
    cg[p] = Gc[p] / (s + 1e-3);
    cb[p] = B[p] / (s + 1e-3);
  }
  const med = median(lum, 0, 256, 1024);
  const ref = [median(cr, 0, 1, 4096), median(cg, 0, 1, 4096), median(cb, 0, 1, 4096)];
  const notGround = new Float32Array(PIX);
  for (let p = 0; p < PIX; p += 1) {
    const cd = Math.abs(cr[p] - ref[0]) + Math.abs(cg[p] - ref[1]) + Math.abs(cb[p] - ref[2]);
    notGround[p] = cd < 0.012 && lum[p] > med - 8 && lum[p] < med + 12 ? 0 : 1;
  }
  const grown = maxFilter(notGround, N, N, 13);

  const f = 8;
  const n = N / f;
  const wsum = new Float32Array(n * n);
  const csum = [new Float32Array(n * n), new Float32Array(n * n), new Float32Array(n * n)];
  for (let y = 0; y < N; y += 1) {
    const by = ((y / f) | 0) * n;
    for (let x = 0; x < N; x += 1) {
      const p = y * N + x;
      const b = by + ((x / f) | 0);
      const w = 1 - grown[p];
      wsum[b] += w;
      csum[0][b] += R[p] * w;
      csum[1][b] += Gc[p] * w;
      csum[2][b] += B[p] * w;
    }
  }
  const w1 = gaussExact(wsum, n, n, 5);
  const w2 = gaussExact(wsum, n, n, 20);
  const fallback = ref.map((c) => c * 3 * med);
  const low = csum.map((sum, c) => {
    const b1 = gaussExact(sum, n, n, 5);
    const b2 = gaussExact(sum, n, n, 20);
    const out = new Float32Array(n * n);
    for (let i = 0; i < n * n; i += 1) {
      const t = clamp01(w1[i] / (0.15 * f * f));
      const far = w2[i] > 1e-3 ? b2[i] / w2[i] : fallback[c];
      out[i] = (w1[i] > 1e-3 ? b1[i] / w1[i] : far) * t + far * (1 - t);
    }
    return out;
  });
  // Bilinear back to full size, pixel centres aligned.
  return low.map((lo) => {
    const out = new Float32Array(PIX);
    for (let y = 0; y < N; y += 1) {
      let sy = (y + 0.5) / f - 0.5;
      sy = sy < 0 ? 0 : sy > n - 1 ? n - 1 : sy;
      const y0 = Math.floor(sy);
      const y1 = Math.min(n - 1, y0 + 1);
      const fy = sy - y0;
      for (let x = 0; x < N; x += 1) {
        let sx = (x + 0.5) / f - 0.5;
        sx = sx < 0 ? 0 : sx > n - 1 ? n - 1 : sx;
        const x0 = Math.floor(sx);
        const x1 = Math.min(n - 1, x0 + 1);
        const fx = sx - x0;
        const top = lo[y0 * n + x0] * (1 - fx) + lo[y0 * n + x1] * fx;
        const bot = lo[y1 * n + x0] * (1 - fx) + lo[y1 * n + x1] * fx;
        out[y * N + x] = top * (1 - fy) + bot * fy;
      }
    }
    return out;
  });
}

/** The cues, against the plate: matte (anything logo-like) and core (unmistakably logo). */
function cues(F, P) {
  const F1 = F.map((ch) => gaussExact(ch, N, N, 1));
  const F3 = F.map((ch) => blur(ch, N, N, 3));
  const matte = new Float32Array(PIX);
  const core = new Float32Array(PIX);
  const ink = new Float32Array(PIX);
  const { green: kG, light: kL, ink: kI, coreGreen: cG, coreLight: cL, coreInk: cI } = KEY;
  for (let p = 0; p < PIX; p += 1) {
    const r1 = F1[0][p] / P[0][p];
    const g1 = F1[1][p] / P[1][p];
    const b1 = F1[2][p] / P[2][p];
    const dark = 1 - (r1 + g1 + b1) / 3;
    const light = Math.max(r1, g1, b1) - 1;
    const green = F3[1][p] / P[1][p] - (F3[0][p] / P[0][p] + F3[2][p] / P[2][p]) / 2;
    matte[p] = Math.max(smoothstep(kG, green), smoothstep(kL, light), smoothstep(kI, dark));
    core[p] = Math.max(smoothstep(cG, green), smoothstep(cL, light), smoothstep(cI, dark));
    ink[p] = dark;
  }
  return { matte, core, ink };
}

const EDGE = (() => {
  const w = new Float32Array(PIX);
  for (let y = 0; y < N; y += 1) {
    for (let x = 0; x < N; x += 1) {
      const d = Math.min(x, N - 1 - x, y, N - 1 - y) / (N / 2);
      w[y * N + x] = smoothstep(KEY.edge, d);
    }
  }
  return w;
})();

function shifted(src, dx, dy) {
  const out = new Float32Array(PIX);
  for (let y = Math.max(0, dy); y < Math.min(N, N + dy); y += 1) {
    const sy = y - dy;
    for (let x = Math.max(0, dx); x < Math.min(N, N + dx); x += 1) out[y * N + x] = src[sy * N + x - dx];
  }
  return out;
}

/**
 * One source frame, keyed. Returns premultiplied planes [alpha, r, g, b] meant to be drawn over
 * `ground`: alpha*colour + (1 - alpha)*ground is the clean picture.
 */
function keyFrame(F, ground, wordmark, t) {
  const P = plate(F);
  const { matte: mRaw, core: cRaw } = cues(F, P);
  const m = soften(mRaw);
  const c = soften(cRaw);
  const { from, to } = KEY.wordmark;
  if (wordmark && t >= from) {
    const ramp = clamp01((t - from) / (to - from));
    for (let p = 0; p < PIX; p += 1) {
      const w = wordmark[p] * ramp;
      if (w > m[p]) m[p] = w;
      if (w > c[p]) c[p] = w;
    }
  }
  for (let p = 0; p < PIX; p += 1) m[p] *= EDGE[p];

  // Soft regions: the deviation from the plate, averaged over soft pixels only, so a glow keeps
  // its shape and loses its macroblocks, and no ink bleeds out of the core into it.
  const nc = new Float32Array(PIX);
  for (let p = 0; p < PIX; p += 1) nc[p] = 1 - c[p];
  const den = blur(nc, N, N, KEY.softSigma);
  const dev = F.map((ch, k) => {
    const d = new Float32Array(PIX);
    for (let p = 0; p < PIX; p += 1) d[p] = (ch[p] - P[k][p]) * nc[p];
    return d;
  });
  const devSoft = dev.map((d) => blur(d, N, N, KEY.softSigma));

  const out = [new Float32Array(PIX), new Float32Array(PIX), new Float32Array(PIX), new Float32Array(PIX)];
  const caster = new Float32Array(PIX);
  for (let p = 0; p < PIX; p += 1) {
    // How much of this pixel the logo covers at least, given the plate behind it.
    let cover = 0;
    for (let k = 0; k < 3; k += 1) {
      const f = F[k][p];
      const b = P[k][p];
      const v = f >= b ? (f - b) / Math.max(255 - b, 1) : (b - f) / Math.max(b, 1);
      if (v > cover) cover = v;
    }
    cover = clamp01(cover);
    out[0][p] = m[p];
    for (let k = 0; k < 3; k += 1) {
      const raw = F[k][p] - P[k][p];
      const soft = den[p] > 1e-4 ? devSoft[k][p] / den[p] : raw;
      const d = c[p] * raw + nc[p] * soft;
      // The colour this pixel would have with the app's ground behind it instead of the video's.
      const col = Math.min(255, Math.max(0, ground[k] + d + cover * (P[k][p] - ground[k])));
      out[k + 1][p] = m[p] * col;
    }
    caster[p] = c[p] * m[p];
  }
  const shade = new Float32Array(PIX);
  const shadowSet = KEY.shadows;
  for (const s of shadowSet) {
    const b = blur(shifted(caster, s.dx, s.dy), N, N, s.sigma);
    for (let p = 0; p < PIX; p += 1) shade[p] += b[p] * s.strength;
  }
  // The shadow darkens the ground only, under the logo's own coverage: black at its strength.
  for (let p = 0; p < PIX; p += 1) {
    const sh = clamp01(shade[p]) * EDGE[p];
    out[0][p] = m[p] + (1 - m[p]) * sh;
  }
  return out;
}

/** The wordmark, matted once from the finished frame: its letters' ink, inside its rows. */
function wordmarkMatte(F) {
  const P = plate(F);
  const { ink } = cues(F, P);
  const [r0, r1] = KEY.wordmark.rows;
  const w = new Float32Array(PIX);
  for (let y = r0; y < r1; y += 1) {
    for (let x = 0; x < N; x += 1) w[y * N + x] = smoothstep(KEY.wordmark.ink, ink[y * N + x]);
  }
  return soften(w);
}

/* ───────────────────────── frames, encoding, verification ───────────────────────── */

function groundFromColorsXml() {
  const xml = fs.readFileSync(COLORS_XML, "utf8");
  const m = /<color name="splash_ground">#([0-9A-Fa-f]{6})<\/color>/.exec(xml);
  if (!m) throw new Error(`no splash_ground in ${path.relative(REPO_ROOT, COLORS_XML)}`);
  return [0, 2, 4].map((i) => parseInt(m[1].slice(i, i + 2), 16));
}

/**
 * Premultiplied planes at N -> the RGBA the WebP stores, at the shipped size.
 *
 * The PICTURE is made first: the clean frame on the app's ground, opaque, scaled with lanczos3 so
 * the ribbon and the letters stay crisp. Alpha is then only a SUPPORT: 1 wherever the picture
 * differs from the ground by more than a trace (the logo, its glows, the core of its shadow),
 * falling smoothly to 0 around that, and never less than the coverage the picture needs. Colour
 * is solved from both, colour = ground + (picture - ground) / alpha, so alpha*colour +
 * (1 - alpha)*ground is the picture again on the phone.
 *
 * Why not alpha = the matte: a matte follows every grain of the source and lossless alpha pays
 * for each one (15-20 KB a frame). A support is flat 0 and flat 255 with a soft edge, a few KB,
 * and the detail goes to the lossy colour planes where it is cheap. Where alpha is 0 the colour
 * is the ground itself, so nothing hard sits under the transparent area for the encoder to chew.
 */
async function toRgba(planes, ground, size) {
  const [A, Rp, Gp, Bp] = planes;
  const rgb = Buffer.alloc(PIX * 3);
  for (let p = 0, i = 0; p < PIX; p += 1, i += 3) {
    const t = 1 - A[p];
    rgb[i] = Math.round(Math.min(255, Math.max(0, Rp[p] + t * ground[0])));
    rgb[i + 1] = Math.round(Math.min(255, Math.max(0, Gp[p] + t * ground[1])));
    rgb[i + 2] = Math.round(Math.min(255, Math.max(0, Bp[p] + t * ground[2])));
  }
  const pic = await sharp(rgb, { raw: { width: N, height: N, channels: 3 } })
    .resize(size, size, { kernel: "lanczos3" })
    .raw()
    .toBuffer();
  const n = size * size;
  const cover = new Float32Array(n);
  for (let p = 0; p < n; p += 1) {
    let v = 0;
    for (let k = 0; k < 3; k += 1) {
      const o = pic[p * 3 + k];
      const g = ground[k];
      const c = o >= g ? (o - g) / (255 - g) : (g - o) / g;
      if (c > v) v = c;
    }
    cover[p] = v;
  }
  const support = gaussExact(maxFilter(cover, size, size, 5), size, size, 1.5);
  const out = Buffer.alloc(n * 4);
  for (let p = 0; p < n; p += 1) {
    const a8 = Math.round(Math.max(cover[p], Math.min(1, support[p] * ALPHA_GAIN)) * 255);
    out[p * 4 + 3] = a8;
    for (let k = 0; k < 3; k += 1) {
      const g = ground[k];
      out[p * 4 + k] = a8 === 0 ? g : Math.round(Math.min(255, Math.max(0, g + ((pic[p * 3 + k] - g) * 255) / a8)));
    }
  }
  return out;
}

/** Which source frames an output frame averages, and how much of each: the overlap of each
 *  source frame's own time slot with the output frame's slot. */
function shutter(i) {
  const { firstSource: first, lastSource: last, frames } = SPLASH;
  const step = (last - first) / (frames - 1);
  const pos = first + i * step;
  if (i === frames - 1) return [[last, 1]];
  const a = Math.max(first, pos - step / 2);
  const b = Math.min(last, pos + step / 2);
  const out = [];
  for (let j = Math.round(a); j <= Math.round(b); j += 1) {
    const w = Math.min(b, j + 0.5) - Math.max(a, j - 0.5);
    if (w > 1e-6) out.push([j, w]);
  }
  return out;
}

export async function makeSplash({ ffmpeg = "ffmpeg", log: print = console.log, preview = null } = {}) {
  const started = Date.now();
  const log = (line) => print(`${line}  [${((Date.now() - started) / 1000).toFixed(0)}s]`);
  if (!fs.existsSync(SRC_VIDEO)) throw new Error(`the splash needs the video at ${path.relative(REPO_ROOT, SRC_VIDEO)}`);
  const ground = groundFromColorsXml();
  const S = SPLASH.size;
  const frameBytes = PIX * 3;
  const { crop, firstSource: first, lastSource: last } = SPLASH;
  const vf = `crop=${crop.size}:${crop.size}:${crop.x}:${crop.y},scale=flags=accurate_rnd+full_chroma_int`;
  let raw;
  try {
    raw = execFileSync(
      ffmpeg,
      ["-v", "error", "-i", SRC_VIDEO, "-an", "-vf", vf, "-frames:v", String(last + 1), "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
      { maxBuffer: frameBytes * (last + 2) },
    );
  } catch (e) {
    throw new Error(`ffmpeg failed (${ffmpeg}): ${e.message}. Pass --ffmpeg=<path to ffmpeg.exe>.`);
  }
  const count = Math.floor(raw.length / frameBytes);
  if (count < last + 1) throw new Error(`ffmpeg returned ${count} frames, need ${last + 1}`);
  log(`video   ${path.relative(REPO_ROOT, SRC_VIDEO)}: ${count} frames at ${N}x${N}, audio dropped`);

  const source = (t) => {
    const planes = [new Float32Array(PIX), new Float32Array(PIX), new Float32Array(PIX)];
    for (let p = 0, i = t * frameBytes; p < PIX; p += 1, i += 3) {
      planes[0][p] = raw[i];
      planes[1][p] = raw[i + 1];
      planes[2][p] = raw[i + 2];
    }
    return planes;
  };
  const wordmark = wordmarkMatte(source(last));
  const cache = new Map();
  const keyed = (t) => {
    if (!cache.has(t)) {
      for (const k of [...cache.keys()]) if (k < t - 2) cache.delete(k);
      cache.set(t, keyFrame(source(t), ground, wordmark, t));
    }
    return cache.get(t);
  };

  const pages = [];
  for (let i = 0; i < SPLASH.frames; i += 1) {
    const taps = shutter(i);
    const total = taps.reduce((s, [, w]) => s + w, 0);
    const acc = [new Float32Array(PIX), new Float32Array(PIX), new Float32Array(PIX), new Float32Array(PIX)];
    for (const [j, w] of taps) {
      const k = keyed(j);
      for (let c = 0; c < 4; c += 1) for (let p = 0; p < PIX; p += 1) acc[c][p] += k[c][p] * (w / total);
    }
    pages.push(await toRgba(acc, ground, S));
  }
  const still = await toRgba(keyed(last), ground, S);
  log(`keyed   source frames ${first}-${last} onto transparency, ground ${hexOf(ground)} from colors.xml`);

  const strip = Buffer.concat(pages);
  const anim = await sharp(strip, { raw: { width: S, height: S * SPLASH.frames, channels: 4, pageHeight: S } })
    .webp({
      quality: SPLASH.quality,
      alphaQuality: 100,
      effort: 6,
      smartSubsample: true,
      loop: 1,
      delay: new Array(SPLASH.frames).fill(SPLASH.frameMs),
    })
    .toBuffer();
  const stillWebp = await sharp(still, { raw: { width: S, height: S, channels: 4 } })
    .webp({ quality: SPLASH.stillQuality, alphaQuality: 100, effort: 6, smartSubsample: true })
    .toBuffer();

  // What a phone will actually decode: every frame's border must be fully transparent, so the
  // only colour around the logo is the one the app paints.
  const meta = await sharp(anim, { pages: -1 }).metadata();
  if (meta.pages !== SPLASH.frames || meta.loop !== 1 || meta.width !== S || meta.pageHeight !== S) {
    throw new Error(`encoded animation is ${meta.pages} frames, loop ${meta.loop}, ${meta.width}x${meta.pageHeight}`);
  }
  const decoded = await sharp(anim, { pages: -1 }).ensureAlpha().raw().toBuffer();
  const ring = 8;
  let worst = 0;
  for (let page = 0; page < SPLASH.frames; page += 1) {
    for (let y = 0; y < S; y += 1) {
      for (let x = 0; x < S; x += 1) {
        if (x >= ring && x < S - ring && y >= ring && y < S - ring) continue;
        worst = Math.max(worst, decoded[((page * S + y) * S + x) * 4 + 3]);
      }
    }
  }
  const stillDecoded = await sharp(stillWebp).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  for (let y = 0; y < S; y += 1) {
    for (let x = 0; x < S; x += 1) {
      if (x >= ring && x < S - ring && y >= ring && y < S - ring) continue;
      worst = Math.max(worst, stillDecoded.data[(y * S + x) * 4 + 3]);
    }
  }
  if (worst !== 0) throw new Error(`the decoded border is not transparent (alpha up to ${worst}) — the app ground would show a seam`);

  fs.mkdirSync(APP_BRAND, { recursive: true });
  fs.writeFileSync(SPLASH_ANIM, anim);
  fs.writeFileSync(SPLASH_STILL, stillWebp);
  log(`splash  ${path.relative(REPO_ROOT, SPLASH_ANIM)}: ${meta.pages} frames x ${SPLASH.frameMs}ms at ${S}px, loop ${meta.loop}, ${(anim.length / 1024).toFixed(0)} KB`);
  log(`splash  ${path.relative(REPO_ROOT, SPLASH_STILL)}: ${(stillWebp.length / 1024).toFixed(0)} KB`);
  log(`border  transparent on all ${meta.pages} decoded frames and the still`);

  if (preview) {
    fs.mkdirSync(preview, { recursive: true });
    const bg = { r: ground[0], g: ground[1], b: ground[2] };
    for (let page = 0; page < SPLASH.frames; page += 1) {
      const one = decoded.subarray(page * S * S * 4, (page + 1) * S * S * 4);
      await sharp(one, { raw: { width: S, height: S, channels: 4 } }).flatten({ background: bg }).png().toFile(path.join(preview, `frame_${String(page).padStart(2, "0")}.png`));
    }
    await sharp(stillDecoded.data, { raw: { width: S, height: S, channels: 4 } }).flatten({ background: bg }).png().toFile(path.join(preview, "still.png"));
    log(`preview ${SPLASH.frames} decoded frames and the still, on the ground, in ${preview}`);
  }
}

function hexOf(rgb) {
  return `#${rgb.map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase()}`;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const opt = (name) => (args.find((a) => a.startsWith(`--${name}=`)) ?? "").slice(name.length + 3) || null;
  // Budget experiments: --size=720 --quality=85 change the shipped file, so the defaults above
  // are what is committed.
  if (opt("size")) SPLASH.size = Number(opt("size"));
  if (opt("quality")) SPLASH.quality = Number(opt("quality"));
  makeSplash({ ffmpeg: opt("ffmpeg") || process.env.FFMPEG || "ffmpeg", preview: opt("preview") }).catch((err) => {
    console.error(err.message);
    process.exitCode = 1;
  });
}

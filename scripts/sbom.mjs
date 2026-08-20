#!/usr/bin/env node
/**
 * CycloneDX 1.6 SBOM generator — reads package-lock.json directly.
 *
 *   node scripts/sbom.mjs                  # every installed package -> sbom.json
 *   node scripts/sbom.mjs --omit=dev       # production dependency tree only
 *   node scripts/sbom.mjs --out=path.json  # write somewhere else
 *   node scripts/sbom.mjs --print          # stdout instead of a file
 *
 * Why not @cyclonedx/cyclonedx-npm? An SBOM exists to answer "what third-party code is in
 * this build". Installing a third-party tool to answer that adds a few dozen packages of
 * new transitive attack surface to the very tree it is meant to describe. The npm lockfile
 * already holds everything CycloneDX needs — name, version, integrity, license, resolved
 * URL and the full edge list — so we parse it and add zero dependencies.
 *
 * Exits 1 if the lockfile is unusable or the generated graph is internally inconsistent,
 * so this can gate CI. Supply-chain anomalies (non-npmjs registry, missing integrity) are
 * reported as warnings and do NOT fail the run — see docs/supply-chain.md for why.
 */
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const arg = (name, fallback = null) => {
  const hit = argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  if (!hit) return fallback;
  return hit.includes("=") ? hit.slice(hit.indexOf("=") + 1) : true;
};
const OMIT_DEV = String(arg("omit", "")).split(",").includes("dev");
const PRINT = arg("print") === true;
const OUT = path.resolve(ROOT, String(arg("out", "sbom.json")));

const die = (msg) => {
  console.error(`sbom: ${msg}`);
  process.exit(1);
};

/* ── read the lockfile ──────────────────────────────────────────────────── */
const lockPath = path.join(ROOT, "package-lock.json");
if (!fs.existsSync(lockPath)) die("package-lock.json not found — run npm install first");
const lockRaw = fs.readFileSync(lockPath, "utf8");
let lock;
try {
  lock = JSON.parse(lockRaw);
} catch (e) {
  die(`package-lock.json is not valid JSON: ${e.message}`);
}
if (!lock.packages) {
  die(`lockfileVersion ${lock.lockfileVersion} has no "packages" map — needs v2 or v3 (npm 7+)`);
}

const pkgJson = JSON.parse(fs.readFileSync(path.join(ROOT, "package.json"), "utf8"));
const packages = lock.packages;
const rootEntry = packages[""] || {};

/* ── helpers ────────────────────────────────────────────────────────────── */

// "node_modules/a/node_modules/@scope/b" -> "@scope/b"
const nameFromPath = (p) => {
  const i = p.lastIndexOf("node_modules/");
  return i === -1 ? p : p.slice(i + "node_modules/".length);
};

// purl spec: the "@" of a scope is percent-encoded, the "/" separating scope is not.
const purlFor = (name, version) => {
  const scoped = name.startsWith("@") && name.includes("/");
  const ns = scoped ? name.slice(0, name.indexOf("/")) : null;
  const base = scoped ? name.slice(name.indexOf("/") + 1) : name;
  const seg = ns ? `${encodeURIComponent(ns)}/${encodeURIComponent(base)}` : encodeURIComponent(base);
  return `pkg:npm/${seg}@${encodeURIComponent(version)}`;
};

// "sha512-<base64>" -> [{ alg: "SHA-512", content: "<hex>" }]
const ALG = { sha512: "SHA-512", sha384: "SHA-384", sha256: "SHA-256", sha1: "SHA-1" };
const hashesFor = (integrity) => {
  if (!integrity) return undefined;
  const out = [];
  for (const token of String(integrity).trim().split(/\s+/)) {
    const dash = token.indexOf("-");
    if (dash === -1) continue;
    const alg = ALG[token.slice(0, dash)];
    if (!alg) continue;
    const content = Buffer.from(token.slice(dash + 1), "base64").toString("hex");
    if (content) out.push({ alg, content });
  }
  return out.length ? out : undefined;
};

// npm "license" is an SPDX id, an SPDX expression, or an array of ids.
const SPDX_OP = /\s(?:OR|AND|WITH)\s|^\(|\)$/;
const licensesFor = (license) => {
  if (!license) return undefined;
  if (Array.isArray(license)) return license.filter(Boolean).map((id) => ({ license: { id: String(id) } }));
  const s = String(license);
  return SPDX_OP.test(s) ? [{ expression: s }] : [{ license: { id: s } }];
};

/**
 * Node resolution applied to lockfile paths: a dependency of `node_modules/a` is either
 * nested at `node_modules/a/node_modules/<dep>` or hoisted somewhere above it. Walk
 * outwards from the deepest candidate exactly the way require() does.
 */
const resolveFrom = (fromPath, depName) => {
  let base = fromPath;
  for (;;) {
    const cand = base ? `${base}/node_modules/${depName}` : `node_modules/${depName}`;
    if (packages[cand]) return cand;
    if (base === "") return null;
    const i = base.lastIndexOf("/node_modules/");
    base = i === -1 ? "" : base.slice(0, i);
  }
};

/* ── select the packages that belong in the SBOM ────────────────────────── */
const included = new Map(); // lockfile path -> entry
for (const [p, entry] of Object.entries(packages)) {
  if (p === "") continue;
  if (entry.link) continue; // workspace symlink; the real entry is listed separately
  if (OMIT_DEV && entry.dev === true) continue;
  if (!entry.version) continue; // nothing installable to describe
  included.set(p, entry);
}
if (included.size === 0) die("no packages found in the lockfile");

/**
 * bom-ref is the purl, so one name@version installed at several paths collapses into a
 * single component (npm duplicates a package whenever two parents need incompatible
 * ranges). The dependency graph below is therefore the union of edges across every
 * install path of that purl — which is the right answer to "can this version reach that
 * version". Every path is still recorded in cdx:npm:package:path so duplication stays
 * visible to a human reading the SBOM.
 */
const byPurl = new Map(); // purl -> { name, version, entry, paths[] }
for (const [p, entry] of included) {
  const name = entry.name || nameFromPath(p);
  const purl = purlFor(name, entry.version);
  const rec = byPurl.get(purl);
  if (rec) rec.paths.push(p);
  else byPurl.set(purl, { name, version: entry.version, entry, paths: [p] });
}

/* ── components ─────────────────────────────────────────────────────────── */
const directProd = new Set(Object.keys(rootEntry.dependencies || {}));
const directDev = new Set(Object.keys(rootEntry.devDependencies || {}));

const components = [];
for (const [purl, rec] of byPurl) {
  const { name, version, entry, paths } = rec;
  const props = [{ name: "cdx:npm:package:path", value: paths.slice().sort().join(",") }];
  if (entry.dev === true) props.push({ name: "cdx:npm:package:development", value: "true" });
  if (entry.devOptional === true) props.push({ name: "cdx:npm:package:devOptional", value: "true" });
  if (entry.optional === true) props.push({ name: "cdx:npm:package:optional", value: "true" });
  if (entry.hasInstallScript === true) props.push({ name: "cdx:npm:package:hasInstallScript", value: "true" });
  if (directProd.has(name)) props.push({ name: "cdx:npm:package:directDependency", value: "true" });
  else if (directDev.has(name)) props.push({ name: "cdx:npm:package:directDevDependency", value: "true" });

  const c = {
    type: "library",
    "bom-ref": purl,
    name,
    version,
    purl,
    scope: entry.optional === true || entry.devOptional === true ? "optional" : "required",
    properties: props,
  };
  const licenses = licensesFor(entry.license);
  if (licenses) c.licenses = licenses;
  const hashes = hashesFor(entry.integrity);
  if (hashes) c.hashes = hashes;
  if (entry.resolved) c.externalReferences = [{ type: "distribution", url: entry.resolved }];
  components.push(c);
}
components.sort((a, b) => (a.purl < b.purl ? -1 : a.purl > b.purl ? 1 : 0));

/* ── dependency graph ───────────────────────────────────────────────────── */
const purlOfPath = new Map();
for (const [purl, rec] of byPurl) for (const p of rec.paths) purlOfPath.set(p, purl);

const ROOT_REF = purlFor(pkgJson.name || lock.name || "root", pkgJson.version || lock.version || "0.0.0");
const edges = new Map(); // ref -> Set<ref>
const addNode = (ref) => {
  if (!edges.has(ref)) edges.set(ref, new Set());
  return edges.get(ref);
};
addNode(ROOT_REF);

const depFieldsOf = (entry) => ({
  ...(entry.dependencies || {}),
  ...(entry.optionalDependencies || {}),
  ...(entry.peerDependencies || {}),
});

// root edges — devDependencies included unless --omit=dev
for (const depName of Object.keys({
  ...(rootEntry.dependencies || {}),
  ...(OMIT_DEV ? {} : rootEntry.devDependencies || {}),
})) {
  const target = resolveFrom("", depName);
  if (target && purlOfPath.has(target)) addNode(ROOT_REF).add(purlOfPath.get(target));
}

let unresolved = 0;
for (const [p, entry] of included) {
  const set = addNode(purlOfPath.get(p));
  for (const depName of Object.keys(depFieldsOf(entry))) {
    const target = resolveFrom(p, depName);
    if (!target || !purlOfPath.has(target)) {
      // peer and optional deps are legitimately absent; a missing hard dependency is not.
      const soft =
        (entry.peerDependencies && depName in entry.peerDependencies) ||
        (entry.optionalDependencies && depName in entry.optionalDependencies) ||
        (OMIT_DEV && packages[resolveFrom(p, depName) || ""] === undefined);
      if (!soft) unresolved++;
      continue;
    }
    set.add(purlOfPath.get(target));
  }
}

const dependencies = [...edges.entries()]
  .map(([ref, set]) => ({ ref, dependsOn: [...set].sort() }))
  .sort((a, b) => (a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0));

/* ── deterministic serial number ────────────────────────────────────────────
 * Derived from the lockfile bytes rather than randomly, so re-running on an unchanged
 * lockfile produces a byte-identical SBOM apart from the timestamp. That makes the file
 * diffable and lets CI compare a freshly generated SBOM against a stored one.
 */
const digest = crypto.createHash("sha256").update(lockRaw).digest("hex");
const uuid = [
  digest.slice(0, 8),
  digest.slice(8, 12),
  "4" + digest.slice(13, 16), // RFC 4122 version nibble
  ((parseInt(digest[16], 16) & 0x3) | 0x8).toString(16) + digest.slice(17, 20), // variant nibble
  digest.slice(20, 32),
].join("-");

const timestamp = process.env.SOURCE_DATE_EPOCH
  ? new Date(Number(process.env.SOURCE_DATE_EPOCH) * 1000).toISOString()
  : new Date().toISOString();

const bom = {
  $schema: "http://cyclonedx.org/schema/bom-1.6.schema.json",
  bomFormat: "CycloneDX",
  specVersion: "1.6",
  serialNumber: `urn:uuid:${uuid}`,
  version: 1,
  metadata: {
    timestamp,
    lifecycles: [{ phase: "build" }],
    tools: {
      components: [
        {
          type: "application",
          name: "hostelpro-sbom",
          version: "1.0.0",
          description: "scripts/sbom.mjs — parses package-lock.json, no third-party dependencies",
        },
      ],
    },
    component: {
      type: "application",
      "bom-ref": ROOT_REF,
      name: pkgJson.name || "hostelpro",
      version: pkgJson.version || "0.0.0",
      purl: ROOT_REF,
      description: "Multi-tenant PG/hostel management SaaS",
    },
    properties: [
      { name: "cdx:npm:lockfileVersion", value: String(lock.lockfileVersion) },
      { name: "cdx:npm:omitDev", value: String(OMIT_DEV) },
      { name: "cdx:npm:lockfileSha256", value: digest },
    ],
  },
  components,
  dependencies,
};

/* ── self-check: an SBOM with dangling refs is worse than no SBOM ────────── */
const known = new Set([ROOT_REF, ...components.map((c) => c["bom-ref"])]);
const dangling = [];
for (const d of dependencies) {
  if (!known.has(d.ref)) dangling.push(d.ref);
  for (const t of d.dependsOn) if (!known.has(t)) dangling.push(t);
}
if (dangling.length) {
  die(`generated graph references ${dangling.length} unknown component(s), first: ${dangling[0]}`);
}

/* ── supply-chain observations (reported, never fatal) ───────────────────── */
const NPM_HOST = "registry.npmjs.org";
const foreignRegistry = [];
const noIntegrity = [];
const installScripts = [];
for (const c of components) {
  const url = c.externalReferences?.[0]?.url;
  if (!url) {
    noIntegrity.push(`${c.name}@${c.version} (no resolved url)`);
  } else {
    let host = url;
    try {
      host = new URL(url).host;
    } catch {
      /* non-URL resolved value (git/file spec) — report it verbatim */
    }
    if (host !== NPM_HOST) foreignRegistry.push(`${c.name}@${c.version} <- ${host}`);
  }
  if (!c.hashes) noIntegrity.push(`${c.name}@${c.version} (no integrity hash)`);
  if (c.properties.some((p) => p.name === "cdx:npm:package:hasInstallScript")) {
    installScripts.push(`${c.name}@${c.version}`);
  }
}

/* ── write ──────────────────────────────────────────────────────────────── */
const json = JSON.stringify(bom, null, 2) + "\n";
if (PRINT) process.stdout.write(json);
else fs.writeFileSync(OUT, json);

const rel = path.relative(ROOT, OUT).replace(/\\/g, "/");
console.log(`sbom: ${components.length} components, ${dependencies.length} graph nodes${OMIT_DEV ? " (production only)" : ""}`);
console.log(`sbom: lockfileVersion ${lock.lockfileVersion}, sha256 ${digest.slice(0, 16)}, serial urn:uuid:${uuid}`);
if (!PRINT) console.log(`sbom: wrote ${rel} (${(json.length / 1024).toFixed(1)} KiB)`);

const overrides = Object.keys(pkgJson.overrides || {});
if (overrides.length) {
  const pinned = overrides.map((n) => {
    const versions = [...new Set(components.filter((c) => c.name === n).map((c) => c.version))];
    return `${n} -> ${versions.length ? versions.join(", ") : "not installed"}`;
  });
  console.log(`sbom: npm overrides in effect: ${pinned.join(" | ")}`);
}
if (installScripts.length) {
  const head = installScripts.slice(0, 8).join(", ");
  console.log(`sbom: ${installScripts.length} package(s) run install scripts: ${head}${installScripts.length > 8 ? ", ..." : ""}`);
}
if (foreignRegistry.length) {
  console.warn(`sbom: WARNING ${foreignRegistry.length} package(s) not from ${NPM_HOST}:\n  ${foreignRegistry.slice(0, 10).join("\n  ")}`);
}
if (noIntegrity.length) {
  console.warn(`sbom: WARNING ${noIntegrity.length} package(s) without an integrity hash:\n  ${noIntegrity.slice(0, 10).join("\n  ")}`);
}
if (unresolved) {
  console.warn(`sbom: WARNING ${unresolved} declared dependency edge(s) could not be resolved in the lockfile`);
}
if (!foreignRegistry.length && !noIntegrity.length && !unresolved) {
  console.log(`sbom: all components resolve to ${NPM_HOST} with an integrity hash`);
}

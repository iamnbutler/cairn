#!/usr/bin/env bun
// App binary sizes (bench/size.md), and the guard `make size` runs.
//
//   bun tools/size/size.ts --bin <release bin dir> --maps <dir> --out <dir> [--limit BYTES] App…
//
// For each app executable, already built with `swift build -c release --product <App>
// -Xlinker -map -Xlinker <maps>/<App>.map`, it strips a copy into <out>/<App> (`strip`, every
// local and debug symbol gone, as a shipped binary would be), prints its size, and attributes
// the bytes the linker kept to where they came from, from the link map:
//
//   Lean runtime    libInit/Std (compiled Lean) and leanrt, libuv, libgmp (C/C++), all from
//                   build/lib/libcairn_lean.a
//   Cairn (Lean)    the framework (`Cairn.*`), also from libcairn_lean.a
//   app library     build/lib/libcairn_app_<app>.a: the app's model, view and exports
//   Swift host      every object SwiftPM compiled, by target (CairnHost, CairnRender, …)
//   Metal shaders   the shader source CairnRender compiles at run time (a string in its object)
//   linker, other   stubs, unwind tables, Objective-C and Swift metadata the linker synthesizes,
//                   the dynamic-symbol and fixup tables left after `strip`, and page padding
//
// The map lists only live symbols (release links dead-strip), so the attribution is what is in
// the binary, not what the archives offer. It fails (exit 1) if a stripped binary is larger than
// --limit: an app that links `Lean` (the compiler) is about 100 MB, every other app a few MB.

import { readFileSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const args = process.argv.slice(2);
const opt = (name: string, dflt?: string) => {
  const i = args.indexOf(name);
  if (i < 0) return dflt;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
};
const binDir = opt("--bin");
const mapDir = opt("--maps");
const outDir = opt("--out", "build/size")!;
const limit = Number(opt("--limit", "5000000"));
const apps = args;
if (!binDir || !mapDir || apps.length === 0) {
  console.error("usage: size.ts --bin <dir> --maps <dir> [--out dir] [--limit bytes] App…");
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });

type Bucket =
  | "Lean runtime: Init, Std"
  | "Lean runtime: leanrt, libuv, libgmp"
  | "Cairn (Lean)"
  | "app library"
  | "Swift host"
  | "Metal shader source";

/** Bytes per object file and per bucket, from a ld64 link map's live symbols. */
function attribute(mapPath: string) {
  const lines = readFileSync(mapPath, "utf8").split("\n");
  const files = new Map<number, string>();
  const bytes = new Map<number, number>();
  const names = new Map<number, string[]>();
  let section = "";
  let shader = 0;
  for (const line of lines) {
    if (line.startsWith("# ")) {
      if (line.startsWith("# Object files:")) section = "files";
      else if (line.startsWith("# Sections:")) section = "sections";
      else if (line.startsWith("# Symbols:")) section = "symbols";
      else if (line.startsWith("# Dead Stripped Symbols:")) section = "dead";
      continue;
    }
    if (section === "files") {
      const m = line.match(/^\[\s*(\d+)\]\s+(.*)$/);
      if (m) files.set(Number(m[1]), m[2]);
    } else if (section === "symbols") {
      const m = line.match(/^0x[0-9A-Fa-f]+\s+0x([0-9A-Fa-f]+)\s+\[\s*(\d+)\]\s+(.*)$/);
      if (!m) continue;
      const size = parseInt(m[1], 16), file = Number(m[2]), name = m[3];
      bytes.set(file, (bytes.get(file) ?? 0) + size);
      const ns = names.get(file) ?? [];
      if (ns.length < 4000) ns.push(name);
      names.set(file, ns);
      // The shader source is one string literal starting with the Metal include.
      if (name.startsWith("literal string: #include <metal_stdlib>")) shader += size;
    }
  }
  const buckets = new Map<string, number>();
  const hostTargets = new Map<string, number>();
  const add = (m: Map<string, number>, k: string, v: number) => m.set(k, (m.get(k) ?? 0) + v);
  for (const [file, n] of bytes) {
    const path = files.get(file) ?? "";
    let b: Bucket | "linker" = "linker";
    if (/libcairn_app_[^/]*\.a\(/.test(path)) b = "app library";
    else if (/libcairn_lean\.a\(/.test(path)) {
      const syms = names.get(file) ?? [];
      if (syms.some((s) => /Cairn/.test(s))) b = "Cairn (Lean)";
      else if (/\.c\.o(\.export)?\)$/.test(path)) b = "Lean runtime: Init, Std";
      else b = "Lean runtime: leanrt, libuv, libgmp";
    } else if (/\/host\/\.build\//.test(path)) {
      // SwiftPM's objects: Products/<Mode>/<Target>.o per library target, and the
      // executable's own <App>-p.build/…/main.o.
      b = "Swift host";
      const t = path.match(/\/([^/]+)-p\.build\//)?.[1] ?? path.match(/\/([^/]+)\.o$/)?.[1] ?? path;
      add(hostTargets, t, n);
    }
    add(buckets, b, n);
  }
  // The shader string is counted inside CairnRender; report it on its own line instead.
  add(buckets, "Swift host", -shader);
  add(hostTargets, "CairnRender", -shader);
  add(buckets, "Metal shader source", shader);
  return { buckets, hostTargets };
}

const mb = (n: number) => (n / 1e6).toFixed(2) + " MB";
const order: (Bucket | "linker, other")[] = [
  "Lean runtime: Init, Std",
  "Lean runtime: leanrt, libuv, libgmp",
  "Cairn (Lean)",
  "app library",
  "Swift host",
  "Metal shader source",
  "linker, other",
];
let failed = false;
const summary: Record<string, unknown> = {};
for (const app of apps) {
  const out = join(outDir, app);
  const r = spawnSync("strip", ["-o", out, join(binDir, app)], { stdio: "inherit" });
  if (r.status !== 0) process.exit(1);
  const total = statSync(out).size;
  const unstripped = statSync(join(binDir, app)).size;
  const { buckets, hostTargets } = attribute(join(mapDir, `${app}.map`));
  let attributed = 0;
  for (const [k, v] of buckets) if (k !== "linker") attributed += v;
  const rows = order.map((k) => {
    const v = k === "linker, other" ? total - attributed : buckets.get(k) ?? 0;
    return [k, v] as const;
  });
  console.log(`${app}: ${total.toLocaleString()} bytes stripped (${mb(total)}), ${unstripped.toLocaleString()} before strip`);
  for (const [k, v] of rows) {
    console.log(`  ${k.padEnd(38)} ${v.toLocaleString().padStart(11)}  ${((100 * v) / total).toFixed(1).padStart(5)}%`);
  }
  const host = [...hostTargets].sort((a, b) => b[1] - a[1]);
  console.log(`  Swift host by target: ${host.map(([t, n]) => `${t} ${n.toLocaleString()}`).join(", ")}`);
  summary[app] = { stripped: total, unstripped, breakdown: Object.fromEntries(rows), host: Object.fromEntries(host) };
  if (total > limit) {
    console.error(`size: ${app} is ${total.toLocaleString()} bytes stripped, over the ${limit.toLocaleString()}-byte limit. Does it link Lean (the compiler)? See bench/size.md.`);
    failed = true;
  }
}
writeFileSync(join(outDir, "size.json"), JSON.stringify(summary, null, 2) + "\n");
if (failed) process.exit(1);
console.log(`size: every app is under ${limit.toLocaleString()} bytes stripped`);

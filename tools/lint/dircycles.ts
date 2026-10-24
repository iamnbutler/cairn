#!/usr/bin/env bun
// Directory-level import cycles (docs/packages-and-std.md, "The graph"), for `make lint`.
//
//   bun tools/lint/dircycles.ts [lean dir]
//
// Lean refuses cycles between modules, but not between directories. Each module belongs to the
// directory its first two name components give (`Cairn.Frame.Encode` and the umbrella
// `Cairn.Frame` are both `Cairn.Frame`; `Cairn.Fuzz.Trusted.Gen` is `Cairn.Fuzz`). Every
// `import` in every .lean file under the Lean package (default lean/, skipping .lake) is an edge
// between directories; the strongly connected components of that graph with more than one
// directory are cycles. It prints each with the imports that close it and exits 1 if there are
// any.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";

const root = process.argv[2] ?? "lean";

function* leanFiles(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    if (name.startsWith(".")) continue; // .lake
    const p = join(dir, name);
    if (statSync(p).isDirectory()) yield* leanFiles(p);
    else if (name.endsWith(".lean")) yield p;
  }
}

const SHIMS = new Set(["Cairn.Frame.Boundary", "Cairn.Runtime.Hit", "Cairn.Text.Metrics"]);

const dirOf = (m: string) => m.split(".").slice(0, 2).join(".");

// The imports in a file's header: `[public] [meta] import [all] A [B …]` lines after an optional
// `module` (or `prelude`), among blank lines and comments; the header ends at the first other line.
const importLine = /^(?:public\s+|private\s+)?(?:meta\s+)?import\s+(?:all\s+)?(.+)$/;
function imports(text: string): string[] {
  const out: string[] = [];
  let inComment = 0;
  for (const raw of text.split("\n")) {
    let line = raw.trim();
    if (inComment > 0 || line.startsWith("/-")) {
      // Lean's block comments nest.
      for (let i = 0; i < line.length - 1; i++) {
        if (line[i] === "/" && line[i + 1] === "-") (inComment++, i++);
        else if (line[i] === "-" && line[i + 1] === "/") (inComment--, i++);
      }
      continue;
    }
    line = line.replace(/--.*$/, "").trim();
    if (line === "" || line === "module" || line === "prelude") continue;
    const m = importLine.exec(line);
    if (!m) break;
    out.push(...m[1].split(/\s+/));
  }
  return out;
}

// edges: from directory → to directory → the module imports that make the edge
const edges = new Map<string, Map<string, string[]>>();
const nodes = new Set<string>();
for (const file of leanFiles(root)) {
  const mod = relative(root, file).slice(0, -".lean".length).split(sep).join(".");
  const from = dirOf(mod);
  nodes.add(from);
  const targets = imports(readFileSync(file, "utf8"));
  // A shim that grew more than its one import is a module again, and is checked like one.
  if (SHIMS.has(mod) && targets.length === 1) continue;
  for (const target of targets) {
    const to = dirOf(target);
    if (to === from) continue;
    nodes.add(to);
    const out = edges.get(from) ?? new Map<string, string[]>();
    edges.set(from, out);
    out.set(to, [...(out.get(to) ?? []), `${mod} → ${target}`]);
  }
}

// Tarjan's strongly connected components.
let index = 0;
const idx = new Map<string, number>();
const low = new Map<string, number>();
const stack: string[] = [];
const onStack = new Set<string>();
const sccs: string[][] = [];
function connect(v: string) {
  idx.set(v, index);
  low.set(v, index++);
  stack.push(v);
  onStack.add(v);
  for (const w of (edges.get(v) ?? new Map()).keys()) {
    if (!idx.has(w)) {
      connect(w);
      low.set(v, Math.min(low.get(v)!, low.get(w)!));
    } else if (onStack.has(w)) low.set(v, Math.min(low.get(v)!, idx.get(w)!));
  }
  if (low.get(v) === idx.get(v)) {
    const c: string[] = [];
    let w: string;
    do {
      w = stack.pop()!;
      onStack.delete(w);
      c.push(w);
    } while (w !== v);
    if (c.length > 1) sccs.push(c.sort());
  }
}
for (const v of [...nodes].sort()) if (!idx.has(v)) connect(v);

if (sccs.length === 0) process.exit(0);
// Simple cycles in a component, each once: start at its least directory, visit only greater ones.
function cycles(c: string[]): string[][] {
  const inC = new Set(c);
  const found: string[][] = [];
  for (const start of c) {
    const walk = (v: string, path: string[]) => {
      for (const w of (edges.get(v) ?? new Map()).keys()) {
        if (!inC.has(w)) continue;
        if (w === start) found.push([...path, start]);
        else if (w > start && !path.includes(w)) walk(w, [...path, w]);
      }
    };
    walk(start, [start]);
  }
  return found;
}

const all = sccs.map(cycles);
const n = all.reduce((k, cs) => k + cs.length, 0);
console.log(`lint: ${n} directory-level import cycle(s) in ${sccs.length} component(s) (docs/packages-and-std.md, "The graph"):`);
for (const [i, c] of sccs.entries()) {
  const inC = new Set(c);
  console.log(`  ${c.join(", ")}:`);
  for (const cyc of all[i]) console.log(`    cycle ${cyc.join(" → ")}`);
  for (const from of c)
    for (const [to, why] of edges.get(from) ?? [])
      if (inC.has(to)) console.log(`    ${from} → ${to}: ${why.join("; ")}`);
}
process.exit(1);

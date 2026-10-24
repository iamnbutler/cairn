// cairn-doc: a package's code and the build's evidence → its docs (docs/doc.md).
//
//   bun tools/doc/cairn-doc.ts --name Todo --dir build/doc/Todo [--app Todo] [--private]
//       [--link Cairn.=../../Cairn/dist/] [--open]
//
// Reads <dir>/doc.json (lake exe doc), <dir>/claims.json (lake exe claims), claims.lock, and for
// --app the same evidence the map reads: build/fuzz/<App>.json, build/fuzz/trusted.json, build/conformance/<App>.json and the
// map's capture, build/map/<App>/capture/. Writes the pages to <dir>/dist/.
//
// The claims' evidence comes from tools/map/evidence.ts, so a claim reads the same here as on
// the map. render.ts draws the pages. Nothing in the output is typed by hand.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { evaluate, type Audit, type Capture, type Claim, type Conformance, type Fuzz, type Lock, type Trusted } from "../map/evidence";
import { render, type DocJson } from "./render";

const { values: opts } = parseArgs({
	options: {
		name: { type: "string" },
		dir: { type: "string" },
		app: { type: "string" },
		private: { type: "boolean", default: false },
		link: { type: "string", multiple: true, default: [] },
		command: { type: "string" },
		open: { type: "boolean", default: false },
		root: { type: "string", default: resolve(import.meta.dir, "../..") },
	},
});
const fail = (message: string): never => {
	console.error(`cairn-doc: ${message}`);
	process.exit(1);
};
const json = <T>(path: string): T => JSON.parse(readFileSync(path, "utf8"));
const maybe = <T>(path: string): T | null => (existsSync(path) ? json<T>(path) : null);

const started = performance.now();
const name = opts.name || fail("--name <Package>");
const root = opts.root!;
const DIR = resolve(opts.dir || join(root, "build/doc", name));
const DIST = join(DIR, "dist");
const app = opts.app;

const doc = json<DocJson>(join(DIR, "doc.json"));
const claims = maybe<{ claims: Claim[] }>(join(DIR, "claims.json"))?.claims ?? [];
// What the map takes from `lake exe audit`, the doc export already has: each theorem's axioms
// beyond the standard three (the same `collectAxioms`), for the package's own theorems.
const audit: Audit = {
	theorems: Object.fromEntries(doc.decls.filter((d) => d.axioms).map((d) => [d.name, { ok: d.axioms!.length === 0, extraAxioms: d.axioms! }])),
};
const lock: Lock[] = readFileSync(join(root, "claims.lock"), "utf8")
	.split("\n")
	.filter((l) => l && !l.startsWith("#"))
	.map((l) => {
		const [id, kind, status, statement, ...title] = l.split("\t");
		return { id: Number(id), kind: kind!, status: status!, statement: statement!, title: title.join("\t") };
	});
const fuzz = app ? maybe<Fuzz>(join(root, "build/fuzz", `${app}.json`)) : null;
const trusted = maybe<Trusted>(join(root, "build/fuzz/trusted.json"));
const conformance = app ? maybe<Conformance>(join(root, "build/conformance", `${app}.json`)) : null;
const captureDir = app ? join(root, "build/map", app, "capture") : "";
const capture = app ? maybe<Capture>(join(captureDir, "capture.json")) : null;

// Screenshots from the map's capture, as WebP when cwebp is installed (as on the map).
rmSync(DIST, { recursive: true, force: true });
mkdirSync(DIST, { recursive: true });
const webp = Bun.which("cwebp");
const scale = capture?.scale || 2;
const sizes = new Map<string, [number, number]>();
for (const seq of capture?.sequences || []) for (const s of seq.shots) sizes.set(s.pinned, [Math.round(s.width / scale), Math.round(s.height / scale)]);
const image = (file: string) => {
	const out = webp ? file.replace(/\.png$/, ".webp") : file;
	mkdirSync(join(DIST, "img"), { recursive: true });
	if (!existsSync(join(DIST, "img", out))) {
		if (webp) Bun.spawnSync([webp, "-quiet", "-q", "85", join(captureDir, file), "-o", join(DIST, "img", out)]);
		else cpSync(join(captureDir, file), join(DIST, "img", out));
	}
	if (sizes.has(file)) sizes.set(out, sizes.get(file)!);
	return out;
};
const conformable = !!app && existsSync(join(root, "tools/conformance/lean/Conformance/Apps", `${app}.lean`));
// Only the screenshots a page shows are copied: a move's before and after, a place's window.
const rows = evaluate({ app: app ?? name, claims, audit, lock, fuzz, trusted, conformance, capture, conformable }, (f) => (webp ? f.replace(/\.png$/, ".webp") : f));
for (const r of rows) {
	const keep = r.claim.kind === "move" ? [r.shots.before, r.shots.after] : r.claim.kind === "place" ? [r.shots.frames[0]] : [];
	for (const f of keep) if (f) image(f.replace(/\.webp$/, ".png"));
}

const inputs = [
	app && claims.some((c) => c.kind !== "assume") ? (fuzz ? `fuzz: ${fuzz.iterations.toLocaleString("en")} sequences` : "fuzz: not run") : "",
	app && claims.some((c) => c.kind !== "assume") ? (conformance ? `conformance: ${conformance.runs?.toLocaleString("en") ?? "?"} walks` : `conformance: ${conformable ? "not run" : "no generator"}`) : "",
	app && claims.some((c) => c.kind !== "assume") ? (capture ? "capture: from the map" : "capture: not run (make map)") : "",
	claims.some((c) => c.kind === "assume") && trusted ? `trusted base: ${Object.keys(trusted.checks ?? {}).length} checks` : "",
].filter(Boolean);

const links = (opts.link as string[]).map((l) => {
	const [prefix, url] = l.split("=");
	return [prefix!, url!] as [string, string];
});
const pages = render({
	name,
	command: opts.command || `make doc ${app ? `APP=${app}` : `PKG=${name}`}`,
	doc,
	rows,
	showPrivate: opts.private!,
	links,
	size: (f) => sizes.get(f.replace(/\.webp$/, ".png")),
	inputs,
});
for (const [file, content] of Object.entries(pages)) writeFileSync(join(DIST, file), content);
cpSync(join(root, "tools/map/style.css"), join(DIST, "style.css"));
cpSync(join(import.meta.dir, "doc.css"), join(DIST, "doc.css"));
cpSync(join(import.meta.dir, "search.js"), join(DIST, "search.js"));
cpSync(join(root, "site/public/icon.svg"), join(DIST, "icon.svg"));

const bytes = [...new Bun.Glob("**/*").scanSync({ cwd: DIST })].reduce((n, f) => n + Bun.file(join(DIST, f)).size, 0);
console.log(
	`${name}: ${doc.modules.length} modules, ${doc.decls.length} declarations, ${rows.length} claims → ${Object.keys(pages).length} files, ${(bytes / 1024).toFixed(0)} KB in ${((performance.now() - started) / 1000).toFixed(1)} s → ${join(DIST, "index.html")}`,
);
if (opts.open) Bun.spawnSync(["open", join(DIST, "index.html")]);

// Publish the "Try it" data (docs/try.md) the way media is published (tools/media/put.sh): the
// files go to the cairn-media R2 bucket, served by the Worker at /m/<key>, and a small list that
// points at them is committed. The deploy builds nothing.
//
//   bun tools/try/put.ts [--out build/try/out] [--examples <cairn_examples checkout>]
//
// Each app's graph.json goes to try/<app>/<hash>.json and each frame to try/img/<file> (`try.ts
// build` names frames by their content hash), so a key never changes what it holds and the
// Worker's immutable caching is right. A key the live site already serves isn't uploaded again.
// Then site/public/try/apps.json lists, per app, its graph's URL and counts, and the examples'
// commit and version. Commit it, merge, and deploy from main (make site). Run from the repo root.
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";

const { values: opts } = parseArgs({ options: { out: { type: "string", default: "build/try/out" }, examples: { type: "string" } } });
const SITE = "https://cairn.iamnbutler.workers.dev";
const LIST = "site/public/try/apps.json";
const fail = (m: string): never => {
	console.error(`try put: ${m}`);
	process.exit(1);
};

const out = opts.out!;
if (!existsSync(out)) fail(`no ${out}: run make try first`);
const apps = readdirSync(out).filter((a) => existsSync(join(out, a, "graph.json"))).sort();
if (!apps.length) fail(`no <app>/graph.json under ${out}`);

/** Every upload, as [key, file, content type]. */
const uploads: [string, string, string][] = [];
const list: Record<string, unknown> = {};
for (const a of apps) {
	const file = join(out, a, "graph.json");
	const bytes = readFileSync(file);
	const g = JSON.parse(bytes.toString("utf8"));
	const key = `try/${a}/${createHash("sha256").update(bytes).digest("hex").slice(0, 16)}.json`;
	uploads.push([key, file, "application/json"]);
	const images = new Set<string>(g.states.map((s: { image: string }) => s.image));
	for (const img of images) uploads.push([`try/img/${img}`, join(out, a, "img", img), "image/webp"]);
	const size = [...images].reduce((n, f) => n + readFileSync(join(out, a, "img", f)).length, 0);
	list[a] = {
		app: g.app,
		graph: `/m/${key}`,
		img: "/m/try/img/",
		first: g.states[0].image,
		width: g.width,
		height: g.height,
		states: g.states.length,
		edges: g.states.reduce((n: number, s: { edges: unknown[] }) => n + s.edges.length, 0),
		images: images.size,
		bytes: size + bytes.length,
		generated: g.generated,
	};
}

// The examples the frames came from: their commit, their version and the Cairn they built on.
let source: Record<string, string> | undefined;
if (opts.examples) {
	const ex = opts.examples;
	const git = (args: string[], cwd: string) => Bun.spawnSync(["git", ...args], { cwd }).stdout.toString().trim();
	const toml = readFileSync(join(ex, "cairn.toml"), "utf8");
	const cairn = join(ex, "lean/.lake/packages/cairn");
	source = {
		repo: "iamnbutler/cairn_examples",
		commit: git(["rev-parse", "HEAD"], ex),
		version: /^version\s*=\s*"([^"]+)"/m.exec(toml)?.[1] ?? "",
		cairn: existsSync(cairn) ? git(["describe", "--tags", "--always"], cairn) : "",
	};
}

const present = async (key: string) => (await fetch(`${SITE}/m/${key}`, { method: "HEAD" })).ok;
let sent = 0, kept = 0;
const queue = [...uploads];
async function worker() {
	for (let u = queue.shift(); u; u = queue.shift()) {
		const [key, file, type] = u;
		if (await present(key)) { kept++; continue; }
		const r = Bun.spawn(["npx", "-y", "wrangler@4", "r2", "object", "put", `cairn-media/${key}`, "--file", file, "--content-type", type, "--remote"], { stdout: "ignore", stderr: "pipe" });
		if ((await r.exited) !== 0) fail(`upload of ${key} failed: ${await new Response(r.stderr).text()}`);
		sent++;
	}
}
await Promise.all(Array.from({ length: 8 }, worker));
// The new list, only once everything it points at is up.
writeFileSync(LIST, JSON.stringify({ source, apps: list }, null, "\t") + "\n");
console.log(`try put: ${sent} uploaded, ${kept} already there; ${LIST} lists ${apps.join(", ")}`);

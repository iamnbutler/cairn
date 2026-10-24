// cairn-map: an app's claims and the build's evidence → Cairn's map (docs/map.md).
//
//   bun tools/map/cairn-map.ts script --claims claims.json > script.json
//       the capture script: the initial state, each flow's witness, and each move no flow presses
//   bun tools/map/cairn-map.ts build --app Counter --dir build/map/Counter
//       reads <dir>/claims.json (lake exe claims), <dir>/audit.json (lake exe audit --json),
//       claims.lock, build/fuzz/<App>.json (make fuzz), build/fuzz/trusted.json (workstream M),
//       build/conformance/<App>.json (make conformance) and <dir>/capture/ (Cairn<App>
//       --map-capture), all but the first two optional; writes <dir>/evidence.json and the pages
//       in <dir>/dist/.
//
// evidence.ts decides every status; render.ts draws the pages. Nothing in the output is typed by
// hand. Needs only bun (and cwebp, if installed, for smaller images).
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { captureScript, counts, evaluate, gaps, type Audit, type Capture, type Claim, type Conformance, type Fuzz, type Lock, type Trusted } from "./evidence";
import { render } from "./render";

const { values: opts, positionals } = parseArgs({
	allowPositionals: true,
	options: {
		claims: { type: "string" },
		app: { type: "string", default: "Counter" },
		name: { type: "string" },
		dir: { type: "string" },
		root: { type: "string", default: resolve(import.meta.dir, "../..") },
	},
});
const fail = (message: string): never => {
	console.error(`cairn-map: ${message}`);
	process.exit(1);
};
const json = <T>(path: string): T => JSON.parse(readFileSync(path, "utf8"));
const maybe = <T>(path: string): T | null => (existsSync(path) ? json<T>(path) : null);

if (positionals[0] === "script") {
	const { claims } = json<{ claims: Claim[] }>(opts.claims || fail("--claims <claims.json>"));
	console.log(JSON.stringify(captureScript(claims), null, 2));
} else if (positionals[0] === "build") build();
else fail("usage: cairn-map.ts script --claims <claims.json> | build --app <App> --dir <dir>");

function build() {
	const app = opts.app!;
	const root = opts.root!;
	const DIR = resolve(opts.dir || join(root, "build/map", app));
	const DIST = join(DIR, "dist");
	const at = (...p: string[]) => join(DIR, ...p);
	const paths = {
		fuzz: join(root, "build/fuzz", `${app}.json`),
		trusted: join(root, "build/fuzz/trusted.json"),
		conformance: join(root, "build/conformance", `${app}.json`),
	};
	const { claims } = json<{ claims: Claim[] }>(at("claims.json"));
	const audit = json<Audit>(at("audit.json"));
	const lock: Lock[] = readFileSync(join(root, "claims.lock"), "utf8")
		.split("\n")
		.filter((l) => l && !l.startsWith("#"))
		.map((l) => {
			const [id, kind, status, statement, ...title] = l.split("\t");
			return { id: Number(id), kind: kind!, status: status!, statement: statement!, title: title.join("\t") };
		});
	const fuzz = maybe<Fuzz>(paths.fuzz);
	const trusted = maybe<Trusted>(paths.trusted);
	const conformance = maybe<Conformance>(paths.conformance);
	const capture = maybe<Capture>(at("capture/capture.json"));

	// Images: the capture's pinned frames, as WebP when cwebp is installed. Sizes are CSS pixels.
	rmSync(DIST, { recursive: true, force: true });
	mkdirSync(join(DIST, "img"), { recursive: true });
	const webp = Bun.which("cwebp");
	const scale = capture?.scale || 2;
	const sizes = new Map<string, [number, number]>();
	for (const seq of capture?.sequences || []) for (const s of seq.shots) sizes.set(s.pinned, [Math.round(s.width / scale), Math.round(s.height / scale)]);
	const image = (file: string) => {
		const out = webp ? file.replace(/\.png$/, ".webp") : file;
		if (!existsSync(join(DIST, "img", out))) {
			if (webp) Bun.spawnSync([webp, "-quiet", "-q", "85", at("capture", file), "-o", join(DIST, "img", out)]);
			else cpSync(at("capture", file), join(DIST, "img", out));
		}
		if (sizes.has(file)) sizes.set(out, sizes.get(file)!);
		return out;
	};

	const conformable = existsSync(join(root, "tools/conformance/lean/Conformance/Apps", `${app}.lean`));
	const rows = evaluate({ app, claims, audit, lock, fuzz, trusted, conformance, capture, conformable }, image);

	// An app-less map (the trusted base's assumptions) has nothing to fuzz, run or capture.
	const isApp = claims.some((c) => c.kind !== "assume");
	const inputs = [
		`Audit: ${Object.keys(audit.theorems).length.toLocaleString("en")} theorems.`,
		!isApp ? "" : fuzz ? `Fuzz: ${fuzz.iterations.toLocaleString("en")} sequences${fuzz.mode === "model" ? " of the model" : ""}, seed ${fuzz.seed}.` : `Fuzz: not run (\`make fuzz APP=${app}\`).`,
		!isApp ? "" : conformance ? `Conformance: ${conformance.runs?.toLocaleString("en") ?? "?"} walks${conformance.commit ? ` at \`${conformance.commit}\`` : ""}.` : `Conformance: ${conformable ? "not run" : "no generator yet"}.`,
		!isApp ? "" : capture ? `Capture: ${capture.sequences.length} sequences, headless.` : `Capture: not run.`,
		trusted ? `Trusted base: ${Object.keys(trusted.checks ?? {}).length} checks${trusted.n ? `, ${trusted.n.toLocaleString("en")} cases a suite` : ""}${trusted.seed ? `, seed ${trusted.seed}` : ""}.` : "",
	].filter(Boolean);

	const pages = render({ app: opts.name || app, rows, size: (f) => sizes.get(f), inputs, code: "https://github.com/iamnbutler/cairn/blob/main/" });
	for (const [file, html] of Object.entries(pages)) writeFileSync(join(DIST, file), html);
	cpSync(join(import.meta.dir, "style.css"), join(DIST, "style.css"));
	cpSync(join(root, "site/public/icon.svg"), join(DIST, "icon.svg"));

	// evidence.json: the same rows, for anything that wants to render its own view.
	const n = counts(rows);
	writeFileSync(
		at("evidence.json"),
		JSON.stringify(
			{
				app,
				generated: new Date().toISOString(),
				inputs: { fuzz: fuzz ? paths.fuzz : null, trusted: trusted ? paths.trusted : null, conformance: conformance ? paths.conformance : null, capture: !!capture, theoremsAudited: Object.keys(audit.theorems).length },
				counts: { kinds: n.kinds, headlines: Object.fromEntries(n.headlines) },
				claims: rows.map((r) => ({
					id: r.claim.id,
					ref: r.claim.ref,
					kind: r.claim.kind,
					title: r.claim.title,
					headline: r.headline,
					evidence: r.marks,
					theorems: r.theorems,
					ledger: r.ledger,
					findings: r.findings,
					shots: { ...r.shots, frames: r.shots.frames.map((f) => `img/${f}`) },
				})),
				gaps: gaps(rows).map((g) => ({ ref: g.row.claim.ref, what: g.what, detail: g.detail, broken: g.broken })),
			},
			null,
			2,
		),
	);
	cpSync(at("evidence.json"), join(DIST, "evidence.json"));

	const spread = [...n.headlines].map(([h, k]) => `${k} ${h}`).join(", ");
	console.log(`${app}: ${rows.length} claims (${spread}); ${gaps(rows).length} gaps → ${join(DIST, "index.html")}`);
}

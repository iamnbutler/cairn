// "Try it" data (docs/try.md): an app's states, explored ahead of time. The site built pages from
// it for the examples until 0.3.0.
//
//   bun tools/try/try.ts script --app Todo --claims claims.json > script.json
//       what Cairn<App> --try-capture may do to each claim's controls, and the walk's bounds
//   bun tools/try/try.ts build --app Todo --dir build/try/Todo --out build/site/try/todo
//       <dir>/claims.json and <dir>/capture/ (try.json and a PNG per state) → <out>/graph.json
//       and <out>/img/*.webp
//
// The actions come from the claims export: a move's triggers, and for a text field the texts its
// flows' witnesses type. Every frame is the app's own (host/Sources/CairnCapture/Explore.swift);
// the page (site/public/try/try.js) only follows the recorded edges. Readings come from
// site/claims.js, as on the claim pages.
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { reading } from "../../site/claims.js";

/** How far each app's walk goes: actions from the start, states in all, texts per field. Chosen
 *  so each graph is rich and the whole site stays small (docs/try.md has the sizes). */
export const BOUNDS: Record<string, { maxDepth: number; maxStates: number; texts: number }> = {
	Counter: { maxDepth: 20, maxStates: 40, texts: 0 },
	Basics: { maxDepth: 8, maxStates: 200, texts: 2 },
	Todo: { maxDepth: 8, maxStates: 400, texts: 2 },
};

type Op = { kind: string; text?: string };
type Step = { trigger: string; claim: number; ref: string; key: number; op?: Op };
type Claim = {
	id: number; ref: string; kind: string; title: string; does: string; sees: string; place: number | null;
	retired: string | null; triggers: string[]; keyed: boolean; witness: Step[] | null | { error: string };
	evidence: { theorem: string; role: string; proved?: boolean; extraAxioms?: string[] }[];
};
type Action = { label: string; steps: { trigger: string; op?: Op }[] };

const { values: opts, positionals } = parseArgs({
	allowPositionals: true,
	options: { app: { type: "string" }, claims: { type: "string" }, dir: { type: "string" }, out: { type: "string" }, root: { type: "string", default: resolve(import.meta.dir, "../..") } },
});
const fail = (m: string): never => {
	console.error(`try: ${m}`);
	process.exit(1);
};
const json = <T>(p: string): T => JSON.parse(readFileSync(p, "utf8"));

/** A typed text with its edge spaces visible: "  eggs " is a test that Enter trims them. */
const shown = (t: string) => t.replace(/^ +| +$/g, (s) => "␣".repeat(s.length));

/** Each live move's actions, by claim id. */
export function actions(claims: Claim[], texts: number): Record<string, Action[]> {
	const witnesses = claims.flatMap((c) => (Array.isArray(c.witness) ? c.witness : []));
	const out: Record<string, Action[]> = {};
	for (const c of claims) {
		if (c.kind !== "move" || c.retired) continue;
		const list: Action[] = [];
		for (const t of c.triggers) {
			if (t === "press") list.push({ label: "Press", steps: [{ trigger: "press" }] });
			else if (t === "doublePress") list.push({ label: "Double-click", steps: [{ trigger: "doublePress" }] });
			else if (t === "edit") {
				// The texts the witnesses type into this field, trimmed of nothing: "  eggs " is a test.
				const typed = [...new Set(witnesses.filter((s) => s.claim === c.id && s.op?.kind === "insert" && s.op.text).map((s) => s.op!.text!))];
				for (const text of typed.slice(0, texts))
					list.push({ label: `Type “${shown(text)}”`, steps: [{ trigger: "edit", op: { kind: "selectAll" } }, { trigger: "edit", op: { kind: "insert", text } }] });
				if (typed.length && texts) list.push({ label: "Clear", steps: [{ trigger: "edit", op: { kind: "selectAll" } }, { trigger: "edit", op: { kind: "deleteBackward" } }] });
			} else if (t === "submit") list.push({ label: "Press Enter", steps: [{ trigger: "submit" }] });
			else if (t === "cancel") list.push({ label: "Press Escape", steps: [{ trigger: "cancel" }] });
			// blur: the capture can't send one yet (docs/try.md).
		}
		if (list.length) out[String(c.id)] = list;
	}
	return out;
}

if (positionals[0] === "script") {
	const app = opts.app || fail("--app <App>");
	const b = BOUNDS[app] || fail(`no bounds for ${app} in tools/try/try.ts`);
	const { claims } = json<{ claims: Claim[] }>(opts.claims || fail("--claims <claims.json>"));
	console.log(JSON.stringify({ scale: 2, maxDepth: b.maxDepth, maxStates: b.maxStates, actions: actions(claims, b.texts) }, null, 2));
} else if (positionals[0] === "build") build();
else fail("usage: try.ts script --app <App> --claims <claims.json> | build --app <App> --dir <dir> --out <dir>");

function build() {
	const app = opts.app || fail("--app <App>");
	const dir = resolve(opts.dir || fail("--dir <dir>"));
	const out = resolve(opts.out || fail("--out <dir>"));
	const { claims } = json<{ claims: Claim[] }>(join(dir, "claims.json"));
	const cap = json<any>(join(dir, "capture", "try.json"));
	const lock = new Map(
		readFileSync(join(opts.root!, "claims.lock"), "utf8")
			.split("\n")
			.filter((l) => l && !l.startsWith("#"))
			.map((l) => {
				const [id, kind, status] = l.split("\t");
				return [Number(id), { kind: kind!, status: status! }] as const;
			}),
	);

	// Only what this writes: the page itself (index.html) comes from bongo.
	rmSync(join(out, "img"), { recursive: true, force: true });
	mkdirSync(join(out, "img"), { recursive: true });
	// One WebP per distinct picture: states whose windows differ only where nothing is painted
	// (focus without a caret, say) share a file. Lossless keeps text crisp at 1:1, and is smaller
	// than lossy for flat UI.
	const webp = Bun.which("cwebp") || fail("cwebp is needed (brew install webp)");
	const byHash = new Map<string, string>();
	const image = (file: string) => {
		const bytes = readFileSync(join(dir, "capture", file));
		const hash = createHash("sha256").update(bytes).digest("hex").slice(0, 12);
		if (!byHash.has(hash)) {
			const name = `${hash}.webp`;
			const r = Bun.spawnSync([webp, "-quiet", "-lossless", "-z", "6", join(dir, "capture", file), "-o", join(out, "img", name)]);
			if (r.exitCode !== 0) fail(`cwebp failed on ${file}`);
			byHash.set(hash, name);
		}
		return byHash.get(hash)!;
	};

	// The claims the controls belong to, and their places: what the side panel says.
	const used = new Set<number>(cap.states.flatMap((s: any) => s.controls.map((c: any) => c.claim)));
	const info: Record<string, unknown> = {};
	for (const c of claims) {
		if (!used.has(c.id) && c.kind !== "place") continue;
		const row = lock.get(c.id);
		const r = reading({ id: c.id, kind: c.kind, status: row?.status ?? "active", detail: c });
		info[c.id] = {
			ref: `cairn^${c.id}`, kind: c.kind, title: c.title, does: c.does, sees: c.sees, place: c.place, reading: r,
			theorems: c.evidence.map((e) => ({ theorem: e.theorem.replace(/^Examples\./, ""), proved: !!e.proved && !(e.extraAxioms ?? []).length })),
		};
	}
	const scale = cap.scale as number;
	const graph = {
		app,
		generated: new Date().toISOString(),
		scale,
		crop: cap.crop,
		width: cap.states[0].width / scale,
		height: cap.states[0].height / scale,
		maxDepth: cap.maxDepth,
		maxStates: cap.maxStates,
		actions: cap.actions,
		claims: info,
		states: cap.states.map((s: any) => ({
			image: image(s.image),
			depth: s.depth,
			from: s.from ?? null,
			focus: s.focus ?? null,
			text: s.text ?? null,
			// Rects in the image's logical pixels: the window's, less the crop's origin.
			controls: s.controls.map((c: any) => ({
				ref: c.ref, claim: c.claim, role: c.role, label: c.label, focused: c.focused || undefined, checked: c.checked ?? undefined,
				rect: [c.rect[0] - cap.crop[0], c.rect[1] - cap.crop[1], c.rect[2], c.rect[3]],
			})),
			edges: s.edges.map((e: any) => [e.ref, e.action, e.outcome === "ok" ? e.to : e.outcome]),
		})),
	};
	writeFileSync(join(out, "graph.json"), JSON.stringify(graph));
	const size = [...byHash.values()].reduce((n, f) => n + readFileSync(join(out, "img", f)).length, 0);
	const edges = graph.states.reduce((n: number, s: any) => n + s.edges.length, 0);
	console.log(`try ${app}: ${graph.states.length} states, ${edges} edges, ${byHash.size} images (${(size / 1024).toFixed(0)} KB) + graph.json (${(readFileSync(join(out, "graph.json")).length / 1024).toFixed(0)} KB) → ${out}`);
}


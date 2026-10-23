// cairn-map: an app's claims and their evidence → a map in the map skill's format (docs/map.md).
//
//   bun tools/map/cairn-map.ts script --claims claims.json > script.json
//       the capture script: the initial state, each flow's witness, and each move no flow presses
//   bun tools/map/cairn-map.ts build --app Counter --dir build/map/Counter
//       reads <dir>/claims.json (lake exe claims), <dir>/audit.json (lake exe audit --json),
//       claims.lock, build/conformance/<App>.json (workstream J; optional) and <dir>/capture/
//       (<App> --map-capture), then writes map.yaml, areas/, img/, notes/evidence.html,
//       evidence.json and ids.txt into <dir>, and builds <dir>/dist with the map skill's map.ts.
//
// Statuses are computed from evidence here and nowhere else; nothing in the output is typed by
// hand. Needs only bun.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";

const { values: opts, positionals } = parseArgs({
	allowPositionals: true,
	options: {
		claims: { type: "string" },
		app: { type: "string", default: "Counter" },
		dir: { type: "string" },
		root: { type: "string", default: resolve(import.meta.dir, "../..") },
	},
});
const fail = (message: string): never => {
	console.error(`cairn-map: ${message}`);
	process.exit(1);
};
const json = <T>(path: string): T => JSON.parse(readFileSync(path, "utf8"));

// ---- Inputs ------------------------------------------------------------------------------------

type Step = { trigger: string; ref: string; claim: number; key: number; op?: string };
type Evidence = { role: string; theorem: string; proved: boolean; extraAxioms: string[] };
type Claim = {
	id: number;
	ref: string;
	kind: "move" | "flow" | "invariant" | "assume" | "place";
	title: string;
	does: string;
	sees: string;
	place: number | null;
	retired: string | null;
	module: string;
	decl: string;
	statement: string;
	triggers: string[];
	keyed: boolean;
	passes: number[];
	witness: Step[] | null | { error: string };
	machine: string | null;
	pos: { file: string; line: number | null };
	evidence: Evidence[];
};
type Audit = { theorems: Record<string, { ok: boolean; extraAxioms: string[] }> };
type Lock = { id: number; kind: string; status: string; statement: string; title: string };
// Workstream J's results. Proposed shape: per claim ref, whether every generated sequence that
// exercised it passed, and how many did.
type Conformance = { runs?: number; commit?: string; claims: Record<string, { pass: boolean; runs?: number; note?: string }> };
type Control = { ref: string; claim: number; key: number; role: string; label: string; rect: number[] };
type Shot = { after?: number; image: string; pinned: string; width: number; height: number; controls: Control[] };
type StepResult = { step: Step; ref: string; outcome: "ok" | "absent" | "unsupported" | "inert"; at?: number[] };
type Capture = { size: number[]; scale: number; crop: number[]; sequences: { name: string; shots: Shot[]; steps: StepResult[]; strip: string }[] };

const witnessOf = (c: Claim): Step[] => (Array.isArray(c.witness) ? c.witness : []);

if (positionals[0] === "script") script();
else if (positionals[0] === "build") build();
else fail("usage: cairn-map.ts script --claims <claims.json> | build --app <App> --dir <dir>");

/** The capture script: the initial frame, every flow's witness, and every move no witness presses. */
function script() {
	const { claims } = json<{ claims: Claim[] }>(opts.claims || fail("--claims <claims.json>"));
	const live = claims.filter((c) => !c.retired);
	const pressed = new Set(live.flatMap((c) => witnessOf(c).map((s) => s.claim)));
	const sequences = [
		{ name: "start", steps: [] as Step[] },
		...live.filter((c) => c.kind === "flow" && witnessOf(c).length).map((c) => ({ name: `flow-${c.id}`, steps: witnessOf(c) })),
		...live
			.filter((c) => c.kind === "move" && !pressed.has(c.id) && !c.keyed)
			.map((c) => ({ name: `move-${c.id}`, steps: [{ trigger: c.triggers[0] || "press", ref: c.ref, claim: c.id, key: 0 }] })),
	];
	console.log(JSON.stringify({ scale: 2, sequences }, null, 2));
}

// ---- Evidence ----------------------------------------------------------------------------------

type Cell = "yes" | "no" | "n/a" | "fails" | "missing" | "not run" | "pass" | "fail";
type Row = {
	id: number;
	ref: string;
	kind: string;
	title: string;
	status: string;
	closed?: string;
	proved: Cell;
	assumed: Cell;
	conformance: Cell;
	seen: Cell;
	theorems: { role: string; theorem: string; ok: boolean | null; extraAxioms: string[] }[];
	lock: string;
	findings: { text: string; at?: number[]; shot?: number }[];
	shots: string[];
};

function build() {
	const app = opts.app!;
	const DIR = resolve(opts.dir || join(opts.root!, "build/map", app));
	const at = (...p: string[]) => join(DIR, ...p);
	const { claims } = json<{ claims: Claim[] }>(at("claims.json"));
	const audit = json<Audit>(at("audit.json"));
	const lock: Lock[] = readFileSync(join(opts.root!, "claims.lock"), "utf8")
		.split("\n")
		.filter((l) => l && !l.startsWith("#"))
		.map((l) => {
			const [id, kind, status, statement, ...title] = l.split("\t");
			return { id: Number(id), kind: kind!, status: status!, statement: statement!, title: title.join("\t") };
		});
	const lockById = new Map(lock.map((l) => [l.id, l]));
	const confPath = join(opts.root!, "build/conformance", `${app}.json`);
	const conformance: Conformance | null = existsSync(confPath) ? json(confPath) : null;
	const capture: Capture | null = existsSync(at("capture/capture.json")) ? json(at("capture/capture.json")) : null;
	const byId = new Map(claims.map((c) => [c.id, c]));

	// Images: the pinned frames, as WebP when cwebp is installed (the map skill's format).
	rmSync(at("img"), { recursive: true, force: true });
	mkdirSync(at("img"), { recursive: true });
	const webp = Bun.which("cwebp");
	const img = (pinned: string) => {
		const out = webp ? pinned.replace(/\.png$/, ".webp") : pinned;
		if (!existsSync(at("img", out))) {
			if (webp) Bun.spawnSync([webp, "-quiet", "-q", "85", at("capture", pinned), "-o", at("img", out)]);
			else cpSync(at("capture", pinned), at("img", out));
		}
		return out;
	};

	// Where each move was seen: a step that pressed it (before and after), else any frame showing it.
	const seenMove = new Map<number, { shots: string[]; inert?: { rect: number[]; crop: number[] } }>();
	const flowSeen = new Map<number, StepResult[]>();
	for (const seq of capture?.sequences || []) {
		const flowId = seq.name.startsWith("flow-") ? Number(seq.name.slice(5)) : null;
		if (flowId !== null) flowSeen.set(flowId, seq.steps);
		seq.steps.forEach((r, k) => {
			if (r.outcome === "absent" || r.outcome === "unsupported") return;
			const before = seq.shots[k]!;
			const ctl = before.controls.find((c) => c.ref === r.ref)!;
			if (!seenMove.has(r.step.claim) || seenMove.get(r.step.claim)!.shots.length < 2)
				seenMove.set(r.step.claim, {
					shots: [img(before.pinned), img(seq.shots[k + 1]!.pinned)],
					inert: r.outcome === "inert" ? { rect: ctl.rect, crop: capture!.crop } : undefined,
				});
		});
		for (const shot of seq.shots)
			for (const c of shot.controls) if (!seenMove.has(c.claim)) seenMove.set(c.claim, { shots: [img(shot.pinned)] });
	}

	const rows: Row[] = claims.map((c) => {
		const findings: Row["findings"] = [];
		const theorems = c.evidence.map((e) => {
			const a = audit.theorems[e.theorem];
			return { role: e.role, theorem: e.theorem, ok: a ? a.ok : null, extraAxioms: a ? a.extraAxioms : [] };
		});
		for (const t of theorems) {
			if (t.ok === null) findings.push({ text: `\`${t.theorem}\` (${t.role}) is not in the axiom audit.` });
			else if (!t.ok) findings.push({ text: `\`${t.theorem}\` (${t.role}) depends on ${t.extraAxioms.map((x) => `\`${x}\``).join(", ")}.` });
		}
		const provable = c.kind === "move" || c.kind === "flow" || c.kind === "invariant";
		const proved: Cell = !provable ? "n/a" : !theorems.length ? "missing" : theorems.some((t) => t.ok === null) ? "missing" : theorems.every((t) => t.ok) ? "yes" : "fails";
		const assumed: Cell = c.kind === "assume" ? "yes" : "no";

		const conf = conformance?.claims[c.ref];
		const conformanceCell: Cell = c.kind === "place" || c.kind === "assume" ? "n/a" : !conformance || !conf ? "not run" : conf.pass ? "pass" : "fail";
		if (conf && !conf.pass) findings.push({ text: `Conformance failed${conf.note ? `: ${conf.note}` : "."}` });

		let seen: Cell = "n/a";
		let shots: string[] = [];
		if (c.kind === "move") {
			const s = seenMove.get(c.id);
			seen = s ? "yes" : "no";
			shots = s?.shots || [];
			if (s?.inert) {
				const [x, y, w, h] = s.inert.rect;
				const [cx, cy, W, H] = s.inert.crop;
				const pct = (v: number, of: number) => Math.round((v / of) * 1000) / 10;
				findings.push({ text: `Pressing ${c.ref} at its centre changed nothing in the frame.`, at: [pct(x! - cx!, W!), pct(y! - cy!, H!), pct(w!, W!), pct(h!, H!)] });
			}
		} else if (c.kind === "flow") {
			const steps = flowSeen.get(c.id);
			if (!witnessOf(c).length) seen = "no";
			else if (!steps) seen = "no";
			else {
				const bad = steps.find((s) => s.outcome !== "ok");
				const complete = steps.length === witnessOf(c).length && !bad;
				seen = complete ? "yes" : "no";
				if (bad?.outcome === "absent" || bad?.outcome === "inert")
					// The witness is proved live in the model; the running app disagreeing is a real finding.
					findings.push({ text: `The app ${bad.outcome === "absent" ? `has no control ${bad.ref} at` : `did not change on`} witness step ${steps.indexOf(bad) + 1} (${bad.step.trigger} ${bad.ref}), though the model's witness is live.` });
				shots = capture!.sequences.find((q) => q.name === `flow-${c.id}`)!.shots.map((s) => img(s.pinned));
			}
		} else if (c.kind === "place") {
			const start = capture?.sequences.find((q) => q.name === "start")?.shots[0];
			seen = start ? "yes" : "no";
			shots = start ? [img(start.pinned)] : [];
		}

		const locked = lockById.get(c.id);
		let lockState = "not locked";
		if (!locked) findings.push({ text: "Not in `claims.lock`: run `lake exe ledger update`." });
		else {
			lockState = locked.status;
			if (locked.statement !== c.statement) {
				lockState += ", meaning changed";
				findings.push({ text: `Its statement hash (\`${c.statement}\`) differs from \`claims.lock\` (\`${locked.statement}\`): give it a new id, or accept the change.` });
			}
		}

		// Status, from the evidence only (docs/map.md has the table).
		const broken = proved === "fails" || proved === "missing" || conformanceCell === "fail" || findings.some((f) => /the model's witness is live|changed nothing/.test(f.text));
		let status: string;
		if (c.retired) status = "closed";
		else if (broken) status = "broken";
		else if (c.kind === "assume") status = "untested";
		else if (conformanceCell === "pass" && (seen === "yes" || seen === "n/a")) status = "tested";
		else if (seen === "yes") status = "visual";
		else status = "untested";
		return {
			id: c.id,
			ref: c.ref,
			kind: c.kind,
			title: c.title,
			status,
			closed: c.retired ? `retired: ${c.retired}` : undefined,
			proved,
			assumed,
			conformance: conformanceCell,
			seen,
			theorems,
			lock: lockState,
			findings,
			shots,
		};
	});
	const rowOf = new Map(rows.map((r) => [r.id, r]));

	// ---- The map's sources -----------------------------------------------------------------------
	const cell = (name: string, v: Cell) => (v === "n/a" ? "" : `${name} ${v === "yes" || v === "pass" ? "✓" : `**${v}**`}`);
	const evidenceLine = (r: Row) =>
		[cell("proved", r.proved), r.assumed === "yes" ? "assumed" : "", r.kind === "assume" ? "" : cell("conformance", r.conformance), cell("seen", r.seen)].filter(Boolean).join(" · ");
	const placeTitle = (p: number | null) => (p !== null && byId.get(p) ? `${byId.get(p)!.title} (^${p})` : "");
	const where = (c: Claim, r: Row) => [placeTitle(c.place), evidenceLine(r)].filter(Boolean).join(" — ");
	const code = (c: Claim) => [c.pos.line ? `${c.pos.file}:${c.pos.line}` : c.pos.file];
	const common = (c: Claim) => {
		const r = rowOf.get(c.id)!;
		return { id: c.id, title: c.title, status: r.status === "closed" ? undefined : r.status, closed: r.closed, code: code(c), gaps: r.findings.length ? r.findings.map((f) => (f.at ? { text: f.text, at: f.at } : f.text)) : undefined };
	};
	const stepOf = (c: Claim) => {
		const r = rowOf.get(c.id)!;
		return { ...common(c), where: where(c, r), does: c.does, sees: c.sees || undefined, shot: r.shots.length ? r.shots : undefined };
	};
	const figuresOf = (c: Claim) => {
		const seq = capture?.sequences.find((q) => q.name === `flow-${c.id}`);
		if (!seq) return undefined;
		const done = seq.steps.length === witnessOf(c).length && seq.steps.every((s) => s.outcome === "ok");
		return {
			src: `img/${img(seq.strip)}`,
			caption: `The witness, ${witnessOf(c).map((s) => `${s.trigger} ${s.ref}`).join(", ")}, replayed on the app as clicks at each control's centre. Pins come from the frame's layout; blue marks the control the next step acts on.${done ? "" : " The replay stopped early."}`,
		};
	};
	const flowOf = (c: Claim, extra: object = {}) => {
		const r = rowOf.get(c.id)!;
		return { ...common(c), summary: `${c.does}${c.sees ? ` ${c.sees}` : ""} — ${evidenceLine(r)}`, ...extra };
	};

	const live = claims;
	const places = live.filter((c) => c.kind === "place");
	const flowPlace = (c: Claim) => c.place ?? byId.get(witnessOf(c)[0]?.claim ?? -1)?.place ?? null;
	const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
	type AreaOut = { slug: string; title: string; order: number; summary: string; flows: object[] };
	const areas: AreaOut[] = places.map((p, i) => ({
		slug: slug(p.title),
		title: p.title,
		order: (i + 1) * 10,
		summary: `${p.does} Generated from the claims in \`${p.module}\`; every status comes from evidence (see the Evidence page).`,
		flows: [
			{ ...flowOf(p), summary: evidenceLine(rowOf.get(p.id)!), steps: live.filter((m) => m.kind === "move" && m.place === p.id).map(stepOf) },
			...live.filter((f) => f.kind === "flow" && flowPlace(f) === p.id).map((f) => flowOf(f, { see: [...new Set(witnessOf(f).map((s) => s.claim))], figure: figuresOf(f) })),
		],
	}));
	const unplacedMoves = live.filter((m) => m.kind === "move" && (m.place === null || !byId.has(m.place)));
	const unplacedFlows = live.filter((f) => f.kind === "flow" && (flowPlace(f) === null || !places.some((p) => p.id === flowPlace(f))));
	if (unplacedMoves.length || unplacedFlows.length)
		areas.push({
			slug: "elsewhere",
			title: "Not in a place",
			order: 900,
			summary: "Moves and flows that name no place.",
			flows: [...unplacedMoves.map((m) => flowOf(m)), ...unplacedFlows.map((f) => flowOf(f, { figure: figuresOf(f) }))],
		});
	const guarantees = live.filter((c) => c.kind === "invariant" || c.kind === "assume");
	if (guarantees.length)
		areas.push({
			slug: "guarantees",
			title: "Invariants and assumptions",
			order: 950,
			summary: "What holds in every reachable state (proved), and what the proofs take as given about the world (assumed, never proved).",
			flows: guarantees.map((c) => flowOf(c)),
		});

	for (const sub of ["areas", "notes"]) rmSync(at(sub), { recursive: true, force: true }), mkdirSync(at(sub), { recursive: true });
	for (const a of areas) {
		const { slug: s, ...body } = a;
		writeFileSync(at("areas", `${s}.yaml`), `# Generated by tools/map/cairn-map.ts from the claims; do not edit.\n${Bun.YAML.stringify(clean(body), null, 2)}\n`);
	}
	writeFileSync(
		at("map.yaml"),
		`# Generated by tools/map/cairn-map.ts; do not edit.\nname: ${app} map\nsubject: ${app}\nowner: Nate\ncode: https://github.com/iamnbutler/cairn/blob/main/\nissues: iamnbutler/cairn\n`,
	);
	// Every id this app has issued; the map's build fails if one goes missing from the pages.
	writeFileSync(at("ids.txt"), claims.map((c) => c.id).sort((a, b) => a - b).join("\n") + "\n");
	const ours = new Set(claims.map((c) => c.id));
	const lockOnly = lock.filter((l) => !ours.has(l.id) && l.status === "retired");
	const summary = {
		app,
		generated: new Date().toISOString(),
		inputs: { conformance: conformance ? confPath : null, capture: !!capture, theoremsAudited: Object.keys(audit.theorems).length },
		claims: rows.map(({ shots, ...r }) => ({ ...r, shots: shots.map((s) => `img/${s}`) })),
		retiredElsewhere: lockOnly,
	};
	writeFileSync(at("evidence.json"), JSON.stringify(summary, null, 2));
	writeFileSync(at("notes/evidence.html"), evidencePage(app, rows, conformance, !!capture, lockOnly));

	// ---- Build with the map skill's renderer ---------------------------------------------------------
	const mapTs = [process.env.MAP_TS, join(homedir(), ".claude/skills/map/map.ts"), join(homedir(), "code/prompts/skills/map/map.ts")].find((p) => p && existsSync(p));
	if (!mapTs) {
		console.log(`map sources in ${DIR}; no map skill found (set MAP_TS=<path to map.ts>) to build dist/`);
		return;
	}
	// The skill's figures are drawn SVGs that scale with the page; ours are wide filmstrips, so
	// override its stylesheet (the skill's documented hook, site/style.css) with one rule added.
	mkdirSync(at("site"), { recursive: true });
	writeFileSync(at("site/style.css"), `${readFileSync(join(mapTs, "../site/style.css"), "utf8")}\n/* cairn-map: filmstrip figures fit the column. */\n.fig img { max-width: 100%; height: auto; display: block; }\n`);
	const res = Bun.spawnSync(["bun", mapTs, "build", "--dir", DIR], { stdout: "inherit", stderr: "inherit" });
	if (!res.success) fail("map build failed");
	const counts = [...Map.groupBy(rows, (r) => r.status)].map(([s, rs]) => `${rs.length} ${s}`);
	console.log(`${app}: ${rows.length} claims (${counts.join(", ")}) → ${at("dist/index.html")}`);
}

/** Drop undefined fields, so the YAML has no `null`s the map would print. */
function clean<T>(v: T): T {
	return JSON.parse(JSON.stringify(v));
}

function evidencePage(app: string, rows: Row[], conformance: Conformance | null, captured: boolean, lockOnly: Lock[]) {
	const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
	const mark = (v: Cell) => `<td class="c ${v.replace(" ", "-")}">${v === "yes" || v === "pass" ? "✓" : v === "n/a" ? "·" : v === "no" ? "–" : esc(v)}</td>`;
	const tr = (r: Row) => `<tr${r.closed ? ' class="closed"' : ""}><td><code>${r.ref}</code></td><td>${r.kind}</td><td>${esc(r.title)}</td>${mark(r.proved)}${mark(r.assumed)}${mark(r.conformance)}${mark(r.seen)}<td><span class="st ${r.status}">${r.status}</span></td><td class="thm">${r.theorems.map((t) => `<div><span class="${t.ok ? "ok" : "bad"}">${t.ok ? "✓" : "✗"}</span> <code>${esc(t.theorem.replace(/^Examples\./, ""))}</code> <small>${esc(t.role)}</small></div>`).join("")}</td><td><small>${esc(r.lock)}</small></td></tr>`;
	return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Evidence</title><link rel="stylesheet" href="../style.css">
<style>
.ev { width: 100%; border-collapse: collapse; font-size: 14px; }
.ev th, .ev td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line, #ddd); vertical-align: top; }
.ev td.c { text-align: center; font-weight: 600; }
.ev td.not-run, .ev td.no { color: var(--muted, #888); font-weight: 400; }
.ev td.fails, .ev td.missing, .ev td.fail { color: #c33; }
.ev tr.closed { opacity: .55; }
.ev .thm div { white-space: nowrap; }
.ev .ok { color: #2a8a3e; } .ev .bad { color: #c33; }
.wrap { overflow-x: auto; }
</style></head><body><main>
<header><div class="eyebrow">${esc(app)} · evidence</div><h1>Evidence</h1>
<p class="lede">One row per claim. Each column is computed from the build: nothing here is written by hand. A step's status on the map is derived from these columns.</p></header>
<div class="wrap"><table class="ev"><thead><tr><th>Id</th><th>Kind</th><th>Claim</th><th>Proved</th><th>Assumed</th><th>Conformance</th><th>Seen</th><th>Status</th><th>Theorems (axiom audit)</th><th>Ledger</th></tr></thead>
<tbody>${rows.map(tr).join("\n")}</tbody></table></div>
${lockOnly.length ? `<h2>Retired elsewhere</h2><p>Retired ids in <code>claims.lock</code> that no module declares any more: ${lockOnly.map((l) => `<code>^${l.id}</code> ${esc(l.title)}`).join(", ")}.</p>` : ""}
<section class="flow"><h2>Columns</h2>
<p><b>Proved.</b> Every theorem the claim names (each move handler's <code>sound</code>; a flow's <code>live</code> and <code>reaches</code>; an invariant's <code>init</code>, <code>step</code> and <code>reachable</code>) is in <code>lake exe audit --json</code> and depends only on <code>propext</code>, <code>Classical.choice</code> and <code>Quot.sound</code>. <code>make check</code> also replays every declaration through the kernel.</p>
<p><b>Assumed.</b> The claim is an <code>assume</code>: recorded, never proved. Theorems that rely on it take it as a hypothesis.</p>
<p><b>Conformance.</b> ${conformance ? `From <code>build/conformance/${esc(app)}.json</code>${conformance.runs ? `, ${conformance.runs} sequences` : ""}.` : "Not run: workstream J's driver will write <code>build/conformance/&lt;App&gt;.json</code>. Until then this column is a placeholder."}</p>
<p><b>Seen.</b> ${captured ? "A headless capture (the app's own <code>step</code> and <code>frame</code>, rendered offscreen by CairnRender) shows the control, pinned from its accessibility rect; for a flow, every witness step was performed as a click at the control's centre and changed the frame." : "No capture ran."}</p></section>
</main></body></html>`;
}

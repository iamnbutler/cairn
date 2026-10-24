// The evidence model: what the build says about each claim (docs/map.md, "Evidence").
//
// Pure: inputs in, one Row per claim out. Every status on the map comes from here.

// ---- Inputs ------------------------------------------------------------------------------------

export type Step = { trigger: string; ref: string; claim: number; key: number; op?: unknown };
export type ClaimKind = "move" | "flow" | "invariant" | "assume" | "place";
/** One claim, as `lake exe claims` exports it. */
export type Claim = {
	id: number;
	ref: string;
	kind: ClaimKind;
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
	witness: Step[] | null | { error: string };
	pos: { file: string; line: number | null };
	evidence: { role: string; theorem: string }[];
};
/** `lake exe audit --json`: every theorem, and any axioms beyond the standard three. */
export type Audit = { theorems: Record<string, { ok: boolean; extraAxioms: string[] }> };
/** One line of `claims.lock`. */
export type Lock = { id: number; kind: string; status: string; statement: string; title: string };
/** `build/conformance/<App>.json` (docs/conformance.md). Only `claims` is read. */
export type Conformance = { runs?: number; commit?: string; claims: Record<string, { pass: boolean; runs?: number; note?: string; known?: Record<string, number> }> };
/** `build/fuzz/<App>.json` (docs/fuzz.md). */
export type FuzzClaim = { pass: boolean | null; steps?: number; sequences?: number; note?: string; checks?: Record<string, number>; failure?: { check: string; seed: number; step: number; message: string } };
export type Fuzz = { mode?: string; seed: number; iterations: number; stepsRun: number; claims: Record<string, FuzzClaim> };
/** `build/fuzz/trusted.json` (`make fuzz-trusted`, docs/fuzz.md "Trusted base"): one entry per
 *  check of the trusted base, naming the `assume` claims it is evidence for. */
export type TrustedCheck = {
	suite?: string;
	claims?: string[];
	cases?: number;
	failingCases?: number;
	pass: boolean | null;
	evidence?: string;
	failures?: { case: number; seed: string; message: string }[];
};
export type Trusted = { seed?: string; n?: number; checks: Record<string, TrustedCheck> };
/** The headless capture (`Cairn<App> --map-capture`). */
export type Control = { ref: string; claim: number; key: number; role: string; label: string; rect: number[] };
export type Shot = { image: string; pinned: string; width: number; height: number; controls: Control[] };
export type StepResult = { step: Step; ref: string; outcome: "ok" | "absent" | "unsupported" | "inert" };
export type Sequence = { name: string; shots: Shot[]; steps: StepResult[]; strip: string };
export type Capture = { size: number[]; scale: number; crop: number[]; sequences: Sequence[] };

export type Inputs = {
	app: string;
	claims: Claim[];
	audit: Audit;
	lock: Lock[];
	fuzz: Fuzz | null;
	trusted: Trusted | null;
	conformance: Conformance | null;
	capture: Capture | null;
	/** Whether the app has a conformance generator (tools/conformance/lean/Conformance/Apps/). */
	conformable?: boolean;
};

// ---- The model ---------------------------------------------------------------------------------

/** The kinds of evidence, strongest first. This order is the ladder. */
export const KINDS = ["proved", "fuzzed", "tested", "seen", "assumed"] as const;
export type EvidenceKind = (typeof KINDS)[number];

/** Which kinds of evidence each kind of claim can have. A kind listed here and absent is a gap. */
export const EXPECTED: Record<ClaimKind, EvidenceKind[]> = {
	move: ["proved", "fuzzed", "tested", "seen"],
	flow: ["proved", "tested", "seen"],
	invariant: ["proved", "fuzzed", "tested"],
	assume: ["assumed", "fuzzed"],
	place: ["seen"],
};

/** One kind of evidence for one claim. `pass`: held. `fail`: contradicted. `gap`: expected and
 *  absent (not run, not reached, not runnable). */
export type Mark = { kind: EvidenceKind; state: "pass" | "fail" | "gap"; label: string; detail: string };

/** The one-word reading of a claim: its strongest held rung, unless something failed. */
export type Headline = "retired" | "broken" | EvidenceKind | "untested";

export type Theorem = { role: string; theorem: string; ok: boolean | null; extraAxioms: string[] };
export type Shots = { before?: string; after?: string; frames: string[]; strip?: string; complete?: boolean };
export type Row = {
	claim: Claim;
	headline: Headline;
	marks: Mark[];
	theorems: Theorem[];
	ledger: string;
	/** Problems that aren't a kind of evidence: the ledger, a capture that contradicts the model. */
	findings: { text: string; broken: boolean }[];
	shots: Shots;
};

const witnessOf = (c: Claim): Step[] => (Array.isArray(c.witness) ? c.witness : []);
const plural = (n: number, one: string, many = `${one}s`) => `${n.toLocaleString("en")} ${n === 1 ? one : many}`;

/** The capture script: the initial frame, every flow's witness, and every move no witness presses. */
export function captureScript(claims: Claim[]) {
	const live = claims.filter((c) => !c.retired);
	const pressed = new Set(live.flatMap((c) => witnessOf(c).map((s) => s.claim)));
	return {
		scale: 2,
		sequences: [
			{ name: "start", steps: [] as Step[] },
			...live.filter((c) => c.kind === "flow" && witnessOf(c).length).map((c) => ({ name: `flow-${c.id}`, steps: witnessOf(c) })),
			...live
				.filter((c) => c.kind === "move" && !pressed.has(c.id) && !c.keyed)
				.map((c) => ({ name: `move-${c.id}`, steps: [{ trigger: c.triggers[0] || "press", ref: c.ref, claim: c.id, key: 0 }] })),
		],
	};
}

/** A dropped click (docs/fuzz.md, docs/conformance.md): what TodoMVC decision T33 says happens. */
const t33 = (n: number) =>
	`${plural(n, "click")} ended an edit and ${n === 1 ? "was" : "were"} dropped by design: the blur saved the edit, which moved or removed the control (T33, an open decision in docs/plan.md).`;

/** Every claim's evidence. `image` maps a capture file to the name the pages use. */
export function evaluate(inp: Inputs, image: (file: string) => string = (f) => f): Row[] {
	const { app, audit, fuzz, conformance, capture } = inp;
	const lockById = new Map(inp.lock.map((l) => [l.id, l]));
	const trusted = trustedClaims(inp.trusted);

	// Where each move was seen: a step that pressed it (before and after; one that changed the
	// frame is preferred), else any frame that shows its control.
	const moveShots = new Map<number, Shots & { changed?: boolean }>();
	const flowSeq = new Map<number, Sequence>();
	for (const seq of capture?.sequences || []) {
		if (seq.name.startsWith("flow-")) flowSeq.set(Number(seq.name.slice(5)), seq);
		seq.steps.forEach((r, k) => {
			if (r.outcome === "absent" || r.outcome === "unsupported") return;
			const have = moveShots.get(r.step.claim);
			if (!have?.after || (!have.changed && r.outcome === "ok")) {
				const before = image(seq.shots[k]!.pinned), after = image(seq.shots[k + 1]!.pinned);
				moveShots.set(r.step.claim, { before, after, frames: [before, after], changed: r.outcome === "ok" });
			}
		});
		for (const shot of seq.shots)
			for (const c of shot.controls) if (!moveShots.has(c.claim)) moveShots.set(c.claim, { frames: [image(shot.pinned)] });
	}
	const start = capture?.sequences.find((q) => q.name === "start")?.shots[0];

	return inp.claims.map((c): Row => {
		const findings: Row["findings"] = [];
		const theorems: Theorem[] = c.evidence.map((e) => {
			const a = audit.theorems[e.theorem];
			return { role: e.role, theorem: e.theorem, ok: a ? a.ok : null, extraAxioms: a ? a.extraAxioms : [] };
		});
		const marks = new Map<EvidenceKind, Mark>();
		const mark = (kind: EvidenceKind, state: Mark["state"], label: string, detail: string) => marks.set(kind, { kind, state, label, detail });

		// Proved: every theorem the claim names passes the axiom audit.
		if (c.kind === "move" || c.kind === "flow" || c.kind === "invariant") {
			const bad = theorems.filter((t) => t.ok !== true);
			if (!theorems.length) mark("proved", "fail", "no theorem", "The claim names no theorem.");
			else if (!bad.length) mark("proved", "pass", "proved", `${plural(theorems.length, "theorem")} (${theorems.map((t) => t.role).join(", ")}), standard axioms only.`);
			else
				mark(
					"proved",
					"fail",
					"proof fails",
					bad.map((t) => (t.ok === null ? `\`${t.theorem}\` (${t.role}) is not in the axiom audit.` : `\`${t.theorem}\` (${t.role}) depends on ${t.extraAxioms.map((x) => `\`${x}\``).join(", ")}.`)).join(" "),
				);
		}

		// Assumed: stated, never proved.
		if (c.kind === "assume") mark("assumed", "pass", "assumed", "Recorded, never proved. Theorems that rely on it take it as a hypothesis.");

		// Fuzzed: the app's fuzzer (moves, invariants) or the trusted-base fuzzer (assumptions).
		if (c.kind === "move" || c.kind === "invariant") {
			const f = fuzz?.claims[c.ref];
			const model = fuzz?.mode === "model" ? " of the model (no App yet)" : "";
			if (!fuzz) mark("fuzzed", "gap", "not fuzzed", `No \`build/fuzz/${app}.json\`: run \`make fuzz APP=${app}\`.`);
			else if ((!f || f.pass === null) && c.kind === "move" && fuzz.mode === "model")
				mark("fuzzed", "gap", "not fuzzed", "The app is fuzzed at the model level only (it has no `App` yet), where a move has no checks of its own: presence and pressability need a frame.");
			else if (!f || f.pass === null)
				mark("fuzzed", "gap", f?.note?.startsWith("not runnable") ? "not runnable" : "not fuzzed", f?.note?.startsWith("not runnable") ? `The fuzzer can't run it: ${f.note}.` : "No fuzzed sequence exercised it.");
			else if (f.pass) mark("fuzzed", "pass", `fuzzed ${short(f.sequences ?? fuzz.iterations)}`, `Held in ${plural(f.sequences ?? fuzz.iterations, "random sequence")}${model}, ${plural(f.steps ?? 0, "step")} checked (seed ${fuzz.seed}).${f.checks?.droppedT33 ? ` ${t33(f.checks.droppedT33)}` : ""}`);
			else {
				const x = f.failure;
				mark("fuzzed", "fail", "fuzz fails", x ? `${x.check} failed at seed ${x.seed}, step ${x.step}: ${x.message}. Replay with \`lake exe fuzz ${app} --seed ${x.seed} --iterations 1 -v\`.` : `Fuzzing failed${f.note ? `: ${f.note}` : "."}`);
			}
		} else if (c.kind === "assume") {
			const checks = trusted.get(c.ref) ?? [];
			const ran = checks.filter(([, t]) => t.pass !== null);
			const failed = ran.filter(([, t]) => t.pass === false);
			const cases = ran.reduce((n, [, t]) => n + (t.cases ?? 0), 0);
			const names = checks.map(([name]) => `\`${name}\``).join(", ");
			if (!inp.trusted) mark("fuzzed", "gap", "unchecked", "Nothing checks it: no `build/fuzz/trusted.json` (`make fuzz-trusted`).");
			else if (!checks.length) mark("fuzzed", "gap", "unchecked", "No check of the trusted-base fuzzer names it.");
			else if (failed.length) {
				const [name, t] = failed[0]!;
				const f = t.failures?.[0];
				mark("fuzzed", "fail", "fuzz fails", `The trusted-base check \`${name}\` ${t.evidence ?? "failed"}${f ? `: ${f.message}. Replay with \`host/.build/release/CairnFuzzTrusted --replay ${t.suite ?? name} --case ${f.case} --seed ${f.seed}\`` : ""}.`);
			} else if (ran.length < checks.length) mark("fuzzed", "gap", "unchecked", `Its check ${names} ran no cases.`);
			else mark("fuzzed", "pass", `fuzzed ${short(cases)}`, `The trusted-base fuzzer's ${names} held in ${plural(cases, "case")}, against Lean's proved side (seed ${inp.trusted.seed ?? "?"}).`);
		}

		// Tested: conformance on the running app.
		if (c.kind === "move" || c.kind === "flow" || c.kind === "invariant") {
			const t = conformance?.claims[c.ref];
			const what = c.kind === "move" ? (n: number) => `${plural(n, "step")} on the running app exercised it` : c.kind === "flow" ? () => "Its witness replayed on the running app" : (n: number) => `Every state the running app reached (${plural(n, "step")}) was the model's`;
			if (!conformance)
				mark("tested", "gap", "not tested", inp.conformable === false ? `${app} has no conformance generator yet (\`tools/conformance/lean/Conformance/Apps/${app}.lean\`).` : `No \`build/conformance/${app}.json\`: run \`make conformance APP=${app}\`.`);
			else if (!t) mark("tested", "gap", "not tested", "No conformance step exercised it.");
			else if (t.pass) mark("tested", "pass", c.kind === "move" && t.runs ? `tested ${short(t.runs)}` : "tested", `${what(t.runs ?? 0)}, and the frame, accessibility tree, effects and pixels matched the model.${t.known?.T33 ? ` ${t33(t.known.T33)}` : ""}`);
			else mark("tested", "fail", "test fails", `Conformance failed${t.note ? `: ${t.note}` : "."}`);
		}

		// Seen: the headless capture.
		let shots: Shots = { frames: [] };
		if (c.kind === "move") {
			const s = moveShots.get(c.id);
			if (s) {
				const { changed, ...rest } = s;
				shots = rest;
				mark("seen", "pass", "seen", s.after ? (changed ? "Pressed in the capture: before and after." : "Performed in the capture; the frame didn't change.") : "Its control is in a captured frame; no capture performed it.");
			} else mark("seen", "gap", "not seen", capture ? "No captured frame shows its control." : "No capture ran.");
		} else if (c.kind === "flow") {
			const seq = flowSeq.get(c.id);
			const steps = witnessOf(c);
			if (!steps.length) mark("seen", "gap", "not seen", "It has no witness to replay.");
			else if (!seq) mark("seen", "gap", "not seen", capture ? "The capture didn't replay it." : "No capture ran.");
			else {
				const bad = seq.steps.find((s) => s.outcome === "absent" || s.outcome === "unsupported");
				const complete = seq.steps.length === steps.length && !bad;
				shots = { frames: seq.shots.map((s) => image(s.pinned)), strip: image(seq.strip), complete };
				if (complete) mark("seen", "pass", "seen", `Its ${plural(steps.length, "step")} replayed in the capture, each on the control it names.`);
				else if (bad?.outcome === "absent") {
					// The witness is proved live in the model, so the app disagreeing is a real failure.
					mark("seen", "fail", "not shown", `The app shows no control ${bad.ref} at witness step ${seq.steps.indexOf(bad) + 1} (${bad.step.trigger} ${bad.ref}), though the model's witness is live.`);
				} else mark("seen", "gap", "partly seen", `The capture can't replay step ${bad ? seq.steps.indexOf(bad) + 1 : seq.steps.length + 1} (${bad ? `${bad.step.trigger} ${bad.ref}` : "stopped early"}).`);
			}
		} else if (c.kind === "place") {
			if (start) {
				shots = { frames: [image(start.pinned)] };
				mark("seen", "pass", "seen", "The window, rendered from the app's initial frame.");
			} else mark("seen", "gap", "not seen", "No capture ran.");
		}

		// The ledger.
		const locked = lockById.get(c.id);
		let ledger = "not locked";
		if (!locked) findings.push({ text: "Not in `claims.lock`: run `lake exe ledger update`.", broken: false });
		else {
			ledger = locked.status;
			// A retired claim's meaning is frozen; only a live claim's hash is compared.
			if (!c.retired && locked.statement !== c.statement) {
				ledger += ", meaning changed";
				findings.push({ text: `Its statement hash (\`${c.statement}\`) differs from \`claims.lock\` (\`${locked.statement}\`): give it a new id, or accept the change.`, broken: false });
			}
		}

		// An assumption leads with what it is; anything that checked it follows.
		const ordered = (c.kind === "assume" ? (["assumed", "fuzzed"] as const) : KINDS).map((k) => marks.get(k)).filter((m): m is Mark => !!m);
		let headline: Headline;
		if (c.retired) headline = "retired";
		else if (ordered.some((m) => m.state === "fail") || findings.some((f) => f.broken)) headline = "broken";
		else if (c.kind === "assume") headline = "assumed";
		else headline = ordered.find((m) => m.state === "pass")?.kind ?? "untested";
		return { claim: c, headline, marks: c.retired ? [] : ordered, theorems, ledger, findings, shots };
	});
}

/** The gaps: every expected kind of evidence a live claim lacks, and every finding. */
export function gaps(rows: Row[]) {
	return rows
		.filter((r) => !r.claim.retired)
		.flatMap((r) => [
			...r.marks.filter((m) => m.state !== "pass").map((m) => ({ row: r, what: m.label, detail: m.detail, broken: m.state === "fail" })),
			...r.findings.map((f) => ({ row: r, what: f.broken ? "broken" : "ledger", detail: f.text, broken: f.broken })),
		]);
}

/** Per kind of evidence: how many live claims have it, of those that can. */
export function counts(rows: Row[]) {
	const live = rows.filter((r) => !r.claim.retired);
	const kinds = KINDS.map((kind) => {
		const can = live.filter((r) => r.marks.some((m) => m.kind === kind));
		const of = (s: Mark["state"]) => can.filter((r) => r.marks.find((m) => m.kind === kind)!.state === s).length;
		return { kind, have: of("pass"), fail: of("fail"), of: can.length };
	});
	const headlines = new Map<Headline, number>();
	for (const r of rows) headlines.set(r.headline, (headlines.get(r.headline) ?? 0) + 1);
	return { kinds, headlines, live: live.length, total: rows.length };
}

/** Each assumption's checks in `trusted.json`, by claim ref. */
function trustedClaims(t: Trusted | null) {
	const m = new Map<string, [string, TrustedCheck][]>();
	for (const [name, check] of Object.entries(t?.checks ?? {})) for (const ref of check.claims ?? []) m.set(ref, [...(m.get(ref) ?? []), [name, check]]);
	return m;
}

/** 1000 → "1k", 12011 → "12k": for chips, where the exact count is in the detail. */
function short(n: number) {
	return n >= 10_000 ? `${Math.round(n / 1000)}k` : n >= 1000 ? `${(n / 1000).toFixed(n % 1000 ? 1 : 0)}k` : `${n}`;
}

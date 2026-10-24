// bun test tools/map: the evidence model's readings on small, hand-made inputs.
import { expect, test } from "bun:test";
import { counts, evaluate, gaps, type Claim, type Inputs } from "./evidence";

const claim = (id: number, kind: Claim["kind"], theorems: string[] = [], extra: Partial<Claim> = {}): Claim => ({
	id,
	ref: `^${id}`,
	kind,
	title: `claim ${id}`,
	does: "does",
	sees: "",
	place: null,
	retired: null,
	module: "Examples.T",
	decl: `Examples.T.c${id}`,
	statement: "h",
	triggers: kind === "move" ? ["press"] : [],
	keyed: false,
	witness: null,
	pos: { file: "lean/Examples/T.lean", line: id },
	evidence: theorems.map((t) => ({ role: "sound", theorem: t })),
	...extra,
});
const inputs = (claims: Claim[], extra: Partial<Inputs> = {}): Inputs => ({
	app: "T",
	claims,
	audit: { theorems: { good: { ok: true, extraAxioms: [] }, bad: { ok: false, extraAxioms: ["sorryAx"] } } },
	lock: claims.map((c) => ({ id: c.id, kind: c.kind, status: "active", statement: "h", title: c.title })),
	fuzz: null,
	trusted: null,
	conformance: null,
	capture: null,
	...extra,
});

test("a proved invariant reads as proved, with its gaps listed", () => {
	const [r] = evaluate(inputs([claim(1, "invariant", ["good"])]));
	expect(r!.headline).toBe("proved");
	expect(r!.marks.map((m) => `${m.kind}:${m.state}`)).toEqual(["proved:pass", "fuzzed:gap", "tested:gap"]);
	expect(gaps([r!]).map((g) => g.what)).toEqual(["not fuzzed", "not tested"]);
});

test("every kind of evidence shows, and the strongest names the reading", () => {
	const fuzz = { seed: 0, iterations: 1000, stepsRun: 1, claims: { "^1": { pass: true, sequences: 1000, steps: 50 } } };
	const conformance = { runs: 10, claims: { "^1": { pass: true, runs: 812 } } };
	const [r] = evaluate(inputs([claim(1, "move", ["good"])], { fuzz, conformance }));
	expect(r!.headline).toBe("proved");
	expect(r!.marks.map((m) => m.label)).toEqual(["proved", "fuzzed 1k", "tested 812", "not seen"]);
	const [s] = evaluate(inputs([claim(1, "move", [])], { fuzz, conformance }));
	expect(s!.headline).toBe("broken"); // a move that names no theorem
});

test("a failure anywhere makes the claim broken", () => {
	const fuzz = { seed: 0, iterations: 5, stepsRun: 1, claims: { "^1": { pass: false, failure: { check: "presence", seed: 3, step: 4, message: "gone" } } } };
	expect(evaluate(inputs([claim(1, "move", ["good"])], { fuzz }))[0]!.headline).toBe("broken");
	expect(evaluate(inputs([claim(1, "move", ["bad"])]))[0]!.headline).toBe("broken");
	expect(evaluate(inputs([claim(1, "move", ["missing"])]))[0]!.headline).toBe("broken");
});

test("assumptions read as assumed, and trusted-base fuzzing adds a chip", () => {
	expect(evaluate(inputs([claim(7, "assume")]))[0]!.marks.map((m) => `${m.label}:${m.state}`)).toEqual(["assumed:pass", "unchecked:gap"]);
	const check = (pass: boolean | null, cases = 20000) => ({ suite: "frame", claims: ["^7"], cases, pass, failures: pass === false ? [{ case: 17, seed: "0", message: "differs" }] : [] });
	const [r] = evaluate(inputs([claim(7, "assume")], { trusted: { seed: "0", checks: { "frame.decode": check(true) } } }));
	expect(r!.headline).toBe("assumed");
	expect(r!.marks.map((m) => m.label)).toEqual(["assumed", "fuzzed 20k"]);
	const [a] = evaluate(inputs([claim(7, "assume")], { trusted: { checks: { "frame.decode": check(true), "frame.other": check(false) } } }));
	expect(a!.headline).toBe("broken");
	expect(a!.marks[1]!.detail).toContain("--replay frame --case 17");
	const [b] = evaluate(inputs([claim(8, "assume")], { trusted: { checks: { "frame.decode": check(true) } } }));
	expect(b!.marks[1]!.state).toBe("gap"); // no check names ^8
	const [c] = evaluate(inputs([claim(7, "assume")], { trusted: { checks: { "frame.decode": check(null, 0) } } }));
	expect(c!.marks[1]!.state).toBe("gap"); // ran no cases
});

test("retired claims have no evidence and no gaps; a changed meaning is a finding", () => {
	const rows = evaluate(inputs([claim(1, "invariant", ["good"], { retired: "gone", statement: "-" }), claim(2, "move", ["good"], { statement: "other" })]));
	expect(rows[0]!.findings).toEqual([]);
	expect(rows[0]!.marks).toEqual([]);
	expect(rows[0]!.headline).toBe("retired");
	expect(gaps(rows).filter((g) => g.row.claim.id === 1)).toEqual([]);
	expect(rows[1]!.ledger).toBe("active, meaning changed");
	expect(counts(rows).live).toBe(1);
});

test("an app's random-host fuzzer adds to the generic one, and its failures break the claim", () => {
	const fuzz = { seed: 0, iterations: 200, stepsRun: 1, claims: { "^1": { pass: null, note: "not runnable: no Decidable instance" }, "^2": { pass: true, sequences: 200, steps: 50 } } };
	const host = (pass: boolean | null) => ({ seed: 0, iterations: 300, stepsRun: 1, claims: { "^1": { pass, steps: 12 }, "^2": { pass: true, steps: 5 } } });
	const rows = evaluate(inputs([claim(1, "invariant", ["good"]), claim(2, "invariant", ["good"])], { fuzz, hostFuzz: host(true) }));
	expect(rows.map((r) => r.marks[1]!.label)).toEqual(["fuzzed 300", "fuzzed 500"]);
	expect(rows[1]!.marks[1]!.detail).toContain("random host");
	expect(evaluate(inputs([claim(1, "invariant", ["good"])], { fuzz, hostFuzz: host(false) }))[0]!.headline).toBe("broken");
	expect(evaluate(inputs([claim(1, "invariant", ["good"])], { fuzz, hostFuzz: host(null) }))[0]!.marks[1]!.label).toBe("not runnable");
});

test("conformance that can't reach a claim is a gap with its reason", () => {
	const conformance = { runs: 10, claims: { "^1": { pass: null, note: "the world is silent" } } };
	const [r] = evaluate(inputs([claim(1, "invariant", ["good"])], { conformance }));
	expect(r!.marks[2]).toMatchObject({ kind: "tested", state: "gap" });
	expect(r!.marks[2]!.detail).toContain("the world is silent");
});

test("a place is seen in a shot that shows it, with how the capture drew it", () => {
	const shot = (name: string, places?: number[]) => ({ image: `${name}.png`, pinned: `${name}.pinned.png`, width: 10, height: 10, controls: [], places });
	const capture = {
		size: [10, 10], scale: 2, crop: [0, 0, 10, 10], places: { "5": "The menu, as the host built it." },
		sequences: [{ name: "start", shots: [shot("start", [5])], steps: [], strip: "s.png" }, { name: "overlay", shots: [shot("a", [5]), shot("b", [5, 6])], steps: [], strip: "o.png" }],
	};
	const rows = evaluate(inputs([claim(5, "place"), claim(6, "place"), claim(7, "place")], { capture }));
	expect(rows.map((r) => r.marks[0]!.state)).toEqual(["pass", "pass", "gap"]);
	expect(rows[0]!.marks[0]!.detail).toBe("The menu, as the host built it.");
	expect(rows[1]!.shots.frames).toEqual(["b.pinned.png"]);
});

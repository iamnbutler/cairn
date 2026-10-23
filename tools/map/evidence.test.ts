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
	const trusted = { claims: { "^7": { pass: true, sequences: 2000 } } };
	const [r] = evaluate(inputs([claim(7, "assume")], { trusted }));
	expect(r!.headline).toBe("assumed");
	expect(r!.marks.map((m) => m.label)).toEqual(["assumed", "fuzzed 2k"]);
	const [a] = evaluate(inputs([claim(7, "assume")], { trusted: { assumptions: [{ claim: 7, pass: false, note: "x" }] } }));
	expect(a!.headline).toBe("broken");
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

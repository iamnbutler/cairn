// bun test tools/map: the move trees and their diffs on small, hand-made inputs.
import { expect, test } from "bun:test";
import { diff, flowTree, graphTree, moveDiff, projectGraph, type Tree } from "./tree";

const step = (trigger: string, claim: number, key = 0) => ({ trigger, ref: key ? `^${claim}#${key}` : `^${claim}`, claim, key });
const flow = (id: number, witness: ReturnType<typeof step>[]) => ({ id, kind: "flow", title: `flow ${id}`, place: null, retired: null, witness });

test("flows that share a prefix share its steps", () => {
	const t = flowTree([flow(8, [step("submit", 2), step("press", 3)]), flow(9, [step("submit", 2), step("press", 4, 1)])]);
	expect(t.children.map((c) => c.key)).toEqual(["submit ^2"]);
	const [shared] = t.children;
	expect(shared.children.map((c) => c.key)).toEqual(["press ^3", "press ^4#1"]);
	expect(shared.children.map((c) => c.flows)).toEqual([[8], [9]]);
});

// A counter: ^1 counts (and makes ^2 available), ^2 resets; ^3 is a menu item in place ^10 that
// ^1 also makes available.
const counter = (resetGivesBack: boolean) => ({
	app: "Counter", depth: 3, states: 3, typed: "milk",
	claims: { "1": "Count", "2": "Reset", "3": "Clear", "10": "Menu" },
	places: { "1": 20, "2": 20, "3": 10, "10": 20, "20": null },
	placeIds: [20, 10],
	nodes: [
		{ id: 0, sig: [1], depth: 0, explored: true },
		{ id: 1, sig: [1, 2, 3], depth: 1, explored: true },
	],
	edges: [
		{ from: 0, to: 1, claim: 1, key: 0, trigger: "press", effects: 0 },
		{ from: 1, to: 1, claim: 1, key: 0, trigger: "press", effects: 0 },
		{ from: 1, to: resetGivesBack ? 0 : 1, claim: 2, key: 0, trigger: "press", effects: 0 },
	],
});

test("the graph unrolls into its spanning tree, with loops folded and back edges as leaves", () => {
	const t = graphTree(counter(true));
	expect(t.moves).toEqual([1]);
	const [count] = t.children;
	expect(count.delta).toEqual({ gain: [2, 3], lose: [] });
	expect(count.stay).toEqual(["press ^1"]);
	const [reset] = count.children;
	expect(reset.back).toBe(true);
	expect(reset.delta).toEqual({ gain: [], lose: [2, 3] });
});

test("a place sees only its own moves, and edges from elsewhere say so", () => {
	const g = projectGraph(counter(true), 10);
	expect(g.nodes.map((n) => n.sig)).toEqual([[], [3]]);
	const count = g.edges.find((e) => e.claim === 1)!;
	expect(count.via).toBe(20);
});

test("the diff marks what a version changed, matched by step", () => {
	const t: Tree = diff(graphTree(counter(true)), graphTree(counter(false)));
	const reset = t.children[0].children.find((c) => c.key === "press ^2");
	// Reset no longer goes back, so it's gone from the tree and joins the moves that stay.
	expect(reset?.status).toBe("removed");
	expect(t.children[0].status).toBe("changed");
	expect(t.children[0].stay).toEqual(["press ^1", "press ^2"]);
});

test("the diff by move says what each move does differently", () => {
	const m = moveDiff(counter(true), counter(false));
	expect(m.moves).toEqual([{ claim: 2, trigger: "press", before: [{ gain: [], lose: [2, 3] }], after: [], kept: [] }]);
	expect(m.reachable).toEqual([]);
	expect(m.unreachable).toEqual([]);
});

// Moves as a left-to-right tree, and the diff of two versions of it (a prototype).
//
//   bun tools/map/tree.ts flows claims.json                   A: the flows' witnesses as one tree
//   bun tools/map/tree.ts graph build/graph/Fixture.json      B: the explored move graph as a tree
//   bun tools/map/tree.ts graph old.json new.json             the diff of two versions
//   … --by-place                                              B: one tree per place
//   … --html out.html                                         a page of cards instead of text
//
// A merges every flow's witness (`lake exe claims`) into one prefix tree from the first state.
// Every edge is a step some flow's `live` theorem covers, and a leaf is where its `reaches`
// holds: proved, but only the paths someone wrote down.
//
// B unrolls the graph `lake exe fuzz <App> --graph D` writes (lean/Cairn/Fuzz/Graph.lean): a node
// is the set of moves a person can take, an edge a move. The tree is the breadth-first spanning
// tree; an edge to a node already placed is a leaf. Exact for the states explored, silent about
// the rest.
//
// The diff matches by claim ids, which never change meaning (docs/claims.md): an edge is the
// same edge in both versions when it is the same trigger on the same claim from the same place
// in the tree.
import { readFileSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";

// ---- The tree ----------------------------------------------------------------------------------

type Status = "same" | "added" | "removed" | "changed";

/** What a move did to what a person can do: the moves it made available, and those it took away. */
export type Delta = { gain: number[]; lose: number[] };

/** The move an edge performs. */
export type Step = { claim: number; trigger: string; key: number; text?: string; via?: number | null; effects?: number };

/** One node of the tree, reached from its parent by `step`. */
export type Tree = {
	/** Identity among siblings: the step, `press ^3`. */
	key: string;
	step?: Step;
	/** B: what the step changed. The root has `moves` instead. */
	delta?: Delta;
	/** The root: every move available at the start. */
	moves?: number[];
	/** B: moves that change nothing here, folded into a badge (a child with key `↺` while diffing). */
	stay?: string[];
	/** A: flows whose witness ends here. */
	flows?: number[];
	/** A leaf for an edge to a node placed elsewhere in the tree. */
	back?: boolean;
	/** Not explored past this node (the depth or state limit). */
	open?: boolean;
	children: Tree[];
	/** Set by `diff`. */
	status?: Status;
	was?: Tree;
};

type Titles = Record<string, string>;
const title = (titles: Titles, id: number) => titles[String(id)] ?? "";
const ref = (id: number) => `^${id}`;
const deltaKey = (d?: Delta) => (d ? [...d.gain.map((c) => `+${c}`), ...d.lose.map((c) => `-${c}`)].join(" ") : "");
const deltaText = (d?: Delta) =>
	d ? [...d.gain.map((c) => `+${ref(c)}`), ...d.lose.map((c) => `−${ref(c)}`)].join(" ") || "no change" : "";

/** What the diff compares: two nodes with the same key are the same node unless this differs. */
const ident = (t: Tree) =>
	[deltaKey(t.delta), (t.moves ?? []).join(","), (t.stay ?? []).join(","), (t.flows ?? []).join(","), t.back ? "back" : ""].join("|");

// ---- A: flows ----------------------------------------------------------------------------------

type WStep = { trigger: string; ref: string; claim: number; key: number; op?: { kind: string; text?: string } };
type Claim = { id: number; kind: string; title: string; place: number | null; retired: string | null; witness: WStep[] | null | { error: string } };

export function flowTree(claims: Claim[]): Tree {
	const root: Tree = { key: "", children: [] };
	for (const c of claims) {
		if (c.kind !== "flow" || c.retired || !Array.isArray(c.witness)) continue;
		let at = root;
		for (const s of c.witness) {
			const text = s.op ? (s.op.text !== undefined ? JSON.stringify(s.op.text) : s.op.kind) : undefined;
			const key = `${s.trigger} ${s.ref}${text ? ` ${text}` : ""}`;
			let next = at.children.find((t) => t.key === key);
			if (!next) {
				next = { key, step: { claim: s.claim, trigger: s.trigger, key: s.key, text }, children: [] };
				at.children.push(next);
			}
			at = next;
		}
		at.flows = [...(at.flows ?? []), c.id];
	}
	return root;
}

// ---- B: the explored graph ---------------------------------------------------------------------

type GNode = { id: number; sig: number[]; depth: number; explored: boolean };
type GEdge = { from: number; to: number; claim: number; key: number; trigger: string; effects: number; via?: number | null };
type Graph = {
	app: string; depth: number; states: number; typed: string; claims: Titles; nodes: GNode[]; edges: GEdge[];
	/** Each claim's place (`in ^P`), and the place claims. */
	places?: Record<string, number | null>; placeIds?: number[];
	/** Set on a graph projected onto one place. */
	place?: number;
};

const sigKey = (sig: number[]) => sig.join(",");
const delta = (from: number[], to: number[]): Delta => ({ gain: to.filter((x) => !from.includes(x)), lose: from.filter((x) => !to.includes(x)) });

/** The places, outermost first, each with its own moves. */
export function placesOf(g: Graph): { id: number; title: string; within: number | null; moves: number[] }[] {
	const of = (c: number) => g.places?.[String(c)] ?? null;
	const moves = [...new Set(g.nodes.flatMap((n) => n.sig))];
	const depth = (p: number): number => (of(p) === null ? 0 : 1 + depth(of(p)!));
	return (g.placeIds ?? [])
		.map((id) => ({ id, title: title(g.claims, id), within: of(id), moves: moves.filter((c) => of(c) === id).sort((a, b) => a - b) }))
		.sort((a, b) => depth(a.id) - depth(b.id) || a.id - b.id);
}

/** The graph as one place sees it: a node is the moves of that place a person can take, so
 *  nodes that differ only elsewhere are one; an edge is kept when it changes that, or is one of
 *  the place's own moves. An edge of another place's move says which place it came from. */
export function projectGraph(g: Graph, place: number): Graph {
	const own = (c: number) => (g.places?.[String(c)] ?? null) === place;
	const nodes: GNode[] = [];
	const index = new Map<string, number>();
	const map = new Map<number, number>();
	// The export lists node 0 (the first state) first, so the projection's root is node 0 too.
	for (const n of g.nodes) {
		const sig = n.sig.filter(own);
		const k = sigKey(sig);
		if (!index.has(k)) {
			index.set(k, nodes.length);
			nodes.push({ id: nodes.length, sig, depth: n.depth, explored: n.explored });
		} else if (n.explored) nodes[index.get(k)!].explored = true;
		map.set(n.id, index.get(k)!);
	}
	const edges: GEdge[] = [];
	const seen = new Set<string>();
	for (const e of g.edges) {
		const from = map.get(e.from)!, to = map.get(e.to)!;
		if (from === to && !own(e.claim)) continue;
		const k = `${from} ${e.trigger} ${e.claim} ${to}`;
		if (seen.has(k)) continue;
		seen.add(k);
		edges.push({ ...e, from, to, via: own(e.claim) ? undefined : (g.places?.[String(e.claim)] ?? null) });
	}
	return { ...g, nodes, edges, place };
}

export function graphTree(g: Graph): Tree {
	const nodes = new Map(g.nodes.map((n) => [n.id, n]));
	const out = new Map<number, GEdge[]>();
	for (const e of g.edges) out.set(e.from, [...(out.get(e.from) ?? []), e]);
	// The spanning tree: breadth first over the nodes from the first one. (A node's depth in the
	// exploration can exceed its distance here: the moves that got there may not change the node.)
	const parent = new Map<number, GEdge>();
	const seen = new Set([0]);
	for (let frontier = [0]; frontier.length; ) {
		const next: number[] = [];
		for (const id of frontier)
			for (const e of out.get(id) ?? [])
				if (!seen.has(e.to)) {
					seen.add(e.to);
					parent.set(e.to, e);
					next.push(e.to);
				}
		frontier = next;
	}
	const stepOf = (e: GEdge): Step => ({ claim: e.claim, trigger: e.trigger, key: e.key, text: e.trigger === "edit" ? JSON.stringify(g.typed) : undefined, via: e.via, effects: e.effects });
	const build = (id: number, key: string, step: Step | undefined, from: number[] | undefined): Tree => {
		const n = nodes.get(id)!;
		const t: Tree = { key, step, children: [], open: !n.explored };
		if (from) t.delta = delta(from, n.sig);
		else t.moves = n.sig;
		const loops = (out.get(id) ?? []).filter((e) => e.to === id);
		const stay = [...new Set(loops.map((e) => `${e.trigger} ^${e.claim}`))];
		if (stay.length) t.stay = stay;
		for (const e of out.get(id) ?? []) {
			if (e.to === id) continue;
			const k = `${e.trigger} ^${e.claim}`;
			if (parent.get(e.to) === e) t.children.push(build(e.to, k, stepOf(e), n.sig));
			else t.children.push({ key: k, step: stepOf(e), delta: delta(n.sig, nodes.get(e.to)!.sig), back: true, children: [] });
		}
		return t;
	};
	return build(0, "", undefined, undefined);
}

// ---- The diff ----------------------------------------------------------------------------------

/** The two trees as one: children matched by key, each marked by what the new version did to it. */
export function diff(a: Tree | undefined, b: Tree | undefined): Tree {
	if (!a) return mark(b!, "added");
	if (!b) return mark(a, "removed");
	const keys = [...a.children.map((t) => t.key), ...b.children.map((t) => t.key).filter((k) => !a.children.some((t) => t.key === k))];
	const children = keys.map((k) => diff(a.children.find((t) => t.key === k), b.children.find((t) => t.key === k)));
	const changed = ident(a) !== ident(b);
	return { ...b, children, status: changed ? "changed" : "same", was: changed ? { ...a, children: [] } : undefined };
}

function mark(t: Tree, status: Status): Tree {
	return { ...t, status, children: t.children.map((c) => mark(c, status)) };
}

/** Whether anything under `t` differs. */
const touched = (t: Tree): boolean => (t.status !== undefined && t.status !== "same") || t.children.some(touched);

function prune(t: Tree, keep: boolean): Tree {
	return { ...t, children: t.children.filter((c) => keep || touched(c)).map((c) => prune(c, keep)) };
}

function count(t: Tree, acc: Record<Status, number> = { same: 0, added: 0, removed: 0, changed: 0 }) {
	if (t.status) acc[t.status]++;
	for (const c of t.children) count(c, acc);
	return acc;
}

/** B's diff by move, independent of where in the tree a move is: for each move, the changes it
 *  makes to what a person can do, anywhere in the explored graph. One changed `enabled` renames
 *  every node holding that claim, so nodes don't diff well; what a move does stays put unless the
 *  move's meaning changed. */
export type MoveChange = { claim: number; trigger: string; before: Delta[]; after: Delta[]; kept: Delta[] };
export function moveDiff(a: Graph, b: Graph): { moves: MoveChange[]; reachable: number[]; unreachable: number[] } {
	const effects = (g: Graph) => {
		const sig = new Map(g.nodes.map((n) => [n.id, n.sig]));
		const m = new Map<string, Map<string, Delta>>();
		for (const e of g.edges) {
			if (e.from === e.to) continue;
			const d = delta(sig.get(e.from)!, sig.get(e.to)!);
			const k = `${e.claim} ${e.trigger}`;
			m.set(k, (m.get(k) ?? new Map()).set(deltaKey(d), d));
		}
		return m;
	};
	const ea = effects(a), eb = effects(b);
	const moves: MoveChange[] = [];
	const keys = [...new Set([...ea.keys(), ...eb.keys()])].sort((x, y) => parseInt(x) - parseInt(y));
	for (const k of keys) {
		const was = ea.get(k) ?? new Map<string, Delta>(), now = eb.get(k) ?? new Map<string, Delta>();
		const before = [...was].filter(([x]) => !now.has(x)).map(([, d]) => d);
		const after = [...now].filter(([x]) => !was.has(x)).map(([, d]) => d);
		if (!before.length && !after.length) continue;
		const [claim, trigger] = k.split(" ");
		moves.push({ claim: +claim, trigger, before, after, kept: [...now].filter(([x]) => was.has(x)).map(([, d]) => d) });
	}
	const reach = (g: Graph) => new Set(g.nodes.flatMap((n) => n.sig));
	const ra = reach(a), rb = reach(b);
	return { moves, reachable: [...rb].filter((c) => !ra.has(c)), unreachable: [...ra].filter((c) => !rb.has(c)) };
}

// ---- Text --------------------------------------------------------------------------------------

const sign: Record<Status, string> = { same: " ", added: "+", removed: "-", changed: "~" };

function stepText(s: Step | undefined, titles: Titles): string {
	if (!s) return "start";
	const via = s.via !== undefined ? ` (from ${s.via === null ? "no place" : ref(s.via)})` : "";
	return `${s.trigger} ${ref(s.claim)}${s.key ? `#${s.key}` : ""}${s.text ? ` ${s.text}` : ""} · ${title(titles, s.claim)}${via}`;
}

function noteText(t: Tree): string {
	if (t.moves) return `${t.moves.length} moves: ${t.moves.map(ref).join(" ")}`;
	const parts = [t.back ? `↩ ${deltaText(t.delta)}` : deltaText(t.delta)];
	if (t.flows) parts.push(t.flows.map((f) => `⚑ ${ref(f)}`).join(" "));
	if (t.stay) parts.push(`↺ ${t.stay.length}`);
	if (t.open) parts.push("⋯");
	return parts.filter(Boolean).join("  ");
}

export function text(t: Tree, titles: Titles): string {
	const lines: string[] = [];
	const go = (t: Tree, pre: string, last: boolean, top: boolean) => {
		const s = t.status ? sign[t.status] + " " : "";
		const was = t.was ? `   (was: ${noteText(t.was)})` : "";
		const line = `${stepText(t.step, titles)}  ⟶  ${noteText(t)}${was}`;
		lines.push(top ? `${s}${line}` : `${s}${pre}${last ? "└─ " : "├─ "}${line}`);
		const next = top ? "" : pre + (last ? "   " : "│  ");
		t.children.forEach((c, i) => go(c, next, i === t.children.length - 1, false));
	};
	go(t, "", true, true);
	return lines.join("\n");
}

// ---- HTML: cards of badges, left to right ------------------------------------------------------

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const short = (s: string, n = 24) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

export type Section = {
	id: number | null;
	title: string;
	sub?: string;
	/** The place's own moves, shown as badges in the header. */
	moves?: number[];
	tree?: Tree;
	/** A diff found nothing in this section. */
	unchanged?: boolean;
	note?: string;
	byMove?: ReturnType<typeof moveDiff>;
};

/** A claim as a badge: its id, its title, and the title in full on hover. */
function pill(titles: Titles, c: number, kind: "gain" | "lose" | "plain", mark: "" | "new" | "gone" = "") {
	const sym = kind === "gain" ? "+" : kind === "lose" ? "−" : "";
	const what = kind === "gain" ? "becomes available" : kind === "lose" ? "goes away" : "";
	const tip = `${ref(c)} ${title(titles, c)}${what ? `\n${what}` : ""}${mark === "new" ? "\n(new in this version)" : mark === "gone" ? "\n(only in the old version)" : ""}`;
	return `<span class="pill ${kind} ${mark}" data-tip="${esc(tip)}">${sym}<b>${ref(c)}</b> ${esc(short(title(titles, c), 20))}</span>`;
}

/** A delta's badges; with the old version's delta, what's new is marked and what's gone struck out. */
function pills(titles: Titles, d: Delta | undefined, was?: Delta, limit = 4): string {
	if (!d) return "";
	const items: string[] = [];
	const has = (xs: number[] | undefined, c: number) => !!xs?.includes(c);
	for (const c of d.gain) items.push(pill(titles, c, "gain", was && !has(was.gain, c) ? "new" : ""));
	for (const c of d.lose) items.push(pill(titles, c, "lose", was && !has(was.lose, c) ? "new" : ""));
	if (was) {
		for (const c of was.gain) if (!d.gain.includes(c)) items.push(pill(titles, c, "gain", "gone"));
		for (const c of was.lose) if (!d.lose.includes(c)) items.push(pill(titles, c, "lose", "gone"));
	}
	if (!items.length) return `<span class="badge quiet" data-tip="This move changes nothing a person can do here">no change</span>`;
	const shown = items.slice(0, limit), rest = items.length - shown.length;
	return shown.join("") + (rest > 0 ? `<span class="badge quiet" data-tip="${esc(`${rest} more:\n${[...d.gain.map((c) => `+${ref(c)} ${title(titles, c)}`), ...d.lose.map((c) => `−${ref(c)} ${title(titles, c)}`)].slice(limit).join("\n")}`)}">+${rest}</span>` : "");
}

const statusTip: Record<Status, string> = {
	same: "",
	added: "Only in the new version",
	removed: "Only in the old version",
	changed: "In both versions, but it does something different now",
};
const statusWord: Record<Status, string> = { same: "", added: "new", removed: "gone", changed: "changed" };

function card(t: Tree, titles: Titles, rootTitle: string): string {
	const st = t.status ?? "same";
	const badges: string[] = [];
	if (st !== "same") badges.push(`<span class="badge st-${st}" data-tip="${statusTip[st]}">${statusWord[st]}</span>`);
	let head: string, body: string;
	if (!t.step) {
		head = `<span class="title">${esc(rootTitle)}</span>`;
		const ms = t.moves ?? [];
		body = t.moves
			? ms.length
				? `<span class="badge" data-tip="${esc(`Available at the start:\n${ms.map((c) => `${ref(c)} ${title(titles, c)}`).join("\n")}`)}">starts with ${ms.length} move${ms.length === 1 ? "" : "s"}</span>`
				: `<span class="badge quiet" data-tip="None of this place's moves is available in the first frame">none available at the start</span>`
			: `<span class="badge quiet">the first frame</span>`;
	} else {
		const s = t.step;
		const trig = `<span class="trig" data-tip="${esc(`${s.trigger} ${ref(s.claim)}${s.key ? `#${s.key}` : ""}${s.text ? ` ${s.text}` : ""}`)}">${esc(s.trigger)}${s.text ? ` ${esc(short(s.text, 10))}` : ""}</span>`;
		const via = s.via !== undefined
			? `<span class="badge via" data-tip="${esc(`A move of ${s.via === null ? "no place" : `${ref(s.via)} ${title(titles, s.via)}`}\nthat changes what this place offers`)}">↗ ${s.via === null ? "elsewhere" : esc(short(title(titles, s.via), 14))}</span>`
			: "";
		head = `${trig}<span class="title" data-tip="${esc(`${ref(s.claim)} ${title(titles, s.claim)}`)}">${esc(short(title(titles, s.claim), 30))}</span>`;
		// Where the move came from goes first on the second line, so the title keeps the room.
		body = via + pills(titles, t.delta, t.was?.delta, via ? 3 : 4);
		if (s.effects) badges.push(`<span class="badge quiet" data-tip="The step put ${s.effects} effect${s.effects === 1 ? "" : "s"} on the frame (a request, a timer, the clipboard…) and the host answered them">⇢ ${s.effects}</span>`);
	}
	if (t.flows) body += t.flows.map((f) => `<span class="pill flow" data-tip="${esc(`Flow ${ref(f)} ${title(titles, f)}\nits witness ends here, and its goal is proved to hold`)}">⚑ <b>${ref(f)}</b> ${esc(short(title(titles, f), 22))}</span>`).join("");
	if (t.back) badges.push(`<span class="badge quiet" data-tip="Leads to a state that is drawn elsewhere in this tree">↩</span>`);
	if (t.stay) {
		const was = t.was?.stay;
		const changed = was && was.join() !== t.stay.join();
		const added = changed ? t.stay.filter((x) => !was!.includes(x)) : [], gone = changed ? was!.filter((x) => !t.stay!.includes(x)) : [];
		const name = (x: string) => { const [tr, c] = x.split(" "); return `${tr} ${c} ${title(titles, +c.slice(1))}`; };
		const tip = `${t.stay.length} moves do something here but change nothing a person can do:\n${t.stay.map(name).join("\n")}` +
			(added.length ? `\n\nnow also: ${added.map(name).join(", ")}` : "") + (gone.length ? `\n\nno longer: ${gone.map(name).join(", ")}` : "");
		badges.push(`<span class="badge ${changed ? "st-changed" : "quiet"}" data-tip="${esc(tip)}">↺ ${t.stay.length}</span>`);
	}
	if (t.open) badges.push(`<span class="badge quiet" data-tip="Not explored past here (the depth limit)">⋯</span>`);
	return `<div class="card s-${st}${t.back ? " back" : ""}${t.step ? "" : " root"}"><div class="head">${head}<span class="badges">${badges.join("")}</span></div><div class="body">${body}</div></div>`;
}

type Dims = { cardW: number; gapX: number; rowH: number; cardH: number };
const full: Dims = { cardW: 300, gapX: 56, rowH: 86, cardH: 62 };
/** A flow's steps carry no badges below the title, so its cards are one line. */
const compact: Dims = { cardW: 240, gapX: 40, rowH: 50, cardH: 36 };
const hasBody = (t: Tree): boolean => !!t.delta || t.children.some(hasBody);

function tree(t: Tree, titles: Titles, rootTitle: string): string {
	const d = hasBody(t) ? full : compact;
	const { cardW, gapX, rowH, cardH } = d;
	type Placed = { t: Tree; x: number; y: number };
	const placed: Placed[] = [];
	const links: [Placed, Placed][] = [];
	let row = 0, maxDepth = 0;
	const place = (t: Tree, depth: number): Placed => {
		maxDepth = Math.max(maxDepth, depth);
		const kids = t.children.map((c) => place(c, depth + 1));
		const y = kids.length ? (kids[0].y + kids[kids.length - 1].y) / 2 : rowH * row++;
		const p = { t, x: depth * (cardW + gapX), y };
		placed.push(p);
		for (const k of kids) links.push([p, k]);
		return p;
	};
	place(t, 0);
	const W = (maxDepth + 1) * (cardW + gapX), H = rowH * Math.max(row, 1);
	const paths = links.map(([a, b]) => {
		const x1 = a.x + cardW, y1 = a.y + cardH / 2, x2 = b.x, y2 = b.y + cardH / 2, mx = (x1 + x2) / 2;
		const st = b.t.status ?? "same";
		return `<path class="l l-${st}${b.t.back ? " dash" : ""}" d="M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}"/>`;
	});
	const cards = placed.map((p) => `<div class="at" style="left:${p.x}px;top:${p.y}px;width:${cardW}px">${card(p.t, titles, rootTitle)}</div>`);
	return `<div class="tree${d === compact ? " compact" : ""}" style="width:${W}px;height:${H}px"><svg width="${W}" height="${H}">${paths.join("")}</svg>${cards.join("")}</div>`;
}

/** Each new outcome next to the old one it overlaps most, so a reader sees one line per outcome
 *  with what's new outlined and what's gone struck out. */
function pair(before: Delta[], after: Delta[]): [Delta | undefined, Delta | undefined][] {
	const left = [...before];
	const ids = (d: Delta) => [...d.gain.map((c) => `+${c}`), ...d.lose.map((c) => `-${c}`)];
	const out: [Delta | undefined, Delta | undefined][] = after.map((a) => {
		let best = -1, score = 0;
		left.forEach((b, i) => {
			const n = ids(a).filter((x) => ids(b).includes(x)).length;
			if (n > score) [best, score] = [i, n];
		});
		return [best >= 0 ? left.splice(best, 1)[0] : undefined, a];
	});
	return [...out, ...left.map((b): [Delta | undefined, Delta | undefined] => [b, undefined])];
}

function byMove(m: ReturnType<typeof moveDiff>, titles: Titles): string {
	const empty: Delta = { gain: [], lose: [] };
	const rows = m.moves.map((c) => {
		const lines = pair(c.before, c.after).map(([b, a]) => {
			const what = !b ? "a new outcome" : !a ? "no longer happens" : "changed";
			const cls = !b ? "st-added" : !a ? "st-removed" : "st-changed";
			return `<div class="delta"><span class="badge ${cls}" data-tip="${esc(`${!b ? "New: this move now does this somewhere" : !a ? "Gone: this move no longer does this anywhere" : "Changed: outlined is new, struck out is gone"}`)}">${what}</span>${pills(titles, a ?? empty, b ?? empty, 8)}</div>`;
		});
		const kept = c.kept.length ? `<span class="badge quiet" data-tip="${esc(`Unchanged outcomes:\n${c.kept.map(deltaText).join("\n")}`)}">${c.kept.length} unchanged</span>` : "";
		return `<tr><td><span class="trig">${esc(c.trigger)}</span> <span class="title" data-tip="${esc(`${ref(c.claim)} ${title(titles, c.claim)}`)}"><b>${ref(c.claim)}</b> ${esc(title(titles, c.claim))}</span></td><td>${lines.join("")}</td><td>${kept}</td></tr>`;
	});
	const reach = [...m.reachable.map((c) => pill(titles, c, "gain")), ...m.unreachable.map((c) => pill(titles, c, "lose"))].join("");
	return `<table class="bymove"><tr><th>Move</th><th data-tip="What the move does to what a person can do, anywhere in the graph">What it does now</th><th></th></tr>${rows.join("")}</table>` +
		(reach ? `<p class="note">Reachable at all: ${reach}</p>` : "");
}

const css = `
:root{--ink:#1f2328;--muted:#656d76;--line:#d0d7de;--bg:#f6f8fa;--gain:#1a7f37;--gainbg:#dafbe1;--lose:#cf222e;--losebg:#ffebe9;--chg:#9a6700;--chgbg:#fff8c5;--flow:#8250df;--flowbg:#fbefff}
body{font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:20px 24px;color:var(--ink);background:#fff}
h1{font-size:18px;margin:0 0 4px}.meta{color:var(--muted);margin:0 0 12px}
.legend{position:sticky;top:0;background:#fffe;backdrop-filter:blur(4px);padding:8px 0;border-bottom:1px solid var(--line);z-index:20;display:flex;gap:6px;flex-wrap:wrap;align-items:center}
details{margin:18px 0;border:1px solid var(--line);border-radius:10px;background:#fff}
summary{cursor:pointer;padding:10px 14px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;list-style:none;background:var(--bg);border-radius:10px}
details[open]>summary{border-bottom:1px solid var(--line);border-radius:10px 10px 0 0}
summary h2{font-size:15px;margin:0}summary .sub{color:var(--muted)}
.scroll{overflow:auto;padding:18px 14px 30px}
.tree{position:relative}.tree svg{position:absolute;inset:0;overflow:visible}
.l{fill:none;stroke:#8c959f;stroke-width:1.4}.l.dash{stroke-dasharray:5 4}
.l-added{stroke:var(--gain);stroke-width:2.2}.l-removed{stroke:var(--lose);stroke-width:2.2;stroke-dasharray:5 4}.l-changed{stroke:var(--chg);stroke-width:2.2}
.at{position:absolute}
.compact .card{min-height:${compact.cardH}px;padding:7px 8px}.compact .body:empty{display:none}
.card{box-sizing:border-box;min-height:${full.cardH}px;border:1px solid var(--line);border-radius:8px;background:#fff;padding:6px 8px;box-shadow:0 1px 2px #1f232810}
.card:hover{z-index:10;position:relative;box-shadow:0 3px 10px #1f232825}
.card.root{background:var(--bg)}
.card.back{border-style:dashed;background:#fcfcfd}
.card.s-added{border-color:#8fd19e;background:#f6fff8}.card.s-removed{border-color:#f5a3a9;background:#fff8f7;opacity:.85}.card.s-changed{border-color:#e3c46a;background:#fffdf0}
.head{display:flex;align-items:center;gap:6px;min-width:0}
.title{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
.badges{margin-left:auto;display:flex;gap:4px;flex-shrink:0}
.body{display:flex;gap:4px;flex-wrap:wrap;margin-top:5px}
.trig{font:11px ui-monospace,Menlo,monospace;background:#eaeef2;color:var(--muted);border-radius:4px;padding:1px 5px;flex-shrink:0}
.badge{font-size:11px;border-radius:10px;padding:1px 7px;background:#eaeef2;color:var(--ink);white-space:nowrap}
.badge.quiet{background:transparent;border:1px solid var(--line);color:var(--muted)}
.badge.via{background:#ddf4ff;color:#0969da}
.st-added{background:var(--gainbg);color:var(--gain)}.st-removed{background:var(--losebg);color:var(--lose)}.st-changed{background:var(--chgbg);color:var(--chg)}
.pill{font-size:11px;border-radius:10px;padding:1px 7px;white-space:nowrap;border:1px solid transparent}
.pill b{font:600 10px ui-monospace,Menlo,monospace;margin-right:2px}
.pill.gain{background:var(--gainbg);color:var(--gain)}.pill.lose{background:var(--losebg);color:var(--lose)}.pill.plain{background:#eaeef2}
.pill.flow{background:var(--flowbg);color:var(--flow)}
.pill.new{border-color:currentColor;font-weight:600}.pill.gone{text-decoration:line-through;opacity:.55;background:transparent;border:1px dashed currentColor}
[data-tip]{cursor:help}
#tip{position:fixed;display:none;max-width:420px;background:#1f2328;color:#fff;font:12px/1.45 -apple-system,sans-serif;padding:6px 9px;border-radius:6px;white-space:pre-wrap;z-index:100;pointer-events:none;box-shadow:0 4px 14px #0004}
.note{color:var(--muted);padding:12px 16px;margin:0}
table.bymove{border-collapse:collapse;margin:14px}table.bymove td,table.bymove th{padding:7px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
table.bymove th{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
.delta{display:flex;gap:4px;margin:3px 0;align-items:center;flex-wrap:wrap}
`;

/** One tooltip for the page, fixed to the window, so the scrolling boxes the trees sit in can't
 *  clip it. Below the badge, or above it when there's no room; kept inside the window. */
const tipScript = `
const tip = document.getElementById("tip");
document.addEventListener("mouseover", (e) => {
	const el = e.target.closest("[data-tip]");
	if (!el) { tip.style.display = "none"; return; }
	tip.textContent = el.dataset.tip;
	tip.style.display = "block";
	const r = el.getBoundingClientRect(), t = tip.getBoundingClientRect(), m = 8;
	const below = r.bottom + 6 + t.height + m <= innerHeight;
	tip.style.top = (below ? r.bottom + 6 : Math.max(m, r.top - 6 - t.height)) + "px";
	tip.style.left = Math.max(m, Math.min(r.left, innerWidth - t.width - m)) + "px";
});
document.addEventListener("scroll", () => (tip.style.display = "none"), true);
`;

export function html(sections: Section[], heading: string, meta: string, titles: Titles, diffing: boolean): string {
	const body = sections.map((s, i) => {
		const n = s.tree ? count(s.tree) : undefined;
		const tally = diffing && n
			? (["changed", "added", "removed"] as Status[]).filter((k) => n[k]).map((k) => `<span class="badge st-${k}" data-tip="${n[k]} ${statusWord[k]} in this ${s.id === null ? "view" : "place"}">${n[k]} ${statusWord[k]}</span>`).join("")
			: "";
		const idBadge = s.id !== null ? `<span class="badge" data-tip="The place's claim id">${ref(s.id)}</span>` : "";
		const moves = s.moves?.length ? `<span class="badge quiet" data-tip="${esc(`Its own moves:\n${s.moves.map((c) => `${ref(c)} ${title(titles, c)}`).join("\n")}`)}">${s.moves.length} move${s.moves.length === 1 ? "" : "s"}</span>` : "";
		const flag = s.unchanged ? `<span class="badge quiet">no change</span>` : "";
		// Open what has something to show: the first section, and in a diff anything that changed.
		const open = (s.tree || s.byMove) && !s.unchanged && (!diffing || i === 0 || tally || s.byMove);
		return `<details${open ? " open" : ""}><summary>${idBadge}<h2>${esc(s.title)}</h2>${s.sub ? `<span class="sub">${esc(s.sub)}</span>` : ""}${moves}${tally}${flag}</summary>
${s.tree ? `<div class="scroll">${tree(s.tree, titles, s.title)}</div>` : ""}${s.byMove ? byMove(s.byMove, titles) : ""}${s.note ? `<p class="note">${esc(s.note)}</p>` : ""}</details>`;
	}).join("\n");
	const legend = `<div class="legend">
<span class="pill gain" data-tip="After this move, a person can also do this">+ becomes available</span>
<span class="pill lose" data-tip="After this move, a person can no longer do this">− goes away</span>
<span class="pill flow" data-tip="A flow's witness ends here: its goal is proved to hold">⚑ flow ends</span>
<span class="badge via" data-tip="A move of another place that changes this one">↗ from another place</span>
<span class="badge quiet" data-tip="Moves that do something but change nothing a person can do; hover one for the list">↺ stay here</span>
<span class="badge quiet" data-tip="Leads to a state drawn elsewhere in the tree">↩ seen elsewhere</span>
${diffing ? `<span class="badge st-changed">changed</span><span class="badge st-added">new</span><span class="badge st-removed">gone</span>
<span class="pill gain new" data-tip="Outlined: new in this version">outlined: new</span><span class="pill gain gone" data-tip="Struck out: only in the old version">struck: gone</span>` : ""}
<span class="meta">hover anything for details</span></div>`;
	return `<!doctype html><meta charset="utf-8"><title>${esc(heading)}</title><style>${css}</style>
<h1>${esc(heading)}</h1><p class="meta">${esc(meta)}</p>${legend}${body}
<div id="tip"></div><script>${tipScript}</script>`;
}

// ---- The command -------------------------------------------------------------------------------

if (import.meta.main) {
	const { values: opts, positionals } = parseArgs({
		allowPositionals: true,
		options: { html: { type: "string" }, all: { type: "boolean" }, "by-place": { type: "boolean" } },
	});
	const [mode, oldPath, newPath] = positionals;
	if ((mode !== "flows" && mode !== "graph") || !oldPath) {
		console.error("usage: tree.ts flows|graph <old.json> [<new.json>] [--by-place] [--html out.html] [--all]");
		process.exit(2);
	}
	const read = (p: string) => JSON.parse(readFileSync(p, "utf8"));
	const [a, b] = [read(oldPath), newPath ? read(newPath) : undefined];
	const titlesOf = (j: any): Titles => (mode === "flows" ? Object.fromEntries(j.claims.map((c: Claim) => [String(c.id), c.title])) : j.claims);
	const titles: Titles = { ...titlesOf(a), ...(b ? titlesOf(b) : {}) };
	// A diff shows only the branches that changed, unless --all.
	const show = (ta: Tree, tb?: Tree) => (tb ? prune(diff(ta, tb), !!opts.all) : ta);
	const sections: Section[] = [];
	if (mode === "flows") sections.push({ id: null, title: "Flows", sub: "every flow's steps from the first frame", tree: show(flowTree(a.claims), b && flowTree(b.claims)) });
	else if (!opts["by-place"]) sections.push({ id: null, title: a.app, sub: "every place", tree: show(graphTree(a), b && graphTree(b)) });
	else {
		// One section per place, outermost first; a place either version has.
		const ps = new Map([...placesOf(a), ...(b ? placesOf(b) : [])].map((p) => [p.id, p]));
		for (const p of ps.values()) {
			const sub = p.within !== null ? `in ${ref(p.within)} ${title(titles, p.within)}` : undefined;
			if (!p.moves.length) {
				sections.push({ id: p.id, title: p.title, sub, note: "No move of this place was taken: the explorer doesn't drive appear moves." });
				continue;
			}
			const t = show(graphTree(projectGraph(a, p.id)), b && graphTree(projectGraph(b, p.id)));
			const same = b && !t.children.length && t.status === "same";
			sections.push({ id: p.id, title: p.title, sub, moves: p.moves, ...(same ? { unchanged: true } : { tree: t }) });
		}
	}
	const moves = mode === "graph" && b ? moveDiff(a, b) : undefined;
	if (moves) sections.push({ id: null, title: "By move", sub: "what each move does to what a person can do, before and after", ...(moves.moves.length ? { byMove: moves } : { unchanged: true }) });
	const kind = mode === "flows" ? "Flows" : `Move graph${opts["by-place"] ? " by place" : ""}`;
	const heading = `${kind}${newPath ? " · diff" : ""}`;
	const meta = newPath ? `${oldPath} → ${newPath}` : `${oldPath}${mode === "graph" ? `, ${a.states} states explored to depth ${a.depth}` : ""}`;
	if (opts.html) {
		writeFileSync(opts.html, html(sections, heading, meta, titles, !!newPath));
		console.log(`wrote ${opts.html}`);
	} else {
		const out = sections.map((s) => {
			const head = `== ${s.id !== null ? `${ref(s.id)} ` : ""}${s.title}${s.sub ? `, ${s.sub}` : ""}`;
			const by = s.byMove
				? s.byMove.moves.map((c) => `${c.trigger} ${ref(c.claim)} ${title(titles, c.claim)}\n${c.before.map((d) => `  - ${deltaText(d)}`).join("\n")}${c.before.length && c.after.length ? "\n" : ""}${c.after.map((d) => `  + ${deltaText(d)}`).join("\n")}`).join("\n")
				: "";
			return [head, s.tree ? text(s.tree, titles) : "", by, s.unchanged ? "No change." : s.note ?? ""].filter(Boolean).join("\n");
		});
		console.log(out.join("\n\n"));
	}
}

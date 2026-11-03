// Moves as a left-to-right tree, and the diff of two versions of it (a prototype).
//
//   bun tools/map/tree.ts flows claims.json                   A: the flows' witnesses as one tree
//   bun tools/map/tree.ts graph build/graph/Fixture.json      B: the explored move graph as a tree
//   bun tools/map/tree.ts flows old.json new.json             the diff of two versions
//   … --html out.html                                         an SVG page instead of text
//
// A merges every flow's witness (`lake exe claims`) into one prefix tree from the first state.
// Every edge is a step some flow's `live` theorem covers, and a leaf is where its `reaches`
// holds: proved, but only the paths someone wrote down.
//
// B unrolls the graph `lake exe fuzz <App> --graph D` writes (lean/Cairn/Fuzz/Graph.lean): a node
// is the set of moves a person can take, an edge a move. The tree is the breadth-first spanning
// tree; an edge to a node already placed is a leaf `↩ S<n>`. Exact for the states explored,
// silent about the rest.
//
// The diff matches by claim ids, which never change meaning (docs/claims.md): an edge is the
// same edge in both versions when it is the same trigger on the same claim from the same place
// in the tree.
import { readFileSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";

// ---- The tree ----------------------------------------------------------------------------------

type Status = "same" | "added" | "removed" | "changed";

/** One node of the tree, reached from its parent by `edge`. */
export type Tree = {
	/** Identity among siblings: the step, `press ^3`. */
	key: string;
	/** The edge from the parent, as a person reads it. */
	edge: string;
	/** What holds at the node: flows that end here (A), moves gained and lost (B). */
	note: string;
	/** The node's identity for the diff: a version's node labels may differ while it is the same. */
	ident: string;
	/** A leaf pointing at a node placed elsewhere in the tree (B's back and cross edges). */
	back?: string;
	/** An edge that delivered nothing to `update` (B). */
	inert?: boolean;
	children: Tree[];
	status?: Status;
	/** The other version's note, when the node changed. */
	was?: string;
};

type Titles = Record<string, string>;
const title = (titles: Titles, id: number) => titles[String(id)] ?? "";
const ref = (id: number) => `^${id}`;

// ---- A: flows ----------------------------------------------------------------------------------

type Step = { trigger: string; ref: string; claim: number; key: number; op?: { kind: string; text?: string } };
type Claim = { id: number; kind: string; title: string; retired: string | null; witness: Step[] | null | { error: string } };

const stepKey = (s: Step) => `${s.trigger} ${s.ref}${s.op ? ` ${s.op.kind}${s.op.text !== undefined ? ` ${JSON.stringify(s.op.text)}` : ""}` : ""}`;

export function flowTree(claims: Claim[]): Tree {
	const titles: Titles = Object.fromEntries(claims.map((c) => [String(c.id), c.title]));
	const root: Tree = { key: "", edge: "start", note: "", ident: "", children: [] };
	for (const c of claims) {
		if (c.kind !== "flow" || c.retired || !Array.isArray(c.witness)) continue;
		let at = root;
		for (const s of c.witness) {
			const key = stepKey(s);
			let next = at.children.find((t) => t.key === key);
			if (!next) {
				const op = s.op ? ` ${s.op.text !== undefined ? JSON.stringify(s.op.text) : s.op.kind}` : "";
				next = { key, edge: `${s.trigger} ${s.ref}${op} · ${title(titles, s.claim)}`, note: "", ident: "", children: [] };
				at.children.push(next);
			}
			at = next;
		}
		at.note = [at.note, `⚑ ^${c.id} ${c.title}`].filter(Boolean).join("; ");
		at.ident = at.note;
	}
	return root;
}

// ---- B: the explored graph ---------------------------------------------------------------------

type GNode = { id: number; sig: number[]; depth: number; explored: boolean };
type GEdge = { from: number; to: number; claim: number; key: number; trigger: string; action: string; delivered: number; effects: number; via?: string };
type Graph = {
	app: string; depth: number; claims: Titles; nodes: GNode[]; edges: GEdge[];
	/** Each claim's place (`in ^P`), and the place claims. */
	places?: Record<string, number | null>; placeIds?: number[];
	/** Set on a graph projected onto one place. */
	place?: number;
};

const sigKey = (sig: number[]) => sig.join(",");

function delta(from: number[], to: number[]): string {
	const gained = to.filter((x) => !from.includes(x)).map(ref);
	const lost = from.filter((x) => !to.includes(x)).map(ref);
	return [...gained.map((r) => `+${r}`), ...lost.map((r) => `−${r}`)].join(" ") || "no change";
}

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
 *  the place's own moves. An edge of another place's move says where it came from. */
export function projectGraph(g: Graph, place: number): Graph {
	const own = (c: number) => (g.places?.[String(c)] ?? null) === place;
	const nodes: GNode[] = [];
	const index = new Map<string, number>();
	const map = new Map<number, number>();
	// Node 0 first, so the projection's root is the first state's.
	for (const n of [...g.nodes].sort((a, b) => (a.id === 0 ? -1 : b.id === 0 ? 1 : a.depth - b.depth))) {
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
		const p = g.places?.[String(e.claim)];
		edges.push({ ...e, from, to, via: own(e.claim) ? undefined : p != null ? `from ^${p} ${title(g.claims, p)}` : "from no place" });
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
	const s0 = nodes.get(0)!;
	const build = (id: number, edge: string, key: string, from: number[]): Tree => {
		const n = nodes.get(id)!;
		const t: Tree = {
			key, edge, ident: id === 0 ? sigKey(n.sig) : delta(from, n.sig),
			note: id === 0 ? (n.sig.length ? `${n.sig.length} moves: ${n.sig.map(ref).join(" ")}` : "none of its moves yet") : delta(from, n.sig) + (n.explored ? "" : " ⋯"),
			children: [],
		};
		const loops = (out.get(id) ?? []).filter((e) => e.to === id);
		const stay = [...new Set(loops.map((e) => `${e.trigger === "press" ? "" : e.trigger + " "}^${e.claim}`))];
		if (stay.length) t.children.push({ key: "↺", edge: `↺ ${stay.length} moves stay here`, note: stay.join(" "), ident: stay.join(" "), children: [] });
		for (const e of out.get(id) ?? []) {
			if (e.to === id) continue;
			const k = `${e.trigger} ^${e.claim}`;
			const label = `${e.action} · ${title(g.claims, e.claim)}${e.via ? ` (${e.via})` : ""}${e.effects ? ` ⇢${e.effects}` : ""}`;
			if (parent.get(e.to) === e) t.children.push(build(e.to, label, k, n.sig));
			else {
				const to = nodes.get(e.to)!;
				t.children.push({
					key: k, edge: label, ident: delta(n.sig, to.sig), back: sigKey(to.sig), inert: e.delivered === 0,
					note: e.to === id ? "↺ same moves" : `↩ ${delta(n.sig, to.sig)}`, children: [],
				});
			}
		}
		return t;
	};
	const head = g.place !== undefined ? `^${g.place} ${title(g.claims, g.place)}` : `${g.app}, explored to depth ${g.depth}`;
	return build(0, head, "", s0.sig);
}

// ---- The diff ----------------------------------------------------------------------------------

/** The two trees as one: children matched by key, each marked by what the new version did to it. */
export function diff(a: Tree | undefined, b: Tree | undefined): Tree {
	if (!a) return mark(b!, "added");
	if (!b) return mark(a, "removed");
	const keys = [...a.children.map((t) => t.key), ...b.children.map((t) => t.key).filter((k) => !a.children.some((t) => t.key === k))];
	const children = keys.map((k) => diff(a.children.find((t) => t.key === k), b.children.find((t) => t.key === k)));
	const changed = a.ident !== b.ident;
	return { ...b, children, status: changed ? "changed" : "same", was: changed ? a.note : undefined };
}

function mark(t: Tree, status: Status): Tree {
	return { ...t, status, children: t.children.map((c) => mark(c, status)) };
}

/** Whether anything under `t` differs. */
const touched = (t: Tree): boolean => (t.status !== undefined && t.status !== "same") || t.children.some(touched);

function prune(t: Tree, keep: boolean): Tree {
	return { ...t, children: t.children.filter((c) => keep || touched(c)).map((c) => prune(c, keep)) };
}

/** B's diff by move, independent of where in the tree a move is: for each move, the changes it
 *  makes to what a person can do, anywhere in the explored graph ("gains ^5", "loses ^4 ^5 ^26").
 *  One changed `enabled` renames every node holding that claim, so nodes don't diff well; what a
 *  move does stays put unless the move's meaning changed. */
export function moveDiff(a: Graph, b: Graph): string[] {
	const effects = (g: Graph) => {
		const sig = new Map(g.nodes.map((n) => [n.id, n.sig]));
		const m = new Map<string, Set<string>>();
		for (const e of g.edges) {
			if (e.from === e.to) continue;
			const k = `${e.trigger} ^${e.claim} ${g.claims[String(e.claim)] ?? ""}`.trim();
			m.set(k, (m.get(k) ?? new Set()).add(delta(sig.get(e.from)!, sig.get(e.to)!)));
		}
		return m;
	};
	const ea = effects(a), eb = effects(b);
	const out: string[] = [];
	for (const k of [...new Set([...ea.keys(), ...eb.keys()])].sort()) {
		const was = ea.get(k) ?? new Set<string>(), now = eb.get(k) ?? new Set<string>();
		const gone = [...was].filter((x) => !now.has(x)), added = [...now].filter((x) => !was.has(x));
		if (!gone.length && !added.length) continue;
		out.push(`${k}`);
		for (const x of gone) out.push(`  - ${x}`);
		for (const x of added) out.push(`  + ${x}`);
		if (!now.size) out.push("  (now never changes what a person can do)");
	}
	// Which claims a person can ever reach.
	const reach = (g: Graph) => new Set(g.nodes.flatMap((n) => n.sig));
	const ra = reach(a), rb = reach(b);
	for (const c of rb) if (!ra.has(c)) out.push(`+ ^${c} is reachable now`);
	for (const c of ra) if (!rb.has(c)) out.push(`- ^${c} is no longer reachable`);
	return out;
}

// ---- Text --------------------------------------------------------------------------------------

const sign: Record<Status, string> = { same: " ", added: "+", removed: "-", changed: "~" };

export function text(t: Tree): string {
	const lines: string[] = [];
	const go = (t: Tree, pre: string, last: boolean, top: boolean) => {
		const s = t.status ? sign[t.status] + " " : "";
		const was = t.was !== undefined ? `   (was: ${t.was})` : "";
		const inert = t.inert ? " [inert]" : "";
		if (top) lines.push(`${s}${t.edge}${t.note ? `  ⟶  ${t.note}` : ""}${was}`);
		else lines.push(`${s}${pre}${last ? "└─ " : "├─ "}${t.edge}${inert}${t.note ? `  ⟶  ${t.note}` : ""}${was}`);
		const next = top ? "" : pre + (last ? "   " : "│  ");
		t.children.forEach((c, i) => go(c, next, i === t.children.length - 1, false));
	};
	go(t, "", true, true);
	return lines.join("\n");
}

// ---- HTML: an SVG, left to right ---------------------------------------------------------------

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const colour: Record<Status, string> = { same: "#555", added: "#1a7f37", removed: "#cf222e", changed: "#9a6700" };

export type Section = { heading: string; tree?: Tree; text?: string };

export function html(sections: Section[], heading: string): string {
	const body = sections.map((s) => `<h2>${esc(s.heading)}</h2>${s.tree ? svg(s.tree) : ""}${s.text ? `<pre>${esc(s.text)}</pre>` : ""}`).join("\n");
	return `<!doctype html><meta charset="utf-8"><title>${esc(heading)}</title>
<style>body{font:13px ui-monospace,Menlo,monospace;margin:16px;color:#222}h1{font-size:15px}h2{font-size:13px;margin:28px 0 0;border-top:1px solid #ddd;padding-top:12px}
pre{color:#555}.e{font-size:11px}.n{font-size:12px}.was{fill:#999}.key span{margin-right:14px}</style>
<h1>${esc(heading)}</h1>
<p class="key"><span style="color:${colour.added}">● added</span><span style="color:${colour.removed}">● removed</span><span style="color:${colour.changed}">● changed</span><span>□ edge to a node shown elsewhere</span></p>
${body}`;
}

function svg(t: Tree): string {
	const colW = 330, rowH = 58, padX = 20, padY = 34;
	type Placed = { t: Tree; x: number; y: number; depth: number };
	const placed: Placed[] = [];
	const links: [Placed, Placed][] = [];
	let row = 0;
	let maxDepth = 0;
	const place = (t: Tree, depth: number): Placed => {
		maxDepth = Math.max(maxDepth, depth);
		const kids = t.children.map((c) => place(c, depth + 1));
		const y = kids.length ? (kids[0].y + kids[kids.length - 1].y) / 2 : padY + rowH * row++;
		const p = { t, x: padX + depth * colW, y, depth };
		placed.push(p);
		for (const k of kids) links.push([p, k]);
		return p;
	};
	place(t, 0);
	const W = padX * 2 + (maxDepth + 1) * colW + 80, H = padY * 2 + rowH * row;
	const col = (t: Tree) => colour[t.status ?? "same"];
	const parts: string[] = [];
	for (const [a, b] of links) {
		const mx = (a.x + b.x) / 2;
		const dash = b.t.back || b.t.status === "removed" ? ` stroke-dasharray="4 3"` : "";
		parts.push(`<path d="M${a.x + 8},${a.y} C${mx},${a.y} ${mx},${b.y} ${b.x - 8},${b.y}" fill="none" stroke="${col(b.t)}" stroke-width="${b.t.status && b.t.status !== "same" ? 2 : 1.2}"${dash}/>`);
	}
	for (const p of placed) {
		const c = col(p.t);
		const shape = p.t.back ? `<rect x="${p.x - 6}" y="${p.y - 6}" width="12" height="12" fill="#fff" stroke="${c}" stroke-width="1.5"/>`
			: `<circle cx="${p.x}" cy="${p.y}" r="7" fill="${p.t.status && p.t.status !== "same" ? c : "#fff"}" stroke="${c}" stroke-width="1.5"/>`;
		const edge = p.depth === 0 ? "" : `<text x="${p.x - 12}" y="${p.y - 10}" text-anchor="end" class="e" fill="${c}">${esc(p.t.edge)}${p.t.inert ? " [inert]" : ""}</text>`;
		const was = p.t.was !== undefined ? `<tspan class="was"> was ${esc(p.t.was)}</tspan>` : "";
		// The edge's label sits above the node, what holds there below it, clear of the lines out.
		const head = p.depth === 0 ? `<text x="${p.x - 4}" y="${p.y - 12}" class="e" fill="${c}">${esc(p.t.edge)}</text>` : "";
		const note = `${head}<text x="${p.x - 4}" y="${p.y + 20}" class="n" fill="${c}">${esc(p.t.note)}${was}</text>`;
		parts.push(`<g>${shape}${edge}${note}<title>${esc(`${p.t.edge}\n${p.t.note}${p.t.was ? `\nwas: ${p.t.was}` : ""}`)}</title></g>`);
	}
	return `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">${parts.join("")}</svg>`;
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
	// A diff shows only the branches that changed, unless --all.
	const show = (ta: Tree, tb?: Tree) => (tb ? prune(diff(ta, tb), !!opts.all) : ta);
	const sections: Section[] = [];
	if (mode === "flows") sections.push({ heading: "Flows", tree: show(flowTree(a.claims), b && flowTree(b.claims)) });
	else if (!opts["by-place"]) sections.push({ heading: "Every place", tree: show(graphTree(a), b && graphTree(b)) });
	else {
		// One section per place, outermost first; a place either version has.
		const ps = new Map([...placesOf(a), ...(b ? placesOf(b) : [])].map((p) => [p.id, p]));
		for (const p of ps.values()) {
			const heading = `^${p.id} ${p.title}${p.within !== null ? `, in ^${p.within}` : ""}: ${p.moves.length ? p.moves.map(ref).join(" ") : "no moves"}`;
			if (!p.moves.length) {
				sections.push({ heading, text: "No move of this place was taken (the explorer doesn't drive appear, and keyed places' moves count here only if on screen)." });
				continue;
			}
			const t = show(graphTree(projectGraph(a, p.id)), b && graphTree(projectGraph(b, p.id)));
			sections.push(b && !t.children.length && t.status === "same" ? { heading, text: "No change." } : { heading, tree: t });
		}
	}
	if (mode === "graph" && b) {
		const lines = moveDiff(a, b);
		sections.push({ heading: "By move: what each does to what a person can do", text: lines.join("\n") || "No change." });
	}
	const heading = `${mode === "flows" ? "A · flows" : "B · move graph"}${opts["by-place"] ? " by place" : ""}: ${newPath ? `${oldPath} → ${newPath}` : oldPath}`;
	if (opts.html) {
		writeFileSync(opts.html, html(sections, heading));
		console.log(`wrote ${opts.html}`);
	} else console.log(sections.map((s) => `== ${s.heading}\n${s.tree ? text(s.tree) : ""}${s.text ?? ""}`).join("\n\n"));
}

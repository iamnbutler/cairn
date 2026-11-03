// The figures on /claims/ (content/claims/index.hbs). Each is HTML or inline SVG laid out by CSS
// alone (site.css, "The claims page"), so nothing moves when claims.js arrives: the script only
// animates what is already there, and without it every figure is a still that reads on its own.
//
// The data is real. The replay is Todo's flow ^216 (iamnbutler/cairn_examples, lean/Todo.lean),
// stepped through the frames `make try` explored and drew with the app's own Lean code (the same
// graph /try/todo/ runs; the six frames are copied into site/public/claims/). The state field is
// that graph's 400 states by distance from launch. The ledger rows are cairn_examples' claims.lock.

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// ---- The replay: flow ^216, frame by frame ---------------------------------------------------

/** A control in a frame: its ref, its label and its rect in the frame's logical pixels. */
type Control = [ref: string, label: string, x: number, y: number, w: number, h: number];

const W = 560;
const H = 316;

/** Todo's states 0, 1, 3, 7, 37 and 138: launch, then after each step of ^216's witness. */
const FRAMES: { img: string; c: Control[] }[] = [
	{ img: "875a0974435b.webp", c: [["^202", "What needs to be done?", 60, 61, 484, 48]] },
	{ img: "8b9c82c02682.webp", c: [["^202", "What needs to be done?", 60, 61, 484, 48]] },
	{ img: "9f9d9a812ad7.webp", c: [
		["^203", "Mark all as complete", 16, 61, 44, 48], ["^202", "What needs to be done?", 60, 61, 484, 48],
		["^204#1", "milk", 16, 109, 44, 44], ["^205#1", "milk", 60, 109, 440, 44], ["^206#1", "Delete milk", 500, 109, 44, 44],
		["^208", "All", 188, 153, 76, 40], ["^209", "Active", 264, 153, 76, 40], ["^210", "Completed", 340, 153, 76, 40]] },
	{ img: "c56df8603b7d.webp", c: [
		["^203", "Mark all as complete", 16, 61, 44, 48], ["^202", "What needs to be done?", 60, 61, 484, 48],
		["^204#1", "milk", 16, 109, 44, 44], ["^205#1", "milk", 60, 109, 440, 44], ["^206#1", "Delete milk", 500, 109, 44, 44],
		["^208", "All", 188, 153, 76, 40], ["^209", "Active", 264, 153, 76, 40], ["^210", "Completed", 340, 153, 76, 40]] },
	{ img: "a144c7001213.webp", c: [
		["^203", "Mark all as complete", 16, 61, 44, 48], ["^202", "What needs to be done?", 60, 61, 484, 48],
		["^204#1", "milk", 16, 109, 44, 44], ["^205#1", "milk", 60, 109, 440, 44], ["^206#1", "Delete milk", 500, 109, 44, 44],
		["^204#2", "eggs", 16, 153, 44, 44], ["^205#2", "eggs", 60, 153, 440, 44], ["^206#2", "Delete eggs", 500, 153, 44, 44],
		["^208", "All", 188, 197, 76, 40], ["^209", "Active", 264, 197, 76, 40], ["^210", "Completed", 340, 197, 76, 40]] },
	{ img: "918cc7b839b6.webp", c: [
		["^203", "Mark all as complete", 16, 61, 44, 48], ["^202", "What needs to be done?", 60, 61, 484, 48],
		["^204#1", "milk", 16, 109, 44, 44], ["^205#1", "milk", 60, 109, 440, 44], ["^206#1", "Delete milk", 500, 109, 44, 44],
		["^204#2", "eggs", 16, 153, 44, 44], ["^205#2", "eggs", 60, 153, 440, 44], ["^206#2", "Delete eggs", 500, 153, 44, 44],
		["^208", "All", 188, 197, 76, 40], ["^209", "Active", 264, 197, 76, 40], ["^210", "Completed", 340, 197, 76, 40],
		["^211", "Clear completed", 416, 197, 128, 40]] },
];

/** ^216's witness: each step's control, what it does, and the code that says so. */
const STEPS: { ref: string; say: string; code: string }[] = [
	{ ref: "^202", say: "Type “milk”", code: `edit ^202 (.insert "milk")` },
	{ ref: "^202", say: "Press Enter", code: "submit ^202" },
	{ ref: "^202", say: "Type “␣␣eggs␣”", code: `edit ^202 (.insert "  eggs ")` },
	{ ref: "^202", say: "Press Enter", code: "submit ^202" },
	{ ref: "^204#1", say: "Check milk", code: "press ^204#1" },
];

/** The moves on Todo's window (lean/Todo.lean), as their claim pages put them. */
const MOVES: Record<string, { title: string; sees: string }> = {
	"202": { title: "New todo", sees: "Enter adds the trimmed text as an active todo at the end of the list and clears the field; blank text adds nothing and stays in the field. Nothing else changes." },
	"203": { title: "Mark all as complete", sees: "Every todo, listed or not, is completed; or, when all were completed already, every todo is active again." },
	"204": { title: "Complete a todo", sees: "The todo is completed, or active again; the counter follows, and under a filter it leaves or joins the list. Nothing else changes." },
	"205": { title: "Edit a todo", sees: "The todo's row becomes a field holding its title, with the caret at the end and keyboard focus in it." },
	"206": { title: "Delete a todo", sees: "The todo is gone, with its row. Nothing else changes." },
	"208": { title: "All", sees: "Every todo is listed; only the filter changes." },
	"209": { title: "Active", sees: "Only active todos are listed; only the filter changes." },
	"210": { title: "Completed", sees: "Only completed todos are listed; only the filter changes." },
	"211": { title: "Clear completed", sees: "Every completed todo is removed, listed or not; active todos stay in order, and the button disappears." },
};

const claimOf = (ref: string) => ref.slice(1).split("#")[0]!;
const pct = (v: number, of: number) => `${+((v / of) * 100).toFixed(3)}%`;

export function replay(): string {
	const last = FRAMES.length - 1;
	const layers = FRAMES.map((f, i) => {
		const spots = f.c
			.map(([ref, label, x, y, w, h]) => {
				const k = claimOf(ref);
				const name = `${ref} ${MOVES[k]?.title ?? ""}${label ? `: ${label}` : ""}`;
				return `<span class="spot${w < 60 ? " sq" : ""}" data-ref="${ref}" data-claim="${k}" style="left:${pct(x, W)};top:${pct(y, H)};width:${pct(w, W)};height:${pct(h, H)}" title="${esc(name)}"><b>${ref}</b></span>`;
			})
			.join("");
		return `<div class="layer${i === last ? " on" : ""}" data-i="${i}"><img src="/claims/${f.img}" width="${W * 2}" height="${H * 2}" alt="${i === last ? "Todo after flow ^216: milk checked, eggs active, 1 item left. Every control carries its claim id." : ""}"${i === last ? "" : ' aria-hidden="true"'} decoding="async"><div class="spots">${spots}</div></div>`;
	}).join("\n");
	const steps = STEPS.map((s, i) => `<li data-i="${i}" data-ref="${s.ref}"><span class="say">${s.say}</span> <code>${esc(s.code)}</code></li>`).join("\n");
	const cards = Object.entries(MOVES)
		.map(([k, m]) => `<div class="card" data-claim="${k}"${k === "204" ? "" : " hidden"}><p class="ch"><span class="id">^${k}</span> <span class="kd">move</span> ${m.title}</p><p class="sees">${m.sees}</p><p class="ev"><span>proved</span> in every state where it's offered</p></div>`)
		.join("\n");
	return `<figure class="replay" aria-labelledby="rp-cap">
<div class="rp">
<div class="win px"><div class="frames">
${layers}
</div></div>
<div class="side">
<div class="flowcard px">
<p class="fh"><span class="id">^216</span> <span class="kd">flow</span> Add two todos and complete one</p>
<ol class="steps">
${steps}
</ol>
<p class="goal"><b>Goal</b> Two todos in order, eggs trimmed, milk completed, the field empty, 1 item left. <span class="ev"><span>proved</span> reachable</span></p>
</div>
<div class="cards" aria-live="off">
${cards}
</div>
</div>
</div>
<figcaption id="rp-cap">Todo running flow ^216, frame by frame: every control on screen carries its claim's id. The frames were drawn by the app's own Lean code. Point at a control to read its claim.</figcaption>
</figure>`;
}

// ---- The state field: a test visits a few states, a proof covers them all ---------------------

/** Todo's explored states by depth (moves from launch), from the /try/ graph: 400 in all. */
const RINGS = [1, 2, 2, 16, 70, 123, 186];
/** Moves out of the explored states into ones the graph stopped short of. */
const BEYOND = 1004;
const R0 = 20;
const DR = 27;

export function stateField(): string {
	const rad = (d: number) => (d === 0 ? 0 : R0 + (d - 1) * DR);
	const AIM = -0.62; // the test's path heads up and to the right
	const dots: string[] = [];
	const path: [number, number][] = [];
	RINGS.forEach((n, d) => {
		const r = rad(d);
		let best = 0;
		let bestErr = 9;
		const pts: [number, number][] = [];
		for (let i = 0; i < n; i++) {
			const a = (i / n) * Math.PI * 2 + d * 0.37;
			pts.push([r * Math.cos(a), r * Math.sin(a)]);
			const err = Math.abs(Math.atan2(Math.sin(a - AIM), Math.cos(a - AIM)));
			if (err < bestErr) { bestErr = err; best = i; }
		}
		pts.forEach(([x, y], i) => {
			const onPath = d <= 5 && i === best;
			dots.push(`<rect class="s${onPath ? " t" : ""}" data-d="${d}" x="${(x - 2.5).toFixed(1)}" y="${(y - 2.5).toFixed(1)}" width="5" height="5"/>`);
		});
		if (d <= 5) path.push(pts[best]!);
	});
	const line = path.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");
	const past = [7, 8, 9].map((d, i) => `<circle class="past" data-d="${d}" r="${rad(d)}" style="opacity:${(0.8 - i * 0.25).toFixed(2)}"/>`).join("");
	return `<figure class="field" aria-labelledby="sf-cap">
<div class="plot">
<svg viewBox="-244 -244 488 488" role="img" aria-label="Todo's 400 explored states as rings by distance from launch. A test's path visits six of them; the proof covers every ring and the unexplored ones past them.">
<g class="rings">${past}</g>
<g class="dots">${dots.join("")}</g>
<path class="tpath" d="${line}"/>
<rect class="start" x="-5" y="-5" width="10" height="10"/>
</svg>
</div>
<ul class="legend">
<li class="lt"><b>A test</b> One run: the six states flow ^216 passes through. It says nothing about the other 394.</li>
<li class="lp"><b>A proof</b> Invariant ^212, “the counter shows the number of active todos, and ids are distinct”, holds in all 400, and in every state past them: ${BEYOND.toLocaleString("en-US")} moves lead out of what was explored.</li>
</ul>
<figcaption id="sf-cap">Todo's states, by how many moves they are from launch. The rings stop at 400 because the explorer did; the app doesn't, and neither does the proof.</figcaption>
</figure>`;
}

// ---- The ledger: ids stay, meaning changes get new ones ---------------------------------------

type Row = [id: number, kind: string, status: string, hash: string, title: string, note?: string];

const ROWS: Row[] = [
	[204, "move", "active", "bfb82886ecadd91c", "Complete a todo"],
	[212, "invariant", "active", "8b1d23f718f063ec", "Counter and ids"],
	[213, "invariant", "retired", "-", "The list is the filter applied to the todos", "Style gained an image field, which changed the statement: reissued as ^225"],
	[215, "move", "retired", "-", "Back through filters", "Web only: the Mac app has no Back command"],
	[216, "flow", "active", "059a40708193b6f5", "Add two todos and complete one"],
	[225, "invariant", "retired", "cdded3b5839c217c", "The list is the filter applied to the todos", "FieldView gained secure: reissued as ^226"],
	[226, "invariant", "active", "5df0a26eadf00c3c", "The list is the filter applied to the todos"],
];

export function ledger(): string {
	const rows = ROWS.map(([id, kind, status, hash, title, note]) =>
		`<li class="${status}"${note ? ` data-note="${esc(note)}"` : ""}><span class="i">${id}</span><span class="k">${kind}</span><span class="st">${status}</span><span class="h">${hash}</span><span class="t">${esc(title)}</span>${note ? `<span class="nt">${esc(note)}</span>` : ""}</li>`,
	).join("\n");
	return `<figure class="ledger" aria-labelledby="lg-cap">
<p class="file">claims.lock <span>cairn_examples, an excerpt</span></p>
<ol class="rows px">
${rows}
</ol>
<div class="says">
<p class="sh">What the build says</p>
<p class="msg warn"><b>warning</b> ^225 “The list is the filter applied to the todos”: meaning changed (statement cdded3b5839c217c → 5df0a26eadf00c3c): give it a new id or <code>lake exe ledger update --accept</code></p>
<p class="msg err"><b>error</b> ^215 move “Back through filters” is in claims.lock but gone from the code. Ids never disappear: retire it with <code>retire ^215 move "Back through filters" because "…"</code></p>
</div>
<figcaption id="lg-cap">Every id a package ever issued, with a hash of what it promises. ^213 and ^225 kept their meaning and lost their id: a published claim keeps its statement, so a changed statement takes a new id. The two messages are the ledger's own, for a hash that changes and for an id deleted instead of retired.</figcaption>
</figure>`;
}

// ---- The six kinds, each with a small figure ---------------------------------------------------

const box = (x: number, y: number, w: number, h: number, cls = "") => `<rect class="bx${cls ? ` ${cls}` : ""}" x="${x}" y="${y}" width="${w}" height="${h}"/>`;
const arrow = (x1: number, y: number, x2: number, cls = "") => `<path class="ar${cls ? ` ${cls}` : ""}" d="M${x1} ${y}H${x2 - 2}M${x2 - 7} ${y - 5}L${x2 - 2} ${y}L${x2 - 7} ${y + 5}"/>`;
const label = (x: number, y: number, s: string, cls = "") => `<text class="${cls || "lb"}" x="${x}" y="${y}">${s}</text>`;

const KIND_ART: Record<string, string> = {
	move: [box(8, 22, 52, 44), label(34, 49, "s"), arrow(66, 44, 134, "hot"), label(100, 34, "^204", "id"), box(140, 22, 52, 44, "on"), label(166, 49, "s′"), label(166, 84, "post ✓", "ok")].join(""),
	flow: [...[0, 1, 2, 3].map((i) => box(8 + i * 40, 36, 16, 16, i === 0 ? "" : "on")), ...[0, 1, 2].map((i) => arrow(26 + i * 40, 44, 46 + i * 40, "hot")), arrow(146, 44, 166, "hot"),
		`<path class="flag" d="M172 62V22h20l-6 7 6 7h-20"/>`, label(100, 80, "witness → goal", "ok")].join(""),
	invariant: [...Array.from({ length: 24 }, (_, i) => box(14 + (i % 8) * 22, 14 + Math.floor(i / 8) * 22, 12, 12, "on")), label(100, 86, "holds in every state", "ok")].join(""),
	assume: [box(8, 20, 70, 48, "on"), label(43, 49, "Lean"), `<path class="cut" d="M100 8V84"/>`, box(122, 20, 70, 48), label(157, 49, "host"), arrow(80, 36, 120, "dim"), arrow(120, 54, 80, "dim"), label(100, 92, "recorded, fuzzed", "lb sm")].join(""),
	place: [box(16, 8, 168, 76), `<path class="ln2" d="M16 22H184"/>`, box(28, 32, 144, 14, "on"), box(28, 52, 22, 22, "on"), box(56, 52, 116, 22, "on"), label(170, 18, "^201", "id")].join(""),
	retire: [`<path class="tomb" d="M70 84V30h4v-6h4v-4h44v4h4v6h4v54z"/>`, label(100, 54, "^215", "id"), `<path class="gr" d="M40 84H160"/>`].join(""),
};

const KINDS: { kind: string; says: string; ex: string }[] = [
	{ kind: "move", says: "Something a person can do: when it's offered, what it does, the promise afterwards and its proof.", ex: "^204 Complete a todo" },
	{ kind: "flow", says: "A goal and a path of moves that reaches it. Lean checks every step is offered and the goal holds at the end.", ex: "^216 Add two todos and complete one" },
	{ kind: "invariant", says: "A property every move keeps, proved once, so it holds in every state the app can reach.", ex: "^212 Counter and ids" },
	{ kind: "assume", says: "What the proofs rely on and can't prove, mostly about the host. Recorded, checked by fuzzing, visible in every theorem that uses it.", ex: "cairn^908 The host's clock is monotonic" },
	{ kind: "place", says: "A region of the view where moves appear: a window, a menu, a panel. Claim pages are grouped by them.", ex: "^201 Todos window" },
	{ kind: "retire", says: "A tombstone with a reason. The claim is gone, the id stays issued forever, and retiring a released claim is a breaking change.", ex: "^215 Back through filters" },
];

export function kinds(): string {
	const cards = KINDS.map((k) => `<li class="kc px"><svg viewBox="0 0 200 96" aria-hidden="true">${KIND_ART[k.kind]}</svg><p class="kn">${k.kind}</p><p>${k.says}</p><p class="ex">${esc(k.ex)}</p></li>`).join("\n");
	return `<ul class="kindgrid">\n${cards}\n</ul>`;
}

if (import.meta.main) console.log(replay(), stateField(), ledger(), kinds());

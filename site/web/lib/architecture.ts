// The homepage's architecture figure: {{{ $utils.architecture() }}}. Three threads as swimlanes
// (docs/architecture.md): the main thread queues events, the Lean thread turns them into the
// latest frame, and the render thread repaints whatever frame is latest on every display
// refresh, so nothing waits on Lean. It is HTML laid out by CSS alone (site.css, `.threads`): on a
// wide window the lanes are rows and time runs right; in a narrow figure they are columns and time
// runs down. threads.js draws the connectors and the playhead in an overlay, so no script moves
// anything, and without it the figure still reads as a still of one frame.
//
// Each step names its lane by where it sits and its moment by --t, the column it takes when
// lanes are rows (--r, the row, when they are columns: the head takes row 1). The still shows
// the moment just after frame 42 is published: the ticks before it repainted 41, the ones after
// paint 42. threads.js recomputes which ticks those are.

const FRAME = 42; // the frame this key press produces, in the still
const TICKS = 12; // display refreshes across one key press
const STILL_NEW = 3; // ticks that show the new frame in the still

const step = (t: number, id: string, name: string, note: string, cls = "") =>
	`<div class="step px${cls ? ` ${cls}` : ""}" id="th-${id}" style="--t:${t};--r:${t + 1}"><b>${name}</b><i>${note}</i></div>`;

const chevron = `<svg class="chev" viewBox="0 0 8 12" aria-hidden="true"><polyline points="2,2 6,6 2,10"/></svg>`;

const lane = (cls: string, name: string, sub: string, tag: string, tagNote: string, body: string) =>
	`<div class="lane ${cls}">
  <p class="head"><span class="nm">${name}</span> <span class="sub">${sub}</span> <span class="tag">${tag}<i>${tagNote}</i></span></p>
  ${body}
</div>`;

export function architecture(): string {
	const chips = ["update", "view", "layout", "hit map", "encode"]
		.map((n, i) => `<span class="chip px" id="th-c${i}">${n}</span>`)
		.join(chevron);
	const n = (k: number) => `<span class="n">${k}</span>`;
	const ticks = Array.from({ length: TICKS }, (_, i) => `<span class="tk">${n(i < TICKS - STILL_NEW ? FRAME - 1 : FRAME)}</span>`).join("");
	return `<figure class="threads" aria-labelledby="th-cap">
<div class="lanes">
${lane("main", "Main thread", "Swift, AppKit", "trusted", "kept thin", [
	step(1, "key", "key press", "from AppKit"),
	step(2, "queue", "queue", "events, as bytes"),
	step(4, "ask", "accessibility, text input", `answered from frame ${n(FRAME)}`, "ask"),
].join("\n  "))}
${lane("lean", "Lean thread", "owns the state", "proved", "claims are theorems", [
	`<div class="step px work" id="th-work" style="--t:3;--r:4"><div class="chips">${chips}</div><i>pure, total functions</i></div>`,
	step(4, "frame", "latest frame", `frame ${n(FRAME)}, as bytes`, "frame"),
].join("\n  "))}
${lane("render", "Render thread", "Swift, Metal", "trusted", "probes, goldens", `<div class="ticks" id="th-ticks" aria-hidden="true">${ticks}</div>`)}
</div>
<figcaption id="th-cap">One frame, from a key press to the screen. The render thread repaints the latest frame on every display refresh, and accessibility answers from it: neither waits for Lean.</figcaption>
</figure>`;
}

if (import.meta.main) console.log(architecture());

// The homepage's architecture figure, as inline SVG: {{{ $utils.architecture() }}}. Pixel style:
// stepped corners, crisp 2px ink, chevron heads; one ink (currentColor), a tint for the proved
// part, the accent for "proved".
const S = 3; // corner step

function box(x: number, y: number, w: number, h: number, cls = ""): string {
	const s = S;
	const pts = [
		[x + 2 * s, y], [x + w - 2 * s, y], [x + w - 2 * s, y + s], [x + w - s, y + s], [x + w - s, y + 2 * s], [x + w, y + 2 * s],
		[x + w, y + h - 2 * s], [x + w - s, y + h - 2 * s], [x + w - s, y + h - s], [x + w - 2 * s, y + h - s], [x + w - 2 * s, y + h],
		[x + 2 * s, y + h], [x + 2 * s, y + h - s], [x + s, y + h - s], [x + s, y + h - 2 * s], [x, y + h - 2 * s],
		[x, y + 2 * s], [x + s, y + 2 * s], [x + s, y + s], [x + 2 * s, y + s],
	];
	const c = cls ? ` class="${cls}"` : "";
	return `<polygon${c} points="${pts.map(([a, b]) => `${a},${b}`).join(" ")}"/>`;
}

// An open chevron pointing in direction d, its tip at (x, y).
function head(x: number, y: number, d: "down" | "left" | "right"): string {
	const k = 6;
	if (d === "down") return `<polyline points="${x - k},${y - k} ${x},${y} ${x + k},${y - k}"/>`;
	if (d === "left") return `<polyline points="${x + k},${y - k} ${x},${y} ${x + k},${y + k}"/>`;
	return `<polyline points="${x - 4},${y - 4} ${x},${y} ${x - 4},${y + 4}"/>`;
}

const text = (x: number, y: number, s: string, cls: string, anchor = "start") =>
	`<text x="${x}" y="${y}" class="${cls}"${anchor !== "start" ? ` text-anchor="${anchor}"` : ""}>${s}</text>`;

export function architecture(): string {
	const X = 120, W = 340; // boxes
	const cxm = X + W / 2; // main axis
	const out: string[] = [];
	// Swift
	out.push("<!-- swift -->", box(X, 16, W, 76), text(X + 16, 40, "SWIFT · MAIN THREAD", "hd"), text(X + 16, 64, "the window and its events", "nm"), text(X + 16, 82, "no application logic", "it"));
	// events down
	out.push("<!-- events -->", `<line x1="${cxm}" y1="92" x2="${cxm}" y2="140"/>`, head(cxm, 140, "down"), text(cxm + 12, 114, "events, as bytes", "it"));
	// Lean
	out.push("<!-- lean -->", box(X, 148, W, 116, "tint"), text(X + 16, 172, "LEAN · OWNS THE STATE", "hd"));
	const names = ["update", "view", "layout", "hit map", "encode"];
	const iw = 52, gap = 12, x0 = X + 16;
	names.forEach((n, i) => {
		const bx = x0 + i * (iw + gap);
		out.push(box(bx, 186, iw, 28, "chip"), text(bx + iw / 2, 205, n, "sm", "middle"));
		if (i < names.length - 1) out.push(head(bx + iw + gap / 2 + 2, 200, "right"));
	});
	out.push(text(X + 16, 238, "pure, total functions; every", "it"), text(X + 16, 254, "claim is a theorem about them", "it"));
	// frame down
	out.push("<!-- frame -->", `<line x1="${cxm}" y1="264" x2="${cxm}" y2="312"/>`, head(cxm, 312, "down"), text(cxm + 12, 286, "the frame, as bytes", "it"));
	// Metal
	out.push("<!-- metal -->", box(X, 320, W, 64), text(X + 16, 344, "METAL · RENDER THREAD", "hd"), text(X + 16, 368, "paints the latest frame", "nm"));
	// back to Swift: a dashed elbow from Lean's right side to Swift's right side
	const rx = X + W + 34;
	out.push(
		"<!-- the frame answers AppKit -->",
		`<polyline class="dash" points="${X + W},206 ${rx},206 ${rx},54 ${X + W + 8},54"/>`,
		head(X + W + 8, 54, "left"),
		text(rx + 10, 120, "accessibility and", "it"),
		text(rx + 10, 136, "text input answer", "it"),
		text(rx + 10, 152, "from the last frame", "it"),
	);
	// brackets on the left
	const bracket = (y0: number, y1: number, label: string, note: string, cls = "") => {
		const bx = X - 14;
		const mid = Math.floor((y0 + y1) / 2);
		return [
			`<polyline${cls ? ` class="${cls}"` : ""} points="${bx + 6},${y0} ${bx},${y0} ${bx},${y1} ${bx + 6},${y1}"/>`,
			text(bx - 10, mid - 2, label, `lb ${cls}`.trim(), "end"),
			text(bx - 10, mid + 15, note, "it", "end"),
		];
	};
	out.push("<!-- what is proved and what is trusted -->");
	out.push(...bracket(18, 90, "trusted", "kept thin"), ...bracket(150, 262, "proved", "in Lean", "accent"), ...bracket(322, 382, "trusted", "probes, goldens"));
	return `<svg viewBox="0 0 640 396" role="img" aria-labelledby="arch-t">
<title id="arch-t">How a frame is made: Swift captures events, Lean computes the frame, Metal paints it</title>
${out.join("\n")}
</svg>`;
}

if (import.meta.main) console.log(architecture());

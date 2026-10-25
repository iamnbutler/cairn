// Draws the pixel-art cairn favicon: icon.svg, favicon.ico and apple-touch-icon.png.
//
//   bun site/icons.ts <dir>   write the three into <dir>
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { crc32, deflateSync } from "node:zlib";

// 16x16. o outline; top stone T/t/u, middle l/m/n, bottom a/b/c (light, mid, dark).
const GRID = [
	"................",
	"................",
	"......oooo......",
	".....oTTtto.....",
	".....ottttuo....",
	"...ooooooooooo..",
	"..olllmmmmmmmo..",
	"..ommmmmmmmnno..",
	"...onnnnnnnnno..",
	".oooooooooooooo.",
	".oaaabbbbbbbbbo.",
	".obbbbbbbbbbcco.",
	".obbbbbbbbcccco.",
	"..occcccccccco..",
	"...oooooooooo...",
	"................",
];

const COLORS: Record<string, string> = {
	o: "#2e3160",
	T: "#c9eadf", t: "#8cc6b6", u: "#5f9590",
	l: "#ddd6f4", m: "#aca1db", n: "#7d72b3",
	a: "#cbd6f2", b: "#8fa1d8", c: "#6070a8",
};
const DARK_OUTLINE = "#e9e4f5";
const TILE = "#cfc8ee"; // opaque background where a platform needs one

if (GRID.length !== 16 || GRID.some((row) => row.length !== 16)) throw new Error("icons: the grid must be 16x16");

const rgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

/** The icon as SVG, one rect per run of a colour in a row; the outline lightens in dark mode. */
export function svg(): string {
	const rects: string[] = [];
	GRID.forEach((row, y) => {
		for (let x = 0; x < 16; ) {
			const ch = row[x];
			if (ch === ".") {
				x++;
				continue;
			}
			let run = 1;
			while (x + run < 16 && row[x + run] === ch) run++;
			rects.push(`<rect${ch === "o" ? ' class="o"' : ""} x="${x}" y="${y}" width="${run}" height="1" fill="${COLORS[ch]}"/>`);
			x += run;
		}
	});
	return (
		'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">\n' +
		`<style>@media (prefers-color-scheme: dark) { .o { fill: ${DARK_OUTLINE}; } }</style>\n` +
		rects.join("\n") +
		"\n</svg>\n"
	);
}

const u32 = (n: number) => Buffer.from([n >>> 24, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]);

/** An RGBA PNG of the grid at `scale`, centred in `size`, on `background` or transparent. */
export function png(scale: number, size: number, background?: string): Buffer {
	const pad = Math.floor((size - 16 * scale) / 2);
	const bg = background ? [...rgb(background), 255] : [0, 0, 0, 0];
	const rows: number[] = [];
	for (let py = 0; py < size; py++) {
		rows.push(0);
		for (let px = 0; px < size; px++) {
			const gx = Math.floor((px - pad) / scale), gy = Math.floor((py - pad) / scale);
			const ch = gx >= 0 && gx < 16 && gy >= 0 && gy < 16 && px >= pad && py >= pad ? GRID[gy][gx] : ".";
			rows.push(...(ch !== "." ? [...rgb(COLORS[ch]), 255] : bg));
		}
	}
	const chunk = (kind: string, data: Buffer) => {
		const body = Buffer.concat([Buffer.from(kind, "latin1"), data]);
		return Buffer.concat([u32(data.length), body, u32(crc32(body))]);
	};
	const ihdr = Buffer.concat([u32(size), u32(size), Buffer.from([8, 6, 0, 0, 0])]);
	return Buffer.concat([
		Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
		chunk("IHDR", ihdr),
		chunk("IDAT", deflateSync(Buffer.from(rows), { level: 9 })),
		chunk("IEND", Buffer.alloc(0)),
	]);
}

/** An ICO with PNG payloads: the header, one directory entry per image, then the PNGs. */
export function ico(images: [number, Buffer][]): Buffer {
	const head = Buffer.alloc(6 + 16 * images.length);
	head.writeUInt16LE(0, 0);
	head.writeUInt16LE(1, 2);
	head.writeUInt16LE(images.length, 4);
	let offset = head.length;
	images.forEach(([size, data], i) => {
		const e = 6 + 16 * i;
		head.writeUInt8(size % 256, e);
		head.writeUInt8(size % 256, e + 1);
		head.writeUInt16LE(1, e + 4);
		head.writeUInt16LE(32, e + 6);
		head.writeUInt32LE(data.length, e + 8);
		head.writeUInt32LE(offset, e + 12);
		offset += data.length;
	});
	return Buffer.concat([head, ...images.map(([, data]) => data)]);
}

if (import.meta.main) {
	const dir = process.argv[2];
	if (!dir) throw new Error("usage: bun site/icons.ts <dir>");
	mkdirSync(dir, { recursive: true });
	writeFileSync(join(dir, "icon.svg"), svg());
	writeFileSync(join(dir, "favicon.ico"), ico([[16, png(1, 16)], [32, png(2, 32)]]));
	writeFileSync(join(dir, "apple-touch-icon.png"), png(10, 180, TILE));
}

// Code samples included from source: a page names a region of a real file, and the build copies it
// in. A region is marked in the source with comments in the file's own syntax (`-- region: name`
// … `-- endregion: name` in Lean, `//` in Swift, `#` in a Makefile or shell script,
// `<!-- region: name -->` in Markdown). A missing file or region, or an unclosed or doubled one,
// fails the build.
import { existsSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { esc, highlight } from "./highlight.ts";

const ROOT = resolve(import.meta.dirname, "../../..");
const fail = (where: string, message: string): never => {
	throw new Error(`${where}: ${message}`);
};

export type Region = { text: string; first: number; last: number };
const regionCache = new Map<string, Map<string, Region>>();
const MARKER = /^\s*(?:--|\/\/|#|<!--)\s*(end)?region:\s*([\w.-]+)\s*(?:-->)?\s*$/;

function regionsOf(path: string, where: string): Map<string, Region> | null {
	if (regionCache.has(path)) return regionCache.get(path)!;
	const abs = join(ROOT, path);
	if (!abs.startsWith(ROOT + "/") || !existsSync(abs) || !statSync(abs).isFile()) {
		fail(where, `includes ${path}, which doesn't exist`);
		return null;
	}
	const lines = readFileSync(abs, "utf8").split("\n");
	const found = new Map<string, Region>();
	const open = new Map<string, number>();
	lines.forEach((line, i) => {
		const m = line.match(MARKER);
		if (!m) return;
		const [, end, name] = m;
		if (!end) {
			if (open.has(name) || found.has(name)) fail(path, `region ${name} is opened twice (line ${i + 1})`);
			open.set(name, i);
		} else {
			const start = open.get(name);
			if (start === undefined) return fail(path, `endregion ${name} without its region (line ${i + 1})`);
			open.delete(name);
			const body = lines.slice(start + 1, i).filter((l) => !MARKER.test(l));
			found.set(name, { text: dedent(body).join("\n"), first: start + 2, last: i });
		}
	});
	for (const [name, i] of open) fail(path, `region ${name} (line ${i + 1}) is never closed`);
	regionCache.set(path, found);
	return found;
}

function dedent(lines: string[]): string[] {
	while (lines.length && !lines[0].trim()) lines.shift();
	while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
	const indent = Math.min(...lines.filter((l) => l.trim()).map((l) => l.match(/^\s*/)![0].length));
	return lines.map((l) => l.slice(Number.isFinite(indent) ? indent : 0));
}

export function include(spec: string, where: string): Region | null {
	const [path, name] = spec.split("#");
	if (!name) {
		fail(where, `include ${spec} names no region (path#region)`);
		return null;
	}
	const regions = regionsOf(path, where);
	if (!regions) return null;
	const r = regions.get(name);
	if (!r) fail(where, `includes ${path}#${name}, and ${path} has no region ${name}`);
	return r ?? null;
}

export { esc } from "./highlight.ts";

const langOf = (path: string) =>
	path.endsWith(".lean") ? "lean" : path.endsWith(".swift") ? "swift" : path.endsWith(".md") ? "md" : "make";

export function codeBlock(path: string, r: Region, lang = langOf(path)): string {
	const lines = r.first === r.last ? `line ${r.first}` : `lines ${r.first}–${r.last}`;
	return (
		`<figure class="code"><pre class="px"><code class="${lang}">${highlight(r.text, lang)}</code></pre>` +
		`<figcaption><code>${esc(path)}</code>, ${lines}</figcaption></figure>`
	);
}


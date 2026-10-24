// The public developer docs: site/docs/*.md → site/public/docs/ (issue #73).
//
//   bun tools/docs/build.ts           write site/public/docs/ (`make docs-site`)
//   bun tools/docs/build.ts --check   build in memory and fail if the committed pages differ
//                                     (`make docs-check`, part of `make check`)
//
// Code is the documentation: a page never holds a code sample. It names a region of a real
// source file on a line of its own,
//
//   <!-- include lean/Examples/Counter.lean#counter-reset -->
//
// and the build copies the region in. A region is marked in the source with comments in the
// file's own syntax (`-- region: name` … `-- endregion: name` in Lean, `//` in Swift, `#` in a
// Makefile or shell script, `<!-- region: name -->` in Markdown). The build fails when a file or
// region is missing, a region is unclosed or doubled, a page has a fenced code block, a link
// points at a page that doesn't exist, or a page links to GitHub (the repository is private;
// only the issues named in ALLOWED_LINKS may be linked). Markdown regions are spliced in as
// Markdown with their links dropped, since they point into internal notes.
//
// Pages are listed in site/docs/nav.json, which is the sidebar. site/public/docs/api/ belongs to
// `cairn doc` (#77): the build never writes or deletes it, and the sidebar links to it once it
// has an index.html. Needs only bun.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "../..");
const SRC = join(ROOT, "site/docs");
const PUBLIC = join(ROOT, "site/public");
const OUT = join(PUBLIC, "docs");
const API = join(OUT, "api");
const CHECK = process.argv.includes("--check");

// The only GitHub links a public page may carry: the issues that unblock its TODO pages.
// Open issues the pages point at. Keep it to issues that are open: replace one when it closes.
const ALLOWED_LINKS = [83, 84, 92, 93, 94, 95, 96, 97, 99].map((n) => `https://github.com/iamnbutler/cairn/issues/${n}`);

const errors: string[] = [];
const fail = (where: string, message: string) => errors.push(`${where}: ${message}`);

// --- Pages and the sidebar ----------------------------------------------------------------------

type NavItem = { page?: string; href?: string; title?: string; children?: string[] };
type NavSection = { section: string; items: NavItem[] };
type Page = {
	id: string; // "book/first-app"; "index" is /docs/
	url: string;
	title: string;
	nav: string; // the sidebar's name for it
	lede: string;
	status: "real" | "todo";
	eyebrow: string;
	body: string; // Markdown, after the front matter
};

const nav: NavSection[] = JSON.parse(readFileSync(join(SRC, "nav.json"), "utf8"));
const urlOf = (id: string) => (id === "index" ? "/docs/" : `/docs/${id.replace(/\/index$/, "")}/`);

function frontMatter(id: string, text: string): Page {
	const m = text.match(/^---\n([\s\S]*?)\n---\n/);
	if (!m) {
		fail(`site/docs/${id}.md`, "no front matter (--- title: … ---)");
		return { id, url: urlOf(id), title: id, nav: id, lede: "", status: "real", eyebrow: "", body: text };
	}
	const meta: Record<string, string> = {};
	for (const line of m[1].split("\n")) {
		const kv = line.match(/^(\w+):\s*(.*)$/);
		if (kv) meta[kv[1]] = kv[2].trim();
	}
	if (!meta.title) fail(`site/docs/${id}.md`, "no title in the front matter");
	return {
		id,
		url: urlOf(id),
		title: meta.title ?? id,
		nav: meta.nav ?? meta.title ?? id,
		lede: meta.lede ?? "",
		status: meta.status === "todo" ? "todo" : "real",
		eyebrow: meta.eyebrow ?? "",
		body: text.slice(m[0].length),
	};
}

function mdFiles(dir: string, base = ""): string[] {
	return readdirSync(dir).flatMap((name) => {
		const p = join(dir, name);
		if (statSync(p).isDirectory()) return mdFiles(p, join(base, name));
		return name.endsWith(".md") ? [join(base, name.slice(0, -3))] : [];
	});
}

const pages = new Map<string, Page>();
for (const id of mdFiles(SRC).sort()) pages.set(id, frontMatter(id, readFileSync(join(SRC, `${id}.md`), "utf8")));

const listed = new Set<string>(["index"]);
for (const s of nav)
	for (const item of s.items) {
		for (const id of [item.page, ...(item.children ?? [])]) {
			if (!id) continue;
			if (!pages.has(id)) fail("site/docs/nav.json", `lists ${id}, and site/docs/${id}.md doesn't exist`);
			listed.add(id);
		}
	}
for (const id of pages.keys()) if (!listed.has(id)) fail(`site/docs/${id}.md`, "is not in nav.json, so no one can reach it");

// The Book reads in order: its contents page, then each chapter.
const bookItem = nav.flatMap((s) => s.items).find((i) => i.page === "book/index");
const bookOrder = bookItem ? ["book/index", ...(bookItem.children ?? [])] : [];

// The API reference is `cairn doc`'s (#74). Until it has published, the sidebar points at the
// page that says so.
const apiPublished = existsSync(join(API, "index.html"));
const navHref = (item: NavItem) =>
	item.page === "use/api" && apiPublished ? "/docs/api/" : item.href ?? urlOf(item.page!);

// --- Includes -----------------------------------------------------------------------------------

type Region = { text: string; first: number; last: number };
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

function include(spec: string, where: string): Region | null {
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

// --- Highlighting -------------------------------------------------------------------------------

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const span = (cls: string, s: string) => `<span class="${cls}">${esc(s)}</span>`;

const LEAN_KW = new Set(
	("def theorem structure inductive where deriving namespace end open section public import meta " +
		"module example instance if then else match with fun let have show by do return for in " +
		"move flow invariant assume place retire does sees enabled on apply emit post sound goal " +
		"witness holds init step receive statement check because mutual private noncomputable " +
		"abbrev class extends partial").split(" "),
);
const SWIFT_KW = new Set(
	("let var func if else guard return import for in while switch case default enum struct class " +
		"final static self true false nil try throw throws async await some any").split(" "),
);

function highlight(code: string, lang: string): string {
	if (lang === "md") return esc(code);
	const rules: [RegExp, string | null][] =
		lang === "lean"
			? [
					[/\/-[\s\S]*?-\//y, "cm"],
					[/--[^\n]*/y, "cm"],
					[/"(?:[^"\\\n]|\\.)*"/y, "str"],
					[/\^\d+(?:#\d+)?/y, "id"],
					[/@\[[^\]\n]*\]/y, "kw"],
					[/[A-Za-z_][\w'.!?]*/y, null],
				]
			: lang === "swift"
				? [
						[/\/\/[^\n]*/y, "cm"],
						[/"(?:[^"\\\n]|\\.)*"/y, "str"],
						[/[A-Za-z_]\w*/y, null],
					]
				: [
						[/#[^\n]*/y, "cm"],
						[/^[\w.-]+(?=:)/my, "kw"],
					];
	let out = "";
	let i = 0;
	let plain = "";
	const flush = () => {
		out += esc(plain);
		plain = "";
	};
	outer: while (i < code.length) {
		for (const [re, cls] of rules) {
			re.lastIndex = i;
			const m = re.exec(code);
			if (!m || m.index !== i || !m[0]) continue;
			const word = m[0];
			const kw = cls === null && (lang === "lean" ? LEAN_KW : SWIFT_KW).has(word);
			if (cls || kw) {
				flush();
				out += span(cls ?? "kw", word);
			} else plain += word;
			i += word.length;
			continue outer;
		}
		plain += code[i++];
	}
	flush();
	return out;
}

const langOf = (path: string) =>
	path.endsWith(".lean") ? "lean" : path.endsWith(".swift") ? "swift" : path.endsWith(".md") ? "md" : "make";

function codeBlock(path: string, r: Region, lang = langOf(path)): string {
	const lines = r.first === r.last ? `line ${r.first}` : `lines ${r.first}–${r.last}`;
	return (
		`<figure class="code"><pre class="px"><code class="${lang}">${highlight(r.text, lang)}</code></pre>` +
		`<figcaption><code>${esc(path)}</code>, ${lines}</figcaption></figure>`
	);
}

// --- One page -----------------------------------------------------------------------------------

const INCLUDE = /^<!--\s*include\s+(\S+)\s*-->$/;

function renderBody(page: Page): string {
	const where = `site/docs/${page.id}.md`;
	const blocks: string[] = [];
	const lines: string[] = [];
	let inFence = false;
	page.body.split("\n").forEach((line, i) => {
		if (/^\s*(```|~~~)/.test(line)) {
			if (!inFence) fail(`${where}:${i + 1}`, "a fenced code block: include the code from a source file instead");
			inFence = !inFence;
		}
		// `:::note Label` … `:::` is a note card, with Markdown inside.
		const note = line.match(/^:::note\s+(.+)$/);
		if (note) return lines.push(`<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">${esc(note[1])}</p>`, "");
		if (line.trim() === ":::") return lines.push("", "</div></aside>");
		const m = line.trim().match(INCLUDE);
		if (!m) return lines.push(line);
		const spec = m[1];
		const r = include(spec, `${where}:${i + 1}`);
		if (!r) return;
		if (spec.split("#")[0].endsWith(".md")) {
			// Internal notes: their links point into the private repository, so keep only the text.
			// A fenced block in the region becomes a code figure like any other include, captioned
			// with its own lines in the note.
			const text = r.text.split("\n");
			let prose: string[] = [];
			const flush = () => {
				if (prose.length) lines.push("", prose.join("\n").replace(/\[([^\]]+)\]\([^)]*\)/g, "$1"), "");
				prose = [];
			};
			for (let k = 0; k < text.length; k++) {
				const open = text[k].match(/^\s*```\s*(\w*)/);
				if (!open) { prose.push(text[k]); continue; }
				const end = text.findIndex((l, j) => j > k && /^\s*```\s*$/.test(l));
				if (end < 0) { fail(`${where}:${i + 1}`, `${spec} has a fenced block that never closes`); break; }
				flush();
				const fence = open[1];
				const lang = fence === "lean" || fence === "swift" ? fence : "make";
				blocks.push(codeBlock(spec.split("#")[0], { text: text.slice(k + 1, end).join("\n"), first: r.first + k + 1, last: r.first + end - 1 }, lang));
				lines.push("", `<div data-include="${blocks.length - 1}"></div>`, "");
				k = end;
			}
			flush();
		} else {
			blocks.push(codeBlock(spec.split("#")[0], r));
			lines.push("", `<div data-include="${blocks.length - 1}"></div>`, "");
		}
	});
	let html = Bun.markdown.html(lines.join("\n"), {}) as string;
	html = html.replace(/<div data-include="(\d+)"><\/div>/g, (_, n) => blocks[Number(n)]);
	html = html.replace(/<table>/g, '<div class="wrap"><table>').replace(/<\/table>/g, "</table></div>");
	// Heading ids, as scene.js's mountAnchors would make them, so links to a section work without
	// JavaScript and the build can check them.
	const ids = new Set<string>();
	html = html.replace(/<h([2-4])>([\s\S]*?)<\/h\1>/g, (_, n, inner) => {
		const base = slugOf(inner);
		let id = base;
		for (let k = 2; ids.has(id); k++) id = `${base}-${k}`;
		ids.add(id);
		return `<h${n} id="${id}">${inner}</h${n}>`;
	});
	anchors.set(page.url, ids);
	return html;
}

const anchors = new Map<string, Set<string>>(); // page url → its heading ids

// scene.js's slugOf, on the heading's HTML.
const slugOf = (inner: string) =>
	inner
		.replace(/<[^>]*>/g, "")
		.replace(/&(amp|lt|gt|quot|#39|apos);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", apos: "'" })[e as string]!)
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-|-$/g, "") || "section";

function checkLinks(page: Page, html: string, urls: Set<string>) {
	const where = `site/docs/${page.id}.md`;
	for (const [, href] of html.matchAll(/href="([^"]*)"/g)) {
		if (/^https?:\/\/(www\.)?github\.com\//.test(href) && !ALLOWED_LINKS.includes(href))
			fail(where, `links to ${href}: the repository is private, so public pages don't link to GitHub`);
		if (!href.startsWith("/")) continue;
		const path = href.split("#")[0];
		if (path.startsWith("/docs/api/")) continue; // `cairn doc`'s, possibly not yet published
		if (path.startsWith("/docs/")) {
			if (!urls.has(path)) fail(where, `links to ${path}, which is not a docs page`);
			const frag = href.split("#")[1];
			if (frag && !anchors.get(path)?.has(frag)) fail(where, `links to ${href}, and that page has no heading #${frag}`);
			continue;
		}
		const file = join(PUBLIC, path.endsWith("/") ? `${path}index.html` : path);
		if (!existsSync(file)) fail(where, `links to ${path}, which isn't in site/public`);
	}
}

function sidebar(current: Page): string {
	const item = (href: string, title: string, on: boolean, todo: boolean) =>
		`<a href="${href}"${on ? ' class="on" aria-current="page"' : ""}>${esc(title)}${todo ? '<span class="todo">to do</span>' : ""}</a>`;
	const sections = nav.map((s) => {
		const items = s.items.map((it) => {
			const p = it.page ? pages.get(it.page) : undefined;
			const title = it.title ?? p?.nav ?? it.href ?? "";
			const head = item(navHref(it), title, it.page === current.id, p?.status === "todo" && !(it.page === "use/api" && apiPublished));
			const kids = (it.children ?? [])
				.map((id) => pages.get(id))
				.filter((c): c is Page => !!c)
				.map((c) => `<li>${item(c.url, c.nav, c.id === current.id, c.status === "todo")}</li>`)
				.join("");
			return `<li>${head}${kids ? `<ol>${kids}</ol>` : ""}</li>`;
		});
		return `<h2>${esc(s.section)}</h2><ul>${items.join("")}</ul>`;
	});
	return sections.join("");
}

function prevNext(page: Page): string {
	const i = bookOrder.indexOf(page.id);
	if (i < 0) return "";
	const prev = i > 0 ? pages.get(bookOrder[i - 1]) : undefined;
	const next = i < bookOrder.length - 1 ? pages.get(bookOrder[i + 1]) : undefined;
	const link = (p: Page | undefined, rel: string, label: string) =>
		p ? `<a class="${rel}" rel="${rel}" href="${p.url}"><small>${label}</small>${esc(p.nav)}</a>` : "<span></span>";
	return `<nav class="pager" aria-label="The Book">${link(prev, "prev", "Previous")}${link(next, "next", "Next")}</nav>`;
}

function shell(page: Page, body: string): string {
	const title = page.id === "index" ? "Cairn docs" : `${page.title} · Cairn docs`;
	const todo = page.status === "todo";
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
${page.lede ? `<meta name="description" content="${esc(page.lede.replace(/`/g, ""))}">\n` : ""}<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/icon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Pixelify+Sans:wght@400..700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/docs/docs.css">
</head>
<body>
<!-- Generated by tools/docs/build.ts from site/docs/${page.id}.md. Edit that, then run make docs-site. -->
<header class="bar">
  <a class="home" href="/"><img src="/icon.svg" alt="">Cairn</a>
  <a href="/milestones/">Milestones</a>
  <a href="/docs/"${page.id === "index" ? ' class="on"' : ""}>Docs</a>
  <a href="/packages/">Packages</a>
  <a href="/docs/evidence/">Maps</a>
</header>
<div class="layout">
<details class="side" open>
<summary>Contents</summary>
<nav aria-label="Docs">${sidebar(page)}</nav>
</details>
<script>if (matchMedia("(max-width: 900px)").matches) document.querySelector("details.side").open = false;</script>
<main>
<header class="page">
${page.eyebrow || todo ? `<p class="eyebrow">${esc(page.eyebrow)}${todo ? '<span class="todo">not written yet</span>' : ""}</p>` : ""}
<h1>${esc(page.title)}</h1>
${page.lede ? `<p class="lede">${inline(page.lede)}</p>` : ""}
</header>
<article class="prose">
${body}
</article>
${prevNext(page)}
</main>
</div>
<footer>Cairn is research, and these docs grow with it. The code samples are included from the source that <code>make check</code> builds.</footer>
<script type="module">
  import { mountAnchors } from "/scene.js";
  mountAnchors(document.querySelector("main"));
</script>
</body>
</html>
`;
}

const inline = (s: string) =>
	(Bun.markdown.html(s, {}) as string).trim().replace(/^<p>/, "").replace(/<\/p>$/, "");

// --- Build --------------------------------------------------------------------------------------

const urls = new Set([...pages.values()].map((p) => p.url));
const out = new Map<string, string>(); // path under site/public/docs → contents
const bodies = new Map([...pages.values()].map((page) => [page.id, renderBody(page)]));
for (const page of pages.values()) {
	const body = bodies.get(page.id)!;
	checkLinks(page, body + inline(page.lede), urls);
	const file = page.id === "index" ? "index.html" : join(page.id.replace(/\/index$/, ""), "index.html");
	out.set(file, shell(page, body));
}
out.set("docs.css", readFileSync(join(import.meta.dir, "docs.css"), "utf8"));

if (errors.length) {
	for (const e of errors) console.error(`docs: ${e}`);
	console.error(`docs: ${errors.length} error${errors.length === 1 ? "" : "s"}; nothing written`);
	process.exit(1);
}

// Everything in site/public/docs except api/, which is `cairn doc`'s.
function existing(dir = OUT, base = ""): string[] {
	if (!existsSync(dir)) return [];
	return readdirSync(dir).flatMap((name) => {
		const rel = join(base, name);
		if (!base && name === "api") return [];
		const p = join(dir, name);
		return statSync(p).isDirectory() ? existing(p, rel) : [rel];
	});
}

if (CHECK) {
	const have = new Set(existing());
	const stale = [...out].filter(([f, text]) => !have.has(f) || readFileSync(join(OUT, f), "utf8") !== text).map(([f]) => f);
	const extra = [...have].filter((f) => !out.has(f));
	if (stale.length || extra.length) {
		for (const f of stale) console.error(`docs: site/public/docs/${f} is out of date`);
		for (const f of extra) console.error(`docs: site/public/docs/${f} has no source`);
		console.error("docs: run make docs-site and commit site/public/docs/");
		process.exit(1);
	}
	console.log(`docs: ${out.size} files up to date; every include resolves`);
} else {
	for (const name of existsSync(OUT) ? readdirSync(OUT) : []) if (name !== "api") rmSync(join(OUT, name), { recursive: true });
	for (const [f, text] of out) {
		mkdirSync(dirname(join(OUT, f)), { recursive: true });
		writeFileSync(join(OUT, f), text);
	}
	console.log(`docs: wrote ${out.size} files to ${relative(ROOT, OUT)}/`);
}

// The docs for language models, from the same sources as the pages (site/web/content/docs): a
// Markdown copy of every docs page beside it (/docs/guide/proving/ → /docs/guide/proving.md), all
// of them in one file (/llms-full.txt), and /llms.txt, the index in the llmstxt.org format that
// names them and the API reference's own llms.txt (`cairn doc`, tools/doc/markdown.ts). Code
// samples are included from source exactly as on the pages; a page marked `status: todo` is left
// out.
//
//   bun tools/site/llms.ts build/site
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { ORIGIN } from "../og/og.ts";
import { include } from "../../site/web/lib/source.ts";

const ROOT = resolve(import.meta.dir, "../..");
const CONTENT = join(ROOT, "site/web/content/docs");
const NAV: { section: string; items: { page?: string; children?: string[]; href?: string; title?: string }[] }[] = JSON.parse(
	readFileSync(join(ROOT, "site/web/data/nav.json"), "utf8"),
);

export type Page = { id: string; url: string; md: string; title: string; lede: string; eyebrow: string; body: string; todo: boolean };

// A page's id is its file under content/docs without .md: "guide/proving", "guide/index".
const urlOf = (id: string) => `/docs/${id.replace(/(^|\/)index$/, "")}${id === "index" ? "" : "/"}`.replace(/\/+$/, "/");
const mdOf = (id: string) => (id === "index" ? "/docs/index.md" : `/docs/${id.replace(/\/index$/, "")}.md`);

function frontmatter(src: string, file: string): [Record<string, string>, string] {
	const m = /^---\n([\s\S]*?)\n---\n/.exec(src);
	if (!m) throw new Error(`llms: ${file} has no frontmatter`);
	const fields: Record<string, string> = {};
	for (const line of m[1].split("\n")) {
		const at = line.indexOf(":");
		if (at > 0) fields[line.slice(0, at).trim()] = line.slice(at + 1).trim().replace(/^(["'])(.*)\1$/, "$2");
	}
	return [fields, src.slice(m[0].length)];
}

const fence = (body: string, lang: string) => {
	const ticks = "`".repeat(Math.max(3, ...[...body.matchAll(/`+/g)].map((x) => x[0].length + 1)));
	return `${ticks}${lang}\n${body}\n${ticks}`;
};
const langOf = (path: string) => (path.endsWith(".lean") ? "lean" : path.endsWith(".swift") ? "swift" : path.endsWith(".md") ? "md" : "make");

// <bongo:include src="path#region" />: the region, fenced and captioned as on the page. An
// internal note's region (a .md file) is prose with its links dropped, as the page shows it.
function includeMd(spec: string, where: string): string {
	const [path] = spec.split("#");
	const r = include(spec, where)!;
	const lines = r.first === r.last ? `line ${r.first}` : `lines ${r.first}–${r.last}`;
	if (!path.endsWith(".md")) return `${fence(r.text, langOf(path))}\n\n\`${path}\`, ${lines}`;
	return r.text.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1");
}

// Links: another docs page → its Markdown copy; anything else on the site → absolute.
function links(md: string): string {
	return md.replace(/\]\((\/[^)\s]*)\)/g, (_, href: string) => {
		const [path, frag] = href.split("#");
		const page = /^\/docs\/(?!api\/)(.*?)\/?$/.exec(path);
		const to = page ? mdOf(page[1] ? (existsPage(page[1]) ? page[1] : `${page[1]}/index`) : "index") : path;
		return `](${ORIGIN}${to}${frag ? `#${frag}` : ""})`;
	});
}
const existsPage = (id: string) => {
	try {
		readFileSync(join(CONTENT, `${id}.md`));
		return true;
	} catch {
		return false;
	}
};

export function page(id: string): Page {
	const file = join(CONTENT, `${id}.md`);
	const [fm, src] = frontmatter(readFileSync(file, "utf8"), file);
	// An include written in inline code is about includes, not one.
	let body = src
		.split(/(`[^`\n]*`)/)
		.map((part, k) => (k % 2 ? part : part.replace(/<bongo:include src="([^"]+)"\s*\/>/g, (_, spec: string) => includeMd(spec, `content/docs/${id}.md`))))
		.join("")
		.replace(/<bongo:note label="([^"]*)">\n?([\s\S]*?)\n?<\/bongo:note>/g, (_, label: string, inner: string) =>
			`> **${label}.** ${inner.trim()}`.replace(/\n/g, "\n> "),
		);
	if (/<bongo:/.test(body.replace(/`[^`\n]*`/g, ""))) throw new Error(`llms: content/docs/${id}.md uses a bongo tag llms.ts doesn't know`);
	body = links(body).trim();
	return { id, url: urlOf(id), md: mdOf(id), title: fm.title ?? id, lede: fm.lede ?? "", eyebrow: fm.eyebrow ?? "", body, todo: fm.status === "todo" };
}

/** The docs pages in the sidebar's order, as the pager walks them. */
export function pages(): Page[] {
	const ids = ["index", ...NAV.flatMap((s) => s.items.flatMap((it) => (it.page ? [it.page, ...(it.children ?? [])] : [])))];
	return [...new Set(ids)].map(page).filter((p) => !p.todo);
}

const ledeText = (s: string) => s.replace(/`/g, "");
const pageMd = (p: Page) =>
	`# ${p.title}\n\n${p.lede ? `> ${p.lede}\n\n` : ""}${p.body}\n\nFrom ${ORIGIN}${p.url}. All of Cairn's docs for language models: ${ORIGIN}/llms.txt\n`;

export function llmsTxt(all: Page[]): string {
	const byId = new Map(all.map((p) => [p.id, p]));
	const entry = (p: Page) => `- [${p.title}](${ORIGIN}${p.md})${p.lede ? `: ${ledeText(p.lede)}` : ""}`;
	const sections = NAV.map((s) => {
		const items = s.items.flatMap((it) => (it.page ? [it.page, ...(it.children ?? [])] : [])).flatMap((id) => (byId.has(id) ? [entry(byId.get(id)!)] : []));
		return items.length ? `## ${s.section}\n\n${items.join("\n")}` : "";
	}).filter(Boolean);
	const index = byId.get("index");
	return `# Cairn

> Research into user interfaces where every action a person can take is a claim with a durable id and machine-checked evidence.

Apps are written in Lean 4: the state, the moves a person can make, the view and the layout are pure functions, and each move, flow and invariant is a claim with an id (\`cairn^N\`, written \`^N\`) that is never reused. Proofs live next to the code and are checked by Lean's kernel with only the standard axioms. What can't be proved is fuzzed, tested on the running app, captured on screen, or recorded as an assumption. A thin Swift host runs the app on macOS with AppKit and Metal and makes no decisions of its own. Cairn is research: it runs on macOS 27, and its APIs change between releases.

Every docs page below is Markdown, with its code samples included from the source that \`make check\` builds. The API reference is generated from the code and lists every claim with its evidence.
${index ? `\n- [Cairn docs](${ORIGIN}${index.md}): ${ledeText(index.lede)}` : ""}
- [All the docs in one file](${ORIGIN}/llms-full.txt)
- [API reference](${ORIGIN}/docs/api/llms.txt): every module, declaration and claim of the framework, with each claim's evidence

${sections.join("\n\n")}

## Optional

- [Milestones](${ORIGIN}/milestones/): what each milestone set out to show, with videos
- [Packages](${ORIGIN}/packages/): the package registry, with each version's claim ledger
- [Source](https://github.com/iamnbutler/cairn): the repository
`;
}

if (import.meta.main) {
	const out = resolve(process.argv[2] ?? "build/site");
	const all = pages();
	for (const p of all) {
		const file = join(out, p.md);
		mkdirSync(dirname(file), { recursive: true });
		writeFileSync(file, pageMd(p));
	}
	const full = `# Cairn docs\n\n> Every page of Cairn's developer docs, in the sidebar's order. The index is ${ORIGIN}/llms.txt.\n\n${all
		.map(pageMd)
		.join("\n---\n\n")}`;
	writeFileSync(join(out, "llms-full.txt"), full);
	writeFileSync(join(out, "llms.txt"), llmsTxt(all));
	console.log(`site: llms.txt, llms-full.txt (${(full.length / 1024).toFixed(0)} KB) and ${all.length} pages as Markdown`);
}

// The built site's internal links, checked the way Cloudflare serves them: _redirects first, then
// a static file (/a/ → a/index.html, /a → a.html or a/index.html), then the Worker's package
// pages (site/registry.js), rendered here and checked in turn. Every href, src, srcset and poster
// on every page, and each #fragment against the ids of the page it lands on.
//
//   bun tools/site/links.ts build/site            package pages from the registry the Worker reads
//                                                 (REGISTRY_URL in site/wrangler.jsonc)
//   bun tools/site/links.ts build/site --fixture  …from site/registry/fixture.json, offline
//
// /m/<key> is the media bucket, which only the deployed Worker reads; those links are listed, not
// checked. Exits 1 on any broken link.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { route } from "../../site/registry.js";

const args = process.argv.slice(2);
const root = args.find((a) => !a.startsWith("--")) ?? "build/site";
const REGISTRY_URL = /"REGISTRY_URL":\s*"([^"]+)"/.exec(readFileSync(new URL("../../site/wrangler.jsonc", import.meta.url), "utf8"))?.[1];
const env: Record<string, string> = args.includes("--fixture") || !REGISTRY_URL ? {} : { REGISTRY_URL };
const ORIGIN = "https://cairn.invalid";
const SELF = "cairn.iamnbutler.workers.dev";

// The Worker asks the registry afresh for every page; one run asks each URL once.
const realFetch = globalThis.fetch;
const answers = new Map<string, Promise<{ status: number; body: string; type: string }>>();
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
	const key = String(input instanceof Request ? input.url : input);
	if (!answers.has(key))
		answers.set(key, realFetch(input, init).then(async (r) => ({ status: r.status, body: await r.text(), type: r.headers.get("content-type") ?? "" })));
	const a = await answers.get(key)!;
	return new Response(a.status === 304 || a.status === 204 ? null : a.body, { status: a.status, headers: { "content-type": a.type } });
}) as typeof fetch;

const filesUnder = (dir: string): string[] =>
	readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? filesUnder(join(dir, n)) : [join(dir, n)]));

/** _redirects as [pattern, target] in order: the first match wins, as on Cloudflare. */
const redirects = existsSync(join(root, "_redirects"))
	? readFileSync(join(root, "_redirects"), "utf8")
			.split("\n")
			.map((l) => l.trim())
			.filter((l) => l && !l.startsWith("#"))
			.map((l) => l.split(/\s+/) as [string, string])
	: [];

function redirect(path: string): string | undefined {
	for (const [from, to] of redirects) {
		if (from.endsWith("*")) {
			const stem = from.slice(0, -1);
			if (path.startsWith(stem)) return to.replace(":splat", path.slice(stem.length));
		} else if (path === from) return to;
	}
	return undefined;
}

/** The static file a path serves, as Workers assets' auto-trailing-slash does. */
function asset(path: string): string | undefined {
	const p = decodeURIComponent(path);
	const tries = p.endsWith("/") ? [`${p}index.html`] : [p, `${p}.html`, `${p}/index.html`];
	return tries.map((t) => join(root, t)).find((f) => existsSync(f) && statSync(f).isFile());
}

type Page = { html: string; ids: Set<string> } | "file" | "media" | undefined;
const pages = new Map<string, Promise<Page>>();
const queue: string[] = [];

const idsOf = (html: string) => new Set([...html.matchAll(/\s(?:id|name)="([^"]+)"/g)].map((m) => m[1]));

/** What a path serves, following redirects; a page that renders HTML is queued for checking. */
function serve(path: string, hops = 0): Promise<Page> {
	if (!pages.has(path)) pages.set(path, resolvePath(path, hops));
	return pages.get(path)!;
}

async function resolvePath(path: string, hops: number): Promise<Page> {
	if (hops > 5) return undefined;
	const to = redirect(path);
	if (to) return to.startsWith("/") ? serve(new URL(to, ORIGIN).pathname, hops + 1) : "file";
	if (path.startsWith("/m/")) return "media";
	const file = asset(path);
	if (file) {
		if (!file.endsWith(".html")) return "file";
		const html = readFileSync(file, "utf8");
		queue.push(path);
		return { html, ids: idsOf(html) };
	}
	if (path.startsWith("/og/pkg/")) return serve("/og/packages.png", hops + 1);
	const res = await route(new Request(new URL(path, ORIGIN)), env);
	if (!res) return undefined;
	if (res.status >= 300 && res.status < 400) return serve(new URL(res.headers.get("location")!, ORIGIN).pathname, hops + 1);
	if (res.status !== 200) return undefined;
	const html = await res.text();
	queue.push(path);
	return { html, ids: idsOf(html) };
}

/** Every internal link on a page, resolved against it: [path, fragment]. */
function linksOf(page: string, html: string): [string, string][] {
	const base = new URL(page, ORIGIN);
	const raw: string[] = [];
	// Script and style bodies hold template strings that look like attributes.
	const markup = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, (s) => s.match(/^<script\b[^>]*>/i)![0]).replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "");
	for (const m of markup.matchAll(/\s(href|src|poster|srcset)="([^"]*)"/g)) {
		if (m[1] === "srcset") raw.push(...m[2].split(",").map((s) => s.trim().split(/\s+/)[0]));
		else raw.push(m[2]);
	}
	const out: [string, string][] = [];
	for (const r of raw) {
		const href = r.replace(/&amp;/g, "&");
		if (!href || /^(mailto|data|javascript|tel):/i.test(href)) continue;
		const url = new URL(href, base);
		// The site's own absolute URLs are internal too.
		if (url.origin !== ORIGIN && url.host !== SELF) continue;
		out.push([url.pathname, url.hash.slice(1)]);
	}
	return out;
}

const broken: string[] = [];
const media = new Set<string>();
const seed = filesUnder(root)
	.filter((f) => f.endsWith(".html"))
	.map((f) => "/" + f.slice(root.length + 1).replace(/(^|\/)index\.html$/, "$1"));
for (const p of seed) await serve(p);
// The homepage's scene reads its media from media.json.
for (const m of readFileSync(join(root, "media.json"), "utf8").matchAll(/"(\/[^"]+)"/g)) {
	const to = await serve(new URL(m[1], ORIGIN).pathname);
	if (to === "media") media.add(m[1]);
	else if (!to) broken.push(`/media.json → ${m[1]}`);
}
// Where each redirect lands, and the site's own URLs in the Markdown and text for language models.
for (const [from, to] of redirects) {
	if (to.startsWith("/") && !to.includes(":splat") && !(await serve(new URL(to, ORIGIN).pathname))) broken.push(`/_redirects ${from} → ${to}`);
}
for (const f of filesUnder(root).filter((f) => /\.(md|txt)$/.test(f))) {
	const text = readFileSync(f, "utf8");
	const page = "/" + f.slice(root.length + 1);
	for (const m of text.matchAll(new RegExp(`https://${SELF.replace(/\./g, "\\.")}(/[^)\\s>"]*)|\\]\\((/[^)\\s]*)\\)`, "g"))) {
		const url = new URL((m[1] ?? m[2]).replace(/[.,;:]+$/, ""), ORIGIN);
		if (!(await serve(url.pathname))) broken.push(`${page} → ${url.pathname}`);
	}
}

let checked = 0;
while (queue.length) {
	const page = queue.shift()!;
	const got = await serve(page);
	if (!got || typeof got === "string") continue;
	const links = linksOf(page, got.html);
	const targets = await Promise.all(links.map(([path]) => serve(path)));
	for (const [i, [path, frag]] of links.entries()) {
		checked++;
		const to = targets[i];
		if (to === "media") media.add(path);
		else if (!to) broken.push(`${page} → ${path}${frag ? `#${frag}` : ""}`);
		else if (frag && typeof to !== "string" && !to.ids.has(decodeURIComponent(frag))) broken.push(`${page} → ${path}#${frag} (no such id)`);
	}
}

const unique = [...new Set(broken)].sort();
const pageCount = [...pages.values()].length;
console.log(`links: ${checked} internal links on ${pageCount} paths, ${unique.length} broken; ${media.size} media links not checked (/m/, the R2 bucket)${env.REGISTRY_URL ? `; package pages from ${env.REGISTRY_URL}` : "; package pages from the fixture"}`);
for (const b of unique) console.log(`  ${b}`);
process.exit(unique.length ? 1 : 0);

// Helpers for the docs layout: Markdown in a lede, and the build's link checks.

// A short piece of Markdown as HTML: a lede's inline code and links, without its <p>.
export function inline(md: string, block = false): string {
	const html = (Bun.markdown.html(md ?? "", {}) as string).trim();
	return block ? html : html.replace(/^<p>/, "").replace(/<\/p>$/, "");
}

// Public pages link nothing on GitHub but the open issues that still describe missing work.
const ALLOWED_LINKS = [83, 84, 94, 95, 99].map((n) => `https://github.com/iamnbutler/cairn/issues/${n}`);

type Entry = { path: string; headings?: { id: string }[] };

// Every link in a page's HTML: to GitHub only for an allowed issue, to a docs page that exists, and
// to a heading that page has. Throws, which fails the build and names the page.
export function checkLinks(path: string, html: string, pages: Entry[]): string {
	const byPath = new Map(pages.map((p) => [p.path, p]));
	const errors: string[] = [];
	for (const [, href] of html.matchAll(/href="([^"]*)"/g)) {
		if (/^https?:\/\/(www\.)?github\.com\//.test(href) && !ALLOWED_LINKS.includes(href))
			errors.push(`links to ${href}: the repository is private, so public pages don't link to GitHub`);
		if (!href.startsWith("/docs/") || href.startsWith("/docs/api/")) continue;
		const [to, frag] = href.split("#");
		const page = byPath.get(to);
		if (!page) errors.push(`links to ${to}, which is not a docs page`);
		else if (frag && !page.headings?.some((h) => h.id === frag)) errors.push(`links to ${href}, and that page has no heading #${frag}`);
	}
	if (errors.length) throw new Error(`${path}:\n  ${errors.join("\n  ")}`);
	return "";
}

// --- The sidebar and the guide's pager, from data/nav.json ---------------------------------------

type NavItem = { page?: string; href?: string; title?: string; children?: string[] };
type NavSection = { section: string; items: NavItem[] };
type Page = Entry & { title: string; params: Record<string, unknown> };

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
// nav.json names pages by id: "guide/proving" is /docs/guide/proving/, "index" is /docs/.
const urlOf = (id: string) => (id === "index" ? "/docs/" : `/docs/${id.replace(/\/index$/, "")}/`);
const navTitle = (p: Page) => String(p.params.nav ?? p.title);
const todo = (p?: Page) => p?.params.status === "todo";

export function sidebar(path: string, pages: Page[], nav: NavSection[]): string {
	const byPath = new Map(pages.map((p) => [p.path, p]));
	const link = (href: string, title: string, on: boolean, isTodo: boolean) =>
		`<a href="${href}"${on ? ' class="on" aria-current="page"' : ""}>${esc(title)}${isTodo ? '<span class="todo">to do</span>' : ""}</a>`;
	return nav
		.map((s) => {
			const items = s.items.map((it) => {
				const url = it.page ? urlOf(it.page) : undefined;
				const p = url ? byPath.get(url) : undefined;
				if (it.page && !p) throw new Error(`data/nav.json lists ${it.page}, and there is no page at ${url}`);
				// The API reference is `cairn doc`'s, at /docs/api/; its page here only points there.
				const href = it.page === "reference/api" ? "/docs/api/" : it.href ?? url!;
				const head = link(href, it.title ?? (p ? navTitle(p) : it.href ?? ""), url === path, todo(p));
				const kids = (it.children ?? [])
					.map((id) => byPath.get(urlOf(id)))
					.filter((c): c is Page => !!c)
					.map((c) => `<li>${link(c.path, navTitle(c), c.path === path, todo(c))}</li>`)
					.join("");
				return `<li>${head}${kids ? `<ol>${kids}</ol>` : ""}</li>`;
			});
			return `<h2>${esc(s.section)}</h2><ul>${items.join("")}</ul>`;
		})
		.join("");
}

// The guide reads in order: its contents page, then each chapter.
export function pager(path: string, pages: Page[], nav: NavSection[]): string {
	const guide = nav.flatMap((s) => s.items).find((i) => i.page === "guide/index");
	if (!guide) throw new Error("data/nav.json has no guide/index, so the guide's chapters get no previous and next links");
	const order = ["guide/index", ...(guide.children ?? [])].map(urlOf);
	const i = order.indexOf(path);
	if (i < 0) return "";
	const byPath = new Map(pages.map((p) => [p.path, p]));
	const link = (url: string | undefined, rel: string, label: string) => {
		const p = url ? byPath.get(url) : undefined;
		return p ? `<a class="${rel}" rel="${rel}" href="${p.path}"><small>${label}</small>${esc(navTitle(p))}</a>` : "<span></span>";
	};
	return `<nav class="pager" aria-label="Chapters">${link(order[i - 1], "prev", "Previous")}${link(order[i + 1], "next", "Next")}</nav>`;
}

// --- Heading ids ----------------------------------------------------------------------------------

// scene.js's slugOf, on a heading's HTML. The site's anchors have always been made this way, so
// links shared before the move keep working; bongo's own ids ("the-hosts-…", "same-1") differ.
export const slugOf = (inner: string) =>
	inner
		.replace(/<[^>]*>/g, "")
		.replace(/&(amp|lt|gt|quot|#39|apos);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", apos: "'" })[e as string]!)
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-|-$/g, "") || "section";

type Heading = { level: number; id: string; text: string; html?: string };

// Gives h2–h4 our ids, in the HTML and in the headings bongo lists for $pages.
export function reId(content: string, headings: Heading[]): { content: string; headings: Heading[] } {
	const seen = new Set<string>();
	const ids = new Map<string, string>();
	content = content.replace(/<h([2-4]) id="([^"]*)">([\s\S]*?)<\/h\1>/g, (_, n, old, inner) => {
		const base = slugOf(inner);
		let id = base;
		for (let k = 2; seen.has(id); k++) id = `${base}-${k}`;
		seen.add(id);
		ids.set(old, id);
		return `<h${n} id="${id}">${inner}</h${n}>`;
	});
	return { content, headings: headings.map((h) => ({ ...h, id: ids.get(h.id) ?? h.id })) };
}

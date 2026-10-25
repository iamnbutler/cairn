// Helpers for the docs layout: Markdown in a lede, and the build's link checks.

// A short piece of Markdown as HTML: a lede's inline code and links, without its <p>.
export function inline(md: string, block = false): string {
	const html = (Bun.markdown.html(md ?? "", {}) as string).trim();
	return block ? html : html.replace(/^<p>/, "").replace(/<\/p>$/, "");
}

type Entry = { path: string; headings?: { id: string }[] };

// Every link in a page's HTML to the docs: to a page that exists, and to a heading that page has. Throws, which fails the build and names the page.
export function checkLinks(path: string, html: string, pages: Entry[]): string {
	const byPath = new Map(pages.map((p) => [p.path, p]));
	const errors: string[] = [];
	for (const [, href] of html.matchAll(/href="([^"]*)"/g)) {
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

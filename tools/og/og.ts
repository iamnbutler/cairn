// Link previews: the Open Graph and Twitter tags every page carries, and the card each one shows.
// The docs, the homepage and /milestones/ write their own tags and cards (site/web, built by
// bongo). These tags are stamped by tools/site/build.ts into the copied output of the map and
// cairn doc. The package pages (site/registry.js) run in the
// Worker and write them too. Each tag block names its card in an `<!-- og card {…} -->` comment;
// render.ts reads those to draw site/public/og/<name>.png.

export const ORIGIN = "https://cairn.iamnbutler.workers.dev";

// label: the small gold line above the title ("" for none); line: an optional sentence below it.
export type Card = { name: string; label: string; title: string; line?: string };

// The cards pages share. The package pages are drawn by the Worker from live data, so they share
// one; so do the API reference's module pages.
export const CARDS = {
	packages: { name: "packages", label: "Cairn", title: "Packages", line: "Libraries to build on and apps to run, with the claims they make." },
	api: { name: "api", label: "Cairn docs", title: "API reference", line: "Every module, declaration and claim, generated from the code." },
} satisfies Record<string, Card>;

// A card of its own for the page at `path`: /docs/guide/proving/ draws og/docs-guide-proving.png.
export const cardFor = (path: string, label: string, title: string): Card => ({
	name: path.replace(/\.html$/, "").replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "").toLowerCase() || "home",
	label,
	title,
});

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// The tags for one page, between <!-- og --> markers so stamp() can replace them.
export function ogTags(o: { title: string; description?: string; path: string; card: Card }): string {
	const c = o.card;
	return [
		"<!-- og -->",
		`<!-- og card ${JSON.stringify(c).replace(/--/g, "\\u002d\\u002d")} -->`,
		`<meta property="og:type" content="website">`,
		`<meta property="og:site_name" content="Cairn">`,
		`<meta property="og:title" content="${esc(o.title)}">`,
		o.description ? `<meta property="og:description" content="${esc(o.description)}">` : "",
		`<meta property="og:url" content="${ORIGIN}${o.path}">`,
		`<meta property="og:image" content="${ORIGIN}/og/${c.name}.png">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:image:alt" content="${esc(`${c.title}, over a pixel cairn on a meadow by a lake at night`)}">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		"<!-- /og -->",
	].filter(Boolean).join("\n");
}

// Every card named in a page's HTML.
export const cardsIn = (html: string): Card[] => [...html.matchAll(/<!-- og card (\{.*?\}) -->/g)].map((m) => JSON.parse(m[1]));

const unesc = (s: string) => s.replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" })[e as string]!);

// The page's own <title> and description.
export const titleOf = (html: string) => unesc(html.match(/<title>([^<]*)<\/title>/)?.[1] ?? "Cairn");

// A page's HTML with its tags in place: replaces an earlier <!-- og --> block, or adds one just
// before </head>. The title and description come from the page's own <title> and description.
export function stamp(html: string, path: string, card: Card): string {
	const description = html.match(/<meta name="description" content="([^"]*)">/)?.[1];
	const tags = ogTags({ title: titleOf(html), description: description && unesc(description), path, card });
	const block = /<!-- og -->[\s\S]*?<!-- \/og -->\n?/;
	if (block.test(html)) return html.replace(block, () => `${tags}\n`);
	return html.replace("</head>", () => `${tags}\n</head>`);
}

// Link previews: the Open Graph and Twitter tags every page carries, and the card each one shows.
// The cards are drawn by render.ts. The tags are written by the generators that own a page's
// head (tools/docs/build.ts), and stamped by tools/site/build.ts into the pages it doesn't
// generate: the homepage, /milestones/, and the copied output of the map and cairn doc. The
// package pages (site/registry.js) run in the Worker and write the same tags themselves.

export const ORIGIN = "https://cairn.iamnbutler.workers.dev";

export type Card = { label: string; title: string; line: string };

// One card per section; a page's own title and description go in its tags, and link previews
// show them beside the card.
export const CARDS = {
	home: { label: "", title: "Cairn", line: "Mac apps where every action is a claim, with machine-checked evidence." },
	milestones: { label: "Cairn", title: "Milestones", line: "What each one sets out to show, and the work as it lands." },
	docs: { label: "Cairn", title: "Docs", line: "Building a Mac app where everything a person can do is a claim." },
	packages: { label: "Cairn", title: "Packages", line: "Libraries to build on and apps to run, with the claims they make." },
	maps: { label: "Cairn", title: "Maps", line: "Every claim an app makes, with the evidence the build has for it." },
} satisfies Record<string, Card>;

export type CardName = keyof typeof CARDS;

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// The tags for one page, between <!-- og --> markers so stamp() can replace them.
export function ogTags(o: { title: string; description?: string; path: string; card: CardName }): string {
	const c = CARDS[o.card];
	const image = `${ORIGIN}/og/${o.card}.png`;
	return [
		"<!-- og -->",
		`<meta property="og:type" content="website">`,
		`<meta property="og:site_name" content="Cairn">`,
		`<meta property="og:title" content="${esc(o.title)}">`,
		o.description ? `<meta property="og:description" content="${esc(o.description)}">` : "",
		`<meta property="og:url" content="${ORIGIN}${o.path}">`,
		`<meta property="og:image" content="${image}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:image:alt" content="${esc(`${c.title}: a pixel cairn on a meadow by a lake at night`)}">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		"<!-- /og -->",
	].filter(Boolean).join("\n");
}

const unesc = (s: string) => s.replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" })[e as string]!);

// A page's HTML with its tags in place: replaces an earlier <!-- og --> block, or adds one just
// before </head>. The title and description come from the page's own <title> and description.
export function stamp(html: string, path: string, card: CardName): string {
	const title = unesc(html.match(/<title>([^<]*)<\/title>/)?.[1] ?? "Cairn");
	const description = html.match(/<meta name="description" content="([^"]*)">/)?.[1];
	const tags = ogTags({ title, description: description && unesc(description), path, card });
	const block = /<!-- og -->[\s\S]*?<!-- \/og -->\n?/;
	if (block.test(html)) return html.replace(block, `${tags}\n`);
	return html.replace("</head>", `${tags}\n</head>`);
}

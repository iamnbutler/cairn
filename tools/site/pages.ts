// The pages the site copies in from other generators: the maps (`make site-maps`, committed in
// site/public/map/) and the API reference (`cairn doc`, built for every deploy into
// build/site/docs/api/). Each gets a link preview card and the tags that name it: bongo draws
// the cards (site/web/lib/og.ts), and `make site-dist` stamps the tags, and the site's own font,
// into build/site, so the committed maps stay exactly what their generator wrote.
//
//   bun tools/site/pages.ts build/site   stamp the copied pages under a built site
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { FONT_LINKS } from "../../site/chrome.js";
import { CARDS, type Card, cardFor, stamp, titleOf } from "../og/og.ts";

const htmlUnder = (dir: string): string[] =>
	existsSync(dir) ? readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? htmlUnder(join(dir, n)) : n.endsWith(".html") ? [join(dir, n)] : [])) : [];

// A map page is titled "Counter map", or "Evidence · Counter map" below it.
const mapCard = (path: string, title: string): Card => {
	const [page, map] = title.includes(" · ") ? title.split(" · ") : ["", title];
	return page ? cardFor(path, map, page) : cardFor(path, "Maps", map.replace(/ map$/, ""));
};

/** The copied pages under a site root (site/public, or build/site), each with its card. */
export function copiedPages(root: string): { file: string; path: string; card: Card }[] {
	return ([["map", mapCard], ["docs/api", () => CARDS.api]] as [string, (path: string, title: string) => Card][]).flatMap(([dir, card]) =>
		htmlUnder(join(root, dir)).map((file) => {
			const path = "/" + relative(root, file).replace(/(^|\/)index\.html$/, "$1");
			return { file, path, card: card(path, titleOf(readFileSync(file, "utf8"))) };
		}),
	);
}

// The generators link Pixelify Sans from Google Fonts, so their output stands alone; on the site it
// comes from the site, like every other page's.
const GOOGLE_FONT = /<link rel="preconnect" href="https:\/\/fonts\.googleapis\.com">\n<link rel="preconnect" href="https:\/\/fonts\.gstatic\.com" crossorigin>\n<link href="https:\/\/fonts\.googleapis\.com\/css2\?family=Pixelify\+Sans[^"]*" rel="stylesheet">/;
const selfHostFont = (html: string) => {
	if (!GOOGLE_FONT.test(html)) throw new Error("site: a copied page doesn't link Pixelify Sans as the generators do");
	return html.replace(GOOGLE_FONT, () => FONT_LINKS);
};

if (import.meta.main) {
	const root = resolve(process.argv[2] ?? "build/site");
	const pages = copiedPages(root);
	for (const { file, path, card } of pages) writeFileSync(file, selfHostFont(stamp(readFileSync(file, "utf8"), path, card)));
	console.log(`site: stamped ${pages.length} copied pages' preview tags and font`);
}

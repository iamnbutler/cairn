// Link preview tags (tools/og/og.ts), between <!-- og --> markers, in the pages no generator here
// writes: the maps and API docs copied in by `make site-maps` and `make site-api`. The docs,
// the homepage, /milestones/ and the feed are bongo's (site/web).
//
//   bun tools/site/build.ts           stamp them (`make site-tags`)
//   bun tools/site/build.ts --check   fail if any is stale (`make site-tags-check`, part of
//                                     `make check` and run before `make site` deploys)
//
// Output depends only on the pages, never on the clock or git, so --check is stable. Needs only
// bun.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { CARDS, type Card, cardFor, stamp, titleOf } from "../og/og.ts";

const ROOT = resolve(import.meta.dir, "../..");
const PUBLIC = join(ROOT, "site/public");
const CHECK = process.argv.includes("--check");

// Link preview tags in the pages nothing else here writes.
const htmlUnder = (dir: string): string[] =>
	existsSync(dir) ? readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? htmlUnder(join(dir, n)) : n.endsWith(".html") ? [join(dir, n)] : [])) : [];
const stamped: [string, string][] = [
	...([
		// A map page is titled "Counter map", or "Evidence · Counter map" below it.
		["map", (path, title) => {
			const [page, map] = title.includes(" · ") ? title.split(" · ") : ["", title];
			return page ? cardFor(path, map, page) : cardFor(path, "Maps", map.replace(/ map$/, ""));
		}],
		["docs/api", () => CARDS.api],
	] as [string, (path: string, title: string) => Card][]).flatMap(([dir, card]) =>
		htmlUnder(join(PUBLIC, dir)).map((file): [string, string] => {
			const path = "/" + relative(PUBLIC, file).replace(/(^|\/)index\.html$/, "$1");
			const html = readFileSync(file, "utf8");
			return [relative(ROOT, file), stamp(html, path, card(path, titleOf(html)))];
		}),
	),
];

const out = stamped;
if (CHECK) {
	const stale = out.filter(([f, s]) => !existsSync(join(ROOT, f)) || readFileSync(join(ROOT, f), "utf8") !== s).map(([f]) => f);
	if (stale.length) {
		for (const f of stale) console.error(`site: ${f} is out of date`);
		console.error("site: run make site-tags and commit the result");
		process.exit(1);
	}
	console.log(`site: ${stamped.length} pages' preview tags are up to date`);
} else {
	for (const [f, s] of out) writeFileSync(join(ROOT, f), s);
	console.log(`site: wrote ${stamped.length} pages' preview tags`);
}

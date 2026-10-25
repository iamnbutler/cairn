// The link preview cards: site/public/og/<name>.png, 1200 × 630.
//
//   bun tools/og/render.ts           (`make og`) draw every card a page names that isn't drawn
//                                    yet or whose text changed, and delete cards no page names
//   bun tools/og/render.ts --all     redraw every card, after a change to the card or the scene
//   bun tools/og/render.ts --check   (`make og-check`, part of check) fail if a card is missing
//                                    or stale; needs no Chrome
//
// The cards are the ones in og.ts's CARDS and every `<!-- og card {…} -->` in site/public's
// HTML. Each is tools/og/card.html, the homepage's scene with the card's text on it, served next
// to site/public and screenshotted by headless Chrome. site/public/og/cards.json records the text
// each PNG was drawn with. The PNGs are committed. Needs bun, and Google Chrome to draw.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { CARDS, type Card, cardsIn } from "./og.ts";

const ROOT = resolve(import.meta.dir, "../..");
const PUBLIC = join(ROOT, "site/public");
const OUT = join(PUBLIC, "og");
const MANIFEST = join(OUT, "cards.json");
const CHECK = process.argv.includes("--check");
const ALL = process.argv.includes("--all");

// Every card, by name. Two pages naming one card must agree on its text.
const htmlUnder = (dir: string): string[] =>
	readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? htmlUnder(join(dir, n)) : n.endsWith(".html") ? [join(dir, n)] : []));
const cards = new Map<string, Card>(Object.values(CARDS).map((c) => [c.name, c]));
const errors: string[] = [];
for (const file of htmlUnder(PUBLIC)) {
	for (const c of cardsIn(readFileSync(file, "utf8"))) {
		const seen = cards.get(c.name);
		if (seen && JSON.stringify(seen) !== JSON.stringify(c)) errors.push(`${relative(ROOT, file)}: card ${c.name} differs from another page's`);
		cards.set(c.name, c);
	}
}
if (errors.length) {
	for (const e of errors) console.error(`og: ${e}`);
	process.exit(1);
}

const drawn: Record<string, Card> = existsSync(MANIFEST) ? JSON.parse(readFileSync(MANIFEST, "utf8")) : {};
const stale = [...cards.values()].filter((c) => ALL || JSON.stringify(drawn[c.name]) !== JSON.stringify(c) || !existsSync(join(OUT, `${c.name}.png`)));
const orphans = Object.keys(drawn).filter((name) => !cards.has(name));

if (CHECK) {
	for (const c of stale) console.error(`og: og/${c.name}.png is missing or out of date`);
	for (const name of orphans) console.error(`og: og/${name}.png is named by no page`);
	if (stale.length || orphans.length) {
		console.error("og: run make og and commit site/public/og/");
		process.exit(1);
	}
	console.log(`og: ${cards.size} cards up to date`);
	process.exit(0);
}

const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (stale.length && !existsSync(CHROME)) throw new Error(`og: no Chrome at ${CHROME}; set CHROME`);
const page = readFileSync(join(import.meta.dir, "card.html"));
const server = Bun.serve({
	port: 0,
	fetch(req) {
		const path = decodeURIComponent(new URL(req.url).pathname);
		if (path === "/card.html") return new Response(page, { headers: { "content-type": "text/html" } });
		const file = Bun.file(join(PUBLIC, path));
		return file.size ? new Response(file) : new Response("not found", { status: 404 });
	},
});

mkdirSync(OUT, { recursive: true });
for (const c of stale) {
	const q = new URLSearchParams({ label: c.label, title: c.title, line: c.line ?? "" });
	const png = join(OUT, `${c.name}.png`);
	// Not spawnSync: it would block the server Chrome is loading the card from.
	const run = Bun.spawn([
		CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
		"--window-size=1200,630", "--virtual-time-budget=5000", `--screenshot=${png}`,
		`http://localhost:${server.port}/card.html?${q}`,
	], { stdout: "ignore", stderr: "pipe" });
	if ((await run.exited) !== 0 || !existsSync(png)) throw new Error(`og: ${c.name}: ${await new Response(run.stderr).text()}`);
	drawn[c.name] = c;
	console.log(`og: drew og/${c.name}.png`);
}
server.stop(true);
for (const name of orphans) {
	rmSync(join(OUT, `${name}.png`), { force: true });
	delete drawn[name];
	console.log(`og: deleted og/${name}.png`);
}
const sorted = Object.fromEntries(Object.entries(drawn).sort(([a], [b]) => a.localeCompare(b)));
writeFileSync(MANIFEST, `${JSON.stringify(sorted, null, "\t")}\n`);
console.log(`og: ${stale.length} drawn, ${orphans.length} deleted, ${cards.size} in all`);

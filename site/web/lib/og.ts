// The cards of the pages bongo doesn't build: the maps and API docs copied into site/public (their
// tags stamped by tools/site/build.ts) and the package pages the Worker renders. Each is drawn by
// partials/og/card.hbs to og/<name>.png, the URL their tags name (content/og/cards.txt.hbs).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { CARDS, type Card, cardsIn } from "../../../tools/og/og.ts";

const ROOT = resolve(import.meta.dirname, "../../..");
const PUBLIC = join(ROOT, "site/public");

const htmlUnder = (dir: string): string[] =>
	readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? htmlUnder(join(dir, n)) : n.endsWith(".html") ? [join(dir, n)] : []));

// Every card, by name: og.ts's CARDS and every `<!-- og card {…} -->` in site/public's HTML. Two
// pages naming one card must agree on its text.
export function ogCards(): Card[] {
	const cards = new Map<string, Card>(Object.values(CARDS).map((c) => [c.name, c]));
	for (const file of htmlUnder(PUBLIC)) {
		for (const c of cardsIn(readFileSync(file, "utf8"))) {
			const seen = cards.get(c.name);
			if (seen && JSON.stringify(seen) !== JSON.stringify(c)) throw new Error(`${relative(ROOT, file)}: card ${c.name} differs from another page's`);
			cards.set(c.name, c);
		}
	}
	return [...cards.values()].sort((a, b) => a.name.localeCompare(b.name));
}

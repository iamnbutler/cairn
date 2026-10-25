// The cards of the pages bongo doesn't build: the maps and API docs copied into site/public (their
// tags stamped by tools/site/build.ts) and the package pages the Worker renders, one card for every
// version the registry holds when the site builds. Each is drawn by
// partials/og/card.hbs to og/<name>.png, the URL their tags name (content/og/cards.txt.hbs).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { CARDS, type Card, cardsIn } from "../../../tools/og/og.ts";
import { packageCards, source } from "../../registry.js";

const ROOT = resolve(import.meta.dirname, "../../..");
const PUBLIC = join(ROOT, "site/public");

const htmlUnder = (dir: string): string[] =>
	readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? htmlUnder(join(dir, n)) : n.endsWith(".html") ? [join(dir, n)] : []));

// The registry the Worker reads (wrangler.jsonc). A build that can't reach it draws no package
// cards, and the Worker serves the Packages card for every version until the next deploy.
const REGISTRY_URL = /"REGISTRY_URL":\s*"([^"]+)"/.exec(readFileSync(join(ROOT, "site/wrangler.jsonc"), "utf8"))?.[1];

async function registryCards(): Promise<Card[]> {
	try {
		return await packageCards(source({ REGISTRY_URL }));
	} catch (err) {
		console.warn(`og: no package cards, the registry didn't answer: ${err}`);
		return [];
	}
}

// Every card, by name: og.ts's CARDS, the package versions' and every `<!-- og card {…} -->` in
// site/public's HTML. Two pages naming one card must agree on its text.
export async function ogCards(): Promise<Card[]> {
	const cards = new Map<string, Card>([...Object.values(CARDS), ...(await registryCards())].map((c) => [c.name, c]));
	for (const file of htmlUnder(PUBLIC)) {
		for (const c of cardsIn(readFileSync(file, "utf8"))) {
			const seen = cards.get(c.name);
			if (seen && JSON.stringify(seen) !== JSON.stringify(c)) throw new Error(`${relative(ROOT, file)}: card ${c.name} differs from another page's`);
			cards.set(c.name, c);
		}
	}
	return [...cards.values()].sort((a, b) => a.name.localeCompare(b.name));
}

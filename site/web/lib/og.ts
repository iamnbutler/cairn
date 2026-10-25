// The cards of the pages bongo doesn't build: the API docs the site copies in
// (tools/site/pages.ts, which stamps their tags), and the package pages the Worker renders, one
// card for every version the registry holds when the site builds. Each is drawn by
// partials/og/card.ts to og/<name>.png, the URL their tags name (content/og/cards.txt.hbs).
import { readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { CARDS, type Card } from "../../../tools/og/og.ts";
import { copiedPages } from "../../../tools/site/pages.ts";
import { packageCards, source } from "../../registry.js";

const ROOT = resolve(import.meta.dirname, "../../..");

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

// Every card, by name: og.ts's CARDS, the package versions' and the copied pages' in site/public
// (the API reference isn't there yet; its pages share CARDS.api). Two pages naming one card must
// agree on its text.
export async function ogCards(): Promise<Card[]> {
	const cards = new Map<string, Card>([...Object.values(CARDS), ...(await registryCards())].map((c) => [c.name, c]));
	for (const { file, card } of copiedPages(join(ROOT, "site/public"))) {
		const seen = cards.get(card.name);
		if (seen && JSON.stringify(seen) !== JSON.stringify(card)) throw new Error(`${relative(ROOT, file)}: card ${card.name} differs from another page's`);
		cards.set(card.name, card);
	}
	return [...cards.values()].sort((a, b) => a.name.localeCompare(b.name));
}

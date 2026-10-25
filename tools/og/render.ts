// The link preview cards: site/public/og/<card>.png, 1200 × 630, one per section of the site.
//
//   bun tools/og/render.ts    (`make og`) redraw every card in og.ts's CARDS
//
// Each card is tools/og/card.html, the homepage's scene with the section's name on it, served
// next to site/public and screenshotted by headless Chrome. The cards are committed; redraw them
// when the scene or a card's text changes. Needs bun and Google Chrome.
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { CARDS } from "./og.ts";

const ROOT = resolve(import.meta.dir, "../..");
const PUBLIC = join(ROOT, "site/public");
const OUT = join(PUBLIC, "og");
const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (!existsSync(CHROME)) throw new Error(`og: no Chrome at ${CHROME}; set CHROME`);

const card = readFileSync(join(import.meta.dir, "card.html"));
const server = Bun.serve({
	port: 0,
	fetch(req) {
		const path = decodeURIComponent(new URL(req.url).pathname);
		if (path === "/card.html") return new Response(card, { headers: { "content-type": "text/html" } });
		const file = Bun.file(join(PUBLIC, path));
		return file.size ? new Response(file) : new Response("not found", { status: 404 });
	},
});

mkdirSync(OUT, { recursive: true });
for (const [name, c] of Object.entries(CARDS)) {
	const q = new URLSearchParams({ label: c.label, title: c.title, line: c.line });
	const png = join(OUT, `${name}.png`);
	// Not spawnSync: it would block the server Chrome is loading the card from.
	const run = Bun.spawn([
		CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
		"--window-size=1200,630", "--virtual-time-budget=5000", `--screenshot=${png}`,
		`http://localhost:${server.port}/card.html?${q}`,
	], { stdout: "ignore", stderr: "pipe" });
	if ((await run.exited) !== 0 || !existsSync(png)) throw new Error(`og: ${name}: ${await new Response(run.stderr).text()}`);
	console.log(`og: wrote site/public/og/${name}.png`);
}
server.stop(true);

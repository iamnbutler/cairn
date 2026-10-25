// The background of the link preview cards: site/web/assets/og/scene.png, 1200 × 630.
//
//   bun tools/og/scene.ts   (`make og-scene`) redraw it, after a change to the homepage's scene
//
// scene.html is the homepage's scene with a shade over the sky, served next to site/public and
// screenshotted by headless Chrome. The cards' text is drawn on it by satori when bongo builds
// (site/web/partials/og/card.hbs); this is the only part that needs a browser, because the scene
// is a canvas. The PNG is committed. Needs bun and Google Chrome.
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "../..");
const PUBLIC = join(ROOT, "site/public");
const OUT = join(ROOT, "site/web/assets/og/scene.png");
const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (!existsSync(CHROME)) throw new Error(`og: no Chrome at ${CHROME}; set CHROME`);

const page = readFileSync(join(import.meta.dir, "scene.html"));
const server = Bun.serve({
	port: 0,
	fetch(req) {
		const path = decodeURIComponent(new URL(req.url).pathname);
		if (path === "/scene.html") return new Response(page, { headers: { "content-type": "text/html" } });
		const file = Bun.file(join(PUBLIC, path));
		return file.size ? new Response(file) : new Response("not found", { status: 404 });
	},
});
// Not spawnSync: it would block the server Chrome is loading the page from.
const run = Bun.spawn([
	CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
	"--window-size=1200,630", "--virtual-time-budget=5000", `--screenshot=${OUT}`,
	`http://localhost:${server.port}/scene.html`,
], { stdout: "ignore", stderr: "pipe" });
if ((await run.exited) !== 0 || !existsSync(OUT)) throw new Error(`og: ${await new Response(run.stderr).text()}`);
server.stop(true);
console.log("og: drew site/web/assets/og/scene.png");

// The site on Nexthub Pages too: https://cairn.iamnbutler.pages.nexthub.sh, from build/site
// (make site-dist). Nexthub serves static files only, so what the Worker does stays with the
// Cloudflare site: media keys (/m/) in the JSON data become absolute URLs there (the Worker
// allows any origin on them), and every internal link the build doesn't hold as a file, the
// package pages chiefly, redirects there. Nexthub redirects match exact paths, so _redirects'
// splats don't carry over. The app is `cairn` in nexthub.sh/iamnbutler/cairn-site, a public
// repo holding only its definition.
//
//   bun tools/site/nexthub.ts build/site
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = process.argv[2] ?? "build/site";
const ORIGIN = "https://cairn.iamnbutler.workers.dev";
const REPO = "https://api.nexthub.sh/repos/iamnbutler/cairn-site";
const API = `${REPO}/applications/cairn`;
const SKIP = new Set(["_headers", "_redirects"]);
const TYPES: Record<string, string> = {
	html: "text/html;charset=utf-8", css: "text/css;charset=utf-8", js: "text/javascript;charset=utf-8",
	json: "application/json;charset=utf-8", xml: "application/xml;charset=utf-8", txt: "text/plain;charset=utf-8",
	md: "text/markdown;charset=utf-8", svg: "image/svg+xml", png: "image/png", jpg: "image/jpeg", webp: "image/webp",
	ico: "image/x-icon", woff2: "font/woff2", mp4: "video/mp4", webmanifest: "application/manifest+json",
};

const token = execFileSync("git", ["credential-osxkeychain", "get"], { input: "protocol=https\nhost=nexthub.sh\n\n" })
	.toString().match(/^password=(.*)$/m)?.[1];
if (!token) throw new Error("no nexthub.sh token in the Keychain");

const walk = (dir: string): string[] =>
	readdirSync(dir).flatMap((n) => (statSync(join(dir, n)).isDirectory() ? walk(join(dir, n)) : [join(dir, n)]));
const files = walk(ROOT).map((f) => relative(ROOT, f)).filter((p) => !SKIP.has(p)).sort();
const have = new Set(files);

const bodies = new Map<string, Buffer>();
for (const p of files) {
	let b = readFileSync(join(ROOT, p));
	if (p.endsWith(".json")) b = Buffer.from(b.toString().replaceAll('"/m/', `"${ORIGIN}/m/`));
	bodies.set(p, b);
}

// Links the build has no file for go to the Cloudflare site, which renders them.
const missing = new Set<string>();
for (const p of files.filter((p) => p.endsWith(".html"))) {
	for (const [, href] of bodies.get(p)!.toString().matchAll(/href="(\/[^"#?]*)/g)) {
		const path = href.endsWith("/") ? `${href}index.html` : href;
		if (!have.has(path.slice(1)) && !have.has(`${path.slice(1)}/index.html`) && !path.startsWith("/m/")) missing.add(href);
	}
}
const redirects = [...missing].sort().map((from) => ({ from, to: ORIGIN + from, status: 302 }));

const sha = (b: Buffer) => createHash("sha256").update(b).digest("hex");
const assets = files.map((path) => {
	const b = bodies.get(path)!;
	const ext = path.split(".").pop()!;
	return { path, size: b.length, sha256: sha(b), content_type: TYPES[ext] ?? "application/octet-stream" };
});
const manifest = {
	version: 1, kind: "pages", assets, modules: [],
	routes: {
		headers: [{ path: "/fonts/*", values: [{ name: "cache-control", value: "public, max-age=31536000, immutable" }] }],
		redirects,
	},
};

const auth = { authorization: `Bearer ${token}` };
async function call(url: string, init: RequestInit) {
	for (let attempt = 0; ; attempt++) {
		const r = await fetch(url, init);
		if ((r.status === 429 || r.status === 503 || r.status === 422) && attempt < 5) {
			await Bun.sleep(1000 * 2 ** attempt);
			continue;
		}
		const text = await r.text();
		if (!r.ok) throw new Error(`${init.method} ${url}: ${r.status} ${text.slice(0, 400)}`);
		return { status: r.status, body: text ? JSON.parse(text) : {} };
	}
}

let res = await call(`${API}/deployments?target=production`, {
	method: "POST", headers: { ...auth, "content-type": "application/json" }, body: JSON.stringify({ manifest }),
});
const byHash = new Map(assets.map((a) => [a.sha256, a.path]));
while (res.status === 202) {
	const id = res.body.id ?? res.body.deployment?.id;
	const want: string[] = res.body.missing ?? [];
	// At most 1,000 files and 64 MiB a request.
	let form = new FormData(), n = 0, bytes = 0;
	for (const h of want) {
		const b = bodies.get(byHash.get(h)!)!;
		if (n && (n === 1000 || bytes + b.length > 60 * 2 ** 20)) break;
		form.append(h, new Blob([b]), h);
		n++; bytes += b.length;
	}
	res = await call(`${REPO}/deployments/${id}/files`, { method: "POST", headers: auth, body: form });
}
console.log(`nexthub: ${assets.length} files, ${redirects.length} redirects to ${ORIGIN}`);
console.log(JSON.stringify(res.body.urls ?? res.body, null, 1).slice(0, 600));

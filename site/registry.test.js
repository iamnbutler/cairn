// The package pages (registry.js), against the fixture and a fake registry. `make registry-check`.
import { afterEach, describe, expect, test } from "bun:test";
import { route } from "./registry.js";

const ORIGIN = "https://cairn.test";
// The docs placeholder must not reach for any asset, so every asset fetch fails the test.
const assets = {
	async fetch(url) {
		throw new Error(`fetched asset ${url}`);
	},
};
const PLACEHOLDER = "will be built by the registry from its source, like docs.rs. Not yet.";
const get = (path, env = { ASSETS: assets }) => route(new Request(ORIGIN + path), env);

describe("with the fixture", () => {
	test("lists libraries, and apps under their own tab, and says the data is a sample", async () => {
		const res = await get("/packages/");
		expect(res.status).toBe(200);
		const text = await res.text();
		expect(text).toContain("Sample data");
		expect(text).toContain('<a href="/packages/" class="on" aria-current="page">Libraries <span class="n">1</span></a>');
		expect(text).toContain('<a href="/packages/?tab=apps">Apps <span class="n">1</span></a>');
		expect(text).toContain('href="/docs/cairn/0.1.2/"');
		expect(text).toContain('<span class="owner">by iamnbutler</span>');
		expect(text).not.toContain('href="/packages/yap/"');
		const apps = await (await get("/packages/?tab=apps")).text();
		expect(apps).toContain('<a href="/packages/?tab=apps" class="on" aria-current="page">Apps <span class="n">1</span></a>');
		expect(apps).toContain('href="/packages/yap/"');
		expect(apps).toContain('href="/docs/yap/0.1.0/"');
		expect(apps).not.toContain('href="/packages/cairn/"');
	});

	test("redirects to the slash form", async () => {
		expect((await get("/packages")).headers.get("location")).toBe(`${ORIGIN}/packages/`);
		expect((await get("/packages/cairn")).headers.get("location")).toBe(`${ORIGIN}/packages/cairn/`);
		expect((await get("/docs/cairn/0.1.0")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.0/`);
	});

	test("shows the latest release with its ledger", async () => {
		const text = await (await get("/packages/cairn/")).text();
		expect(text).toContain("<dd>0.1.2</dd>");
		expect(text).toContain("<dt>Owner</dt><dd>iamnbutler</dd>");
		expect(text).toContain('<tr id="301" class="moved">');
		expect(text).toContain("<code>cairn^1</code>");
	});

	test("shows an older version and its own ledger", async () => {
		const text = await (await get("/packages/cairn/0.1.0/")).text();
		expect(text).toContain("<dd>0.1.0</dd>");
		expect(text).toContain('<tr id="301" class="moved">');
		expect(text).toContain("<td>moved:yap</td>");
		expect(text).toContain('<a href="/docs/cairn/0.1.0/">Docs for 0.1.0</a>');
	});

	test("links a package's dependencies", async () => {
		const text = await (await get("/packages/yap/")).text();
		expect(text).toContain('<a href="/packages/cairn/"><code>cairn</code></a> <code>^0.1.1</code>');
		expect(text).toContain("<code>yap^301</code>");
	});

	test("tells a library, which apps depend on, from an app, which they build", async () => {
		const lib = await (await get("/packages/cairn/")).text();
		expect(lib).toContain("<dt>Kind</dt><dd>Library</dd>");
		const app = await (await get("/packages/yap/")).text();
		expect(app).toContain("<dt>Kind</dt><dd>App</dd>");
		expect(app).toContain('<h2 id="use">Build it</h2>');
	});

	test("gives no install lines, as nothing resolves from a registry yet", async () => {
		for (const name of ["cairn", "yap"]) {
			const text = await (await get(`/packages/${name}/`)).text();
			expect(text).toContain("Not from a registry yet");
			expect(text).toContain('<a href="/docs/book/first-app/#an-app-in-its-own-repository">');
			expect(text).not.toContain(`cairn add ${name}@`);
			expect(text).not.toContain("cairn build --release");
			expect(text).not.toContain("git clone");
			expect(text).not.toContain("[[require]]");
		}
	});

	test("answers a version's docs with the placeholder, in the site's style", async () => {
		for (const path of ["/docs/cairn/0.1.2/", "/docs/cairn/0.1.1/", "/docs/cairn/0.1.0/", "/docs/yap/0.1.0/"]) {
			const res = await get(path);
			expect(res.status).toBe(200);
			expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
			const text = await res.text();
			expect(text).toContain(PLACEHOLDER);
			expect(text).toContain('<link rel="stylesheet" href="/docs/docs.css">');
			expect(text).toContain('<span class="todo">not yet</span>');
		}
		expect(await (await get("/docs/cairn/0.1.0/")).text()).toContain('href="/packages/cairn/0.1.0/"');
	});

	test("sends every path under a version, and latest, to the placeholder", async () => {
		expect((await get("/docs/cairn/0.1.0/Cairn.UI.html")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.0/`);
		expect((await get("/docs/cairn/0.1.0/a/b/index.html")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.0/`);
		expect((await get("/docs/cairn/latest/Cairn.UI.html")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.2/`);
		expect((await get("/docs/cairn/")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.2/`);
	});

	test("leaves everything else to the static site", async () => {
		for (const path of [
			"/packages/nope/",
			"/packages/Cairn/",
			"/packages/cairn/9.9.9/",
			"/packages/cairn/0.1.0/extra/",
			"/docs/nope/1.0.0/",
			"/docs/cairn/9.9.9/",
			"/docs/cairn/0.1.0/../../index.html",
			"/docs/cairn/not-a-version/",
			"/docs/docs.css",
			"/",
		]) {
			expect(await get(path)).toBeUndefined();
		}
	});
});

describe("with a registry", () => {
	const real = globalThis.fetch;
	afterEach(() => {
		globalThis.fetch = real;
	});

	// The one public registry: a URL and no token.
	const env = { ASSETS: assets, REGISTRY_URL: "https://reg.test/" };
	const release = {
		version: "1.2.0",
		revision: "a".repeat(40),
		tag: "v1.2.0",
		date: "2026-10-24T00:00:00.000Z",
		toolchain: "leanprover/lean4:v4.35.0",
		yanked: false,
		publisher: "carl",
		description: "Says <b>hello</b>",
		license: "MIT",
		dependencies: {},
		claims: { active: 1, retired: 0, moved: 0 },
		docs: true,
		swift: true,
	};
	const answers = {
		"/api/v1/packages?per_page=100": {
			data: {
				items: [
					{ name: "hello", fullName: "carl/hello", version: "1.2.0", description: "Says <b>hello</b>" },
					{ name: "wave", fullName: "acme/wave", kind: "bin", version: "0.3.0", description: "Waves" },
				],
			},
		},
		// A name has one owner, which /api/v1/names/<name> answers; an unknown name is a 404.
		"/api/v1/names/hello": { data: { owner: "carl", name: "hello" } },
		"/api/v1/names/wave": { data: { owner: "acme", name: "wave" } },
		"/api/v1/names/pure": { data: { owner: "carl", name: "pure" } },
		"/api/v1/packages/carl/hello": { data: { name: "hello", fullName: "carl/hello", owner: "carl", description: "Says <b>hello</b>" } },
		"/api/v1/packages/acme/wave": { data: { name: "wave", fullName: "acme/wave", owner: "acme", kind: "bin", description: "Waves" } },
		"/api/v1/packages/acme/wave/versions?yanked=true": { data: [{ ...release, version: "0.3.0", kind: "bin", tag: "v0.3.0", publisher: "dee" }] },
		"/api/v1/packages/carl/hello/versions?yanked=true": { data: [release] },
		// A pure-Lean library, from a registry that may not say `swift` at all.
		"/api/v1/packages/carl/pure": { data: { name: "pure", fullName: "carl/pure", owner: "carl", description: "Lean only" } },
		"/api/v1/packages/carl/pure/versions?yanked=true": { data: [{ ...release, version: "0.1.0", tag: "v0.1.0", swift: undefined }] },
		"/api/v1/packages/carl/hello/versions/1.2.0/claims": {
			data: { claims: [{ id: 1, kind: "move", status: "active", statement: "-", title: "Wave" }] },
		},
	};
	const seen = [];
	const paths = [];
	const fake = async (url, init) => {
		seen.push(new Headers(init?.headers).get("authorization"));
		const path = url.replace("https://reg.test", "");
		paths.push(path);
		// A registry that still served uploaded docs: the site must never ask for them.
		if (path.includes("/docs")) return new Response("<script>alert(document.cookie)</script>", { headers: { "content-type": "text/html" } });
		if (path in answers) return Response.json(answers[path]);
		return Response.json({ error: { status: 404, message: "Not found" } }, { status: 404 });
	};

	test("renders from the API with each package's owner, escapes what publishers wrote, and sends no token", async () => {
		globalThis.fetch = fake;
		const list = await (await get("/packages/", env)).text();
		expect(list).not.toContain("Sample data");
		expect(list).toContain("Says &lt;b&gt;hello&lt;/b&gt;");
		// A registry from before kinds says none: a library.
		expect(list).toContain("Libraries <span class=\"n\">1</span>");
		expect(list).not.toContain('href="/packages/wave/"');
		expect(list).toContain('<span class="owner">by carl</span>');
		const apps = await (await get("/packages/?tab=apps", env)).text();
		expect(apps).toContain('href="/packages/wave/"');
		expect(apps).not.toContain('href="/packages/hello/"');
		expect(apps).toContain('<span class="owner">by acme</span>');
		const page = await (await get("/packages/hello/", env)).text();
		expect(page).toContain("<code>hello^1</code>");
		expect(page).toContain('<a href="/docs/hello/1.2.0/">Docs for 1.2.0</a>');
		expect(page).toContain("cairn add hello@^1.2.0");
		expect(page).toContain('version = "^1.2.0"');
		expect(page).toContain('.package(url: "https://reg.test/git/carl/hello.git", from: "1.2.0")');
		expect(page).toContain("the lakefile and SwiftPM lines");
		expect(page).toContain("<dt>Owner</dt><dd>carl</dd>");
		expect(page).toContain('scope = "carl"');
		expect(page).not.toContain("Not from a registry yet");
		const app = await (await get("/packages/wave/", env)).text();
		expect(app).toContain("<dt>Owner</dt><dd>acme</dd>");
		expect(app).toContain("git clone https://reg.test/git/acme/wave.git");
		expect(seen.length).toBeGreaterThan(0);
		expect(seen.every((auth) => auth === null)).toBe(true);
		expect(paths).not.toContain("/config.json");
		expect(paths.filter((path) => path.includes("?q="))).toEqual([]);
	});

	test("prints a Package.swift line only for a version with a Swift package", async () => {
		globalThis.fetch = fake;
		const pure = await (await get("/packages/pure/", env)).text();
		expect(pure).toContain("cairn add pure@^0.1.0");
		expect(pure).toContain('scope = "carl"');
		expect(pure).toContain("the lakefile line");
		expect(pure).not.toContain(".package(url:");
		expect(pure).not.toContain("<code>Package.swift</code>");
	});

	test("never fetches, proxies or renders docs from the registry", async () => {
		globalThis.fetch = fake;
		paths.length = 0;
		const doc = await get("/docs/hello/1.2.0/", env);
		expect(doc.status).toBe(200);
		expect(doc.headers.get("content-type")).toBe("text/html; charset=utf-8");
		const text = await doc.text();
		expect(text).toContain(PLACEHOLDER);
		expect(text).not.toContain("<script>alert");
		expect((await get("/docs/hello/1.2.0/index.html", env)).headers.get("location")).toBe(`${ORIGIN}/docs/hello/1.2.0/`);
		expect((await get("/docs/hello/latest/", env)).headers.get("location")).toBe(`${ORIGIN}/docs/hello/1.2.0/`);
		expect(await get("/docs/hello/9.9.9/", env)).toBeUndefined();
		expect(paths.length).toBeGreaterThan(0);
		expect(paths.filter((path) => path.includes("/docs"))).toEqual([]);
		expect(await get("/packages/other/", env)).toBeUndefined();
	});
});

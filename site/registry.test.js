// The package pages (registry.js), against the fixture and a fake registry. `make registry-check`.
import { afterEach, describe, expect, test } from "bun:test";
import { route } from "./registry.js";
// Counter's claims and one of the trusted base's, as the registry serves a claims export.
import sample from "./registry/export-sample.json";

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
		expect(text).toContain('href="/docs/cairn/0.2.1/"');
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
		expect(text).toContain("<dd>0.2.1</dd>");
		expect(text).toContain("<dt>Owner</dt><dd>iamnbutler</dd>");
		expect(text).toContain('<tr id="301" class="moved">');
		expect(text).toContain("<code>cairn^1</code>");
	});

	test("shows what changed since the previous version", async () => {
		const text = await (await get("/packages/cairn/0.2.0/")).text();
		expect(text).toContain('<h2 id="changes">What changed in 0.2.0</h2>');
		expect(text).toContain('<a href="/packages/cairn/0.1.3/">0.1.3</a>');
		expect(text).toContain('<tr class="active"><td><a href="#225"><code>cairn^225</code></a></td><td>new</td>');
		expect(text).toContain('<tr class="retired"><td><a href="#213"><code>cairn^213</code></a></td><td>retired</td>');
		expect(text).not.toContain('<a href="#1"><code>cairn^1</code></a>');
		const first = await (await get("/packages/cairn/0.1.0/")).text();
		expect(first).not.toContain('id="changes"');
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
			expect(text).toContain('<a href="/docs/guide/first-app/#an-app-in-its-own-repository">');
			expect(text).not.toContain(`cairn add ${name}@`);
			expect(text).not.toContain("cairn build --release");
			expect(text).not.toContain("git clone");
			expect(text).not.toContain("[[require]]");
		}
	});

	test("answers a version's docs with the placeholder, in the site's style", async () => {
		for (const path of ["/docs/cairn/0.2.1/", "/docs/cairn/0.2.0/", "/docs/cairn/0.1.3/", "/docs/cairn/0.1.2/", "/docs/cairn/0.1.1/", "/docs/cairn/0.1.0/", "/docs/yap/0.1.0/"]) {
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
		expect((await get("/docs/cairn/latest/Cairn.UI.html")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.2.1/`);
		expect((await get("/docs/cairn/")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.2.1/`);
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
	// Counter's ledger: the sample's claims, ^6 retired, and ^301 moved to another package.
	const counterLedger = [
		...sample.claims.map((c) => ({ id: c.id, kind: c.kind, status: c.retired ? "retired" : "active", statement: c.statement, title: c.title })),
		{ id: 301, kind: "move", status: "moved:yap", statement: "-", title: "Dictate" },
	];
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
		// A package with a claims export, and a version before it without one.
		"/api/v1/names/counter": { data: { owner: "carl", name: "counter" } },
		"/api/v1/packages/carl/counter": { data: { name: "counter", fullName: "carl/counter", owner: "carl", description: "Counts" } },
		"/api/v1/packages/carl/counter/versions?yanked=true": {
			data: [
				{ ...release, version: "0.2.0", tag: "v0.2.0", export: true },
				{ ...release, version: "0.1.0", tag: "v0.1.0", export: false },
			],
		},
		"/api/v1/packages/carl/counter/versions/0.2.0/claims": { data: { claims: counterLedger } },
		"/api/v1/packages/carl/counter/versions/0.1.0/claims": { data: { claims: counterLedger.filter((c) => c.id < 900) } },
		"/api/v1/packages/carl/counter/versions/0.2.0/claims/export": { data: { ...sample, version: "0.2.0" } },
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

	test("renders a version's claim pages from its export: places, evidence, steps and source", async () => {
		globalThis.fetch = fake;
		const res = await get("/packages/counter/claims/", env);
		expect(res.status).toBe(200);
		const text = await res.text();
		// Grouped by place: the Counter window holds its moves and both flows (a flow's place is
		// its first step's).
		expect(text).toContain('<section class="place" id="place-3">');
		const place = text.slice(text.indexOf('id="place-3"'), text.indexOf("</section>", text.indexOf('id="place-3"')));
		for (const id of [1, 2, 4, 5]) expect(place).toContain(`<tr id="${id}" `);
		expect(text).toContain('<tr id="1" class="proved"><td><a href="/packages/counter/claims/1/"><code>counter^1</code></a></td>');
		expect(text).toContain('<tr id="6" class="retired">');
		// Assumptions by module: the app's own apart from the trusted base.
		expect(text).toContain('<section id="assumptions">');
		expect(text).toContain("<h3><code>Cairn.Fuzz.Trusted.Claims</code></h3>");
		expect(text).toContain('<tr id="7" class="assumed">');
		expect(text).toContain('<a href="/packages/yap/claims/301/"><code>yap^301</code></a>');
		expect(text).toContain("Not shown yet:</strong> fuzzed, tested and seen");
		expect(text).not.toContain("ledger only");

		const move = await (await get("/packages/counter/claims/2/", env)).text();
		expect(move).toContain("Press Reset.");
		expect(move).toContain("The count is zero, and Reset disappears.");
		expect(move).toContain('<a href="/packages/counter/claims/3/">Counter window</a>');
		expect(move).toContain("<code>Examples.Counter.reset.press.sound</code>");
		expect(move).toContain('<span class="chip ev proved">proved</span>');
		expect(move).toContain("lean/Examples/Counter.lean:");
		for (const k of ["fuzzed", "tested", "seen"]) expect(move).toContain(`<span class="chip ev later">${k}</span></td><td colspan="2">Not shown yet`);

		const flow = await (await get("/packages/counter/claims/5/", env)).text();
		expect(flow).toContain('<ol class="steps">');
		expect(flow).toContain('<span class="trigger">press</span> on <a href="/packages/counter/claims/2/"><code>^2</code></a> Reset</li>');

		const window = await (await get("/packages/counter/claims/3/", env)).text();
		expect(window).toContain('<h2 id="in">In this place</h2>');
		expect(window).toContain('<tr id="4" ');

		const trusted = await (await get("/packages/counter/claims/901/", env)).text();
		expect(trusted).toContain('<span class="chip ev assumed">assumed</span>');
		expect(trusted).toContain("the trusted-base fuzzer's check <code>");

		const retired = await (await get("/packages/counter/0.2.0/claims/6/", env)).text();
		expect(retired).toContain("The runtime owns press tracking");
		expect(retired).toContain('href="/packages/counter/0.2.0/claims/#6"');
		const moved = await (await get("/packages/counter/claims/301/", env)).text();
		expect(moved).toContain('Now <a href="/packages/yap/claims/301/">');
	});

	test("falls back to the ledger for a version without an export, and asks for none it says it lacks", async () => {
		globalThis.fetch = fake;
		paths.length = 0;
		const text = await (await get("/packages/counter/0.1.0/claims/", env)).text();
		expect(text).toContain("This version also has no claims export");
		expect(text).toContain('<tr id="1" class="ledger"><td><a href="/packages/counter/0.1.0/claims/1/">');
		expect(text).toContain("Which claims are in this place is in the claims export");
		const one = await (await get("/packages/counter/0.1.0/claims/2/", env)).text();
		expect(one).toContain('<span class="chip ev ledger">ledger only</span>');
		// The live registry from before exports answers 404, and the pages still render.
		const hello = await (await get("/packages/hello/claims/1/", env)).text();
		expect(hello).toContain("<code>hello^1</code>");
		expect(paths).toContain("/api/v1/packages/carl/hello/versions/1.2.0/claims/export");
		expect(paths.filter((p) => p.endsWith("/0.1.0/claims/export"))).toEqual([]);
	});

	test("links the package page to its claim pages, and leaves other paths alone", async () => {
		globalThis.fetch = fake;
		const pkg = await (await get("/packages/counter/0.2.0/", env)).text();
		expect(pkg).toContain('<a href="/packages/counter/0.2.0/claims/">Claims in 0.2.0</a>');
		expect(pkg).toContain('<a href="/packages/counter/0.2.0/claims/2/"><code>counter^2</code></a>');
		expect((await get("/packages/counter/claims", env)).headers.get("location")).toBe(`${ORIGIN}/packages/counter/claims/`);
		expect((await get("/packages/counter/claims/2", env)).headers.get("location")).toBe(`${ORIGIN}/packages/counter/claims/2/`);
		for (const path of ["/packages/counter/claims/999/", "/packages/counter/claims/x/", "/packages/counter/claims/2/place.svg", "/packages/counter/9.9.9/claims/", "/packages/nope/claims/"]) {
			expect(await get(path, env)).toBeUndefined();
		}
	});

	test("escapes every field of an export", async () => {
		const evil = { ...sample, claims: sample.claims.map((c) => (c.id === 1 ? { ...c, title: "<img src=x onerror=alert(1)>", does: "<script>x</script>", pos: { file: '"><b>', line: 1 } } : c)) };
		globalThis.fetch = async (url, init) => {
			if (url.endsWith("/0.2.0/claims/export")) return Response.json({ data: evil });
			return fake(url, init);
		};
		for (const path of ["/packages/counter/claims/", "/packages/counter/claims/1/", "/packages/counter/claims/3/"]) {
			const text = await (await get(path, env)).text();
			expect(text).not.toContain("<img src=x");
			expect(text).not.toContain("<script>x</script>");
			expect(text).not.toContain('"><b>');
		}
	});
});

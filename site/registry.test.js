// The package pages (registry.js), against the fixture and a fake registry. `make registry-check`.
import { afterEach, describe, expect, test } from "bun:test";
import { route } from "./registry.js";

const ORIGIN = "https://cairn.test";
const assets = {
	async fetch(url) {
		const path = new URL(url).pathname;
		if (path === "/docs/api/" || path === "/docs/api/Cairn.UI") return new Response(`asset ${path}`);
		return new Response("not found", { status: 404 });
	},
};
const get = (path, env = { ASSETS: assets }) => route(new Request(ORIGIN + path), env);

describe("with the fixture", () => {
	test("lists packages, newest first, and says the data is a sample", async () => {
		const res = await get("/packages/");
		expect(res.status).toBe(200);
		const text = await res.text();
		expect(text).toContain("Sample data");
		expect(text.indexOf('href="/packages/yap/"')).toBeLessThan(text.indexOf('href="/packages/cairn/"'));
		expect(text).toContain('href="/docs/cairn/0.1.0/"');
	});

	test("redirects to the slash form", async () => {
		expect((await get("/packages")).headers.get("location")).toBe(`${ORIGIN}/packages/`);
		expect((await get("/packages/cairn")).headers.get("location")).toBe(`${ORIGIN}/packages/cairn/`);
		expect((await get("/docs/cairn/0.1.0")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.0/`);
	});

	test("shows the latest release, not a pre-release, with its ledger and install lines", async () => {
		const text = await (await get("/packages/cairn/")).text();
		expect(text).toContain("<dd>0.1.0</dd>");
		expect(text).toContain('version = "^0.1.0"');
		expect(text).toContain('<tr id="301" class="moved">');
		expect(text).toContain("<code>cairn^1</code>");
	});

	test("shows an older version and its own ledger", async () => {
		const text = await (await get("/packages/cairn/0.1.0-rc.1/")).text();
		expect(text).toContain("<dd>0.1.0-rc.1</dd>");
		expect(text).toContain('<tr id="301" class="active">');
		expect(text).not.toContain("API docs for");
	});

	test("links a package's dependencies", async () => {
		const text = await (await get("/packages/yap/")).text();
		expect(text).toContain('<a href="/packages/cairn/"><code>cairn</code></a> <code>^0.1.0</code>');
		expect(text).toContain("<code>yap^301</code>");
	});

	test("serves a version's docs from the committed API reference", async () => {
		expect(await (await get("/docs/cairn/0.1.0/")).text()).toBe("asset /docs/api/");
		expect(await (await get("/docs/cairn/0.1.0/Cairn.UI.html")).text()).toBe("asset /docs/api/Cairn.UI");
		expect((await get("/docs/cairn/latest/Cairn.UI.html")).headers.get("location")).toBe(
			`${ORIGIN}/docs/cairn/0.1.0/Cairn.UI.html`,
		);
		expect((await get("/docs/cairn/")).headers.get("location")).toBe(`${ORIGIN}/docs/cairn/0.1.0/`);
	});

	test("says when a version has no docs", async () => {
		const res = await get("/docs/yap/0.1.0/");
		expect(res.status).toBe(404);
		expect(await res.text()).toContain("published without docs");
	});

	test("leaves everything else to the static site", async () => {
		for (const path of [
			"/packages/nope/",
			"/packages/Cairn/",
			"/packages/cairn/9.9.9/",
			"/packages/cairn/0.1.0/extra/",
			"/docs/nope/1.0.0/",
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

	const env = { ASSETS: assets, REGISTRY_URL: "https://reg.test/", REGISTRY_TOKEN: "t0ken" };
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
	};
	const answers = {
		"/config.json": { owner: "carl" },
		"/api/v1/packages?per_page=100": { data: { items: [{ name: "hello", version: "1.2.0", description: "Says <b>hello</b>", docs: true }] } },
		"/api/v1/packages/carl/hello": { data: { name: "hello", description: "Says <b>hello</b>" } },
		"/api/v1/packages/carl/hello/versions?yanked=true": { data: [release] },
		"/api/v1/packages/carl/hello/versions/1.2.0/claims": {
			data: { claims: [{ id: 1, kind: "move", status: "active", statement: "-", title: "Wave" }] },
		},
	};
	const seen = [];
	const fake = async (url, init) => {
		seen.push(new Headers(init?.headers).get("authorization"));
		const path = url.replace("https://reg.test", "");
		if (path === "/api/v1/packages/carl/hello/versions/1.2.0/docs/dist/index.html") {
			return new Response("<h1>hello docs</h1>", { headers: { "content-type": "text/html" } });
		}
		if (path in answers) return Response.json(answers[path]);
		return Response.json({ error: { status: 404, message: "Not found" } }, { status: 404 });
	};

	test("renders from the API, escapes what publishers wrote, and sends the token", async () => {
		globalThis.fetch = fake;
		const list = await (await get("/packages/", env)).text();
		expect(list).not.toContain("Sample data");
		expect(list).toContain("Says &lt;b&gt;hello&lt;/b&gt;");
		const page = await (await get("/packages/hello/", env)).text();
		expect(page).toContain("<code>hello^1</code>");
		expect(page).toContain('.package(url: "https://reg.test/git/carl/hello.git", from: "1.2.0")');
		expect(seen.every((auth) => auth === "Bearer t0ken")).toBe(true);
	});

	test("serves stored docs and 404s the rest", async () => {
		globalThis.fetch = fake;
		const doc = await get("/docs/hello/1.2.0/", env);
		expect(await doc.text()).toBe("<h1>hello docs</h1>");
		expect(doc.headers.get("content-type")).toBe("text/html");
		expect(await get("/docs/hello/1.2.0/missing.html", env)).toBeUndefined();
		expect(await get("/packages/other/", env)).toBeUndefined();
	});
});

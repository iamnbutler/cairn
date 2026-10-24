// The package pages: /packages/, /packages/<name>/[<version>/], and each version's `cairn doc`
// output at /docs/<name>/<version>/. They render from a Cairn package registry, the nextpm
// `cairn` kind (its ADR 0005), when the Worker has REGISTRY_URL and REGISTRY_TOKEN, and from
// site/registry/fixture.json (tools/registry/fixture.ts) when it doesn't. Everything a registry
// answers is escaped: a package's description is its publisher's text, not ours.
import fixture from "./registry/fixture.json";

const esc = (value) =>
	String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const NAME = /^[a-z][a-z0-9_]{0,63}$/;
const VERSION = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;

/** The registry's API, or the fixture with the same answers. */
export function source(env) {
	if (env.REGISTRY_URL && env.REGISTRY_TOKEN) return remote(env.REGISTRY_URL.replace(/\/$/, ""), env.REGISTRY_TOKEN);
	return local();
}

function remote(base, token) {
	const get = async (path) => {
		const res = await fetch(`${base}${path}`, { headers: { authorization: `Bearer ${token}` } });
		if (res.status === 404) return undefined;
		if (!res.ok) throw new Error(`registry: ${path} answered ${res.status}`);
		return res;
	};
	const data = async (path) => (await (await get(path))?.json())?.data;
	let config;
	const owner = async () => (config ??= await (await get("/config.json")).json()).owner;
	return {
		fixture: false,
		git: (name) => `${base}/git/${encodeURIComponent(config?.owner ?? "")}/${name}.git`,
		async list() {
			const found = await data("/api/v1/packages?per_page=100");
			return found?.items ?? [];
		},
		async pkg(name) {
			const who = await owner();
			const pkg = await data(`/api/v1/packages/${encodeURIComponent(who)}/${name}`);
			if (!pkg) return undefined;
			const versions = (await data(`/api/v1/packages/${encodeURIComponent(who)}/${name}/versions?yanked=true`)) ?? [];
			return { name, owner: who, description: pkg.description, versions };
		},
		async claims(name, version) {
			const who = await owner();
			return (await data(`/api/v1/packages/${encodeURIComponent(who)}/${name}/versions/${version}/claims`))?.claims ?? [];
		},
		async doc(name, version, path) {
			const who = await owner();
			const res = await get(`/api/v1/packages/${encodeURIComponent(who)}/${name}/versions/${version}/docs/dist/${path}`);
			if (!res) return undefined;
			const headers = new Headers({ "content-type": res.headers.get("content-type") ?? "application/octet-stream" });
			headers.set("cache-control", "public, max-age=300");
			return new Response(res.body, { headers });
		},
	};
}

function local() {
	const find = (name) => fixture.packages.find((one) => one.name === name);
	return {
		fixture: true,
		git: (name) => `https://<registry>/git/${fixture.owner}/${name}.git`,
		async list() {
			const all = fixture.packages.map((one) => {
				const latest = latestOf(one.versions);
				return {
					name: one.name,
					fullName: `${fixture.owner}/${one.name}`,
					version: latest.version,
					description: latest.description,
					license: latest.license,
					updated: latest.date,
					claims: latest.claims,
					docs: latest.docs,
				};
			});
			return all.sort((a, b) => b.updated.localeCompare(a.updated));
		},
		async pkg(name) {
			const one = find(name);
			return one && { name, owner: fixture.owner, description: latestOf(one.versions).description, versions: one.versions };
		},
		async claims(name, version) {
			return find(name)?.claims[version] ?? [];
		},
		// The fixture's Cairn docs are the API reference that `make site-api` commits.
		async doc(name, version, path, assets, url) {
			if (name !== "cairn" || version !== "0.1.0") return undefined;
			// Static assets answer `/x.html` with a redirect to `/x`, so ask for the clean path.
			const clean = path.replace(/(^|\/)index\.html$/, "$1").replace(/\.html$/, "");
			const res = await assets.fetch(new URL(`/docs/api/${clean}`, url));
			return res.ok ? res : undefined;
		},
	};
}

/** The newest version that isn't yanked and isn't a pre-release, else the newest that isn't yanked. */
function latestOf(versions) {
	const live = versions.filter((v) => !v.yanked);
	return live.find((v) => !v.version.includes("-")) ?? live[0] ?? versions[0];
}

const date = (iso) => new Date(iso).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "UTC" });

function page({ title, lede, eyebrow, body, on = "packages" }) {
	return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(lede)}">
<link rel="icon" href="/favicon.ico" sizes="32x32">
<link rel="icon" href="/icon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Pixelify+Sans:wght@400..700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/docs/docs.css">
<link rel="stylesheet" href="/packages.css">
</head>
<body>
<header class="bar">
  <a class="home" href="/"><img src="/icon.svg" alt="">Cairn</a>
  <a href="/docs/">Docs</a>
  <a href="/packages/"${on === "packages" ? ' class="on"' : ""}>Packages</a>
  <a href="/docs/evidence/">Maps</a>
</header>
<main class="registry">
<header class="page">
<p class="eyebrow">${eyebrow}</p>
<h1>${esc(title)}</h1>
<p class="lede">${esc(lede)}</p>
</header>
${body}
</main>
<footer>Packages come from the Cairn package registry. Each version carries its source, its build, its docs and its claim ledger.</footer>
<script type="module">
  import { mountAnchors } from "/scene.js";
  mountAnchors(document.querySelector("main"));
</script>
</body>
</html>
`;
}

function sample(src) {
	if (!src.fixture) return "";
	return `<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">Sample data</p>
<p>No registry is deployed yet, so these pages show a fixture built from this repository's own claims. The versions and dates are samples, not releases.</p>
</div></aside>`;
}

function counts(claims) {
	if (!claims) return "";
	const chip = (n, label, cls) => (n ? `<span class="chip ${cls}">${n} ${label}</span>` : "");
	return `<span class="chips">${chip(claims.active, "active", "active")}${chip(claims.retired, "retired", "retired")}${chip(claims.moved, "moved", "moved")}</span>`;
}

/** /packages/: every package of the registry, newest release first. */
export async function listPage(src) {
	const items = await src.list();
	const cards = items
		.map(
			(one) => `<li class="pkg px">
<div class="head"><a class="name" href="/packages/${esc(one.name)}/">${esc(one.name)}</a><span class="ver">${esc(one.version)}</span></div>
<p>${esc(one.description ?? "")}</p>
<div class="meta">${counts(one.claims)}<span class="links">${one.docs ? `<a href="/docs/${esc(one.name)}/${esc(one.version)}/">Docs</a>` : ""}<a href="/packages/${esc(one.name)}/">Versions and claims</a></span></div>
</li>`,
		)
		.join("\n");
	const body = `${sample(src)}
<section class="prose wide">
<h2 id="all">All packages</h2>
${items.length ? `<ul class="pkgs">${cards}</ul>` : "<p>No package is published yet.</p>"}
<h2 id="use">Use one</h2>
<p>An app requires a package in its <code>cairn.toml</code>, and <code>cairn build</code> resolves it from the registry, downloads its prebuilt Lean code, and links it. A version's id never moves: its tag, its commit, and its claims stay as published.</p>
</section>`;
	return page({
		title: "Packages",
		eyebrow: "Registry",
		lede: "Cairn packages: libraries and apps, each version with its docs and the claims it makes.",
		body,
	});
}

/** /packages/<name>/[<version>/]: a package's versions, how to depend on it, and a version's claim ledger. */
export async function packagePage(src, name, wanted) {
	if (!NAME.test(name)) return undefined;
	const pkg = await src.pkg(name);
	if (!pkg) return undefined;
	const shown = wanted ? pkg.versions.find((v) => v.version === wanted) : latestOf(pkg.versions);
	if (!shown) return undefined;
	const claims = await src.claims(name, shown.version);
	const range = `^${shown.version.replace(/-.*$/, "")}`;
	const deps = Object.entries(shown.dependencies ?? {});
	const rows = pkg.versions
		.map(
			(v) => `<tr${v.version === shown.version ? ' class="on"' : ""}><td><a href="/packages/${esc(name)}/${esc(v.version)}/">${esc(v.version)}</a>${v.yanked ? ' <span class="chip retired">yanked</span>' : ""}</td><td>${esc(date(v.date))}</td><td><code title="${esc(v.revision)}">${esc(v.revision.slice(0, 10))}</code></td><td>${counts(v.claims)}</td><td>${v.docs ? `<a href="/docs/${esc(name)}/${esc(v.version)}/">docs</a>` : '<span class="muted">none</span>'}</td></tr>`,
		)
		.join("\n");
	const ledger = claims
		.map(
			(c) => `<tr id="${esc(c.id)}" class="${esc(c.status.split(" ")[0])}"><td><code>${esc(name)}^${esc(c.id)}</code></td><td>${esc(c.kind)}</td><td>${esc(c.status)}</td><td>${esc(c.title)}</td></tr>`,
		)
		.join("\n");
	const body = `${sample(src)}
<div class="facts px"><dl>
<div><dt>Version</dt><dd>${esc(shown.version)}${shown.yanked ? ' <span class="chip retired">yanked</span>' : ""}</dd></div>
<div><dt>Published</dt><dd>${esc(date(shown.date))}${shown.publisher ? ` by ${esc(shown.publisher)}` : ""}</dd></div>
<div><dt>Commit</dt><dd><code>${esc(shown.revision.slice(0, 12))}</code> at <code>${esc(shown.tag ?? `v${shown.version}`)}</code></dd></div>
<div><dt>Toolchain</dt><dd><code>${esc(shown.toolchain)}</code></dd></div>
<div><dt>License</dt><dd>${esc(shown.license ?? "none")}</dd></div>
<div><dt>Claims</dt><dd>${counts(shown.claims) || "none"}</dd></div>
</dl>
${shown.docs ? `<p class="go"><a href="/docs/${esc(name)}/${esc(shown.version)}/">API docs for ${esc(shown.version)}</a></p>` : ""}
</div>
<section class="prose wide">
<h2 id="use">Use it</h2>
<p>With the <code>cairn</code> tool:</p>
<figure class="code"><pre><code>cairn add ${esc(name)}@${esc(range)}</code></pre></figure>
<p>Which writes <code>cairn.toml</code>, and the lakefile and SwiftPM lines that it keeps in step:</p>
<figure class="code"><pre><code>[dependencies]
${esc(name)} = "${esc(range)}"</code></pre><figcaption><code>cairn.toml</code></figcaption></figure>
<figure class="code"><pre><code>[[require]]
name = "${esc(name)}"
scope = "${esc(pkg.owner)}"
version = "${esc(range)}"</code></pre><figcaption><code>lean/lakefile.toml</code></figcaption></figure>
<figure class="code"><pre><code>.package(url: "${esc(src.git(name))}", from: "${esc(shown.version.replace(/-.*$/, ""))}")</code></pre><figcaption><code>Package.swift</code></figcaption></figure>
${deps.length ? `<h2 id="deps">Depends on</h2><ul>${deps.map(([dep, r]) => `<li><a href="/packages/${esc(dep)}/"><code>${esc(dep)}</code></a> <code>${esc(r)}</code></li>`).join("")}</ul>` : ""}
<h2 id="versions">Versions</h2>
<div class="wrap"><table><thead><tr><th>Version</th><th>Published</th><th>Commit</th><th>Claims</th><th>Docs</th></tr></thead><tbody>
${rows}
</tbody></table></div>
<h2 id="claims">Claims in ${esc(shown.version)}</h2>
<p>Every id this package has issued, as its <code>claims.lock</code> held them at this version. An id never moves or changes meaning: the registry refuses a version that drops, renumbers or redefines one.</p>
${claims.length ? `<div class="wrap"><table class="ledger"><thead><tr><th>Id</th><th>Kind</th><th>Status</th><th>Claim</th></tr></thead><tbody>
${ledger}
</tbody></table></div>` : "<p>This version makes no claims.</p>"}
</section>`;
	return page({
		title: name,
		eyebrow: `Package · ${esc(pkg.owner)}`,
		lede: shown.description ?? pkg.description ?? "",
		body,
	});
}

function missing(name, version, why) {
	return page({
		title: `${name} ${version}`,
		eyebrow: "Docs",
		lede: why,
		body: `<section class="prose"><p><a href="/packages/${esc(name)}/">See ${esc(name)}'s versions and claims.</a></p></section>`,
	});
}

const html = (text, status = 200) =>
	new Response(text, { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=60" } });

/**
 * Answer a package page, or `undefined` for a path that isn't one. /docs/<name>/<version>/…
 * serves that version's `cairn doc` output; /docs/<name>/ and /docs/<name>/latest/ go to the
 * newest version. The Worker asks this only when no static file matched, so the docs pages
 * under site/public/docs/ always win.
 */
export async function route(request, env) {
	const url = new URL(request.url);
	const parts = url.pathname.split("/").slice(1);
	const src = source(env);
	if (parts[0] === "packages") {
		if (parts.length === 1) return Response.redirect(new URL("/packages/", url), 301);
		const [, name = "", version = "", ...rest] = parts;
		if (!name && !version) return html(await listPage(src));
		if (rest.length > 1 || rest[0]) return undefined;
		if (!url.pathname.endsWith("/")) return Response.redirect(new URL(`${url.pathname}/`, url), 301);
		if (version && !VERSION.test(version)) return undefined;
		const text = await packagePage(src, name, version || undefined);
		return text ? html(text) : undefined;
	}
	if (parts[0] === "docs" && NAME.test(parts[1] ?? "")) {
		const [, name, version = "", ...rest] = parts;
		if (!version || version === "latest") {
			const pkg = await src.pkg(name);
			if (!pkg) return undefined;
			const latest = latestOf(pkg.versions);
			return Response.redirect(new URL(`/docs/${name}/${latest.version}/${rest.join("/")}`, url), 302);
		}
		if (!VERSION.test(version)) return undefined;
		if (!rest.length) return Response.redirect(new URL(`/docs/${name}/${version}/`, url), 301);
		const path = rest.join("/") || "index.html";
		if (path.split("/").some((part) => part === ".." || part === ".")) return undefined;
		const pkg = await src.pkg(name);
		const found = pkg?.versions.find((v) => v.version === version);
		if (!found) return undefined;
		if (!found.docs) return html(missing(name, version, `${name} ${version} was published without docs.`), 404);
		return (await src.doc(name, version, path, env.ASSETS, url)) ?? undefined;
	}
	return undefined;
}

// The package pages: /packages/ and /packages/<name>/[<version>/]. They render from the Cairn
// package registry, the nextpm `cairn` kind (its ADR 0005), when the Worker has REGISTRY_URL, and
// from site/registry/fixture.json (tools/registry/fixture.ts) when it doesn't. There is one
// public registry, https://cairn.registry.nexthub.sh, which anyone reads with no token, so the
// site sends none. Each package has its own owner, the account that first published its name.
// Everything a registry answers is escaped: a package's description is its publisher's text,
// not ours.
//
// /docs/<name>/<version>/ is a placeholder. It never fetches, proxies or renders HTML from the
// registry: HTML served from a publisher's upload would run as this origin, so a registry takes
// no docs from publishers (nextpm#23) and will build them from the published source, as docs.rs
// does. Only the JSON API is read, and only to know the package and version exist.
//
// A package is a library (`kind = "lib"` in cairn.toml) or an app (`kind = "bin"`), as Cargo has
// it. /packages/ shows the libraries and /packages/?tab=apps the apps; a registry that doesn't
// say (nextpm before kinds) means a library.
import fixture from "./registry/fixture.json";

const esc = (value) =>
	String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const NAME = /^[a-z][a-z0-9_]{0,63}$/;
const VERSION = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;

/** `lib` or `bin`: anything but `bin` is a library. */
const kindOf = (one) => (one?.kind === "bin" ? "bin" : "lib");

/** The registry's API, or the fixture with the same answers. */
export function source(env) {
	if (env.REGISTRY_URL) return remote(env.REGISTRY_URL.replace(/\/$/, ""));
	return local();
}

/** The owner half of a search result's `fullName`, `owner/name`. */
const ownerIn = (fullName) => (String(fullName ?? "").includes("/") ? String(fullName).split("/")[0] : "");

function remote(base) {
	const get = async (path) => {
		const res = await fetch(`${base}${path}`, { headers: { accept: "application/json" } });
		if (res.status === 404) return undefined;
		if (!res.ok) throw new Error(`registry: ${path} answered ${res.status}`);
		return res;
	};
	const data = async (path) => (await (await get(path))?.json())?.data;
	// The API reads a package only as <owner>/<name>, and a name has one owner, which
	// /api/v1/names/<name> answers (404 for a name the registry doesn't hold). A source lives for
	// one request, so this caches no longer.
	const owners = new Map();
	const ownerOf = async (name) => {
		if (!owners.has(name)) owners.set(name, (await data(`/api/v1/names/${encodeURIComponent(name)}`))?.owner ?? "");
		return owners.get(name);
	};
	const at = (who, name) => `/api/v1/packages/${encodeURIComponent(who)}/${name}`;
	return {
		fixture: false,
		git: (owner, name) => `${base}/git/${encodeURIComponent(owner)}/${name}.git`,
		async list() {
			const found = await data("/api/v1/packages?per_page=100");
			return (found?.items ?? []).map((one) => ({ ...one, owner: ownerIn(one.fullName) }));
		},
		async pkg(name) {
			const who = await ownerOf(name);
			if (!who) return undefined;
			const pkg = await data(at(who, name));
			if (!pkg) return undefined;
			const versions = (await data(`${at(who, name)}/versions?yanked=true`)) ?? [];
			return { name, owner: pkg.owner ?? who, description: pkg.description, kind: kindOf(pkg), versions };
		},
		async claims(name, version) {
			const who = await ownerOf(name);
			if (!who) return [];
			return (await data(`${at(who, name)}/versions/${version}/claims`))?.claims ?? [];
		},
	};
}

function local() {
	const find = (name) => fixture.packages.find((one) => one.name === name);
	return {
		fixture: true,
		git: (owner, name) => `https://<registry>/git/${owner}/${name}.git`,
		async list() {
			const all = fixture.packages.map((one) => {
				const latest = latestOf(one.versions);
				return {
					name: one.name,
					fullName: `${fixture.owner}/${one.name}`,
					owner: fixture.owner,
					version: latest.version,
					kind: kindOf(latest),
					description: latest.description,
					license: latest.license,
					updated: latest.date,
					claims: latest.claims,
				};
			});
			return all.sort((a, b) => b.updated.localeCompare(a.updated));
		},
		async pkg(name) {
			const one = find(name);
			const latest = one && latestOf(one.versions);
			return one && { name, owner: fixture.owner, description: latest.description, kind: kindOf(latest), versions: one.versions };
		},
		async claims(name, version) {
			return find(name)?.claims[version] ?? [];
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
  <a href="/milestones/">Milestones</a>
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
<footer>Each version on a Cairn package registry carries its source, its build and its claim ledger.</footer>
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
<p>No registry is deployed yet, so these pages show a fixture. Cairn's versions are its real releases, read from its git tags with their commits, dates and claims. Yap's entry is a sample: it isn't tagged yet.</p>
</div></aside>`;
}

function counts(claims) {
	if (!claims) return "";
	const chip = (n, label, cls) => (n ? `<span class="chip ${cls}">${n} ${label}</span>` : "");
	return `<span class="chips">${chip(claims.active, "active", "active")}${chip(claims.retired, "retired", "retired")}${chip(claims.moved, "moved", "moved")}</span>`;
}

const TABS = { lib: { title: "Libraries", tab: "", none: "No library is published yet." }, bin: { title: "Apps", tab: "?tab=apps", none: "No app is published yet." } };

/** /packages/: the registry's libraries, or with `kind` "bin" its apps, newest release first. */
export async function listPage(src, kind = "lib") {
	const all = await src.list();
	const items = all.filter((one) => kindOf(one) === kind);
	const tabs = Object.entries(TABS)
		.map(([k, t]) => {
			const n = all.filter((one) => kindOf(one) === k).length;
			const on = k === kind;
			return `<a href="/packages/${t.tab}"${on ? ' class="on" aria-current="page"' : ""}>${t.title} <span class="n">${n}</span></a>`;
		})
		.join("");
	const cards = items
		.map(
			(one) => `<li class="pkg px">
<div class="head"><a class="name" href="/packages/${esc(one.name)}/">${esc(one.name)}</a><span class="ver">${esc(one.version)}</span>${one.owner ? `<span class="owner">by ${esc(one.owner)}</span>` : ""}</div>
<p>${esc(one.description ?? "")}</p>
<div class="meta">${counts(one.claims)}<span class="links"><a href="/docs/${esc(one.name)}/${esc(one.version)}/">Docs</a><a href="/packages/${esc(one.name)}/">Versions and claims</a></span></div>
</li>`,
		)
		.join("\n");
	const body = `${sample(src)}
<section class="prose wide">
<nav class="tabs" aria-label="Package kinds">${tabs}</nav>
<h2 id="all">${TABS[kind].title}</h2>
${items.length ? `<ul class="pkgs">${cards}</ul>` : `<p>${TABS[kind].none}</p>`}
</section>`;
	return page({
		title: "Packages",
		eyebrow: "Registry",
		lede: "Cairn packages: libraries to build on and apps to run, each version with the claims it makes.",
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
	const app = kindOf(shown.kind ? shown : pkg) === "bin";
	const deps = Object.entries(shown.dependencies ?? {});
	const rows = pkg.versions
		.map(
			(v) => `<tr${v.version === shown.version ? ' class="on"' : ""}><td><a href="/packages/${esc(name)}/${esc(v.version)}/">${esc(v.version)}</a>${v.yanked ? ' <span class="chip retired">yanked</span>' : ""}</td><td>${esc(date(v.date))}</td><td><code title="${esc(v.revision)}">${esc(v.revision.slice(0, 10))}</code></td><td>${counts(v.claims)}</td><td><a href="/docs/${esc(name)}/${esc(v.version)}/">docs</a></td></tr>`,
		)
		.join("\n");
	const ledger = claims
		.map(
			(c) => `<tr id="${esc(c.id)}" class="${esc(c.status.split(/[ :]/)[0])}"><td><code>${esc(name)}^${esc(c.id)}</code></td><td>${esc(c.kind)}</td><td>${esc(c.status)}</td><td>${esc(c.title)}</td></tr>`,
		)
		.join("\n");
	const body = `${sample(src)}
<div class="facts px"><dl>
<div><dt>Kind</dt><dd>${app ? "App" : "Library"}</dd></div>
<div><dt>Owner</dt><dd>${esc(pkg.owner)}</dd></div>
<div><dt>Version</dt><dd>${esc(shown.version)}${shown.yanked ? ' <span class="chip retired">yanked</span>' : ""}</dd></div>
<div><dt>Published</dt><dd>${esc(date(shown.date))}${shown.publisher ? ` by ${esc(shown.publisher)}` : ""}</dd></div>
<div><dt>Commit</dt><dd><code>${esc(shown.revision.slice(0, 12))}</code> at <code>${esc(shown.tag ?? `v${shown.version}`)}</code></dd></div>
<div><dt>Toolchain</dt><dd><code>${esc(shown.toolchain)}</code></dd></div>
<div><dt>License</dt><dd>${esc(shown.license ?? "none")}</dd></div>
<div><dt>Claims</dt><dd>${counts(shown.claims) || "none"}</dd></div>
</dl>
<p class="go"><a href="/docs/${esc(name)}/${esc(shown.version)}/">Docs for ${esc(shown.version)}</a></p>
</div>
<section class="prose wide">
${
	src.fixture
		? `<h2 id="use">${app ? "Build it" : "Use it"}</h2>
<p>Not from a registry yet: none is deployed, so <code>cairn add</code> and <code>cairn build</code> have nothing to resolve against. Today an app depends on Cairn by its git tag, in its lakefile and <code>Package.swift</code>: see <a href="/docs/guide/first-app/#an-app-in-its-own-repository">An app in its own repository</a>.</p>`
		: app
		? `<h2 id="use">Build it</h2>
<p>${esc(name)} is an app: nothing can depend on it. Clone it from the registry and build it with the <code>cairn</code> tool:</p>
<figure class="code"><pre><code>git clone ${esc(src.git(pkg.owner, name))}
cd ${esc(name)} &amp;&amp; git checkout ${esc(shown.tag ?? `v${shown.version}`)} &amp;&amp; cairn build --release</code></pre></figure>`
		: `<h2 id="use">Use it</h2>
<p>With the <code>cairn</code> tool:</p>
<figure class="code"><pre><code>cairn add ${esc(name)}@${esc(range)}</code></pre></figure>
<p>Which writes <code>cairn.toml</code>, and the lakefile ${shown.swift === true ? "and SwiftPM lines" : "line"} that it keeps in step:</p>
<figure class="code"><pre><code>[dependencies]
${esc(name)} = "${esc(range)}"</code></pre><figcaption><code>cairn.toml</code></figcaption></figure>
<figure class="code"><pre><code>[[require]]
name = "${esc(name)}"
scope = "${esc(pkg.owner)}"
version = "${esc(range)}"</code></pre><figcaption><code>lean/lakefile.toml</code></figcaption></figure>${
	// Only a version with a SwiftPM package (`swift: true`) has a Package.swift line: a pure-Lean
	// package has no Swift side, and a registry from before the field says none.
	shown.swift === true
		? `
<figure class="code"><pre><code>.package(url: "${esc(src.git(pkg.owner, name))}", from: "${esc(shown.version.replace(/-.*$/, ""))}")</code></pre><figcaption><code>Package.swift</code></figcaption></figure>`
		: ""
}`
}
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

/** /docs/<name>/<version>/: a placeholder until the registry builds docs from source. */
export function docsPage(name, version) {
	return page({
		title: `${name} ${version}`,
		eyebrow: 'Docs<span class="todo">not yet</span>',
		lede: `API docs for ${name} ${version}.`,
		body: `<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">To do</p>
<p>Docs for this version will be built by the registry from its source, like docs.rs. Not yet.</p>
<p>Publishers don't upload docs. HTML served from an upload runs as the site that serves it, so the registry takes none and this site shows none.</p>
</div></aside>
<section class="prose"><p><a href="/packages/${esc(name)}/${esc(version)}/">See ${esc(name)} ${esc(version)}: its versions, how to depend on it, and its claims.</a></p></section>`,
	});
}

const html = (text, status = 200) =>
	new Response(text, { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=60" } });

/**
 * Answer a package page, or `undefined` for a path that isn't one. /docs/<name>/<version>/ is the
 * docs placeholder, and any path under it goes there; /docs/<name>/ and /docs/<name>/latest/ go
 * to the newest version's. The Worker asks this only when no static file matched, so the docs
 * pages under site/public/docs/ always win.
 */
export async function route(request, env) {
	const url = new URL(request.url);
	const parts = url.pathname.split("/").slice(1);
	const src = source(env);
	if (parts[0] === "packages") {
		if (parts.length === 1) return Response.redirect(new URL("/packages/", url), 301);
		const [, name = "", version = "", ...rest] = parts;
		if (!name && !version) return html(await listPage(src, url.searchParams.get("tab") === "apps" ? "bin" : "lib"));
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
			return Response.redirect(new URL(`/docs/${name}/${latest.version}/`, url), 302);
		}
		if (!VERSION.test(version)) return undefined;
		const pkg = await src.pkg(name);
		if (!pkg?.versions.some((v) => v.version === version)) return undefined;
		if (rest.length !== 1 || rest[0]) return Response.redirect(new URL(`/docs/${name}/${version}/`, url), 302);
		return html(docsPage(name, version));
	}
	return undefined;
}

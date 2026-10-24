// cairn doc's pages: a package's modules, declarations and claims → static HTML (docs/doc.md).
//
// Pure: returns { path: content }. The pages are flat and relative: index.html, claims.html, one
// <Module.Name>.html per module, and search-index.js. Every declaration's anchor is its full
// name, and every claim's is its number, so `Examples.Todo.html#Examples.Todo.visible` and
// `Examples.Todo.html#202` stay valid for as long as the name or the id does.
import { KINDS, type Claim, type Headline, type Mark, type Row, type Step } from "../map/evidence";

// ---- Inputs ------------------------------------------------------------------------------------

/** A pretty-printed term: plain text, or [text, constant, module] for a constant to link. */
export type Seg = string | [string, string, string];
export type Decl = {
	name: string;
	kind: string;
	module: string;
	line: number;
	private: boolean;
	sig: Seg[];
	doc: string | null;
	fields: { name: string; type: Seg[]; doc: string | null }[];
	ctors: { name: string; sig: Seg[]; doc: string | null }[];
	instance: { class: string | null; for: string[] } | null;
	axioms: string[] | null;
};
export type Module = { name: string; file: string; docs: { doc: string; line: number }[]; imports: string[] };
export type Statement = { binders?: string[]; body?: Seg[]; sig?: Seg[] };
/** `lake exe doc`. */
export type DocJson = {
	roots: string[];
	modules: Module[];
	decls: Decl[];
	statements: Record<string, Statement>;
	doctests: { checked: boolean; blocks: number; failed: number };
};

export type Context = {
	/** The package's name: `Cairn`, `Todo`. */
	name: string;
	/** The command that made these pages, for the footer. */
	command: string;
	doc: DocJson;
	/** One evidence row per claim (tools/map/evidence.ts), or none for a package without claims. */
	rows: Row[];
	/** Show private declarations. */
	showPrivate: boolean;
	/** Other packages' docs, by module prefix: `Cairn.` → `../Cairn/`. */
	links: [string, string][];
	size: (file: string) => [number, number] | undefined;
	/** What the build had, for the index. */
	inputs: string[];
};

// ---- Helpers -----------------------------------------------------------------------------------

export const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const md = (s: string) => esc(s).replace(/`([^`]+)`/g, "<code>$1</code>");
export const pageOf = (module: string) => `${module}.html`;
/** A name as a URL fragment: `%` and spaces encoded (notation names like `«term_%_»` have
 *  them). The element's id stays the name itself; browsers decode the fragment to match it. */
const pct = (name: string) => name.replace(/%/g, "%25").replace(/ /g, "%20");
/** The same, escaped for an attribute. */
const frag = (name: string) => esc(pct(name));
const plural = (n: number, one: string, many = `${one}s`) => `${n.toLocaleString("en")} ${n === 1 ? one : many}`;
const lastOf = (name: string) => {
	const parts = splitName(name);
	return parts[parts.length - 1] ?? name;
};
/** A Lean name's components, keeping «guillemets» whole. */
function splitName(name: string): string[] {
	const out: string[] = [];
	let cur = "";
	let quoted = false;
	for (const ch of name) {
		if (ch === "«") quoted = true;
		if (ch === "»") quoted = false;
		if (ch === "." && !quoted) {
			out.push(cur);
			cur = "";
		} else cur += ch;
	}
	out.push(cur);
	return out;
}
const prefixOf = (name: string) => splitName(name).slice(0, -1).join(".");

const GROUPS: { title: string; id: string; kinds: string[] }[] = [
	{ title: "Structures", id: "structures", kinds: ["structure"] },
	{ title: "Inductive types", id: "inductives", kinds: ["inductive"] },
	{ title: "Classes", id: "classes", kinds: ["class"] },
	{ title: "Definitions", id: "definitions", kinds: ["def", "abbrev", "opaque"] },
	{ title: "Theorems", id: "theorems", kinds: ["theorem"] },
	{ title: "Instances", id: "instances", kinds: ["instance"] },
	{ title: "Axioms", id: "axioms", kinds: ["axiom"] },
];
const HEADLINES: Headline[] = ["broken", ...KINDS, "untested", "retired"];

export function render(ctx: Context): Record<string, string> {
	const { doc, rows, name } = ctx;
	const modules = new Map(doc.modules.map((m) => [m.name, m]));

	// Claims own the declarations their commands generate (`reset.press.sound`, `reset.info`,
	// `Cairn.Claims.Issued.«^2»`): those are listed under the claim, not as loose definitions.
	const claimOf = new Map<string, Row>();
	const ownedBy = (n: string): Row | undefined => {
		for (let p = n; p; p = prefixOf(p)) if (claimOf.has(p)) return claimOf.get(p);
		return undefined;
	};
	for (const r of rows) claimOf.set(r.claim.decl, r);
	const issued = (n: string) => n.startsWith("Cairn.Claims.Issued.");
	const visible = doc.decls.filter((d) => (ctx.showPrivate || !d.private) && !issued(d.name));
	const loose = visible.filter((d) => !ownedBy(d.name));
	const generated = new Map<number, Decl[]>();
	for (const d of visible) {
		const r = ownedBy(d.name);
		if (r) generated.set(r.claim.id, [...(generated.get(r.claim.id) ?? []), d]);
	}
	const hiddenPrivate = doc.decls.filter((d) => d.private && !ctx.showPrivate).length;

	// Where each name is documented, for links in signatures and doc comments.
	const where = new Map<string, string>();
	for (const d of visible) where.set(d.name, `${pageOf(d.module)}#${frag(d.name)}`);
	for (const d of visible) for (const c of d.ctors) where.set(c.name, `${pageOf(d.module)}#${frag(c.name)}`);
	for (const d of visible) for (const f of d.fields) where.set(`${d.name}.${f.name}`, `${pageOf(d.module)}#${frag(`${d.name}.${f.name}`)}`);
	for (const m of doc.modules) where.set(m.name, pageOf(m.name));
	const claimHref = new Map<number, string>();
	for (const r of rows) claimHref.set(r.claim.id, `${pageOf(r.claim.module)}#${r.claim.id}`);
	const external = (module: string, constant: string) => {
		const hit = ctx.links.find(([prefix]) => module.startsWith(prefix));
		return hit ? `${hit[1]}${pageOf(module)}${constant ? `#${frag(constant)}` : ""}` : undefined;
	};
	const hrefOf = (constant: string, module: string) => where.get(constant) ?? (module && !modules.has(module) ? external(module, constant) : undefined);

	/** A name written in a doc comment, resolved the way Lean would from `ns`: `layout` in
	 *  `Cairn.Layout` finds `Cairn.Layout.layout`. */
	const resolve = (text: string, ns: string): string | undefined => {
		const t = text.trim();
		if (!/^[A-Za-z_][\w.'!?«»^]*$/u.test(t)) return undefined;
		for (let p = ns; ; p = prefixOf(p)) {
			const hit = where.get(p ? `${p}.${t}` : t);
			if (hit) return hit;
			if (!p) break;
		}
		return where.get(`Cairn.${t}`);
	};

	const claimLink = (id: number, label = `^${id}`) => {
		const h = claimHref.get(id);
		return h ? `<a class="id" href="${h}">${esc(label)}</a>` : `<span class="id" title="not in this package">${esc(label)}</span>`;
	};
	/** `^N` in prose becomes a link to the claim. */
	const linkIds = (html: string) =>
		html
			.split(/(<[^>]+>)/)
			.map((part, k, all) => {
				if (part.startsWith("<")) return part;
				const open = all.slice(0, k).filter((p) => /^<(a|pre)[\s>]/.test(p)).length;
				const close = all.slice(0, k).filter((p) => /^<\/(a|pre)>/.test(p)).length;
				if (open > close) return part;
				return part.replace(/\^(\d+)(#\d+)?/g, (m, n) => (claimHref.has(Number(n)) ? `<a class="id" href="${claimHref.get(Number(n))}">${m}</a>` : m));
			})
			.join("");
	/** A doc comment: Markdown, with `^N` and `names` linked. */
	const docHtml = (text: string | null, ns: string) => {
		if (!text) return "";
		let html = Bun.markdown.html(text);
		html = html.replace(/<code>([^<]+)<\/code>/g, (m, inner: string) => {
			const id = /^\^(\d+)(#\d+)?$/.exec(inner.trim());
			if (id && claimHref.has(Number(id[1]))) return `<a class="id" href="${claimHref.get(Number(id[1]))}"><code>${inner}</code></a>`;
			const h = resolve(inner.replace(/&amp;/g, "&"), ns);
			return h ? `<a href="${h}"><code>${inner}</code></a>` : m;
		});
		return `<div class="doc">${linkIds(html)}</div>`;
	};
	const firstSentence = (text: string | null) => {
		if (!text) return "";
		const para = text.replace(/^#+ .*\n+/, "").split(/\n\s*\n/)[0] ?? "";
		const s = para.replace(/\s+/g, " ").trim();
		const m = /^(.+?\.)(\s|$)/.exec(s);
		return (m ? m[1]! : s).slice(0, 240);
	};

	const segs = (ss: Seg[]) =>
		ss
			.map((s) => {
				if (typeof s === "string") return esc(s);
				const [text, constant, module] = s;
				const h = hrefOf(constant, module);
				return h ? `<a href="${h}" title="${esc(constant)}">${esc(text)}</a>` : `<span title="${esc(constant)}">${esc(text)}</span>`;
			})
			.join("");
	/** A signature with the declaration's own (full) name replaced by its last component. */
	const sigHtml = (d: { name: string; sig: Seg[] }) => {
		const ss = [...d.sig];
		const first = ss[0];
		if (typeof first === "string" && first.startsWith(d.name)) ss[0] = first.slice(d.name.length);
		return `<pre class="sig"><b class="nm">${esc(lastOf(d.name))}</b>${segs(ss)}</pre>`;
	};
	const src = (file: string, line: number | null) => `<span class="src" title="source">${esc(file)}${line ? `:${line}` : ""}</span>`;

	// Instances, by the types they are for.
	const instancesFor = new Map<string, Decl[]>();
	for (const d of visible)
		if (d.instance) for (const t of new Set(d.instance.for)) instancesFor.set(t, [...(instancesFor.get(t) ?? []), d]);

	// ---- A declaration -----------------------------------------------------------------------------
	const declHtml = (d: Decl, inClaim = false) => {
		const ns = prefixOf(d.name);
		const fields = d.fields.length
			? `<div class="members"><b class="pix muted">Fields</b>${d.fields
					.map((f) => `<div class="member" id="${esc(d.name)}.${esc(f.name)}"><pre class="sig"><b class="nm">${esc(f.name)}</b> : ${segs(f.type)}</pre>${docHtml(f.doc, d.name)}</div>`)
					.join("")}</div>`
			: "";
		const ctors = d.ctors.length
			? `<div class="members"><b class="pix muted">Constructors</b>${d.ctors.map((c) => `<div class="member" id="${esc(c.name)}">${sigHtml(c)}${docHtml(c.doc, d.name)}</div>`).join("")}</div>`
			: "";
		const insts = instancesFor.get(d.name) ?? [];
		const instHtml = insts.length && !d.instance ? `<div class="members"><b class="pix muted">Instances</b><p class="insts">${insts.map((i) => `<a href="${pageOf(i.module)}#${frag(i.name)}"><code>${esc(i.instance?.class ? lastOf(i.instance.class) : lastOf(i.name))}</code></a>`).join(" ")}</p></div>` : "";
		const axioms =
			d.axioms === null ? "" : d.axioms.length ? `<span class="m fail" title="axioms beyond propext, Classical.choice and Quot.sound">uses ${esc(d.axioms.join(", "))}</span>` : `<span class="m proved pass" title="depends only on propext, Classical.choice and Quot.sound">proved</span>`;
		return `<section class="decl${d.private ? " private" : ""}${inClaim ? " gen" : ""}" id="${esc(d.name)}" data-line="${d.line}">
<div class="dhead"><span class="kind pix">${d.private ? "private " : ""}${d.kind}</span><h3><a href="#${frag(d.name)}"><span class="ns">${esc(ns ? `${ns}.` : "")}</span>${esc(lastOf(d.name))}</a></h3>${axioms}${src(modules.get(d.module)?.file ?? "", d.line)}</div>
${sigHtml(d)}${docHtml(d.doc, ns)}${fields}${ctors}${instHtml}
</section>`;
	};

	// ---- A claim -----------------------------------------------------------------------------------
	const chip = (m: Mark) => `<span class="m ${m.kind} ${m.state}" title="${esc(m.detail.replace(/`/g, ""))}">${esc(m.label)}</span>`;
	const headline = (h: Headline) => `<span class="hl ${h}">${h}</span>`;
	const img = (file: string, alt: string, caption = "") => {
		const [w, h] = ctx.size(file) ?? [];
		return `<figure class="shot"><div class="box px"><img src="img/${esc(file)}" alt="${esc(alt)}"${w ? ` width="${w}" height="${h}"` : ""} loading="lazy"></div>${caption ? `<figcaption>${caption}</figcaption>` : ""}</figure>`;
	};
	const witnessOf = (c: Claim): Step[] => (Array.isArray(c.witness) ? c.witness : []);
	const statementHtml = (c: Claim & { statementDecls?: string[] }) => {
		const ds = c.statementDecls ?? [];
		if (!ds.length) return "";
		const lines = ds.map((n) => {
			const s = doc.statements[n];
			const short = n.startsWith(`${c.decl}.`) ? n.slice(c.decl.length + 1) : lastOf(n);
			if (!s) return `<pre class="sig"><b class="nm">${esc(short)}</b></pre>`;
			if (s.body) return `<pre class="sig"><b class="nm">${esc(short)}</b>${s.binders?.length ? ` ${esc(s.binders.join(" "))}` : ""} := ${segs(s.body)}</pre>`;
			return `<pre class="sig"><b class="nm">${esc(short)}</b>${segs(s.sig ?? [])}</pre>`;
		});
		return `<b class="pix muted">Formal statement</b>${lines.join("")}`;
	};
	const claimHtml = (r: Row) => {
		const c = r.claim as Claim & { statementDecls?: string[] };
		const ns = c.decl;
		const said = c.retired
			? `<p class="retired-why">Retired: ${linkIds(md(c.retired))}</p>`
			: [c.does && `<b>Does</b><p>${linkIds(md(c.does))}</p>`, c.sees && `<b>Sees</b><p>${linkIds(md(c.sees))}</p>`].filter(Boolean).join("");
		const place = c.place !== null ? `<p class="where">In ${claimLink(c.place)}${rows.find((x) => x.claim.id === c.place) ? ` ${esc(rows.find((x) => x.claim.id === c.place)!.claim.title)}` : ""}</p>` : "";
		const ev = r.marks.length ? `<dl class="ev">${r.marks.map((m) => `<dt>${chip(m)}</dt><dd>${linkIds(md(m.detail))}</dd>`).join("")}</dl>` : "";
		const findings = r.findings.map((f) => `<p class="finding${f.broken ? "" : " soft"}">${md(f.text)}</p>`).join("");
		const proofs = r.theorems.length
			? `<b class="pix muted">Proofs</b><div class="thm">${r.theorems.map((t) => `<div><span class="${t.ok ? "ok" : t.ok === null ? "muted" : "bad"}">${t.ok ? "✓" : t.ok === null ? "?" : "✗"}</span> ${where.has(t.theorem) ? `<a href="${where.get(t.theorem)}"><code>${esc(t.theorem.slice(prefixOf(c.decl).length + 1))}</code></a>` : `<code>${esc(t.theorem)}</code>`} <span class="muted">${esc(t.role)}</span></div>`).join("")}</div>`
			: "";
		const steps = witnessOf(c);
		const witness = c.kind === "flow" && steps.length ? `<b class="pix muted">Witness</b><ol class="witness">${steps.map((s) => `<li>${esc(s.trigger)} ${claimLink(s.claim, s.ref)}</li>`).join("")}</ol>` : "";
		let pictures = "";
		if (c.kind === "move" && r.shots.after) pictures = `<div class="pair">${img(r.shots.before!, `${c.title}, before`, "before")}${img(r.shots.after, `${c.title}, after`, "after")}</div>`;
		else if (c.kind === "place" && r.shots.frames[0]) pictures = `<div class="pair">${img(r.shots.frames[0], c.title, "as the app starts")}</div>`;
		const gen = generated.get(c.id) ?? [];
		const genHtml = gen.length ? `<details class="gen"><summary>${plural(gen.length, "generated declaration")}</summary>${gen.map((d) => declHtml(d, true)).join("")}</details>` : "";
		return `<section class="claim px" id="${c.id}" data-line="${c.pos.line ?? 0}">
<div class="head"><a class="id" href="#${c.id}">${esc(c.ref)}</a><h3>${esc(c.title)}</h3><span class="pix muted">${c.kind}</span>${headline(r.headline)}</div>
<div class="said">${said}${place}${statementHtml(c)}${witness}${ev}${findings}${proofs}</div>
${pictures}
<p class="srcline">${src(c.pos.file, c.pos.line)} · <code>${esc(lastOf(ns))}</code> · ledger: ${esc(r.ledger)}</p>
${genHtml}
</section>`;
	};

	// ---- The shell ---------------------------------------------------------------------------------
	const nav = (on: string) =>
		`<nav class="bar"><a class="home" href="../../"><img src="icon.svg" alt="">Cairn</a><span class="sep">/</span><a href="index.html"${on === "index.html" ? ' class="on"' : ""}>${esc(name)} docs</a>${rows.length ? `<a href="claims.html"${on === "claims.html" ? ' class="on"' : ""}>Claims</a>` : ""}<span class="search"><input id="search" type="search" placeholder="Search names, docs, ^N  ( / )" autocomplete="off" spellcheck="false"><div id="results" hidden></div></span></nav>`;
	const shell = (file: string, title: string, body: string, aside = "") => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(name)}'s API, generated from its code.">
<link rel="icon" href="icon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Pixelify+Sans:wght@400..700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="style.css">
<link rel="stylesheet" href="doc.css">
</head>
<body>
${nav(file)}
${aside ? `<div class="layout">${aside}<main>\n${body}\n</main></div>` : `<main>\n${body}\n</main>`}
<footer>Generated by <code>${esc(ctx.command)}</code> from the code and the build. Nothing here is written by hand.</footer>
<script src="search-index.js"></script>
<script src="search.js"></script>
<script type="module">
// On the site, the headings get the meadow's sprigs and a "#" that copies a link to them
// (site/public/scene.js); elsewhere, nothing.
import("/scene.js").then((m) => { const main = document.querySelector("main"); m.mountSprigs(main); m.mountAnchors(main); }).catch(() => {});
</script>
</body>
</html>
`;

	const out: Record<string, string> = {};

	// ---- Module pages ------------------------------------------------------------------------------
	const declsBy = Map.groupBy(loose, (d) => d.module);
	const claimsBy = Map.groupBy(rows, (r) => r.claim.module);
	// Every module gets a page, umbrellas too (they list what they import).
	const shown = doc.modules;
	for (const m of shown) {
		const ds = declsBy.get(m.name) ?? [];
		const cs = (claimsBy.get(m.name) ?? []).toSorted((a, b) => a.claim.id - b.claim.id);
		const groups = GROUPS.map((g) => ({ ...g, decls: ds.filter((d) => g.kinds.includes(d.kind)) })).filter((g) => g.decls.length);
		const [top, ...sections] = m.docs;
		const ns = m.name;
		const toc = [
			cs.length ? `<a href="#claims">Claims <span class="n">${cs.length}</span></a><ol>${cs.map((r) => `<li><a href="#${r.claim.id}"><span class="id">${r.claim.ref}</span> ${esc(r.claim.title)}</a></li>`).join("")}</ol>` : "",
			...groups.map((g) => `<a href="#${g.id}">${g.title} <span class="n">${g.decls.length}</span></a><ol>${g.decls.map((d) => `<li><a href="#${frag(d.name)}">${esc(lastOf(d.name))}</a></li>`).join("")}</ol>`),
		].join("");
		const aside = `<aside class="toc"><div class="pix muted">${esc(m.name)}</div>${toc}</aside>`;
		const imps = [...new Set(m.imports)].filter((i) => i !== "Init");
		const imports = imps.length
			? `<p class="imports"><span class="pix muted">Imports</span> ${imps.map((i) => (modules.has(i) ? `<a href="${pageOf(i)}">${esc(i)}</a>` : external(i, "") ? `<a href="${external(i, "")}">${esc(i)}</a>` : `<span class="muted">${esc(i)}</span>`)).join(", ")}</p>`
			: "";
		const sectionDocs = sections.map((s) => `<div class="mdoc" data-line="${s.line}" hidden>${docHtml(s.doc, ns)}</div>`).join("");
		const body = `<header class="page"><div class="eyebrow">${esc(name)} · module</div><h1 class="mod">${esc(m.name)}</h1><p class="src">${esc(m.file)}</p></header>
${top ? docHtml(top.doc, ns) : ""}
${imports}
<div class="order"><span class="pix muted">Order</span> <button type="button" data-order="kind" class="on">by kind</button><button type="button" data-order="source">as in the source</button></div>
<div id="items">
${cs.length ? `<h2 id="claims">Claims <span class="n">${cs.length}</span></h2>\n${cs.map(claimHtml).join("\n")}` : ""}
${groups.map((g) => `<h2 id="${g.id}">${g.title} <span class="n">${g.decls.length}</span></h2>\n${g.decls.map((d) => declHtml(d)).join("\n")}`).join("\n")}
${sectionDocs}
</div>`;
		out[pageOf(m.name)] = shell(pageOf(m.name), `${m.name} · ${name} docs`, body, aside);
	}

	// ---- Index -------------------------------------------------------------------------------------
	const rootDoc = modules.get(doc.roots[0] ?? "")?.docs[0]?.doc ?? null;
	const theorems = loose.filter((d) => d.kind === "theorem");
	const unproved = visible.filter((d) => d.axioms && d.axioms.length);
	const tree = shown
		.toSorted((a, b) => a.name.localeCompare(b.name))
		.map((m) => {
			const depth = splitName(m.name).length - 1;
			const n = (declsBy.get(m.name) ?? []).length;
			const c = (claimsBy.get(m.name) ?? []).length;
			return `<tr><td class="modname" style="--d:${depth}"><a href="${pageOf(m.name)}">${esc(m.name)}</a></td><td class="muted num">${n || ""}</td><td class="muted num">${c ? `${c} ^` : ""}</td><td>${linkIds(md(firstSentence(m.docs[0]?.doc ?? null)))}</td></tr>`;
		})
		.join("");
	const tally = HEADLINES.map((h) => [h, rows.filter((r) => r.headline === h).length] as const).filter(([, k]) => k);
	out["index.html"] = shell(
		"index.html",
		`${name} docs`,
		`<header class="page"><div class="eyebrow">Cairn · API</div><h1>${esc(name)}</h1>
${rootDoc ? `<div class="lede">${docHtml(rootDoc, doc.roots[0] ?? "")}</div>` : `<p class="lede">${esc(name)}'s modules, declarations and claims, generated from its code.</p>`}</header>
<p class="inputs">${[
			plural(shown.length, "module"),
			plural(loose.length, "declaration"),
			`${plural(theorems.length, "theorem")}${unproved.length ? `, <span class="bad">${unproved.length} with other axioms</span>` : ", every one on the standard axioms"}`,
			rows.length ? `${plural(rows.length, "claim")} (${tally.map(([h, k]) => `${k} ${h}`).join(", ")})` : "",
			doc.doctests.checked ? `${plural(doc.doctests.blocks, "doc test")}${doc.doctests.failed ? `, ${doc.doctests.failed} failed` : ", all passing"}` : "",
			hiddenPrivate ? `${plural(hiddenPrivate, "private declaration")} hidden` : "",
			...ctx.inputs,
		]
			.filter(Boolean)
			.join(" · ")}</p>
<h2>Modules <span class="n">${shown.length}</span></h2>
<div class="wrap"><table class="mods"><thead><tr><th>Module</th><th>Decls</th><th>Claims</th><th>About</th></tr></thead><tbody>${tree}</tbody></table></div>`,
	);

	// ---- Claims: every id, as an address book ------------------------------------------------------
	if (rows.length) {
		const slots = (r: Row) => KINDS.map((k) => `<td class="slot">${r.marks.find((m) => m.kind === k) ? chip(r.marks.find((m) => m.kind === k)!) : ""}</td>`).join("");
		out["claims.html"] = shell(
			"claims.html",
			`Claims · ${name} docs`,
			`<header class="page"><div class="eyebrow">${esc(name)} · claims</div><h1>Claims</h1>
<p class="lede">Every claim ${esc(name)} declares, by id. Each links to its entry in the module that declares it, with its statement, its proofs and the evidence from this build.</p></header>
<div class="wrap"><table class="claims"><thead><tr><th>Id</th><th>Claim</th><th>Kind</th><th>Reads as</th>${KINDS.map((k) => `<th>${k}</th>`).join("")}<th>Module</th></tr></thead><tbody>${rows
				.map((r) => `<tr${r.claim.retired ? ' class="retired"' : ""}><td class="id">${claimLink(r.claim.id, r.claim.ref)}</td><td>${esc(r.claim.title)}</td><td class="kind">${r.claim.kind}</td><td>${headline(r.headline)}</td>${slots(r)}<td><a href="${pageOf(r.claim.module)}">${esc(r.claim.module)}</a></td></tr>`)
				.join("")}</tbody></table></div>`,
		);
	}

	// ---- Search ------------------------------------------------------------------------------------
	const plain = (s: string | null) => (s ?? "").replace(/```[\s\S]*?```/g, " ").replace(/[`*_#|]/g, "").replace(/\s+/g, " ").trim().slice(0, 280);
	const index: [string, string, string, string][] = [
		...shown.map((m) => [m.name, "module", pageOf(m.name), plain(m.docs[0]?.doc ?? null)] as [string, string, string, string]),
		...loose.map((d) => [d.name, d.kind, `${pageOf(d.module)}#${pct(d.name)}`, plain(d.doc)] as [string, string, string, string]),
		...rows.map((r) => [`${r.claim.ref} ${r.claim.title}`, r.claim.kind, claimHref.get(r.claim.id)!, plain(`${r.claim.does} ${r.claim.sees}`)] as [string, string, string, string]),
	];
	out["search-index.js"] = `window.CAIRN_DOC_INDEX = ${JSON.stringify(index)};\n`;

	// Every claim and every visible declaration must be addressable.
	for (const r of rows) if (!out[pageOf(r.claim.module)]?.includes(` id="${r.claim.id}"`)) throw new Error(`^${r.claim.id} is on no page`);
	for (const d of visible) if (!out[pageOf(d.module)]?.includes(` id="${esc(d.name)}"`)) throw new Error(`${d.name} is on no page`);
	return out;
}

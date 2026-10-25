// The claim pages: /packages/<name>/[<version>/]claims/ and …/claims/<id>/ (docs/claim-pages.md).
// Every package on the registry gets them, rendered here from two JSON answers of the registry:
// the version's ledger (`…/versions/<v>/claims`, its claims.lock) and its claims export
// (`…/versions/<v>/claims/export`, `lake exe claims --scope <name>` as `cairn publish` sent it,
// re-encoded by the registry). A version published without an export gets pages from its ledger
// alone. Nothing here is written by hand and nothing is an agent's: titles and prose come from
// the claims, and every status from the export. Every field is a publisher's text, so all of it
// is escaped; the registry serves no HTML and the site renders all of it.
//
// Evidence on these pages is only what the export holds: proved (each evidence theorem and its
// axioms), assumed, a flow's witness, retired and moved. Fuzzing, conformance and screenshots
// need a build that runs the app; until a CI step publishes them (#95) they read "not shown yet".
//
// A claim's own page, …/claims/<id>/, is where a picture of it will go: its place with its
// control highlighted, as PNG or SVG, at …/claims/<id>/<file> (host/Sources/CairnCapture can
// draw it). Not yet; the route answers nothing under a claim's page.

const esc = (value) =>
	String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export const ID = /^\d{1,9}$/;

/** The evidence a kind of claim can have once a CI step publishes it, and what each would say. */
const LATER = {
	fuzzed: "the claim-driven fuzzer held it in every random sequence (docs/fuzz.md)",
	tested: "the running app matched the model at every step that exercised it (docs/conformance.md)",
	seen: "a screenshot of the app shows it",
};
const EXPECTED = {
	move: ["fuzzed", "tested", "seen"],
	flow: ["tested", "seen"],
	invariant: ["fuzzed", "tested"],
	assume: ["fuzzed"],
	place: ["seen"],
};

/** `moved:yap` or `moved yap` → `yap`. */
const movedTo = (status) => (/^moved[: ]/.test(status) ? status.slice(6) : undefined);

/**
 * One claim's reading, from what the export and the ledger say: `retired`, `moved`, `assumed`,
 * `proved` (every evidence theorem proved from the standard axioms), `unproved` (one isn't), `open`
 * (a move, flow or invariant that names no theorem, or a place, which has nothing to prove), or
 * `ledger` (the version has no export, so only its ledger row is known).
 */
export function reading(c) {
	if (c.status === "retired" || c.detail?.retired) return "retired";
	if (movedTo(c.status)) return "moved";
	if (!c.detail) return "ledger";
	if (c.kind === "assume") return "assumed";
	const thms = c.detail.evidence ?? [];
	if (!thms.length) return "open";
	return thms.every((t) => t.proved && !(t.extraAxioms ?? []).length) ? "proved" : "unproved";
}

const LABEL = { retired: "retired", moved: "moved", assumed: "assumed", proved: "proved", unproved: "not proved", open: "no proof", ledger: "ledger only" };

/**
 * The claims of one version: the ledger's rows, each with its export entry (`detail`) when the
 * export has it, and how they group by place. A flow belongs to its own place, or else to the
 * place of its first witness step's move; any other claim to the place it names.
 */
export function model(name, version, ledger, exp) {
	const details = new Map((exp?.claims ?? []).map((d) => [d.id, d]));
	const claims = ledger.map((row) => ({ ...row, detail: details.get(row.id) }));
	// The registry refuses an export whose ids aren't in the ledger; keep any anyway.
	for (const d of details.values()) {
		if (!claims.some((c) => c.id === d.id)) claims.push({ id: d.id, kind: d.kind, status: d.retired ? "retired" : "active", statement: d.statement, title: d.title, detail: d });
	}
	claims.sort((a, b) => a.id - b.id);
	const byId = new Map(claims.map((c) => [c.id, c]));
	const placeOf = (c) => {
		const d = c.detail;
		if (!d) return null;
		if (d.place != null && byId.get(d.place)?.kind === "place") return d.place;
		if (c.kind === "flow") {
			const first = (d.witness ?? [])[0];
			const move = first && byId.get(first.claim);
			const at = move?.detail?.place;
			if (at != null && byId.get(at)?.kind === "place") return at;
		}
		return null;
	};
	for (const c of claims) c.place = c.kind === "place" ? null : placeOf(c);
	const places = claims.filter((c) => c.kind === "place" && !movedTo(c.status));
	return { name, version, exported: Boolean(exp), modules: exp?.modules ?? [], claims, byId, places };
}

const ref = (m, id) => `${m.name}^${id}`;

/** The claims of a place, by kind: moves, flows, invariants, assumptions. */
const ORDER = ["move", "flow", "invariant", "assume", "place"];
const KIND_TITLE = { move: "Moves", flow: "Flows", invariant: "Invariants", assume: "Assumptions", place: "Places" };
const byKind = (list) => ORDER.map((k) => [k, list.filter((c) => c.kind === k)]).filter(([, l]) => l.length);

const chip = (r) => `<span class="chip ev ${r}">${LABEL[r]}</span>`;

/** A table of claims: id, kind, title, reading. Each row is anchored by its id. */
function table(m, list, base, { kind = true } = {}) {
	if (!list.length) return "";
	const rows = list
		.map((c) => {
			const r = reading(c);
			const d = c.detail;
			const said = d?.does ? `<span class="does">${esc(d.does)}</span>` : "";
			return `<tr id="${c.id}" class="${r}"><td><a href="${base}${c.id}/"><code>${esc(ref(m, c.id))}</code></a></td>${kind ? `<td>${esc(c.kind)}</td>` : ""}<td><a href="${base}${c.id}/">${esc(d?.title ?? c.title)}</a>${said}</td><td>${chip(r)}</td></tr>`;
		})
		.join("\n");
	return `<div class="wrap"><table class="ledger claims"><thead><tr><th>Id</th>${kind ? "<th>Kind</th>" : ""}<th>Claim</th><th>Reads as</th></tr></thead><tbody>
${rows}
</tbody></table></div>`;
}

/** What each reading means, and what isn't shown yet. */
function legend(m) {
	return `<aside class="note"><div class="card px"><p class="label"><img src="/icon.svg" alt="">How to read these</p>
<p>${chip("proved")} every theorem the claim names is proved in Lean from its standard axioms. ${chip("unproved")} one isn't, or uses another axiom. ${chip("assumed")} stated and relied on, never proved: the trusted base. ${chip("open")} names no theorem (a place has nothing to prove). ${chip("retired")} and ${chip("moved")} keep their ids for ever.</p>
<p><strong>Not shown yet:</strong> fuzzed, tested and seen. They need a build that runs the app, which a CI step will publish with each version (#95); until then no claim shows them, rather than a status we can't back.${m.exported ? "" : " This version also has no claims export, so its pages show only its ledger: ids, kinds, titles and status."}</p>
</div></aside>`;
}

/** Counts of the readings, as chips. */
function tally(m) {
	const n = {};
	for (const c of m.claims) n[reading(c)] = (n[reading(c)] ?? 0) + 1;
	return `<span class="chips">${Object.keys(LABEL)
		.filter((r) => n[r])
		.map((r) => `<span class="chip ev ${r}">${n[r]} ${LABEL[r]}</span>`)
		.join("")}</span>`;
}

/** The overview: every place with its claims, then what belongs to no place, then moved ids. */
export function overview(m, base) {
	const placed = new Set();
	const sections = m.places.map((p) => {
		const inside = m.claims.filter((c) => c.place === p.id);
		for (const c of inside) placed.add(c.id);
		const d = p.detail;
		return `<section class="place" id="place-${p.id}">
<h2><a href="${base}${p.id}/">${esc(d?.title ?? p.title)}</a> <code class="id">${esc(ref(m, p.id))}</code>${p.status !== "active" ? ` ${chip(reading(p))}` : ""}</h2>
${d?.does ? `<p>${esc(d.does)}</p>` : ""}
${inside.length ? byKind(inside).map(([k, l]) => `<h3>${KIND_TITLE[k]}</h3>\n${table(m, l, base, { kind: false })}`).join("\n") : `<p class="muted">${m.exported ? "No claim names this place." : "Which claims are in this place is in the claims export, which this version doesn't have."}</p>`}
</section>`;
	});
	const rest = m.claims.filter((c) => c.kind !== "place" && !placed.has(c.id) && !movedTo(c.status));
	const moved = m.claims.filter((c) => movedTo(c.status));
	const groups = [];
	const loose = rest.filter((c) => c.kind === "move" || c.kind === "flow");
	if (loose.length) groups.push(["elsewhere", m.exported ? "Not in a place" : "Moves and flows", m.exported ? "Moves and flows that name no place." : "", loose]);
	const inv = rest.filter((c) => c.kind === "invariant");
	if (inv.length) groups.push(["invariants", "Invariants", "What holds in every state the app can reach.", inv]);
	const assumes = rest.filter((c) => c.kind === "assume");
	const other = rest.filter((c) => !["move", "flow", "invariant", "assume"].includes(c.kind));
	const assumeSection = () => {
		if (!assumes.length) return "";
		// By module: an app's own assumptions apart from the framework's trusted base.
		const mods = new Map();
		for (const c of assumes) {
			const key = c.detail?.module ?? "";
			if (!mods.has(key)) mods.set(key, []);
			mods.get(key).push(c);
		}
		const parts = [...mods.entries()].map(([mod, l]) => (mods.size > 1 || mod ? `<h3>${mod ? `<code>${esc(mod)}</code>` : "Other"}</h3>\n${table(m, l, base, { kind: false })}` : table(m, l, base, { kind: false })));
		return `<section id="assumptions"><h2>Assumptions</h2>
<p>What the proofs rely on and nothing proves: the host, the OS and the hardware behaving as stated.${m.name === "cairn" ? ` Cairn's own are its trusted base (<a href="/docs/internals/trusted-base/">docs</a>).` : ""}</p>
${parts.join("\n")}</section>`;
	};
	return `<p class="lede-row">${tally(m)}</p>
${legend(m)}
${m.places.length ? `<nav class="places" aria-label="Places"><span>Places:</span> ${m.places.map((p) => `<a href="#place-${p.id}">${esc(p.detail?.title ?? p.title)}</a>`).join("")}${assumes.length ? `<a href="#assumptions">Assumptions</a>` : ""}</nav>` : ""}
<section class="prose wide">
${sections.join("\n")}
${groups.map(([id, title, text, l]) => `<section id="${id}"><h2>${title}</h2>${text ? `<p>${text}</p>` : ""}\n${table(m, l, base, { kind: id !== "invariants" })}</section>`).join("\n")}
${assumeSection()}
${other.length ? `<section id="other"><h2>Other claims</h2>${table(m, other, base)}</section>` : ""}
${moved.length ? `<section id="moved"><h2>Moved to other packages</h2><p>Ids this package issued and another now owns. They stay issued here and can't come back.</p>
<div class="wrap"><table class="ledger claims"><thead><tr><th>Id</th><th>Kind</th><th>Claim</th><th>Now in</th></tr></thead><tbody>
${moved.map((c) => `<tr id="${c.id}" class="moved"><td><code>${esc(ref(m, c.id))}</code></td><td>${esc(c.kind)}</td><td>${esc(c.title)}</td><td><a href="/packages/${esc(movedTo(c.status))}/claims/${c.id}/"><code>${esc(movedTo(c.status))}^${c.id}</code></a></td></tr>`).join("\n")}
</tbody></table></div></section>` : ""}
${m.claims.length ? "" : "<p>This version makes no claims.</p>"}
</section>`;
}

/** One step of a flow's witness, as a sentence: what is done to which control. */
function step(m, s, base) {
	const target = m.byId.get(s.claim);
	const name = target ? esc(target.detail?.title ?? target.title) : "";
	const what = s.op ? `${esc(s.op.kind)}${s.op.text != null ? ` <code>${esc(JSON.stringify(s.op.text))}</code>` : ""}` : "";
	return `<li><span class="trigger">${esc(s.trigger)}</span>${what ? ` ${what}` : ""} on <a href="${base}${s.claim}/"><code>${esc(s.ref)}</code></a>${name ? ` ${name}` : ""}</li>`;
}

/** Evidence rows for one claim: its theorems, and what isn't shown yet. */
function evidence(m, c) {
	const d = c.detail;
	const r = reading(c);
	if (r === "retired") return `<p>${chip("retired")} ${d?.retired ? esc(d.retired) : "Retired: the id stays issued and can't be reused."}</p>`;
	if (r === "moved") {
		const to = movedTo(c.status);
		return `<p>${chip("moved")} Now <a href="/packages/${esc(to)}/claims/${c.id}/"><code>${esc(to)}^${c.id}</code></a>. The id stays issued here and can't come back.</p>`;
	}
	if (!d) return `<p>${chip("ledger")} This version was published without a claims export, so its pages know only the ledger row below.</p>`;
	const rows = [];
	if (c.kind === "assume") rows.push(`<tr><td>${chip("assumed")}</td><td colspan="2">Stated, not proved. The proofs rely on it.</td></tr>`);
	for (const t of d.evidence ?? []) {
		const ok = t.proved && !(t.extraAxioms ?? []).length;
		rows.push(
			`<tr><td>${chip(ok ? "proved" : "unproved")}</td><td>${esc(t.role)}</td><td><code>${esc(t.theorem)}</code>${(t.extraAxioms ?? []).length ? `<br><span class="bad">uses ${t.extraAxioms.map((a) => `<code>${esc(a)}</code>`).join(", ")}</span>` : ""}</td></tr>`,
		);
	}
	if (!(d.evidence ?? []).length && c.kind !== "assume") {
		rows.push(`<tr><td>${chip("open")}</td><td colspan="2">${c.kind === "place" ? "A place states where claims live; it has nothing to prove." : "The claim names no theorem."}</td></tr>`);
	}
	for (const k of EXPECTED[c.kind] ?? []) {
		const how = k === "fuzzed" && c.kind === "assume" && d.check ? `the trusted-base fuzzer's check <code>${esc(d.check)}</code> held` : LATER[k];
		rows.push(`<tr class="later"><td><span class="chip ev later">${k}</span></td><td colspan="2">Not shown yet: ${how}. A CI step will publish it (#95).</td></tr>`);
	}
	return `<div class="wrap"><table class="evidence"><tbody>
${rows.join("\n")}
</tbody></table></div>`;
}

/** One claim's page: what it says, where it lives, its evidence and where it is defined. */
export function claimPage(m, c, base) {
	const d = c.detail;
	const place = c.place != null ? m.byId.get(c.place) : undefined;
	const facts = [
		["Id", `<code>${esc(ref(m, c.id))}</code>`],
		["Kind", esc(c.kind)],
		["Reads as", chip(reading(c))],
		place ? ["Place", `<a href="${base}${place.id}/">${esc(place.detail?.title ?? place.title)}</a> <code>^${place.id}</code>`] : null,
		["Version", `<a href="/packages/${esc(m.name)}/${esc(m.version)}/">${esc(m.version)}</a>`],
	].filter(Boolean);
	const inside = c.kind === "place" ? m.claims.filter((x) => x.place === c.id) : [];
	const defined = d
		? `<h2 id="defined">Where it's defined</h2>
<dl class="defs">
<div><dt>Declaration</dt><dd><code>${esc(d.decl)}</code></dd></div>
<div><dt>Module</dt><dd><code>${esc(d.module)}</code></dd></div>
<div><dt>Source</dt><dd><code>${esc(d.pos?.file)}${d.pos?.line != null ? `:${esc(d.pos.line)}` : ""}</code> at <code>v${esc(m.version)}</code></dd></div>
${d.machine ? `<div><dt>Machine</dt><dd><code>${esc(d.machine)}</code></dd></div>` : ""}
${(d.statementDecls ?? []).length ? `<div><dt>Statement</dt><dd>${d.statementDecls.map((s) => `<code>${esc(s)}</code>`).join(" ")}</dd></div>` : ""}
<div><dt>Statement hash</dt><dd><code>${esc(d.statement)}</code></dd></div>
</dl>`
		: "";
	return `<div class="facts px"><dl>
${facts.map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join("\n")}
</dl>
<p class="go"><a href="${base}#${c.id}">All of ${esc(m.name)} ${esc(m.version)}'s claims</a></p>
</div>
<section class="prose wide claim">
${d?.does ? `<h2 id="does">${c.kind === "place" ? "What it is" : c.kind === "assume" || c.kind === "invariant" ? "What it says" : "What you do"}</h2>\n<p class="said">${esc(d.does)}</p>` : ""}
${d?.sees ? `<h2 id="sees">What you see</h2>\n<p class="said">${esc(d.sees)}</p>` : ""}
${c.kind === "flow" && (d?.witness ?? []).length ? `<h2 id="steps">Steps</h2>\n<p>The witness its liveness proof follows, from the app's first state.</p>\n<ol class="steps">${d.witness.map((s) => step(m, s, base)).join("\n")}</ol>` : ""}
${c.kind === "place" ? `<h2 id="in">In this place</h2>\n${inside.length ? byKind(inside).map(([k, l]) => `<h3>${KIND_TITLE[k]}</h3>\n${table(m, l, base, { kind: false })}`).join("\n") : `<p class="muted">${m.exported ? "No claim names this place." : "Which claims are in this place is in the claims export, which this version doesn't have."}</p>`}` : ""}
<h2 id="evidence">Evidence</h2>
${evidence(m, c)}
${defined}
<h2 id="ledger">Ledger</h2>
<p><code>${esc(ref(m, c.id))}</code> is <strong>${esc(c.status)}</strong> in this version's <code>claims.lock</code>${c.statement && c.statement !== "-" ? `, statement <code>${esc(c.statement)}</code>` : ""}. An id never moves or changes meaning.</p>
</section>`;
}

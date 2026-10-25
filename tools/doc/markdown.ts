// cairn doc's llms.txt: the same package as the pages, as one Markdown file for a language model
// (docs/doc.md). Every claim with its evidence first, since that is what Cairn adds to an API,
// then every module's public declarations with their signatures and doc comments. Pure, like
// render.ts, and from the same inputs.
import { type Claim, type Row } from "../map/evidence";
import type { Context, Decl, Seg } from "./render";

const text = (ss: Seg[]) => ss.map((s) => (typeof s === "string" ? s : s[0])).join("");
const prefixOf = (name: string) => name.slice(0, Math.max(0, name.lastIndexOf(".")));
const plural = (n: number, one: string, many = `${one}s`) => `${n.toLocaleString("en")} ${n === 1 ? one : many}`;
// A fenced block that can't be closed early by the text inside it.
const fence = (body: string, lang = "lean") => {
	const ticks = "`".repeat(Math.max(3, ...[...body.matchAll(/`+/g)].map((m) => m[0].length + 1)));
	return `${ticks}${lang}\n${body}\n${ticks}`;
};
// Doc comments are Markdown already; their headings move under the declaration's.
const docText = (doc: string | null, depth: number) =>
	(doc ?? "").trim().replace(/^(#+) /gm, (_, h: string) => `${"#".repeat(Math.min(6, h.length + depth))} `);

const KIND_ORDER = ["structure", "inductive", "class", "def", "abbrev", "opaque", "theorem", "axiom", "instance"];

export function markdown(ctx: Context): string {
	const { doc, rows, name } = ctx;
	const issued = (n: string) => n.startsWith("Cairn.Claims.Issued.");
	const visible = doc.decls.filter((d) => (ctx.showPrivate || !d.private) && !issued(d.name));
	// The declarations a claim's command generates are part of the claim, not the API.
	const claimDecls = new Set(rows.map((r) => r.claim.decl));
	const owned = (n: string) => {
		for (let p = n; p; p = prefixOf(p)) if (claimDecls.has(p)) return true;
		return false;
	};
	const loose = visible.filter((d) => !owned(d.name));
	const byId = new Map(rows.map((r) => [r.claim.id, r]));

	const out: string[] = [];
	out.push(`# ${name}: API reference`);
	out.push(
		`> ${name}'s modules, declarations and claims, generated from the code by \`cairn doc\`: ${plural(doc.modules.length, "module")}, ${plural(loose.length, "declaration")}${rows.length ? `, ${plural(rows.length, "claim")}` : ""}.`,
	);
	if (rows.length)
		out.push(
			"A claim is a promise about the UI with a durable id, `^N` (`cairn^N` in full): a **move** a person can make, a **flow** of moves, an **invariant**, a **place** moves happen in, or an **assume**d fact about the host. Each one's reading is its strongest evidence: proved (a Lean theorem, checked by the kernel, using only the standard axioms), fuzzed, tested (conformance runs on the real app), seen (captured on screen), or assumed; broken if any evidence failed, untested if it has none. Ids are never reused or renumbered.",
		);

	if (rows.length) {
		out.push("## Claims");
		for (const r of rows) out.push(claimMd(r, byId, doc.statements));
	}

	out.push("## Modules");
	for (const m of doc.modules) {
		const decls = loose
			.filter((d) => d.module === m.name)
			.sort((a, b) => KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind) || a.line - b.line);
		const intro = m.docs.map((d) => d.doc.trim()).filter(Boolean);
		if (!decls.length && !intro.length) continue;
		out.push(`### ${m.name}`);
		out.push(`Source: \`${m.file}\``);
		for (const d of intro) out.push(docText(d, 3));
		for (const d of decls.filter((d) => d.kind !== "instance")) out.push(declMd(d));
		// Instances, one line: the class and what it's for are the signature.
		const insts = decls.filter((d) => d.kind === "instance");
		if (insts.length) out.push(`Instances: ${insts.map((d) => `\`${text(d.sig).replace(/^\S+ : /, "")}\``).join(", ")}`);
	}
	return out.join("\n\n").replace(/\n{3,}/g, "\n\n") + "\n";
}

function declMd(d: Decl): string {
	const parts = [`#### ${d.private ? "private " : ""}${d.kind} \`${d.name}\``];
	const extra = d.axioms?.length ? ` (uses ${d.axioms.join(", ")})` : "";
	parts.push(fence(text(d.sig)) + (d.kind === "theorem" ? `\n${d.axioms === null ? "" : `Proved${extra}.`}` : ""));
	if (d.doc) parts.push(docText(d.doc, 4));
	if (d.fields.length) parts.push(`Fields:\n${d.fields.map((f) => `- \`${f.name} : ${text(f.type)}\`${f.doc ? `: ${f.doc.trim().replace(/\s+/g, " ")}` : ""}`).join("\n")}`);
	if (d.ctors.length) parts.push(`Constructors:\n${d.ctors.map((c) => `- \`${text(c.sig)}\`${c.doc ? `: ${c.doc.trim().replace(/\s+/g, " ")}` : ""}`).join("\n")}`);
	return parts.join("\n\n");
}

function claimMd(r: Row, byId: Map<number, Row>, statements: Context["doc"]["statements"]): string {
	const c = r.claim as Claim & { statementDecls?: string[] };
	const lines = [`### ${c.ref} ${c.title}`, `${c.kind}, ${r.headline}. Source: \`${c.pos.file}${c.pos.line ? `:${c.pos.line}` : ""}\`, \`${c.decl}\`. Ledger: ${r.ledger}.`];
	if (c.retired) lines.push(`Retired: ${c.retired}`);
	else {
		if (c.does) lines.push(`Does: ${c.does}`);
		if (c.sees) lines.push(`Sees: ${c.sees}`);
	}
	if (c.place !== null) lines.push(`In: ^${c.place}${byId.has(c.place) ? ` ${byId.get(c.place)!.claim.title}` : ""}`);
	const stmt = (c.statementDecls ?? []).map((n) => {
		const s = statements[n];
		const short = n.startsWith(`${c.decl}.`) ? n.slice(c.decl.length + 1) : n;
		if (!s) return short;
		if (s.body) return `${short}${s.binders?.length ? ` ${s.binders.join(" ")}` : ""} := ${text(s.body)}`;
		return `${short}${text(s.sig ?? [])}`;
	});
	if (stmt.length) lines.push(`Formal statement:\n\n${fence(stmt.join("\n"))}`);
	const steps = Array.isArray(c.witness) ? c.witness : [];
	if (c.kind === "flow" && steps.length) lines.push(`Witness:\n${steps.map((s, i) => `${i + 1}. ${s.trigger} ${s.ref}`).join("\n")}`);
	if (r.marks.length) lines.push(`Evidence:\n${r.marks.map((m) => `- ${m.kind}: ${m.state}. ${m.detail}`).join("\n")}`);
	if (r.findings.length) lines.push(`Findings:\n${r.findings.map((f) => `- ${f.broken ? "Broken: " : ""}${f.text}`).join("\n")}`);
	if (r.theorems.length) lines.push(`Proofs:\n${r.theorems.map((t) => `- \`${t.theorem}\` (${t.role}): ${t.ok ? "proved" : t.ok === null ? "not audited" : `uses ${t.extraAxioms.join(", ") || "a failed check"}`}`).join("\n")}`);
	return lines.join("\n\n");
}

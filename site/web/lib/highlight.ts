// Code samples, highlighted by Shiki when bongo builds. Lean goes through `cairn`, a grammar on
// top of Shiki's Lean 4 grammar that knows Cairn's own syntax (lean/Cairn/Claims/Elab.lean): the
// claim commands, claim ids, the clauses inside a claim, and the `moves%` terms. Shiki's colours
// are not used: each token's scopes map to one of the site's classes (kw, id, str, cm), which
// docs.css colours, so the code matches the rest of the site.
import { createHighlighter, type LanguageRegistration } from "shiki";

// The claim commands' keywords are not reserved in Lean (`move` stays usable as a name), so they
// count only where a claim starts: at the start of a line, before its id.
const COMMANDS = "move|flow|invariant|assume|place|retire";
// A clause opens an indented line of a claim: prose (`does "…"`), a definition
// (`post s' := …`), a handler (`on press`) or a witness (`witness press ^1, …`).
const PROSE = "does|sees|check";
const DEFN = "post|sound|apply|emit|enabled|goal|holds|init|step|receive|statement|reaches";

export const cairn: LanguageRegistration = {
	name: "cairn",
	scopeName: "source.cairn",
	embeddedLangs: ["lean"],
	patterns: [
		{
			match: `^(?:(@\\[[^\\]\\n]*\\])\\s*)?(${COMMANDS})(?=\\s+\\^\\d)`,
			captures: { 1: { name: "storage.modifier.attribute.cairn" }, 2: { name: "keyword.other.command.cairn" } },
		},
		// A whole attribute, `@[export cairn_app_init]`; Lean's grammar stops at the first space.
		{ match: "@\\[[^\\]\\n]*\\]", name: "storage.modifier.attribute.cairn" },
		{ match: "\\^\\d+(?:#\\d+)?", name: "constant.other.claim.cairn" },
		{ match: `^\\s+(${PROSE})(?=\\s+")`, captures: { 1: { name: "keyword.other.clause.cairn" } } },
		{ match: `^\\s+(${DEFN})(?=[^\\n]*?:=)`, captures: { 1: { name: "keyword.other.clause.cairn" } } },
		{ match: "^\\s+(on|witness)(?=\\s+\\w)", captures: { 1: { name: "keyword.other.clause.cairn" } } },
		{ match: '\\b(because)(?=\\s+")', captures: { 1: { name: "keyword.other.clause.cairn" } } },
		{ match: "\\b(?:moves|claims|fuzz_targets)%", name: "keyword.other.term.cairn" },
		{ include: "source.lean4" },
	],
};

// Lean's `--` comment rule includes this grammar (markdown in comments), which Shiki doesn't ship;
// without it the rule never matches and line comments come out plain.
const commentMarkdown: LanguageRegistration = { name: "lean4-markdown", scopeName: "source.lean4.markdown", patterns: [] };

const shiki = await createHighlighter({ langs: [commentMarkdown, "lean", cairn, "swift", "make"], themes: ["min-dark"] });

export const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// The site's class for a token's scopes, innermost first; none for plain text.
function classOf(scopes: string[]): string | null {
	for (const s of scopes) {
		if (s.startsWith("comment")) return "cm";
		if (s === "constant.other.claim.cairn") return "id";
		if (s.startsWith("entity.name.function.target")) return "kw";
		if (s.startsWith("string") || s.startsWith("constant.character")) return "str";
		if (s.startsWith("keyword") || s.startsWith("storage")) return s.startsWith("keyword.operator") ? null : "kw";
	}
	return null;
}

export function highlight(code: string, lang: string): string {
	if (lang === "md") return esc(code);
	const { tokens } = shiki.codeToTokens(code, { lang: lang === "lean" ? "cairn" : lang, theme: "min-dark", includeExplanation: "scopeName" });
	return tokens
		.map((line) => {
			let out = "";
			let cls: string | null = null;
			let run = "";
			const flush = () => {
				if (run) out += cls ? `<span class="${cls}">${esc(run)}</span>` : esc(run);
				run = "";
			};
			for (const t of line)
				for (const part of t.explanation ?? [{ content: t.content, scopes: [] }]) {
					const c = classOf(part.scopes.map((s) => s.scopeName).reverse());
					if (c !== cls) flush();
					cls = c;
					run += part.content;
				}
			flush();
			return out;
		})
		.join("\n");
}

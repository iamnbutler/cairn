---
title: "Lean's website and docs: lean-lang.org, the reference, Mathlib docs, Reservoir, Loogle, live.lean-lang.org"
urls:
  - https://lean-lang.org/
  - https://lean-lang.org/learn/
  - https://lean-lang.org/install/
  - https://lean-lang.org/doc/reference/latest/
  - https://lean-lang.org/doc/reference/latest/Error-Explanations/
  - https://lean-lang.org/doc/reference/latest/ValidatingProofs/
  - https://verso.lean-lang.org/
  - https://leanprover-community.github.io/mathlib4_docs/
  - https://github.com/leanprover/doc-gen4
  - https://reservoir.lean-lang.org/
  - https://reservoir.lean-lang.org/inclusion-criteria
  - https://reservoir.lean-lang.org/@leanprover-community/batteries
  - https://loogle.lean-lang.org/
  - https://live.lean-lang.org/
  - https://github.com/leanprover-community/lean4web
date: 2026-10-25
relevance: 5
---

# Lean's site and docs

Lean is Cairn's host language, so this note matters twice: Cairn's readers will already have
been through these pages, and Cairn's tooling (docs, registry, evidence) sits directly beside
Lean's. The strongest pieces are not on the marketing site: a page that ranks what a proof is
worth (*Validating a Lean Proof*), a doc system whose examples are type-checked (Verso),
search by type shape (Loogle), and a registry that records which toolchain each commit builds
on (Reservoir).

## 1. What the site and docs contain

**lean-lang.org** (fetched 2026-10-24).

- Top nav: Install, Learn, Community, Use Cases, FRO (About, Team, Roadmap, Contact); external
  links to Playground (live.lean-lang.org), Mathlib, CSLib, Reservoir, GitHub.
- Tagline: an open-source programming language and proof assistant for "correct, maintainable,
  formally verified code".
- Hero "Powerful automation": two `grind` examples. Then two worked samples (`IsPrime` with
  `exists_prime_factor`; factorial with `!` notation and `InfinitudeOfPrimes`), each with a link
  that opens it in the Playground.
- Three cards: Trustworthy ("minimal trusted kernel"), Powerful, Extensible.
- "Lean in Action": ArkLib, Veil, Cedar, Aeneas, Mathlib, Fermat's Last Theorem.
- "Growth and Impact": a dated news timeline (July–September 2026), testimonials (Terence Tao,
  Byron Cook, Pushmeet Kohli, Tudor Achim, Emina Torlak), sponsor logos.

**/learn/**: Core documentation (Functional Programming in Lean, Theorem Proving in Lean,
Mathematics in Lean, the Language Reference, FAQ), further reading (Mathlib API reference,
course texts, the founder's blog), interactive games (Natural Number Game), tools (VS Code
extension manual), resources (Loogle, Verso, LeanExplore, LeanSearch, LeanDojo, REPL,
Pantograph, lean4web), and how to cite Lean (with BibTeX).

**/install/**: VS Code first. Install VS Code, install the Lean 4 extension, follow its setup
guide; elan is not mentioned on the page; a manual path is at /install/manual.

**The Language Reference** (https://lean-lang.org/doc/reference/latest/): 26 chapters for Lean
4.36.0-rc1, then "Validating a Lean Proof", "Error Explanations", "Release Notes", "Supported
Platforms" and an index. Written in Verso.

**Error Explanations**: 14 entries named `lean.<camelCase>` (`lean.unknownIdentifier`,
`lean.synthInstanceFailed`, `lean.invalidField`, `lean.dependsOnNoncomputable`, …), each with a
summary, severity and a "Since" Lean version, and an "About" page.

**Validating a Lean Proof**: four levels of trust, in increasing strength:

1. the editor's blue ticks ("the theorem statement has been successfully elaborated" and the
   kernel accepted it), which trust imported libraries;
2. `#print axioms` (expected: `propext`, `Classical.choice`, `Quot.sound`; "If `sorryAx` is
   reported, then this theorem or one of its dependencies uses `sorry`"; "Any other axiom means
   that a custom axiom was declared and used");
3. `lean4checker`, which replays `.olean` declarations through the kernel (recommended in CI;
   it "trusts that the `.olean` files are structurally correct");
4. `comparator` plus external checkers such as `nanoda`, for "actively malicious proofs": the
   statement lives in a trusted file and the proof is built in a sandbox.

It separates an *honest* threat model ("mistakes and bugs in proofs and meta-code") from a
*malicious* one, and lists what even the gold standard still assumes ("no human error in the
challenge statement"; notation and instances must be inspected).

**Verso** (https://verso.lean-lang.org/): "Every code example is type-checked." "Every rendered
page is interactive" (proof states, hovers, links into docs). Genres: reference manuals,
textbooks, websites and blogs, blueprints. "Extensions are ordinary Lean functions."

**Mathlib docs (doc-gen4)**: one page per module with Imports / Imported by, a declaration list,
`source` links per declaration, search; the footer names the exact Lean commit it was built
with. doc-gen4 is a Lake facet: `lake build YourLibraryName:docs`; it "is perfectly capable of
generating documentation for Lean code that contains `sorry`, just not for code that doesn't
compile". Source links default to GitHub and can be switched (`DOCGEN_SRC="vscode"`).

**Reservoir** (https://reservoir.lean-lang.org/): "indexes, builds, and tests packages within
the Lean and Lake ecosystem." Home shows the latest stable toolchain, then Most Popular, Newly
Created, Recently Updated. Each entry shows a commit and "builds on" a toolchain (recent/old) or
"fails to build on". A package page (batteries) has Readme, Versions (114, each a commit with its
toolchain) and Dependents (583), licence, stars, and the `require` snippet for `lakefile.lean`
and `lakefile.toml`. Inclusion is automatic: public non-fork repo, a root `lake-manifest.json`,
an OSI licence, at least 2 stars; reindexed about daily.

**Loogle** (https://loogle.lean-lang.org/): search by constant (`Real.sin`), by name substring
(`"differ"`), by subexpression pattern with wildcards and metavariables (`_ * (_ ^ _)`,
`Real.sqrt ?a * Real.sqrt ?a`), by conclusion (`|- _ < _ → tsum _ < tsum _`), and combinations.
Argument order doesn't matter: `(?a -> ?b) -> List ?a -> List ?b` finds `List.map`. Available on
the web, in VS Code, in lean.nvim, as a CLI, and as a Zulip bot.

**live.lean-lang.org**: lean4web runs the Lean server on a server (in bubblewrap), not in the
browser. Its stated scope: "Doodling around with Lean before installing it as a newcomer", running
MWEs from Zulip "with the latest Mathlib installed", demos in talks, mobile. "Serious Lean code
development and larger projects are considered out-of-scope."

## 2. High-ROI pieces

1. **Every sample opens in the Playground.** The homepage samples link into live.lean-lang.org,
   so a reader goes from "this proof" to "I edited this proof" with no install. The Playground
   also serves the community's "minimal working example" habit on Zulip.
2. **Validating a Lean Proof.** It answers the question a sceptic actually asks ("how much should
   I trust this green tick?") with ranked, named checks and what each still assumes. This is the
   single page most worth imitating for Cairn.
3. **Docs that are checked.** Verso's "Every code example is type-checked" means the reference
   can't drift from the language; hovers make examples explorable.
4. **Search by shape (Loogle).** In a library of tens of thousands of lemmas, names aren't
   enough. Loogle meets people where they are (editor, CLI, chat bot), not just on a web page.
5. **Reservoir's build matrix.** "builds on v4.35.0" per commit tells a user whether a package
   works with their toolchain before they add it. Inclusion is automatic, so the index is
   complete without anyone submitting anything.
6. **Error explanations with stable names and "Since".** Small (14 entries) but growing, in the
   same reference as the language.
7. **One VS Code path for install.** The extension installs elan and the toolchain; the install
   page is three steps.

## 3. Low-value or missing

- **The homepage is aimed at funders as much as users**: testimonials, sponsor logos, a news
  timeline and FRO pages take most of its length. Useful for credibility, not for learning.
- **/learn lists ~25 resources across three hosts** (lean-lang.org, leanprover-community.github.io,
  personal sites). FPIL is "the main resource for programmers", but you have to read the list
  to know that.
- **Docs are scattered across hosts.** The API reference for core lives inside Mathlib's docs
  (leanprover-community.github.io/mathlib4_docs), a module URL I tried 404'd, and Reservoir's
  batteries page has no docs link (its README says to build docs locally).
- **Reservoir's versions are commits, not semver.** The page lists toolchains per commit; there
  is no notion of a release's contract, and no changelog.
- **live.lean-lang.org is a JS app** that shows nothing without scripts; Reservoir and the
  reference are plain HTML.

## 4. For Cairn: cut / keep / add

**Cut or shrink**

- **Duplicated evidence entry points.** The top nav's "Maps" goes to /docs/evidence/, which
  the sidebar also lists under Evidence, alongside each /map/<app>/, while /docs/reference/evidence/
  ("The evidence ladder") explains the levels. Lean has one page that explains trust levels and
  links out. Merge /docs/evidence/ and /docs/reference/evidence/ into one "Evidence" page (what
  each level means, then the maps), and keep /map/<app>/ as generated leaves.
- **/map/trusted/ as a top-level "app".** It is the host's assumptions with their fuzz checks:
  Cairn's `lean4checker` level, not an example app. List it on the evidence page as "what we
  trust", not beside Counter and TodoMVC.
- **Most of /docs/internals/** (host protocol, host effects, profiling, contributing) is for
  people working on Cairn, not with it. Lean keeps this in a separate dev guide; Cairn could
  move it under a "Contributing" heading at the bottom of the sidebar.

**Keep**

- **Homepage "What a claim is" and the evidence levels.** This is Cairn's version of "Trustworthy:
  minimal trusted kernel"; it's the idea, stated once, with code.
- **/docs/api/claims.html and the per-claim evidence columns.** Lean's docs say *what* a
  declaration is; Cairn's say what it is and *how sure we are*. Nothing in Lean's ecosystem does
  this.
- **The axiom audit and kernel replay** (`make check`), which map exactly onto Lean's levels 2
  and 3.

**Add**

1. **A "How much to trust a claim" page modelled on Validating a Lean Proof.** Rank Cairn's
   evidence (proved → fuzzed → tested → seen → assumed), and for each say what it rules out and
   what it still assumes: proved still trusts Lean's kernel and the host's assumptions in
   docs/trusted.md; seen trusts the capture. Include the honest vs malicious distinction (an app
   author can declare an `assume`; who checks it?). This replaces /docs/reference/evidence/.
2. **Link every homepage sample to something live.** Lean links samples to the Playground. Cairn's
   Reset button sample on the homepage should link to its claim on /map/counter/ (id, screenshot,
   evidence), so the first code a visitor sees opens onto evidence.
3. **Build status per version on /packages/**: "builds with Lean v4.35.0, macOS 27, cairn 0.2.0",
   and "fails" when it stops. Reservoir shows this is the first thing a user checks.
4. **Search across claims, not just names.** docs/doc.md's search index already covers names,
   doc comments and claims. Add a Loogle-style query on claim kind and statement ("moves whose
   `post` mentions `items`", "every `assume` in this package") on /docs/api/ and /packages/.
5. **The exact toolchain and commit in every generated page's footer**, as doc-gen4 does
   ("built using Lean 4 4.36.0-rc1" with a commit link). Maps already print their build; do the
   same on /docs/api/.

## 5. Ideas for the language and tooling

- **A `cairn verify` ladder like Lean's** (docs/cli.md, docs/trusted.md). Today `make check` runs
  the axiom audit and kernel replay. For a published package, the registry could run the
  equivalent of `comparator`: rebuild from source in a sandbox, re-audit axioms, replay the
  kernel, and record the result in the claim ledger, so a package's "proved" is checked by
  someone other than its author.
- **Write the docs in Verso, or steal its rule.** docs/doc.md chose "our own export, rendered
  beside the map". Verso's rule ("every code example is type-checked") is what Cairn's guides
  already approximate with "code samples are included from source built by `make check`". If the
  guides move to Verso, hovers and proof states come free, and claims could be a Verso genre.
  Worth re-reading docs/doc.md's decision with this in mind.
- **Error explanations in Lean's format** (issue #99, /docs/reference/errors/). Lean names errors
  `lean.<name>` with a "Since" version. Cairn's claims DSL can register its own under a `cairn.`
  prefix, so they show up in the same reference format and the same editor hovers.
- **Reservoir-style automatic indexing** (docs/package.md). Today a version enters Cairn's
  registry by `cairn publish`. Reservoir's rule (index anything that meets public criteria) is
  wrong for Cairn because the ledger must be checked at publish, but its build-and-test of every
  version against new toolchains is right: re-run each package's claims when Cairn or Lean
  moves, and show which still hold.
- **Toolchain pinning through the editor.** Lean's install is "install the VS Code extension";
  elan follows. Cairn's first-app needs four toolchains. A `cairn doctor` (planned in
  cairn-tool.md) that reads `lean-toolchain` and checks Xcode, the Metal toolchain and elan is
  the Cairn equivalent of the extension's setup guide.
- **A hosted proof playground for claims, not apps.** lean4web runs Lean on a server in
  bubblewrap. A Cairn variant could take a pure `update`/`view` snippet plus a claim and show
  whether it's proved, with the axiom list, without the Swift host. Out of scope for now
  (docs/roadmap.md lists no such item), but it's the only realistic "try Cairn without a Mac".

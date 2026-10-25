---
title: "Dafny's website, docs and VS Code experience, read for Cairn's site"
urls:
  - https://dafny.org/
  - https://dafny.org/latest/toc
  - https://dafny.org/latest/OnlineTutorial/guide
  - https://dafny.org/latest/DafnyRef/DafnyRef
  - https://dafny.org/latest/HowToFAQ/Errors
  - https://dafny.org/blog/
  - https://dafny.org/blog/2023/04/19/making-verification-compelling-visual-verification-feedback-for-dafny/
  - https://dafny.org/blog/2023/12/15/teaching-program-verification-in-dafny-at-amazon/
  - https://dafny.org/blog/2023/08/14/clear-specification-and-implementation/
  - https://dafny.org/blog/2023/12/01/avoiding-verification-brittleness/
  - https://marketplace.visualstudio.com/items?itemName=dafny-lang.ide-vscode
date: 2026-10-25
relevance: 5
---

# Dafny: pitching proofs to working programmers

Dafny is the verification language with the most industrial use (AWS Encryption SDK, Amazon
Verified Permissions, IronFleet) and the longest effort to make proofs feel like programming.
Its *site* is weak; its *IDE* and a few blog posts are where the persuasion actually happens.
Fetched 2026-10-24.

## 1. What the site and docs contain

**dafny.org homepage**: no nav bar, a list of links at the top: Install ("or just use the VS
Code extension"), Zulip, Reference Manual and User Guide, Resources for Users, Blog, YouTube,
GitHub, Documentation snapshots, and the book *Program Proofs* (Leino, MIT Press). Then three
dense paragraphs: "Dafny is a verification-aware programming language that has native support for
recording specifications and is equipped with a static program verifier … empowers developers to
write provably correct code (w.r.t. specifications)", compiles to "C#, Java, JavaScript, Go and
Python", and two long lists of features (subset types, lemmas, loop invariants, read/write
specifications…). It ends with one screenshot, "Dafny running in Visual Studio Code".

**Resources for Users** (`/latest/toc`): a link list. Quick start (Installation, Cheatsheet,
Quick Reference, Getting started tutorial, blog); detailed documents (Reference Manual, FAQs,
**"Explanations of Error and Warning messages"**, Verification optimization guide, Style Guide,
type-system reference); short tutorials (Value Types, Sets, Sequences, Lemmas and Induction,
Modules, Termination); a 4-part video course (pre/postconditions, invariants, binary search,
Dutch national flag, ~20 min each); papers and books.

**Getting started guide** (`/latest/OnlineTutorial/guide`): "Dafny is a language that is
designed to make it easy to write correct code … Dafny lifts the burden of writing bug-free code
into that of writing bug-free annotations. This is often easier than writing the code, because
annotations are shorter and more direct." It promises "no run time errors, such as index out of
bounds, null dereferences, division by zero" and termination, then teaches `method Abs`,
`requires`/`ensures`, loops and invariants, imperative examples first.

**Reference Manual** (one ~2.3 MB page): 19 chapters, grammar through types, specifications,
statements, refinement; ch. 13 the User's Guide (commands `dafny verify/run/build/test/format/
doc/audit/generate-tests`, and **13.7 "Verification debugging when verification fails"**:
failing postconditions, failing asserts, counterexamples, "when verification is slow",
"Analyzing proof dependencies", "Debugging brittle verification"); ch. 14 the VS Code extension.

**Errors catalog** (`/latest/HowToFAQ/Errors`): "a catalog of the dafny tool's Error and Warning
messages, all in one long page to facilitate searching. The title of each section is an error
message. Each section contains example code that produces the error, which is then followed by
explanation and references."

**Documentation snapshots**: the docs are versioned (`/latest/`, `/v3.9.0/`…).

**Blog** (`/blog/`, RSS): 2023–2025 posts from maintainers and guests: Dafny 4 release, visual
verification feedback, specification vs implementation, brittleness, teaching at Amazon, test
generation, a verified statistics library, `dafny-annotator` (AI-assisted annotation, 2025).

**No online playground.** The old rise4fun browser version is gone; the repo now says the
easiest way to try Dafny is VS Code. The extension (58k installs) installs the Dafny language
server on first start but asks you to install .NET yourself.

## 2. High-ROI pieces

- **The VS Code extension, specifically its gutter.** Mikael Mayer's post is the best thing
  Dafny has published on adoption: users asked "Is Dafny actually stuck?", "Can we not verify a
  single method at a time?", "Where are the hidden assertions? What are they proving?", "Are
  there still assertions to prove in my current method?" The answer was gutter icons designed on
  stated principles: "Verified is visible but the least distracting", shapes not just colours
  for colour-blind users, light/dark, "Past-awareness: Icons indicating ongoing computation should
  still display previous verification status", a green bar for verified, a red block for an
  error, yellow "clogged pipe" lines for a declaration with an error elsewhere, and a check
  circle for assertions proved past an earlier failure. A user said: "It's ridiculous how good
  all green gutter feels." Positive feedback, not just errors, is what made proofs engaging.
- **Walking through a failure, step by step.** The same post's Euclidean division example runs
  with `--no-verify` (works, 100% coverage), then verifies: "cannot prove termination; try
  supplying a decreases clause", then a postcondition fails and exposes a real `<=`/`<` bug.
  The pitch is *verification found a bug tests with full coverage missed*, shown, not asserted.
- **Error catalog with example code per message.** Searchable, one page, every message with a
  reproducer.
- **Verification debugging as documentation.** Reference 13.7 teaches a method: move the
  failing `assert` up, which is "similar to computing the weakest precondition". People stuck on
  a proof need a procedure, not more theory.
- **Separating programming from proving when teaching.** The Amazon course introduces Dafny "as a
  programming language (with no verification)", then "as a proof assistant (with no
  programming)", then verification. Its rationale: Leino's style where "'proving' amounts to
  explaining" is effective until automation falls short, and then "it may seem as if one needs to
  provide the right assertion at the right place, without a clear methodology".
- **Honest posts about failure modes.** "Avoiding verification brittleness" says proofs "may fail
  to verify after seemingly unrelated changes such as upgrading to a new version of Dafny … or
  even changing the name of a variable", and how to structure code to avoid it.

## 3. Low-value or missing

- **The homepage is a feature list.** Two paragraphs of nouns (subset types, iterators,
  calculational proofs) with no example program, no failure, no "why". The compelling material
  (the Euclidean division walkthrough, the gutter) is buried in a 2023 blog post.
- **No primary action and no playground.** Install requires .NET; there is nothing to try
  without installing.
- **Docs IA is a link list** across `/latest/`, snapshots, GitHub wikis, MSR PDFs, Stack
  Overflow and videos. No single linear path.
- **A 2.3 MB single-page reference manual.** Searchable with Ctrl-F, hard to link or skim.
- **"Testing syntax rendering"** is a chapter of the published reference manual (ch. 18), an
  internal page leaking into user docs.
- **Little on what verification does *not* cover** on the homepage: trust in the compilers to
  C#/Java/Go, `{:extern}` code and `assume` statements are in the manual (`dafny audit`), not in
  the pitch.

## 4. For Cairn: cut / keep / add

Cairn has what Dafny's homepage lacks (a concrete annotated claim, an evidence ladder, maps of
real apps) and lacks what Dafny's IDE and blog do best (a felt verification loop, failure
walkthroughs, a debugging method).

**Keep**

- **"How sure we are" and `/docs/reference/evidence/`.** The ladder (proved, fuzzed, tested,
  seen, assumed) and the statement that "Proved and fuzzed are about the Lean model; tested and
  seen are about the app" is clearer than anything on dafny.org about what verification does and
  doesn't cover. Keep it prominent.
- **The trusted base and its map** (`/map/trusted/`, `/docs/internals/trusted-base/`). This is
  `dafny audit` as a page. Keep; it answers the sceptic's first question.
- **The maps.** They are Cairn's green gutter at product scale: every claim with a status. Keep,
  and see below about making them the primary action.

**Cut or demote**

- **Long dense paragraphs on the homepage.** Dafny shows how a feature list loses readers.
  "Not a layer on top" and "The idea" overlap; merge them into three sentences.
- **"Maps" as a bare top-nav word.** It points to four example maps, which is right, but "Maps"
  means nothing to a newcomer (and the name is being reconsidered). Until it's renamed, label the
  homepage link by what it shows: "Every claim, with its evidence".
- **"Internals" in the user sidebar** (host protocol, host effects, profiling, contributing).
  Dafny's "Testing syntax rendering" chapter is the cautionary example. Move to a separate
  "Contributing to Cairn" section or leave in the repo's `docs/`.

**Add**

- **A failure walkthrough, the Euclidean-division post for Cairn.** A short page (or homepage
  section with a video): a TodoMVC-sized move whose handler has the bug Quickstrom found in real
  implementations (e.g. "Toggle all doesn't untoggle when filtered", see
  [../../quickstrom/README.md](../../quickstrom/README.md)); it runs, it passes a click-through
  test, then the proof fails with the exact Lean error, then the one-line fix. That is the most
  persuasive possible artifact for "why proofs" aimed at working programmers.
- **"When a proof fails"**: a guide chapter after "Proving a claim" with a procedure per common
  failure: presence fails (the control is drawn when the move is disabled), pressable fails
  (something overlaps it), a frame condition fails, `omega` gives up on layout arithmetic, a proof
  breaks after a Lean upgrade. Dafny's 13.7 is the model.
- **Errors catalog** (issue #99, `/docs/reference/errors/`): Dafny's format exactly. Title is the
  message, a minimal reproducer, the explanation, the fix.
- **Versioned docs** (`/docs/v0.2.0/`), as Dafny's snapshots. Cairn has no stability promise
  before 1.0, so an app pinned to v0.1.3 needs the docs for v0.1.3.
- **A short course split like Amazon's**: "Cairn without proofs" (moves, view, layout, run it),
  then "Lean proofs for UI people" (`omega`, `simp only`, `decide`), then "proving claims". The
  current guide interleaves them from chapter 2.

## 5. Ideas for the language and tooling

- **Verification feedback in the editor** (docs/doc.md, docs/claims.md, research/lean/07).
  Lean's infoview already gives goal states, but a Cairn author wants Dafny's gutter *per claim*:
  next to each `move ^N`, an icon for proved / proof failing / `sorry` / assumed / not yet
  conformance-tested, updated live, keeping the previous status while rebuilding
  ("past-awareness"). A Lean code-action or ProofWidgets panel listing the file's claims with
  their evidence chips is the map, in the editor. Follow Mayer's principles: verified is quiet,
  shapes plus colours, works in dark mode.
- **`cairn audit`** (docs/cli.md, docs/trusted.md). `dafny audit` reports everything that limits
  "the soundness claims of verification" (`{:axiom}`, `assume`, externs), writes txt/html/md, and
  `--compare-report` fails CI when the report changes. Cairn has the pieces (axiom audit, kernel
  replay, `assume` claims, the trusted-base map); one command with a committed report and a
  compare mode would make "the trusted base grew" a reviewable diff.
- **Proof dependencies and redundant assumptions** (docs/claims.md). Dafny's
  `--warn-redundant-assumptions` reports `assume`/`requires` a proof didn't need. For Cairn:
  report which `assume` claims each move's proof actually uses (Lean can collect constants a
  proof term mentions), show it on the map ("^12 relies on ^7"), and warn when an `assume` is
  used by nothing.
- **Test generation from specs** (docs/conformance.md, docs/fuzz.md). `dafny generate-tests`
  derives tests covering every block. Cairn's flows have witness paths already; generating
  conformance sequences that cover every move's `enabled` boundary is the analogue.
- **Brittleness as a documented risk** (docs/roadmap.md, research/lean/01). Dafny documents that
  SMT proofs break on unrelated changes. Cairn's rule of `simp only`/`grind only` in committed
  proofs is the same defence; say so on the site, and measure proof time per claim in `bench/`
  so a toolchain bump that slows or breaks proofs shows up.
- **AI-assisted annotation** (`dafny-annotator`, 2025). Cairn already runs agents; a published
  note on how agents write and repair Cairn proofs would be a differentiator, and Dafny shows the
  community wants it.

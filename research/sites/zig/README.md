---
title: "Zig: ziglang.org, the language reference, learn pages, ZSF and the devlog"
urls:
  - https://ziglang.org/
  - https://ziglang.org/learn/
  - https://ziglang.org/documentation/master/
  - https://ziglang.org/documentation/master/std/
  - https://ziglang.org/download/
  - https://ziglang.org/download/0.15.1/release-notes.html
  - https://ziglang.org/devlog/2026/
  - https://ziglang.org/zsf/
  - https://ziglang.org/learn/overview/
  - https://ziglang.org/learn/build-system/
  - https://github.com/ziglang/zig/pull/19208
date: 2026-10-25
relevance: 4
---

# Zig's site and docs

Zig is a pre-1.0 language (latest stable 0.17.0, 2026-10-01) with a small team, a non-profit,
and a site that is almost entirely plain static HTML. It is the closest analogue to Cairn's
situation: research-grade, breaking changes every release, a few authors, and a need to show
progress honestly without pretending to be stable.

## 1. What the site and docs contain

**Top nav** (ziglang.org, fetched 2026-10-24): Download & Documentation (`/download/`),
Introduction (`/intro/`), News (`/news/`), Zig Software Foundation (`/zsf/`), Devlog
(`/devlog/2026/`), Source (Codeberg), Community (`/community`). Nine translations.

**Homepage**, in order:

- One sentence: "Zig is a general-purpose programming language and toolchain for maintaining
  **robust**, **optimal** and **reusable** software."
- Three pitches, three bullets each. "A Simple Language" ("No hidden control flow. No hidden
  memory allocations. No preprocessor, no macros."), "Comptime" ("Call any function at
  compile-time."), "Maintain it with Zig" (drop-in C/C++ compiler, `zig build`).
- One code sample (`index.zig`, a test that parses integers) plus the shell transcript of
  `zig test index.zig` passing. Link: "More code samples".
- Community ("decentralized"), Main development (Codeberg + Code of Conduct), ZSF blurb,
  sponsor logos (TigerBeetle, Blacksmith, ZML, Silares, Synadia).

No video, no animation, no testimonials, no "latest release" panel.

**Learn** (`/learn/`): Documentation split into *Unstable (master)* and *Latest Stable
(0.17.0)*, each with Language Reference, Standard Library Documentation, Platform Support; then
one guide (Zig Build System), Introduction pages (In-depth Overview, "Why Zig When There is
Already C++, D, and Rust?", Code Examples, Tools), Getting started, and *external* learning
resources (Ziglings, zig.guide, Exercism, a community book). The official site does not try to
write a tutorial; it links to community ones.

**Language reference** (`/documentation/<version>/`): one HTML page per version, 0.1.1 to
master. Its own reasons: "It is all on one page so you can search with your browser's search
tool" and it "depends on no external files, so you can use it offline". Every example is a
named file (`hello.zig`) followed by the shell command and its real output, sometimes a compile
error; "The code samples in this document are compiled and tested as part of the main test
suite of Zig." Ends with Style Guide, Keyword Reference, Grammar and the Zen.

**Std docs** (`/documentation/<version>/std/`): Autodoc. Since PR #19208 (0.12.0) it is a
WebAssembly module fed a `sources.tar` of the library; it parses the source in the browser.
`zig std` serves it locally. Keyboard-first: `s` search, `u` go to source, `?` help. Every
declaration has a `[src]` link.

**Download** (`/download/`): latest stable and master side by side, each with links to its
release notes, language reference and std docs; a table of OS/arch/file/minisig/size; the
minisign public key on the page; `/download/index.json` for tools.

**Release notes** (e.g. `/download/0.15.1/release-notes.html`): one very long page per
release. Sections: Target Support, Language Changes, Standard Library, Build System, Compiler,
Linker, Fuzzer, Bug Fixes, Toolchain, **Roadmap**, Thank You Contributors, Thank You Sponsors.
Each breaking change gets a subsection with before/after code (e.g. the `usingnamespace`
removal, "Writergate"). Roadmap: "The two major themes of the 0.16.0 release cycle will be
async I/O and aarch64 backend."

**Devlog** (`/devlog/2026/`, RSS at `/devlog/index.xml`): one page per year, entries newest
first, each a date, title, optional author, and a few paragraphs to a few sections with code,
shell transcripts and benchmark tables. Recent: "Naked Package Metadata" (Oct 20), "Package
Hash Consistency Validation" (Oct 14), "Printing Package Tree" (Oct 13), "Build System
Reworked" (May 26), "Incremental compilation with LLVM" (Apr 8). Written by the people who did
the work (Kelley, Lugg, Cheraghi, Lyman).

**ZSF** (`/zsf/`): mission, board, minutes, a 2025 financials post, tax info, core team list,
corporate sponsors. Pure funding/governance.

## 2. High-ROI pieces

- **The single-page, versioned, tested language reference.** It is the canonical answer to
  "what does Zig mean by X", it is searchable with Ctrl-F, it works offline, and every example's
  output is produced by the toolchain in CI. A reader trusts it because it can't drift. This is
  the most-cited piece of Zig documentation.
- **The devlog.** Short, frequent, dated, written by whoever landed the change, with real
  transcripts and numbers. It shows momentum between releases without the ceremony of a
  release post, and it is the main way people follow Zig's progress pre-1.0. Entry length
  scales with the change: four entries in eight days in October, each a few paragraphs.
- **Release notes as migration guides.** Pre-1.0 Zig breaks things every release; the notes
  make that survivable by giving each break a before/after snippet. The Roadmap section at the
  end tells readers what the next cycle is for.
- **Master vs stable everywhere.** Learn and Download both show two columns. Readers on a
  release never land on docs for code they don't have.
- **Homepage code sample with its real output.** One small program and the command that runs
  it says more than the pitch bullets.
- **Std docs generated from source with `[src]` on everything.** Low maintenance; the docs are
  the code.

## 3. Low-value or missing

- **No official tutorial.** The site outsources learning to Ziglings, zig.guide and books. It
  works because the community is large; for a small project it would leave a gap.
- **The homepage pitch bullets** are generic ("robust, optimal and reusable") and the sponsor
  and community sections take as much space as the language.
- **The devlog index** (`/devlog/`) is just year links; no summaries, no tags, no search.
- **The release notes are enormous**, one page with contributor and sponsor lists that dwarf
  some sections; useful as reference, hard as an announcement.
- **Std docs are sparse in places** and need JS/wasm; the language reference is far better
  loved.
- **ZSF page** matters for funding, not for understanding or adoption.
- **No playground.** Zig has never had an official in-browser runner.

## 4. For Cairn: cut / keep / add

Cairn's site today: homepage (animated pixel-art night scene, "Latest milestone" panel, The
idea, frame diagram, "What a claim is" walkthrough of `^2` Reset, six kinds table, evidence
ladder), `/milestones/` (long posts with videos, the RSS source), `/docs/` (guides, examples,
reference, internals, evidence), `/docs/api/`, `/docs/evidence/` and `/map/<app>/`,
`/packages/`.

**Keep**

- **`/milestones/` + `/feed.xml`.** This is Cairn's devlog and it is the right shape for a
  research project. But see "add": Zig's devlog works because entries are short and frequent.
- **The homepage's "What a claim is" block.** It is Cairn's equivalent of Zig's one code
  sample with its output: one real `move ^2 reset` with numbered callouts. It is the most
  persuasive thing on the page. Move it higher.
- **`/docs/reference/releases.md` (Release notes).** Keep, and make it Zig-shaped (below).
- **Generated `/docs/api/` with claim counts and the axiom audit summary.** Same idea as
  Autodoc's `[src]` everywhere, plus evidence. Keep.

**Cut or demote**

- **The animated scene as the hero.** Zig's homepage leads with what the thing is and a code
  sample. The night scene is charming but carries no information; it should not sit above the
  claim example. Keep it as decoration lower or smaller, not as the first screen.
- **The "Maps" top-nav item.** It points at `/docs/evidence/`, which is also under Docs >
  Evidence. Two nav entries for one page. Zig's nav has exactly one entry per destination.
- **Long milestone posts as the only progress channel.** `/milestones/` mixes the milestone
  brief ("Can an app be built from packages alone…") with the progress log. Split it (below)
  rather than cutting it.
- **`/docs/internals/profiling.md` and `contributing.md` in the main docs sidebar.** Zig keeps
  contributor material out of Learn; Cairn's sidebar shows Internals to every newcomer. Move to
  the repo or collapse under one "Contributing" item.

**Add**

- **A single-page, versioned "Cairn reference" for the claim language.** `move`, `flow`,
  `invariant`, `assume`, `place`, `retire`, `moves%`, `claims%`, each with one example *and
  the compiler's real output* (the generated theorem, the error when `sound` fails, the
  `claims.lock` diff when an id vanishes). Today this is spread over `/docs/reference/claims/`,
  `/docs/reference/errors/` and the guide. The Zig model is "one page, Ctrl-F, offline,
  examples run in CI"; Cairn's docs already include samples from compiled sources, so the
  outputs can be captured by `make check` too.
- **Version switch on docs.** `/docs/` documents main; `/packages/cairn/` has per-version docs
  links. Add the Zig "stable vs master" choice at the top of `/docs/` so someone on v0.2.0
  isn't reading main.
- **A devlog track with short entries.** Keep milestone briefs as the long posts, and add
  dated, short entries (a few paragraphs, one transcript or screenshot) when a piece lands:
  "images have a size Lean knows", "cairn_json round-trip proved". Same feed. Zig shows four
  entries in eight days is normal and nobody minds.
- **Release notes with before/after per break and a Roadmap section.** Cairn has no stability
  promise before 1.0 (the docs say so). Zig's answer to the same situation is a migration
  snippet for every break. For claims, the per-version ledger diff on `/packages/cairn/`
  ("What changed in 0.2.0": `cairn^213 retired`, `cairn^225 new`) is already better than
  anything Zig has; link it from the release notes.
- **A homepage transcript.** Zig shows `zig test index.zig` and its output. Cairn could show
  `cairn new counter --bin && cairn build` and the claim summary line the build prints.

## 5. Ideas for the language itself

- **`zig build` is Zig code; Cairn's build is make + Lake + SwiftPM + `bin/cairn-link`.**
  Zig's devlog this year is dominated by moving package management "from Compiler to Build
  System" and making it consistent (hash validation, printing the package tree, "naked
  packages" without a manifest). Cairn's `cairn` command (docs/cli.md) wraps several build
  systems and still leaves check/fuzz/map/bundle as make targets. Long term: one entry point
  where every step is visible (`cairn build --summary`, like `zig build --summary all`'s step
  tree with timings). Touches docs/cli.md ("One build entry point").
- **`cairn tree` / package tree printing.** Zig added "Printing Package Tree". Cairn could print
  the dependency tree *with each package's claim counts and evidence*, which is uniquely
  Cairn's. docs/cli.md, docs/package.md.
- **Package hash validation.** Zig validates package hashes for consistency. Cairn's registry
  stores source, build and ledger per version; the ledger should be content-addressed too, so
  a client can check that a version's claims are the ones published. docs/package.md.
- **comptime ≈ Cairn's claim commands running at compile time.** Zig's pitch is "call any
  function at compile-time". Cairn's equivalent, claims that fail the build, is a stronger
  story than Cairn currently tells on its homepage; frame it the way Zig does: three bullets,
  "No unowned action. No id reuse. No unproved move."
- **Zen.** The reference ends with the Zig Zen (a short list of principles). Cairn's GOAL.md and
  architecture.md have principles scattered ("Lean owns meaning", "Swift is a thin host", "ids
  are never reused"). A short Cairn Zen at the end of the reference would be cheap and useful
  for agents and contributors. docs/roadmap.md or the reference page.
- **Autodoc runs the parser in the browser from a `sources.tar`.** Not worth copying for
  Cairn's docs, but the idea of shipping docs *without uploading generated HTML* matches
  docs/cli.md's "Docs aren't uploaded"; Zig is evidence that it works.
- **Signed downloads (minisign, key on the page) and `/download/index.json`.** When Cairn
  ships a `cairn` binary, publish a machine-readable releases index and signatures from the
  start. docs/cli.md.

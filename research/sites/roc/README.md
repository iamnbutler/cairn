---
title: "Roc's website, tutorial, examples, FAQ and builtins docs, read for Cairn's site"
urls:
  - https://www.roc-lang.org/
  - https://www.roc-lang.org/fast
  - https://www.roc-lang.org/friendly
  - https://www.roc-lang.org/functional
  - https://www.roc-lang.org/examples
  - https://www.roc-lang.org/faq
  - https://www.roc-lang.org/install/
  - https://www.roc-lang.org/community
  - https://www.roc-lang.org/docs/main/
  - https://www.roc-lang.org/docs/main/langref/platforms/
  - https://github.com/roc-lang/roc/blob/main/docs/mini-tutorial-new-compiler.md
date: 2026-10-25
relevance: 4
---

# Roc: a pre-0.1 language's site

Roc is the closest analogue to Cairn's *situation*: a research-stage language, not yet 0.1,
with a site that has to recruit people while the compiler is being rewritten. Its central idea,
the **platform/application split**, is also Cairn's Lean/host split under another name. Fetched
2026-10-24 (the examples page says it was validated with Roc nightly-2026-10-21).

## 1. What the site and docs contain

**Top nav**: Tutorial, Install, Examples, Community, Docs, Donate.

**Homepage**, in order:

1. Logo and "A fast, friendly, functional language.", with a one-line code sample
   (`credits = songs.map(|song| "Performed by ${song.artist}")`).
2. Three cards, each linking to a long explainer page: **Fast** ("designed to build fast and run
   fast. It compiles to machine code or WebAssembly. What does fast mean here?"), **Friendly**,
   **Functional**.
3. **Examples**: "Browse examples built and tested with the same Roc compiler as this website.
   You can run the full compiler in the browser without a backend server!" and an editable,
   runnable todo-list program ("Enable JS to Run").
4. "To get started with the language, try the tutorial!"
5. **Sponsors**: three companies, ~26 named individuals, a $4,000/month goal and the 501(c)(3)
   foundation. This is about half the page.

**Explainer pages.** `/fast` is an honest essay: what fast means per domain, "Limiting factors:
memory management and async I/O", "it's a non-goal to outperform languages that support memory
unsafety", and how close the current implementation is. `/friendly` covers syntax and `roc fmt`
("no configuration options"), the "Helpful compiler" (a real `── ✗ type mismatch ──` error), "you
can run a program that has compile-time errors" (with a candid "this feature is only partially
completed"), `roc test` with `expect`, inline `expect`s stripped in optimized builds, and planned
testing (generative, snapshot, simulated I/O, "reproduction replays"). `/functional` explains
purity with local mutation ("a variable can only be reassigned inside the function where it was
declared").

**Tutorial**: `/tutorial` 302-redirects to a GitHub markdown file,
`docs/mini-tutorial-new-compiler.md`, because the compiler is being rewritten. It opens with "Roc
is still a work in progress and has not reached a 0.1 release, so expect missing features and
bugs", then Hello World, the REPL, `main!`, pure and effectful functions (the `!` suffix), `for`
and `fold`, `expect`/`dbg`/`crash`, records, tags, `Try` and `?`, types, "Upgrading from
alpha-4", and Dependencies → Platforms.

**Examples** (`/examples`): 30 short programs in nine groups (Getting started, Types and
functions, Collections, Error handling, Parsing and encoding, Programs and algorithms, Organizing
code, Packages, Platforms (basic-cli)). Each links a README with code and output, from the
`roc-lang/examples` repo at a stated commit. The page says "Code examples are validated with Roc
nightly-2026-10-21-5349569, unless noted otherwise", and marks exceptions per example
("Multi-line Comments (not validated)", "Custom Literals (nightly-2026-10-06-…)").

**FAQ** (`/faq`): 13 design questions, most answered with a firm plan: "The explicit plan is that
Roc will never support higher-kinded polymorphism", "The plan is to never implement Roc's
compiler in Roc", "never have linear types, dependent types, refinement types, or uniqueness
types", "compile only to very low-level targets like machine code and WebAssembly", and "Can one
application have multiple platforms? … No."

**Docs** (`/docs/main/`): generated builtins reference with a sidebar of every module and every
function (Bool, Box, Crypto, Dict, Encoding, …), each entry a signature with `where` clauses, plus
a language reference (`/docs/main/langref/…`). `/platforms` redirects into the langref.

**Install** is one line, "Roc is a Work in Progress!", and OS tabs. **Community** names Zulip as
the hub, a monthly online meetup, a "new contributors" topic, and an idea → proposal →
implementation process with "We follow a BDFN leadership model today".

## 2. High-ROI pieces

- **"Built and tested with the same compiler as this website."** Every example is validated
  against a named nightly, exceptions are marked per example. A reader never wonders whether a
  sample is stale. Cairn already compiles every doc sample (`make check`); Roc shows the
  *version* on the page, which is the part readers see.
- **The in-browser compiler on the homepage.** "run the full compiler in the browser without a
  backend server" turns the homepage example into a playground. Same lever as Elm's.
- **The FAQ as a design record.** Answers say "the plan is to never…" and give the reason. It
  heads off the same forum arguments every functional language gets, and tells a newcomer what
  the language is *not*. This is cheap and very high signal for a research project.
- **Explainer pages that are honest about status.** `/fast` states the goal, the ceiling and the
  current gap; `/friendly` admits a feature "has a ways to go". For a pre-1.0 project, candour
  builds more trust than claims.
- **Platforms explained with domains people know.** The langref says a platform is like "many
  game engines and web frameworks … a high-level Roc API which presents a nice interface to a
  lower-level implementation (written in a different language)", then lists a game engine, a web
  server, Vim plugins, Postgres extensions, and a "safe scripting" platform that prompts before
  file I/O. Readers get it from the analogies before the mechanism.

## 3. Low-value or missing

- **The tutorial lives on GitHub** behind a redirect. The site's most important page leaves the
  site and its styling, signalling transition; fine for insiders, poor for first visits.
- **Install says almost nothing** beyond "Work in Progress!" and OS tabs.
- **Sponsors take half the homepage.** Necessary for funding, but they push the platform idea,
  Roc's most original feature, off the homepage entirely. The word "platform" doesn't appear on
  the homepage.
- **The docs sidebar lists every function of every module** (the Num subtree alone is hundreds
  of entries), so `/platforms` lands on a page whose first 100 KB is navigation.
- **No changelog or news** on the site; progress is on Zulip and in talks.

## 4. For Cairn: cut / keep / add

**Keep**

- Cairn's docs claim "Every code sample is included from a source file that `make check`
  compiles" (`/docs/`). That is Roc's best practice already. **Add the version** to the page:
  "Samples checked against cairn v0.2.0 (commit …)" in the docs footer and on each example.
- `/milestones/` covers what Roc lacks (a visible progress log). Keep.
- The homepage's "Not a layer on top" is Cairn's equivalent of Roc's explainer cards. Keep it
  short; link to a longer page.

**Cut or demote**

- **Packages in the top nav** (2 libraries, 0 apps). Roc, with a real ecosystem of platforms and
  packages, doesn't put a registry in its nav at all; it links packages from examples. Move
  `/packages/` under Docs → Reference until it has apps; keep the per-version claim ledger, which
  is the distinctive part.
- **Generated sidebars that list everything.** `/docs/api/` opens with 67 modules and stats
  ("1,981 declarations · 684 theorems … 41 private declarations hidden · trusted base: 39
  checks"). Roc's builtins sidebar shows the cost of this. Lead `/docs/api/` with the five
  modules an app author touches (`Cairn.App`, `Cairn.Claims`, view nodes, effects, layout), and
  fold the rest under "All modules". The stats line is good for the homepage's "How sure we are",
  not as the API page's opener.
- **The pixel-art night scene** is identity, not information. Roc's origami bird is small and the
  code sample is beside it. Keep the scene but make sure the pitch, the claim example and a
  primary button are above the fold on a laptop.

**Add**

- **A FAQ with firm answers**, Roc-style. Questions Cairn already gets or will: Why Lean and not
  Dafny/Agda/Idris? Why not SwiftUI with tests? Why a custom renderer instead of AppKit views?
  Will it run on iOS/Linux/the web? Why integer pixels? Why no Mathlib? Is the host proved? (No:
  the trusted base, and here is how it's checked.) What does "proved" not mean? Each answer one
  paragraph, with "the plan is…" where there is one. Today these answers are spread across
  `docs/architecture.md`, `docs/trusted.md` and milestone posts.
- **Status per page.** Cairn's docs already mark a `status: todo` page. Extend to Roc's candour:
  each guide chapter says what works in the current tag and what doesn't.
- **"What Cairn is not" on the homepage**, like Roc's FAQ "never" answers: not a model checker
  for existing apps, not a web framework, not cross-platform (yet), no stability before 1.0.

## 5. Ideas for the language and tooling

- **Name the host a platform** (docs/package.md "Host capabilities and painters",
  docs/roadmap.md, issue #84). Roc: "Every Roc application is built on exactly one platform …
  that platform (not Roc's standard library) provides all of the application's I/O primitives",
  and a platform is a Roc API plus a host in another language. That is exactly Cairn's Lean app
  + Swift host with effects as data. Making the host a *versioned package with a declared
  effect API* (the macOS AppKit/Metal platform; later an iOS one, a headless test one, a web one)
  would make "which effects can this app ask for" a property of the platform, the way Roc's
  browser platform simply has no file I/O. The headless `--selftest` host is already a second
  platform in all but name.
- **Capabilities enforced by the platform, shown to the person** (docs/effects.md,
  docs/trusted.md). Roc's "safe scripting" platform prompts before harmful I/O. Cairn's effects
  are already `assume` claims; a platform could refuse undeclared effects and list the app's
  effect claims in an About box or on the map, so the person sees what the app is allowed to do.
- **Inline expectations with doc comments in output** (docs/doc.md "Doc tests", docs/fuzz.md).
  Roc prints the `##` comment above a failing `expect`. Cairn's runtime checks and fuzz failures
  should print the claim's `does`/`sees` text and id, not just the Lean name.
- **Run with errors** (docs/cli.md). Roc lets a program with compile errors run until it hits
  one. The Cairn analogue: `cairn run --unproved` building with `sorry`-backed moves marked
  "unproved" on the map and in the window, so people can try UI before finishing proofs. Must
  never be publishable (`cairn publish` already gates on the audit).
- **Planned testing modes** Roc lists (simulated I/O, reproduction replays) map onto Cairn's
  effects-as-data: an effect log is a replay. A "record a session, replay it against the model"
  tool would give conformance from real use (docs/conformance.md).
- **Stating examples' toolchain version** (docs/doc.md, site/): stamp every example and map page
  with the cairn tag and Lean toolchain it was checked against.

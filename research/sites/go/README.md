---
title: "Go: go.dev, the tour, the playground, pkg.go.dev, the blog and release notes"
urls:
  - https://go.dev/
  - https://go.dev/doc/
  - https://go.dev/tour/welcome/1
  - https://go.dev/play/
  - https://pkg.go.dev/net/http
  - https://pkg.go.dev/about
  - https://go.dev/blog/
  - https://go.dev/blog/examples
  - https://go.dev/blog/toolchain
  - https://go.dev/doc/go1compat
  - https://go.dev/doc/go1.27
  - https://raw.githubusercontent.com/golang/website/master/_content/tour/welcome.article
date: 2026-10-25
relevance: 4
---

# Go's site and docs

Go's site is a corporate-scale property (Google-funded, survey banners, logo walls), but the
pieces that made Go easy to adopt are small and old: the tour, the playground, testable
examples rendered on pkg.go.dev, and the Go 1 compatibility promise. Those transfer to Cairn;
the marketing does not.

## 1. What the site and docs contain

**Top nav** (go.dev, fetched 2026-10-24): Why Go (dropdown: Case Studies, Use Cases,
Security), Learn (`/learn/`), Docs (dropdown: Go Spec, Go User Manual, Standard library,
Release Notes, Effective Go), Packages (pkg.go.dev), Community (Talks, Meetups, Conferences,
Go blog, Go project).

**Homepage**, in order: hero "Build simple, secure, scalable systems with Go" with Get Started
and Download; a logo grid of companies; testimonials ("we have seen a CPU reduction of
approximately 10%", PayPal); **Try Go**, an embedded playground preloaded with "Hello, 世界",
Run/Share/Tour, and eight example programs (Game of Life, Concurrent Prime Sieve, …); "What's
possible with Go" use-case cards; "Get started with Go" (learning resources, training).

**Docs** (`/doc/`), the "Go User Manual": Getting Started (install, tutorials: getting started,
create a module, workspaces, Gin, generics, fuzzing; "How to write Go code"; A Tour of Go),
Using and understanding Go (Effective Go, FAQ, editors, diagnostics, GC guide, managing
dependencies, fuzzing, coverage, PGO, a json/v2 migration guide), References (package docs,
command docs, **Language Specification**, Modules reference, go.mod reference, Memory Model,
Contribution guide, Release History), Accessing databases (10 pages), Developing modules
(7 pages), Talks, Codewalks, Blog articles grouped by topic, Wiki.

**A Tour of Go** (`/tour/`): slides with prose on one side and an editable, runnable program on
the other. From its source: "The tour is interactive. Click the Run button now (or press
Shift + Enter) to compile and run the program… Edit the program and run it again." Format runs
gofmt. PageUp/PageDown between slides; a table of contents at `/tour/list`; exercises; eleven
community translations. Runnable offline too.

**Playground** (`/play/`): Run, Format, Share, a Go version selector (1.27, 1.26, dev), 15
example programs. "About the Playground": programs are vetted, compiled and run in a sandbox;
"if a program has tests or examples and no main function, the service runs the tests"; only
stdout/stderr reach the outside; "The clock starts at 2009-11-10 23:00:00 UTC, so output is
deterministic and easier to cache."

**pkg.go.dev** (e.g. `/net/http`): header with Version (go1.27.3, "Latest"), Published,
License, Imports, Imported by (1,776,917); tabs Main / Versions / Licenses / Imports / Imported
By; a **details checklist**, "Valid go.mod file", "Redistributable license", "Tagged version",
"Stable version", each with help; a "Jump to" sidebar (Overview, Index, Examples, Constants,
Variables, Functions, Types, Source Files, Directories); every declaration with "View Source";
deprecated items labelled; **Examples with Output: and Run/Share/Format** in place. `/about`:
docs "generated from Go source code downloaded from the Go Module Mirror", new versions added
"every few minutes"; "Projects at v0 are considered experimental"; a badge generator.

**Blog** (`/blog/`, Atom feed at `/blog/feed.atom`): title, date, authors, one-line summary,
newest first. Recent: "Help set Go's priorities for next year" (Oct 21), "Interactive
refactoring in gopls" (Oct 16), "Go 1.27 is released" (Aug 19), "Introducing the pkg.go.dev API"
(May 21). The doc index also curates old blog posts by topic, so the blog doubles as docs.

**Release notes** (`/doc/go1.27`): Introduction, Changes to the language, Tools, Runtime,
Compiler, Linker, Standard library, Ports. The intro restates the promise every time: "As
always, the release maintains the Go 1 promise of compatibility. We expect almost all Go
programs to continue to compile and run as before."

## 2. High-ROI pieces

- **The playground and the tour.** Zero install, real compiler, shareable link. The tour turns
  the language into ~90 runnable slides; the homepage puts a playground above the fold. The
  playground's determinism (fixed clock, sandbox, tests run when there's no main) is what makes
  shared links reproducible.
- **Testable examples rendered next to the API.** "Examples are compiled (and optionally
  executed) as part of a package's test suite… The test passes if the test's output matches its
  output comment" (go.dev/blog/examples), and pkg.go.dev shows them next to the declaration by
  naming convention, runnable. Docs can't rot because they are tests.
- **pkg.go.dev's uniform package page.** Every module, standard or third-party, gets the same
  page, generated from source, with the same details checklist. The checklist is a quality
  signal readers learn once and apply everywhere.
- **The compatibility promise** (`/doc/go1compat`): "programs written to the Go 1
  specification will continue to compile and run correctly, unchanged". Hedged, with eight
  listed exceptions, but restated in every release note. It is why companies adopted Go.
- **The spec as a single page** (`/ref/spec`). Like Zig's reference: one authoritative,
  searchable document.
- **Curating old blog posts into the docs index.** Writing that explains *why* (Laws of
  Reflection, Error Handling and Go) stays findable years later.

## 3. Low-value or missing

- **Logo walls, testimonials, use-case cards, training vendors.** Adoption marketing for a
  mainstream language; zero value for a research project.
- **The docs index is a flat link farm.** 60+ links in one page, including 10 database pages,
  with no sense of order beyond "Getting Started".
- **Effective Go is old** and partly superseded; the FAQ and wiki overlap.
- **pkg.go.dev "Imported by" counts** are vanity for most packages.
- **The tour has no progress or explanation of errors**; it is a slide deck with a runner, and
  the exercises have no checker.
- **Survey and cookie banners** take the first line of the homepage.

## 4. For Cairn: cut / keep / add

**Keep**

- **`/packages/<name>/` with its claim ledger.** Cairn's package page already has the pkg.go.dev
  shape (kind, owner, version, published, commit, toolchain, license) and adds something Go
  can't: "Claims 108 active 3 retired 44 moved" and a per-version "What changed" table of ids.
  This is Cairn's best page relative to the state of the art. Keep and invest.
- **`/docs/api/`'s summary line** ("684 theorems, every one on the standard axioms · 43 claims ·
  1 doc test, all passing"). It's Cairn's version of pkg.go.dev's details checklist; see below.
- **Code samples included from compiled sources** (`/docs/` says so). Same guarantee as Go's
  testable examples. Keep and extend to outputs.

**Cut or demote**

- **The "Maps" nav item** duplicates Docs > Evidence (`/docs/evidence/`). Go's nav has one entry
  per place. Either make Maps a real top-level index of every package's maps (including
  registry packages) or drop it from the nav.
- **The homepage's long essay sections** ("The idea", "Not a layer on top", "Ids are the
  contract", "Six kinds", "How sure we are"). Go's homepage is a pitch, then *a thing you can
  run*. Cairn's homepage is five sections of prose around one excellent example. Keep the `^2`
  Reset walkthrough and the frame diagram; move "Six kinds" and the evidence ladder to
  `/docs/reference/claims/` and `/docs/reference/evidence/`, which already cover them.
- **`/docs/examples/` as prose pages that only read source.** Go's examples are things you run.
  Cairn can't run a Mac app in a browser, but it can show a map (below).

**Add**

- **A details checklist on every package page**, pkg.go.dev style, but for evidence: "Claims
  ledger present", "Every theorem on standard axioms", "No `sorry`", "Fuzzed", "Conformance
  run", "Retired ids have reasons", "Tagged version", "License". The data already exists
  (the axiom audit, the ledger, the map's proved/fuzzed/tested/seen counts on `/map/todo/`).
  Readers learn the checklist once and read every package with it. This is the single
  highest-ROI addition from Go.
- **Per-package maps on the registry.** `/packages/cairn_json/` should link to its map like
  `/map/todo/`. Today maps exist only for the repo's examples; Clock, Tray and Yap "don't have
  published maps yet" (`/docs/evidence/`). Generating a map at publish time makes every package
  page show evidence, not just counts.
- **A "playground" that fits Cairn: a claim explorer.** Cairn can't run AppKit in a browser,
  but the Lean half is pure. A page that loads an app's `update`/`view` (Lean compiled to wasm,
  or a recorded trace) and lets you press moves by id and see the next frame and which claims
  held would be Cairn's tour. Cheaper first step: a recorded, steppable trace on each map page
  (fuzz walk N, step through frames with the move ids). That is the "run it" experience.
- **A stability statement modelled on go1compat, about ids, not APIs.** Cairn already has the
  rule ("ids are never renumbered or reused") on the homepage. Write it as a promise page with
  explicit exceptions, the way Go does: what a `cairn^N` guarantees across versions, what
  "moved" means, what a retired id keeps, and what has *no* promise before 1.0 (the Lean API).
  Restate it in every release note.
- **Short "why" posts curated into the docs.** Go's docs index links "The Laws of Reflection"
  etc. Cairn's milestone posts contain design reasoning (why hit testing is in Lean, why ids
  are integers) that is only findable by date. Index them by topic from `/docs/`.

## 5. Ideas for the language and tooling

- **Testable examples with expected output → Cairn doc tests that show the frame.** Cairn's
  `cairn doc` already has doc tests (docs/doc.md, "Doc tests"; `/docs/api/` reports "1 doc
  test"). Go's convention is that an example's name ties it to a declaration and its
  `// Output:` is checked. The Cairn analogue: an example that names a move and whose expected
  output is the claim result or a rendered frame snapshot, shown beside the move on the API and
  map pages. docs/doc.md.
- **gofmt: one canonical format, no options.** The tour's Format button runs gofmt. Cairn's
  claim blocks (`move ^2 reset … does … sees … enabled … apply … post … sound`) would benefit
  from a canonical formatter so diffs of claims are only semantic. That also makes the
  `claims.lock` statement hash less sensitive. docs/cli.md (`cairn fmt`).
- **The `go` line and toolchain switching** (go.dev/blog/toolchain): "Go toolchains will treat
  the `go` line in `go.mod` not as a guideline but as a rule", and the `go` command downloads a
  newer toolchain when needed. Cairn pins Lean (`leanprover/lean4:v4.35.0` shows on the package
  page). `cairn.toml` could declare the minimum Cairn and Lean, and `cairn build` fetch them.
  docs/package.md, docs/cli.md.
- **Module mirror + checksum database.** Go's homepage notes the `go` command uses Google's
  module mirror and checksum database. Cairn's one public registry could keep a transparency
  log of (package, version, source hash, ledger hash). A claim ledger that can't be rewritten
  after publishing is the registry-level form of "ids are never reused". docs/package.md.
- **Go 1 compatibility as a dated decision.** Go made the promise at 1.0 and has kept it for
  14 years. Cairn's equivalent is narrower and could start now: the id promise (never
  reused, never renumbered, retired with a reason) is already enforced by `claims.lock`. Put
  it on docs/roadmap.md as the first thing that is stable, ahead of the API.
- **Fixed clock in the playground.** Go's sandbox starts every program at 2009-11-10 so output
  is reproducible. Cairn's fuzz runs record a seed ("Fuzz: 1,000 sequences, seed 0" on
  `/map/todo/`); give every shared trace a URL with the seed and commit, so any map failure is
  a link someone can replay. docs/fuzz.md, docs/map.md.
- **`govulncheck` / advisories on package pages.** pkg.go.dev has "Report a Vulnerability".
  Cairn's analogue is a claim that turns out false: a way to file "claim cairn^N is wrong in
  0.2.0" against a version, shown on its package page. docs/package.md.

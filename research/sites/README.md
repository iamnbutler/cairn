---
title: "Twelve language and framework sites, read for Cairn's site and tooling"
date: 2026-10-25
relevance: 4
---

# Language and framework sites

Twelve sites and their docs, each read against Cairn's site as it stood on 2026-10-25 (the
homepage scene and latest-milestone panel, /milestones/, /docs/, /docs/api/, /docs/evidence/ and
the maps, /packages/). Each note covers what the site contains, what pulls its weight, what
doesn't, what Cairn should cut, keep and add, and what the language or framework itself suggests.
This page is the meta-analysis, written after the per-source notes. It counts how many notes
make each point, and it flags points where the notes disagree.

| Note | What it is | Relevance |
|---|---|---|
| [rust/](rust/README.md) | rust-lang.org, the Book, docs.rs, crates.io, the playground, the error index | 4 |
| [lean/](lean/README.md) | lean-lang.org, the Lean docs, doc-gen4, Reservoir, Loogle, "Validating a Lean Proof" | 5 |
| [gleam/](gleam/README.md) | gleam.run, its in-browser tour, HexDocs, packages.gleam.run | 4 |
| [elm/](elm/README.md) | elm-lang.org, the guide, package.elm-lang.org, Ellie, the compiler errors | 5 |
| [roc/](roc/README.md) | roc-lang.org, the tutorial, platforms and apps, the FAQ | 4 |
| [dafny/](dafny/README.md) | dafny.org, the reference manual, how a verifier pitches proofs to programmers | 5 |
| [swift/](swift/README.md) | swift.org, Swift Package Index, Apple's SwiftUI tutorials | 4 |
| [flutter/](flutter/README.md) | flutter.dev, DartPad, the widget catalog, pub.dev scores | 5 |
| [svelte/](svelte/README.md) | svelte.dev, the interactive tutorial, the playground, `llms.txt` | 4 |
| [zig/](zig/README.md) | ziglang.org, the one-page language reference, the devlog | 4 |
| [go/](go/README.md) | go.dev, the tour, the playground, pkg.go.dev, go1compat, release notes | 4 |
| [elixir/](elixir/README.md) | elixir-lang.org, HexDocs and ExDoc, hex.pm, Livebook, Phoenix and LiveView | 5 |

## The one pattern

Every one of the twelve sites opens with **code and its result**, then one way to start (a
playground, a tour, or an install line), and then lets a reader go deeper. Cairn's homepage
opens with the night scene and the latest-milestone panel. Its best block, the annotated
`move ^2 reset` claim, comes third, and the homepage doesn't say how to install Cairn. This is
the most common finding: 10 of the 12 notes make it.

None of the twelve has a site feature like Cairn's evidence: a durable id on every action, a
claim ledger for each package version, or a map with evidence on every step. The notes agree
that this is what Cairn has to put first, and that it currently comes after the scene.

## Cut or demote

Each point is listed with the notes that make it.

- **The homepage order** (elm, roc, zig, go, elixir, swift, flutter, svelte, rust, gleam). Lead
  with the `^2` claim, a captured frame of the real app and a "Get started" button. Shrink the
  scene to a band. The latest-milestone panel moves below or to /milestones/. The scene stays
  as Cairn's identity; it just stops being the content.
- **"Maps" in the top nav** (zig, go, elixir, swift, flutter, lean). It links /docs/evidence/,
  which the docs sidebar already lists, and a newcomer doesn't know what a map is yet. Link each
  map from its example page and package version instead.
- **Two evidence pages** (lean, rust, gleam). Merge /docs/evidence/ and /docs/reference/evidence/
  into one page that explains each level and then lists the maps.
- **/map/trusted/ shown as an app** (lean, swift). It's the host's assumptions, so it belongs on
  the evidence page as "what we trust".
- **Internals in the newcomer sidebar** (elm, zig, lean). Host protocol, host effects, profiling
  and contributing should go under a Contributing heading at the bottom.
- **"Errors (to do)"** (elm, rust, gleam). Take it out of the sidebar until errors have stable
  codes (#99).
- **Plans in the reference** (rust). The planned-commands table in /docs/reference/cairn-tool/
  belongs in docs/roadmap.md.
- **Homepage essay sections that repeat the reference** (zig). "Six kinds" and "How sure we
  are" duplicate /docs/reference/claims/ and /docs/reference/evidence/.
- **/milestones/ as one long page** (rust, swift). Give each milestone its own URL and treat
  /milestones/ as the blog, with /docs/reference/releases/ as the changelog.
- **Contested: /packages/ in the nav.** elm and swift would move it out of the nav while the
  registry holds 2 libraries and 0 apps. go and elixir would keep it, because the per-version
  claim ledger is something neither pkg.go.dev nor hex.pm has. Keep the page; either label its
  counts (they're claims, which it doesn't say) or move the nav link until there's more on it.
- **Stale text** (gleam, swift, elm). The guide and the contributing page said the repository
  "isn't public yet". This PR fixes that.

## Add, ranked by return

1. **A way to try Cairn without installing it** (rust, lean, gleam, elm, roc, zig, go, flutter,
   svelte). Every playground in this set runs a compiler in the browser, and Cairn can't do that
   because it runs on the Mac. What Cairn can do is make the map interactive: step through
   recorded frames, and click a control to see its `cairn^N`, its claim and its evidence. The
   map already has the frames. This is the one "try it" that shows what's different about
   Cairn.
2. **Get started on the homepage** (go, swift, flutter, rust, gleam): one install line and the
   version (`0.2.0`).
3. **"How much to trust each kind of evidence"** (lean, dafny). Model it on Lean's "Validating a
   Lean Proof". For each level, say what it rules out and what it still assumes: proved still
   trusts the kernel and docs/trusted.md, and seen trusts the capture. Add Dafny's kind of
   walkthrough: a bug that tests miss and the proof catches.
4. **Docs for AI** (svelte, go, elixir): `llms.txt`, `llms-small.txt` and `llms-full.txt`,
   generated from the same sources. They cost little, and agents are already Cairn's main
   users.
5. **Evidence and docs for every package version** (go, flutter, lean, rust, elixir). Add a
   pkg.go.dev- or pub.dev-style checklist of named checks: ledger present, standard axioms only,
   no `sorry`, fuzzed, conformance run, and the toolchain each was run with. Add docs built by
   the registry for every version (docs.rs, HexDocs; issue #94).
6. **A screenshot at every step of the guide** (swift). The six chapters have no images. The map
   capture can generate one frame per step, which Apple's SwiftUI tutorials do by hand.
7. **Errors people can look up** (rust, elm, dafny, gleam): stable codes, `cairn explain`, a
   "When a proof fails" guide, and one real error on the homepage, the way Elm shows its errors.
8. **A stability promise for ids** (go), written like go1compat and linked from every release
   note.
9. **A FAQ, including what Cairn is not** (roc), with firm "the plan is …" answers.
10. **The 7GUIs tasks as examples with maps** (flutter). Counter is already the first of the
    seven; the rest would give a comparison against other frameworks.
11. **Source links, "since" versions and the toolchain on every API item and claim** (lean,
    rust), as doc-gen4 and rustdoc have.

## For the language and tooling, later

- **Versioning from the claim ledger** (elm, rust, gleam). The registry checks semver against the
  ledger diff and rejects a release that breaks it, as Elm checks its API diff. This touches
  docs/package.md; see also the parked auto-versioning idea.
- **The host as a Roc-style platform** (roc): a versioned package that declares the effects it
  runs. Touches docs/host.md and docs/effects.md.
- **Claim status in the editor** (dafny): a mark next to each claim with its evidence, and the
  `assume`s each proof depends on. Touches docs/claims.md and docs/doc.md.
- **`cairn check --json`** (svelte), so an agent can loop until it's clean, and **`cairn fmt`**
  for claims (go). Touches docs/cli.md.
- **Previews of named states, reload that keeps state, and an inspector** that shows a
  control's claim on click (swift, flutter). Touches docs/roadmap.md and docs/host.md.
- **Doc tests over move sequences** (elixir), so a doc example runs as a short witness.
- **Build each package against the lowest Cairn it says it supports** (flutter/pub), and a
  policy for retiring a bad release (rust, elm).

## What I'd do first

The site work is small and needs no new machinery. It's the homepage order, Get started, the
nav and sidebar moves, the merged evidence page and `llms.txt`. The interactive map is the one
real project, and it's the "try it" that shows what's different about Cairn. The tooling ideas
belong in docs/roadmap.md, not on the site.

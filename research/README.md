# Research

Sourced notes on prior art. One folder per source or topic. Each note has frontmatter (title,
urls, date, relevance 1–5), quoted findings with locations, pitfalls, counter-evidence and a
"For Cairn" section naming the workstream it serves (see `docs/plan.md`). Archived originals and
probe scripts go in a `raw/` folder next to the notes.

## macOS host and renderer (`macos/`)

How custom-rendered macOS apps do text, input methods, accessibility and GPU drawing, and where
they break. For workstreams F (renderer/text) and G (host).

| Note | For | Relevance |
|---|---|---|
| [macos/text-rendering.md](macos/text-rendering.md): Core Text shaping, glyph atlases, grayscale AA, font smoothing, gamma, measured caret offsets | F | 5 |
| [macos/text-input-ime.md](macos/text-input-ime.md): NSTextInputClient in GPUI, winit, Chromium, Firefox, Ghostty, kitty; IME, dead keys, press-and-hold, dictation | G, D, E | 5 |
| [macos/accessibility.md](macos/accessibility.md): NSAccessibilityElement trees, AccessKit, GPUI, Chromium, Flutter; identity, coordinates, notifications | G | 5 |
| [macos/metal-ui-rendering.md](macos/metal-ui-rendering.md): SDF rects, clipping, batching, frame pacing, colour space, latency | F | 5 |
| [macos/appkit-events.md](macos/appkit-events.md): tracking areas, cursors, scroll phases, key equivalents, Edit-menu routing | G | 5 |

## Surfaces (`surfaces/`)

Status-item menus as data and non-activating overlay panels on macOS, for M2's surfaces
([docs/surfaces.md](../docs/surfaces.md)).

| Note | For | Relevance |
|---|---|---|
| [surfaces/README.md](surfaces/README.md): NSStatusItem, NSMenu reconciliation and run-loop modes, NSMenuItem accessibility ids, nonactivating NSPanel, levels and collection behaviour, accessory policy; menus as data in GPUI, Tauri/muda, Electron, Flutter, SwiftUI, iced | R, host | 5 |

## Formal UI, verified layout and the TodoMVC spec

What has been specified, proved or tested about UIs before, and the exact spec M1's TodoMVC must
meet. For workstreams A (claims), B (layout), C (runtime), I (TodoMVC) and J (conformance).

| Note | For | Relevance |
|---|---|---|
| [todomvc/README.md](todomvc/README.md): the official app spec, Cypress suite and template, archived; **requirements T1–T50**, M1's claim checklist | I, A, J | 5 |
| [quickstrom/README.md](quickstrom/README.md): Quickstrom/Specstrom/QuickLTL (PLDI 2022), its TodoMVC spec and the 14 bugs in 20 of 43 implementations; Bombadil | I, A, J | 5 |
| [verified-layout/README.md](verified-layout/README.md): Cassius, VizAssert, Troika (SMT-verified CSS layout), Spineless Traversal, μSkia (Skia semantics in Lean) | B, C, F, J | 4 |
| [constraint-layout/README.md](constraint-layout/README.md): Cassowary, Auto Layout ambiguity, ORC, Flutter's one-pass box protocol | B | 3 |
| [mvu-semantics/README.md](mvu-semantics/README.md): Elm Architecture; λMVU, Essence of React, React-tRace, Willow, Smalite | C, A | 4 |
| [verified-gui/README.md](verified-gui/README.md): state-dependent GUIs proved in Agda; PVS-verified medical device UIs | A, I, J | 4 |
| [xstate-mbt/README.md](xstate-mbt/README.md): XState path generation and model-based testing | J | 3 |
| [imgui-identity/README.md](imgui-identity/README.md): Dear ImGui's ID stack, egui's `Id`, React keys; how derived widget identity fails | A, G | 4 |

### Open questions (formal UI)

- TodoMVC *Decide* items (todomvc/README.md T8, T29, T33, T48, T49, T50): whitespace after an
  empty Enter, what counts as blur on the Mac, what other controls do during an edit, whether
  pending text persists, how delete is reached without hover, and where focus goes after an edit.
- Presence vs hover (T21) vs accessibility (T49): is presence one theorem over the drawn frame,
  or two (pointer surface and accessibility tree)?
- Which "trim": ASCII whitespace or Unicode White_Space? Quickstrom only ever typed `" "`.
- How strong is the conformance comparison? Cassius's mutation check (perturb one coordinate,
  confirm it is rejected) is a cheap way to find out.
- Is a Lean rendering semantics (μSkia-style, over integers rather than reals) worth having for
  the pixel probes, or is "every control's box is painted" enough for M1?
- No prior work found proves *presence* or *pressability* of controls in a proof assistant;
  the searches were not exhaustive (2026-10-23). Worth one more targeted search before claiming
  novelty in writing.

## Lean as a platform (`lean/`)

What Lean 4.35 (core + Std) gives and costs us for verified code that runs every frame:
automation and the axioms it adds, proof-friendly recursion, the runtime's reference counting,
the claims DSL's metaprogramming, FFI, and widgets. Claims were tested on the pinned toolchain;
scratch code is in `lean/raw/`. For every workstream, A–E most.

| Note | For | Relevance |
|---|---|---|
| [lean/01-proof-automation.md](lean/01-proof-automation.md): `omega`, `grind`, `simp`, `decide`/`+kernel`, `cbv`, `bv_decide`, `native_decide`; axioms observed per tactic; `lake check` | all | 5 |
| [lean/02-proof-friendly-code.md](lean/02-proof-friendly-code.md): structural recursion on `Node`, no derived `DecidableEq` for nested types, `@[csimp]` vs `@[implemented_by]`, Array/String lemmas, `Id.run do` proofs | B, C, D, E | 5 |
| [lean/03-runtime-performance.md](lean/03-runtime-performance.md): reset/reuse, when arrays update in place, boxing, `markLinear`, stack depth on host threads; numbers | C, E, G, B | 5 |
| [lean/04-production-verification.md](lean/04-production-verification.md): Cedar's verification-guided development, SampCert, LNSym; spec/impl structure, upgrades, differential testing | all, J | 5 |
| [lean/05-metaprogramming-dsl.md](lean/05-metaprogramming-dsl.md): env extensions, `move` command, cross-module uniqueness, `initialize`, module system and `meta import` | A | 5 |
| [lean/06-ffi-embedding.md](lean/06-ffi-embedding.md): export/extern ownership, initialization, threads, struct layout, linking, lean-ios | G, E, F | 5 |
| [lean/07-proofwidgets.md](lean/07-proofwidgets.md): drawing a counterexample frame in the infoview with core widgets | B, C, D | 3 |
| [lean/raw/release-notes-4.20-4.35.md](lean/raw/release-notes-4.20-4.35.md): release-note digest filtered for Cairn | all | 4 |

## Language and framework sites (`sites/`)

Twelve languages' and frameworks' sites and docs, read against Cairn's: what pulls its weight,
what Cairn should cut, keep and add, and what the language or tooling suggests for later. The
meta-analysis is [sites/README.md](sites/README.md).

| Note | For | Relevance |
|---|---|---|
| [sites/README.md](sites/README.md): the meta-analysis: code first, a no-install "try it" (an interactive map), evidence per package version, `llms.txt`, errors people can look up | site, package, cli | 4 |
| [sites/rust/](sites/rust/README.md), [lean/](sites/lean/README.md), [gleam/](sites/gleam/README.md), [elm/](sites/elm/README.md), [roc/](sites/roc/README.md), [dafny/](sites/dafny/README.md) | site, package, claims | 4–5 |
| [sites/swift/](sites/swift/README.md), [flutter/](sites/flutter/README.md), [svelte/](sites/svelte/README.md), [zig/](sites/zig/README.md), [go/](sites/go/README.md), [elixir/](sites/elixir/README.md) | site, host, cli | 4–5 |

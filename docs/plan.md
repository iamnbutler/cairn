# Plan to M1

The boundary spike landed (`docs/spike-boundary.md`). This page splits the rest of
[GOAL.md](../GOAL.md) into workstreams that can run in parallel, each owning its own files, all
coding against the contracts below.

## Contracts (landed first, change by PR only)

| Contract | File | What it fixes |
|---|---|---|
| Geometry | `lean/Cairn/Geometry.lean` | `Point`, `Size`, `Rect`, `Insets`, integer logical points, y down |
| Claims | `lean/Cairn/Claim.lean` | `ClaimId`, `ClaimKind`, `ClaimInfo`, `ControlRef` (`^5`, `^5#12`) |
| Text metrics | `lean/Cairn/Text/Metrics.lean` | `Font`, `TextMetrics` (caret offsets per scalar), `TextMetrics.Valid`, a mono stand-in |
| View and layout | `lean/Cairn/UI/Node.lean` | `Node` (what `view` returns), `Laid` (what layout returns), `Style`, `Control`, `FieldView` |
| Input | `lean/Cairn/Input.lean` | `Event` (host → Lean), `TextOp`, `Action` (runtime → app), `Effect`, `Cursor` |
| Frame | `lean/Cairn/Frame.lean` | `Frame`: draws, accessibility nodes, text-input state, cursor, effects |
| App | `lean/Cairn/App.lean` | `App S`: `init`, `view : S → UI → Node`, `update : S → Action → S × List Effect`, `claims` |
| Swift mirror | `host/Sources/CairnFrame/Model.swift` | The same frame and event types in Swift |

If a workstream needs a contract changed, change it in its own PR with the reason, keep every
other workstream compiling, and say so in the PR body. Small additions (a field with a default,
a helper) are fine; renames and semantic changes need a note in the PR.

## Principles every workstream follows

- **Every behaviour is a claim.** The runtime only delivers `Action`s that name a control, and
  a control names a claim. There is no way for an app to react to input except through a move.
- **Proofs live next to the code.** A function and its theorems go in the same module, or a
  `…/Proofs.lean` beside it.
- **Quantify over metrics.** Layout and text theorems take `(m : TextMetrics) (hm : m.Valid)`;
  nothing may depend on the mono stand-in except tests.
- **Small total functions.** Structural recursion where possible; `termination_by` with a
  measure where not. No `partial` in anything a theorem mentions.
- **No `native_decide`**, no `sorry`, no axioms (`make check` audits).
- **Tests are examples too.** Each Lean module gets `#guard` checks or `example`s on concrete
  values next to its theorems, so a wrong definition fails fast before a proof is attempted.

## Workstreams

Each workstream is one lane, one or more PRs, and owns the files listed. Status lives in the PR
list and in this table.

| | Workstream | Owns | Delivers |
|---|---|---|---|
| A | Claims language | `lean/Cairn/Claims/`, `tools/ledger/`, `claims.lock` | `move`, `flow`, `invariant`, `assume`, `place` commands; registry; ledger check (`lake exe ledger`); claims as JSON for the map |
| B | Layout | `lean/Cairn/Layout/` | `layout : TextMetrics → Size → Node → Laid`; theorems: children inside their parent's clip, siblings disjoint in rows and columns, controls preserved (the claims in `Laid` are exactly those in `Node`), deterministic sizes |
| C | Interaction runtime | `lean/Cairn/Runtime/` | hit testing, hover, press tracking, focus and keyboard routing, `Event` → `Action`, the pressable theorem (stated over layout facts B proves) |
| D | Text editing | `lean/Cairn/Text/Field.lean`, `lean/Cairn/Text/` (not Metrics) | `Field` model: text, caret, anchor, marked range, undo history; `Field.apply : TextOp → Field → Field × List Effect`; theorems: indices stay in bounds, undo after edit restores, insert then delete-backward restores |
| E | Frame and encoding | `lean/Cairn/Frame/`, `host/Sources/CairnFrame/` (not Model.swift), `docs/frame.md` | `Frame.ofLaid` (draws, accessibility tree, text input); byte encoding v1 for frames and events with `decode (encode x) = x` proved; Swift decoder and event encoder; a corpus test that Swift decodes what Lean encodes |
| F | Renderer and text | `host/Sources/CairnRender/` | Metal: rects with fill, border and radius, clipping, glyph runs from a Core Text–rasterised atlas at the backing scale; Core Text metrics exported to Lean (`cairn_text_metrics`, docs/render.md) with a cache |
| G | Host | `host/Sources/CairnHost/`, `host/Sources/CLean/` | window, threads (main, Lean, render), AppKit events → `Event`, `NSTextInputClient`, accessibility mirror with `^N` identifiers, effects (clipboard), cursor; a generic app runner any Lean app plugs into |
| H | Research | `research/` | sourced notes per source; see `research/README.md` |
| I | TodoMVC | `lean/Examples/Todo/` | the app, its claims and its proofs (after A–E) |
| J | Conformance and debug socket | `tools/conformance/`, `host/Sources/CairnHost/Debug*` | debug socket; generated move sequences from the model replayed on the real app (after C, E, G) |
| K | Map | `tools/map/` | claims + evidence → the map skill's format, with pins from layout (after A, I) |

A, B, C, D, E, F, G and H start now. I, J and K start as their inputs land.

## Boundaries between workstreams

- **B and C** meet at `Laid`. C states the facts about a laid tree it needs for pressability as a
  structure of hypotheses (`Cairn.Runtime.LayoutFacts`); B proves its layout produces trees that
  satisfy them. Whichever lands second writes the bridging theorem.
- **D and B** meet at `FieldView`: D produces it from a `Field`; B places the caret and selection
  using `TextMetrics.offsets`.
- **E and F/G** meet at `Model.swift` and `docs/frame.md`. Until E lands its decoder, F and G
  build against `Model.swift` with hand-made frames.
- **F and B** meet at `TextMetrics`: F implements `cairn_text_metrics` in Swift; the Lean side
  declares it `@[extern]` in `lean/Cairn/Text/Host.lean` (F owns that file). Lean executables
  that don't link the host (bench, audit, tests) use the mono metrics.
- **G** owns the Swift package layout (`Package.swift`) and the `Makefile`; others add their
  target or rule in their PR and G keeps it tidy.

## Decisions

Answers to questions raised in workstream PRs. Newest last.

- **Replacement ranges (2026-10-23).** `Event.insertText` and `Event.setMarked` carry
  `replace : Option (Nat × Nat)` in scalar indices; the runtime selects the clamped range, then
  applies the op. Press-and-hold accents, Korean input and reconversion need it.
- **Text is left-to-right only in M1.** The host enforces `TextMetrics.Valid` (running max), and
  Lean re-checks it (`TextMetrics.host_valid`). RTL and bidi carets are out of scope.
- **Editing is per Unicode scalar in M1.** Grapheme-cluster deletion and ICU word boundaries
  may come later from the host, like metrics. Known limitation: `👍🏽` takes two Backspaces.
- **Hit testing:** opaque boxes and text without a control block clicks; a label inside a
  button routes to the button. `LayoutFacts` is stated that way.
- **Focusable controls** are chosen by role (`group`, `text`, `heading`, `list` are skipped).
  Apps pick roles accordingly; anything that acts is a button, checkbox, field, link or tab.
- **Fonts across the boundary** convert `Nat` to `UInt32` by saturating, as `Text.Host.sat` does,
  so layout and painting always name the same font.
- **Effects** ride on the frame of the step that produced them; the host runs them once per
  step.
- **Double-click word selection** in fields is deferred; it needs a word-select `TextOp`.
- **The pressed-relayout hypothesis** in `click_presses` stays. Apps whose controls don't move
  when pressed discharge it with the same layout fact.
- **Focus has one source:** `Frame.ofLaid` reads `ui.focus`; `FieldView.focused` is advisory for
  the view only.
- **Fields are always `textField`** in the accessibility tree, whatever role the control declares.
- **The caret is hidden while text is selected**, as in AppKit.
- **`Key.char` is one scalar.** Text arrives through `insertText`, so a multi-scalar key
  character (an emoji with a skin tone) only matters for shortcuts; the encoder sends the first.
- **Both sides of the frame codec:** Lean's is proved; Swift's is trusted and checked by the
  corpus (`make corpus`). See `docs/trusted.md`.
- **Layout pressability** needs `Layout.Pressable` (root inside the window, children fit, only a
  stack's top child has controls, controls have no controls below them). Apps prove it for their
  views at sizes at or above their minimum.

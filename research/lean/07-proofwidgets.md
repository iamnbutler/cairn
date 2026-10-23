---
title: "Widgets in the infoview: drawing a counterexample frame"
urls:
  - https://github.com/leanprover-community/ProofWidgets4
  - https://github.com/leanprover-community/ProofWidgets4/releases/tag/v0.0.116
  - https://lean-lang.org/examples/1900-1-1-widgets/
  - https://github.com/leanprover/vscode-lean4/blob/master/lean4-infoview/src/infoview/userWidget.tsx
date: 2026-10-23
relevance: 3
---

# Widgets in the infoview: drawing a counterexample frame

Question: when a check fails on some state, can the editor show that state's frame (boxes,
text, claim ids) as a picture? Yes, and core Lean alone is enough. ProofWidgets is optional
sugar.

## Core Lean already has what we need

Lean 4.35's core has a widget system. You don't need ProofWidgets for it. All paths below are
under `~/.elan/toolchains/leanprover--lean4---v4.35.0/src/lean/Lean/`.

- **A widget is a JS module stored in a Lean constant.** `Widget/Types.lean:49-65`:
  > "A JS module intended for use in user widgets. The JS environment in which modules execute
  > provides a fixed set of libraries accessible via direct `import`, notably
  > `@leanprover/infoview` and `react`."
  >
  > "To initialize this field from an external JS file, you may use `include_str`… However
  > **beware** that this does not register a dependency with Lake, so your Lean module will not
  > automatically be rebuilt when the `.js` file changes."
- **Registration is an attribute backed by a persistent env extension.** In
  `Widget/UserWidget.lean:44-56`, `@[widget_module]` stores `hash javascript ↦ (name, expr)` in a
  `SimplePersistentEnvExtension`. Line 60 registers the attribute. This is the same mechanism
  workstream A will use for the claim registry (see `05-metaprogramming.md`).
- **`#widget M with props`** (`Widget/Commands.lean:107-114`) puts a panel widget on the
  command's line. `props : Json` works: "the type of `<props>` must implement
  `Server.RpcEncodable`. In particular, `<props> : Json` works."
- **`savePanelWidgetInfo hash props stx`** (`Widget/UserWidget.lean:217`) does the same thing
  from any `CoreM` code, so a custom command or tactic can attach a picture to a source range.
- **Widgets inside messages.** `Message.lean:114-127` defines
  `MessageData.ofWidget : WidgetInstance → MessageData → MessageData`:
  > "the nested message `alt` should approximate the contents of the widget … This is used as
  > fallback in environments that cannot display user widgets."

  An error or info message from a failing check can therefore carry the picture inline, with a
  text fallback for `lake build` and CI logs.

## Verified example (core only, v4.35.0)

`/tmp/cairn-widget/Widget.lean` imports only `Lean` and elaborates cleanly with
`~/.elan/toolchains/leanprover--lean4---v4.35.0/bin/lean Widget.lean` (exit 0). It prints the
`alt` text of the inline widget: `frame with frameProps counterexample (open in infoview to see
the picture)`. I couldn't see the infoview from the CLI, so the rendering itself is untested. The
elaboration, the registration and the message are tested. The core of it:

```lean
import Lean
open Lean Widget Elab Command

structure Box where
  x : Int
  y : Int
  w : Nat
  h : Nat
  fill : String := "#ddd"
  claim : Option Nat := none
  label : String := ""
deriving ToJson

@[widget_module]
def FrameView : Widget.Module where
  javascript := "
import * as React from 'react';
const e = React.createElement;
export default function FrameView(props) {
  const boxes = props.boxes || [];
  return e('svg', {width: props.width, height: props.height},
    boxes.map((b, i) => e('g', {key: i},
      e('rect', {x: b.x, y: b.y, width: b.w, height: b.h, fill: b.fill, stroke: '#333'}),
      e('text', {x: b.x + 4, y: b.y + 14, fontSize: 11},
        (b.claim != null ? '^' + b.claim + ' ' : '') + b.label))));
}"

def frameProps (bs : List Box) : Json := json% { width: 220, height: 140, boxes: $(toJson bs) }

#widget FrameView with frameProps counterexample          -- panel widget on this line

elab "#show_frame " t:term : command => liftTermElabM do  -- inline, in a message
  let e ← Term.elabTerm t (some (mkConst ``Json))
  let j ← unsafe Meta.evalExpr Json (mkConst ``Json) e
  let wi ← WidgetInstance.ofHash FrameView.javascriptHash (pure j)
  logInfo (.ofWidget wi m!"frame with {t} (open in infoview to see the picture)")
```

## ProofWidgets4

- **No Mathlib.** At `main` and at `v0.0.116`, `lake-manifest.json` has `"packages": []`.
- **Version pinning.** The README says: "To ensure ProofWidgets works with your version of the
  Lean toolchain, reference a **release tag** rather than the `main` branch." `v0.0.116` pins
  `leanprover/lean4:v4.35.0`. `v0.0.112` to `v0.0.115` are the 4.35 release candidates, and
  `v0.0.117` and later (and `main`, pushed 2026-10-21) are on `v4.36.0-rc1`. Each Lean bump
  needs a ProofWidgets bump.
- **Prebuilt JS.** "This repository contains pre-built JavaScript files (`widget/js/`) which
  will be reused as long as none of the sources have changed… you and your users should not need
  to have NPM installed. However, in case there is a bug in the build process, ProofWidgets may
  still revert to a full build." The lakefile shells out to `npm` in that case.
- **What it adds:** JSX syntax (`#html jsx%{<b>…</b>}`), `MessageData.ofHtml`
  (`ProofWidgets/Component/HtmlDisplay.lean:81`), an `Html` data type, `Svg` helpers
  (`ProofWidgets/Data/Svg.lean`, Float coordinates with a `Frame`), `InteractiveSvg` (drag
  points, re-run Lean), Recharts plots, Graphviz, and a red-black tree demo that is a close
  analogue of drawing a tree of nodes.

## Counter-evidence and limits

- **Editor only.** Widgets render in the VS Code (and compatible) infoview. In `lake build`, CI
  and `make check` you only get the `alt` text. Pictures help a human debug a proof. They are not
  evidence and never appear in the map.
- **Values are computed at elaboration time** by the interpreter (`evalExpr`). Large frames,
  such as layout of 10k nodes, will be slow in the editor unless the module that defines layout
  is compiled for the interpreter (`precompileModules`). Keep counterexamples small.
- **Untyped JS.** The widget JS is a string with no type checking against our `Laid`/`Frame`
  JSON. If the `ToJson` shape drifts, the picture breaks silently. Keep the JS tiny and derive
  `ToJson` from the same structures.
- **`include_str` isn't tracked by Lake** (quoted above). Inline the JS in a Lean string, or
  `touch` the module when the JS changes.
- **`decide` and `grind` failures don't hand us a state.** The widget only shows what our own
  code finds. To get a picture you need a checker that searches for a counterexample, such as a
  `#check_presence` command that enumerates states, or a `#guard`-style test, and that then calls
  `logError (.ofWidget …)`. A plain kernel proof failure gives no state to draw.
- **ProofWidgets is a dependency.** AGENTS.md says "none beyond core and Std". Lake `require`s
  are transitive, so adding it to the main package leaks to every consumer, and ProofWidgets
  brings its npm fallback. It would have to live in a separate dev-only Lake package, for
  example `lean/dev/` requiring `cairn` and `proofwidgets`.

## For Cairn

- **B (layout), C (runtime):** the most useful case. Add one core-only `@[widget_module]` (about
  30 lines of JS) that draws a `Laid` tree: rects, clip outlines, claim ids `^N`, and an
  optional hit point. Use it in `#guard`-style example checks and in a small state-enumerating
  checker for presence and pressability, so a failure shows *where* the control ended up. Give
  `Laid` and `Frame` `ToJson` instances (derivable) in a debug module, not in the contract
  files.
- **A (claims DSL):** a `move` command could put a panel widget on its declaration showing the
  control in a sample state. That's nice but not needed for M1. The `@[widget_module]`
  registry is a working, in-tree example of the persistent env extension pattern A needs.
- **D (text):** draw caret, selection and marked range over a monospace stand-in. Useful when
  debugging the index-bounds theorems.
- **E (encoding):** low value. Byte dumps are better as `#eval` text.
- **Recommendation:** use core widgets, not ProofWidgets. Revisit ProofWidgets (in a dev-only
  package) only if we want interactive SVG, for example dragging the window size to watch
  pressability hold.

# Try it

The site no longer builds `/try/` pages (#137). They ran Counter, Basics and Todo in the browser,
and those apps are in iamnbutler/cairn_examples now. The tools stay, for an app package: they
walk an app's frames ahead of time and write the data such a page shows. Every frame is one the
app's own Lean code produced, and every control carries its claim (`<scope>^N`, its title, does
and sees, its reading on the claim pages). A page built on it decides nothing: a click follows an
edge the app recorded.

## How it is generated

In an app package, with `$CAIRN` the Cairn checkout Lake uses (as `make site-try` ran them on
the examples before 0.3.0):

| Step | Command | Output in `build/try/<App>/` |
|---|---|---|
| Claims | `cairn claims --out build/try/<App>/claims.json` | `claims.json` |
| Script | `bun $CAIRN/tools/try/try.ts script --claims build/try/<App>/claims.json > build/try/<App>/script.json` | `script.json`: each claim's actions, and the walk's bounds |
| Walk | `swift run <App> --try-capture build/try/<App>/script.json build/try/<App>/capture` | `capture/`: `try.json` and a PNG per state (deleted after the next step) |
| Data | `bun $CAIRN/tools/try/try.ts build --app <App> --dir build/try/<App> --out <out>` | `<out>/graph.json` and `img/<hash>.webp` |

**Actions** come from the claims export: `press` and `doublePress` as they are; a text field
(`edit`) gets one "Type" action per text its flows' witnesses type (the first few, so "  eggs "
tests trimming), each replacing the field's contents (select all, then insert), and "Clear";
`submit` is Enter and `cancel` is Escape. `blur` isn't sent yet (the capture can't). The page
offers these as choices rather than free typing.

**The walk** (`host/Sources/CairnCapture/Explore.swift`, `TryCapture`) runs inside each app's
executable, like the map capture, on one Lean thread with no window. Breadth first from the
initial frame: for each state, for each control in its accessibility nodes, for each of its
claim's actions, it replays the state's path from a fresh start (`AppCore.start` again), sends
the action's steps through the same event code as `--map-capture` (pointer events at the
control's centre; a click to focus a text field first), and takes the next frame. States are
deduplicated by the window's canvas (draws, accessibility nodes, text input, cursor). An edge is
`ok` (to a state), `inert` (the frame didn't change), `beyond` (a new frame past the bound) or
`unsupported`. Every state is expanded, so a step from the last layer that lands on a known
state still works; only genuinely new frames past the bound are `beyond`, and the page says so.

Each state is rendered offscreen with `Renderer.image` at 2×, unpinned, all cropped to one rect
(whatever was painted plus every control, padded). `try.ts build` encodes each distinct image
once as lossless WebP (text stays crisp at 1:1; smaller than lossy for flat UI) and writes
`graph.json`: per state its image, depth, the edge that first reached it, its controls (ref,
claim, role, label, rect relative to the crop) and its edges; per claim its title, does, sees,
theorems and reading. The reading is `reading()` from `site/claims.js`, so a chip reads as it
does on the claim pages and uses the same colours (`packages.css`, `.chip.ev`). The export is
this build's, the one that drew the frames; the live claim pages read the latest published
version's, so until a version with an export is published they show `ledger only` where this
page shows `proved`.

**Bounds**: depth 8, 200 states and 2 texts per field by default (`BOUNDS` in `tools/try/try.ts`),
or `--depth`, `--states` and `--texts`. Measured 2026-10-25, when the site built these three
(Counter at depth 20, Todo with 400 states):

| App | Depth | States | Steps (edges) | Beyond | Images | Size |
|---|---|---|---|---|---|---|
| Counter | 20 | 21 | 41 | 1 | 21 | 75 KB + 7 KB JSON |
| Basics | 8 | 200 (cap) | 1,720 | 500 | 169 | 2.6 MB + 152 KB JSON |
| Todo | 8 | 400 (cap) | 5,007 | 1,004 | 332 | 3.3 MB + 442 KB JSON |

A page loads its `graph.json` and only the images of the states it visits (and their
neighbours, preloaded).

## The page

The page (`site/web/content/try/`, `site/public/try/try.js` and `try.css`, and its `mount` for
embedding a compact one) went with the `/try/` pages; it is in git history before 0.3.0.

## Limits

- **Frames, not a model.** States are merged when their windows are equal, so two states that
  look the same but differ inside (undo history, say) share the edges of whichever was found
  first. Everything shown is a frame the app drew, but a path through merged states may be one
  the app wouldn't take step for step.
- **Seen is the model's frames**, rendered by the real renderer, as with the capture: no AppKit,
  no accessibility mirror. Conformance covers the host (docs/conformance.md).
- **Bounded.** Past the bound the page stops and says so; it never guesses a frame.

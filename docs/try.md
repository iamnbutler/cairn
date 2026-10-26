# Try it

The site's `/try/` pages run Counter, Basics and Todo, from iamnbutler/cairn_examples, in the
browser. The tools walk an app's frames ahead of time and write the data the page shows. Every frame is one the
app's own Lean code produced, and every control carries its claim (`<scope>^N`, its title, does
and sees, its reading on the claim pages). A page built on it decides nothing: a click follows an
edge the app recorded.

## How it is generated

In an app package, with `$CAIRN` a Cairn checkout (`make try` runs these on the examples):

| Step | Command | Output in `build/try/<App>/` |
|---|---|---|
| Claims | `cairn claims --out build/try/<App>/claims.json` | `claims.json` |
| Script | `bun $CAIRN/tools/try/try.ts script --claims build/try/<App>/claims.json > build/try/<App>/script.json` | `script.json`: each claim's actions, and the walk's bounds |
| Walk | `swift run <App> --try-capture build/try/<App>/script.json build/try/<App>/capture` | `capture/`: `try.json` and a PNG per state (deleted after the next step) |
| Data | `bun $CAIRN/tools/try/try.ts build --app <App> --dir build/try/<App> --scope <package> --out <out>` | `<out>/graph.json` and `img/<hash>.webp` |

## How the site gets it

None of it is committed, and `make site` builds none of it: the data is published the way demo
videos are (docs/media.md).

1. `make try` clones iamnbutler/cairn_examples at `TRY_REV` into `build/try/cairn_examples`
   (or uses `EXAMPLES=<dir>`), builds Counter, Basics and Todo with the Cairn they require, and
   runs the four steps on each into `build/try/out/<app>/`. Offscreen, no window; about three
   minutes from nothing, most of it the examples' build.
2. `bun tools/try/put.ts --examples build/try/cairn_examples` uploads each `graph.json` to the
   `cairn-media` R2 bucket as `try/<app>/<hash>.json` and each frame as `try/img/<hash>.webp`
   (keys the live site already serves are skipped), then writes `site/public/try/apps.json`:
   per app, its graph's URL, its first frame and its counts, and the examples' commit, version
   and Cairn. Every key is named by its content, so the Worker's immutable caching of `/m/` is
   right, and `apps.json` is served `no-cache`.
3. Commit `apps.json` in a lane, merge, and deploy from main (`make site`).

Redo it when the examples change what they draw or claim (a new `TRY_REV`) or the capture
changes.

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
theorems and reading, with ids as `<scope>^N` (`--scope`, the package's claim scope). The
reading is `reading()` from `site/claims.js`, so a chip reads as it does on the claim pages and
uses the same colours (`packages.css`, `.chip.ev`). The export is this build's, the one that
drew the frames; the live claim pages read the latest published version's. Each chip links to
its claim page, `/packages/<scope>/claims/<id>/`.

**Bounds**: depth 8, 200 states and 2 texts per field by default (`BOUNDS` in `tools/try/try.ts`),
or `--depth`, `--states` and `--texts`; `make try` takes Counter to depth 20 and Todo to 400
states (`TRY_BOUNDS`). Measured 2026-10-26, cairn_examples 0.2.0 on Cairn 0.3.0:

| App | Depth | States | Steps (edges) | Beyond | Images | Size |
|---|---|---|---|---|---|---|
| Counter | 20 | 21 | 41 | 1 | 21 | 75 KB + 7 KB JSON |
| Basics | 8 | 200 (cap) | 1,720 | 500 | 169 | 2.6 MB + 152 KB JSON |
| Todo | 8 | 400 (cap) | 5,007 | 1,004 | 332 | 3.3 MB + 442 KB JSON |

A page loads its `graph.json` and only the images of the states it visits (and their
neighbours, preloaded).

## The page

`site/web/content/try/` (bongo, with `site/web/layouts/try/`), `site/public/try/try.js` and
`try.css`. `try.js` reads `/try/apps.json`, then the app's graph and only the frames it shows
(and their neighbours, preloaded). Its `mount(el, app, { compact: true })` embeds a compact one,
with no steps and no note, in another page.

## Limits

- **Frames, not a model.** States are merged when their windows are equal, so two states that
  look the same but differ inside (undo history, say) share the edges of whichever was found
  first. Everything shown is a frame the app drew, but a path through merged states may be one
  the app wouldn't take step for step.
- **Seen is the model's frames**, rendered by the real renderer, as with the capture: no AppKit,
  no accessibility mirror. Conformance covers the host (docs/conformance.md).
- **Bounded.** Past the bound the page stops and says so; it never guesses a frame.

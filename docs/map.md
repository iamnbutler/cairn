# The map

[M1](goals/m1.md) item 7: the map is a build output. The claims in an app's code compile to a map in the
map skill's format (`~/.claude/skills/map`): one page per place, a stable `^N` on every flow and
step, screenshots, and a status per step. Here nothing in the map is written by hand: titles and
prose come from the claims, every status comes from evidence, and pins on the screenshots come
from layout.

```sh
make map APP=Counter        # writes build/map/Counter/, open build/map/Counter/dist/index.html
```

## How it is generated

| Step | Command (inside `make map`) | Output in `build/map/<App>/` |
|---|---|---|
| Claims | `lake exe claims Examples.<App>` | `claims.json`: id, kind, title, does, sees, place, retired, source position, evidence theorems, a flow's witness |
| Proofs | `lake exe audit --json` | `audit.json`: every theorem in `Cairn` and `Examples`, with any axioms beyond the standard three |
| Script | `bun tools/map/cairn-map.ts script` | `script.json`: the initial state, each flow's witness, and each move no witness presses |
| Capture | `swift run Cairn<App> --map-capture` | `capture/`: every frame of every sequence as PNG, plain and pinned, a filmstrip per sequence, `capture.json` |
| Map | `bun tools/map/cairn-map.ts build` | `map.yaml`, `areas/*.yaml`, `img/`, `notes/evidence.html`, `evidence.json`, `ids.txt`, then `dist/` |

The last step also reads `claims.lock` and, if present, `build/conformance/<App>.json`, and runs
the map skill's own `map.ts build` (found at `$MAP_TS`, `~/.claude/skills/map/map.ts` or
`~/code/prompts/skills/map/map.ts`). Without the skill it still writes the sources and evidence.

### The capture

`host/Sources/CairnCapture` (`MapCapture`) runs the app's real `step` and `frame` exports on a
Lean thread, with no window: no AppKit, no screen capture. For each step of a sequence it finds
the control with that ref in the current frame's accessibility nodes, sends pointer events at its
centre (a `press` is move, down, up; a `doublePress` adds a second click with `clicks: 2`), or,
for text steps, clicks the field unless it has focus and sends the text or key (`edit` with
`insert`, `paste`, `deleteBackward`, `deleteForward`, `selectAll`, `undo`, `redo`; `submit` is
Enter, `cancel` is Escape), and takes the next frame. A step that leaves the frame unchanged is
recorded as `inert` and still counts as performed: submitting blank text is meant to do nothing.
Every frame is rendered offscreen with CairnRender's `Renderer.image(frame, scale:)`. All images
are cropped to one rect (whatever was painted, and the pins, padded), so they line up.

**Pins** are drawn from each accessibility node's rect (the visible rect: the node's rect
intersected with its clip, as `Frame.ofLaid` computes it), labelled with its `ControlRef` (`^N`,
or `^N#k` for keyed controls). Dashed orange is a control; solid blue is the control the next
step acts on. They are burned into the image, because the skill's pins (`gaps[].at`) are for
findings, not for every control.

Each app executable opts in with one line, since each links exactly one app library:

```swift
if let code = MapCapture.main(args, size: Size(w: 480, h: 320), core: { LeanCore(counter) }) { exit(code) }
```

`make map APP=<App>` then works for any app whose module is `Examples.<App>` and whose executable
is `Cairn<App>`: today `Counter` and `Basics`, both on v1.

## How claims become map pages

The map skill's shape is areas, flows and steps, each id unique. Claims fit it like this:

| Claim | On the map |
|---|---|
| place `^P` | an area (a page), and its first flow, whose steps are the moves `in ^P` |
| move | a step: `does`, `sees`, the place and evidence in `where`, two shots (before and after a press, from a witness that presses it) |
| flow | a flow in its place's area (or the place of its first witness step), with a filmstrip of its witness and `see:` links to the moves it passes through |
| invariant, assume | a flow in the "Invariants and assumptions" area |
| retired claim | `closed: retired: <reason>` |

A flow's witness can't be its steps: the same move appears in several flows (and twice in one),
and the skill requires each id once. So flows link to their moves and show the witness as a
filmstrip. `ids.txt` lists every id the app has issued, so the skill's build fails if one goes
missing from the pages.

The skill's renderer is used unchanged. The one adapter is its documented stylesheet hook:
`site/style.css` is the skill's stylesheet plus one rule so the filmstrips fit the column.

## Evidence columns

| Column | Computed from | Values |
|---|---|---|
| **proved** | every theorem the claim names (a move's `sound` per handler; a flow's `live` and `reaches`; an invariant's `init`, `step`, `reachable`) is in `audit.json` and depends only on `propext`, `Classical.choice`, `Quot.sound` | yes, fails, missing, n/a (places, assumptions) |
| **fuzzed** | `build/fuzz/<App>.json` from `make fuzz APP=<App>` ([fuzz.md](fuzz.md)): the claim's checks held in every randomized sequence of the model and runtime | pass, fail, not run, not runnable (an invariant without a `check`), n/a (flows, places, assumptions) |
| **assumed** | the claim is an `assume` | yes, no |
| **conformance** | `build/conformance/<App>.json` (workstream J) | pass, fail, not run, n/a |
| **seen** | the capture: a move's control is in a captured frame; a flow's whole witness was replayed, each step on the control it names; a place's window was rendered | yes, no, n/a (invariants, assumptions) |

They are on the Evidence page (`notes/evidence.html`, linked from the rail) and in
`evidence.json`, one row per claim, with each theorem's audit result and the claim's ledger state.

## Status

The map skill's ladder is about who saw a step work. Status is derived from the columns, in this
order:

| Status | When |
|---|---|
| `closed` | the claim is retired |
| `broken` | a named theorem is missing or uses another axiom; conformance failed; fuzzing failed; or the capture contradicts the model: a flow's witness step names a control the app doesn't show, although the witness is proved live (every step answered by an enabled move) |
| `untested` | an assumption (stated, never checked) |
| `tested` | proved, conformance passed, and seen where seeing applies (an automated study on the real app, the skill's meaning) |
| `visual` | proved and seen: the app's own code produced frames showing it, rendered by the real renderer |
| `untested` | proved, but nothing has run it on the app: invariants today, and any move no capture reached |

A proved invariant shows `untested` unless a conformance run covers it (an invariant passes
there when every state the app reached was the model's); its proof is on the Evidence page.
**Fuzzing has no rung:** the skill's ladder (planned, untested, visual, tested, partial, broken,
missing) is fixed and measures the real app, while the fuzzer runs the Lean model and runtime.
So a fuzz pass never moves a status up; it shows in the fuzzed column, in `evidence.json` and in
each step's evidence line, between proved and seen. A fuzz failure does move it down, to
`broken`. Findings become the step's
`gaps` (so they reach the skill's Gaps page): a failing theorem, a capture that contradicts the
model, a conformance failure, a fuzz failure (with its replay command), a claim missing from `claims.lock`, or a statement hash that
differs from the lock (meaning changed and not accepted).

## For workstream J: the conformance file

The shape of `build/conformance/<App>.json`, as `make conformance` writes it (docs/conformance.md,
which also says how moves, flows and invariants are counted); the map reads only `claims`:

```json
{"runs": 1000, "commit": "abc1234",
 "claims": {"^1": {"pass": true, "runs": 812}, "^2": {"pass": false, "note": "Reset stayed visible"}}}
```

A claim missing from the file is "not run".

## What is not yet evidenced

- **Conformance** is read only when `build/conformance/<App>.json` exists: run
  `make conformance APP=<App>` before `make map`.
- **Seen is the Lean model's own frames,** rendered by the real renderer, not the running host:
  no window, no accessibility mirror, no AppKit event path. The capture clicks through the app's
  hit testing, so a control that is covered or mis-laid fails to act, but the host's event
  mapping and threads are J's to check.
- **`blur` and the rarer text operations** (word and caret movement, marked text, cut, copy)
  are not replayed yet; a witness that uses one stops there and the flow is not seen.
- **Presence and pressability** theorems are per app and not linked to claims in the export, so
  they are not columns yet (`Counter.reset_present_iff_enabled` exists, but only the audit sees
  it).
- **Model-checked** (M1 item 7) has no source yet.
- **Prose isn't checked:** `does` and `sees` are shown as written; nothing proves `sees` matches
  `post` (docs/claims.md).
- **Kernel replay** is whole-build (`make kernel` in `make check`), not per theorem.
- **Retired ids no module declares** are listed on the Evidence page from `claims.lock`; they
  can't be attributed to an app.

## Publishing

`build/map/<App>/dist/` is a static folder with relative links. It is not committed. To put it on
the microsite, the site's owner copies it under `site/public/map/<app>/` in a lane from main
(or a site build step runs `make map` first), links it from the page, and deploys from main
(docs/media.md). The map skill's `hosting.md` lists other hosts; `evidence.json` is there for a
site that wants to render its own summary.

# The map

[M1](goals/m1.md) item 7: the map is a build output. The claims in an app's code compile to a set of pages:
one per place, every claim on one of them under its id (`page.html#12` cites `^12`), real
screenshots with pins placed from layout, and for every claim the evidence the build has for it.
Nothing on the map is written by hand: titles and prose come from the claims, and every status
comes from evidence.

```sh
make map APP=Counter        # writes build/map/Counter/dist/; open build/map/Counter/dist/index.html
make map-trusted            # the trusted base's assumptions → build/map/Trusted/dist/
make site-maps              # fuzz, conformance and map for Counter, Basics, Todo and the trusted base → site/public/map/
```

`make map` reads whatever evidence is already in `build/`: run `make fuzz APP=<App>` and
`make conformance APP=<App>` first, or use `make site-maps`, which does both.

## How it is generated

| Step | Command (inside `make map`) | Output in `build/map/<App>/` |
|---|---|---|
| Claims | `lake exe claims Examples.<App>` | `claims.json`: id, kind, title, does, sees, place, retired, source position, evidence theorems, a flow's witness |
| Proofs | `lake exe audit --json` | `audit.json`: every theorem in `Cairn` and `Examples`, with any axioms beyond the standard three |
| Script | `bun tools/map/cairn-map.ts script` | `script.json`: the initial state, each flow's witness, and each move no witness presses |
| Capture | `swift run Cairn<App> --map-capture` | `capture/`: every frame of every sequence as PNG, plain and pinned, and `capture.json` |
| Map | `bun tools/map/cairn-map.ts build` | `evidence.json`, and the pages in `dist/` |

The last step also reads `claims.lock` and, when present, `build/fuzz/<App>.json`,
`build/fuzz/trusted.json` and `build/conformance/<App>.json`.

The code is three files in `tools/map/`, with no dependencies beyond bun (and `cwebp`, if
installed, for smaller images):

- `evidence.ts` turns the inputs into one row per claim: its evidence, its reading, its findings
  and its screenshots. Every status is decided here and nowhere else.
- `render.ts` turns the rows into pages.
- `cairn-map.ts` is the command line: it reads the files, converts the images, and writes
  `dist/` and `evidence.json`.

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
step acts on. They are burned into the image.

Each app executable opts in with one line, since each links exactly one app library:

```swift
if let code = MapCapture.main(args, size: Size(w: 480, h: 320), core: { LeanCore(counter) }) { exit(code) }
```

`make map APP=<App>` then works for any app whose module is `Examples.<App>` and whose executable
is `Cairn<App>`: today `Counter`, `Basics` and `Todo`, all on v1.

## Evidence

Each claim carries a list of evidence, one entry per kind it can have. Each entry is a **pass**,
a **fail**, or a **gap**: evidence the claim could have and doesn't (the input wasn't run, or ran
and never reached the claim).

The kinds, strongest first. This order is the ladder:

| Kind | Computed from | Passes when |
|---|---|---|
| **proved** | `audit.json` | every theorem the claim names (each move handler's `sound`; a flow's `live` and `reaches`; an invariant's `init`, `step`, `reachable`) is in the audit and depends only on `propext`, `Classical.choice`, `Quot.sound` |
| **fuzzed** | `build/fuzz/<App>.json` ([fuzz.md](fuzz.md)); for an assumption, `build/fuzz/trusted.json` | the claim's checks held in every random sequence that exercised it, shown as `fuzzed N` (N sequences); for an assumption, every trusted-base check naming it held (N cases) |
| **tested** | `build/conformance/<App>.json` ([conformance.md](conformance.md)) | the running app matched the model at every step that exercised it; `tested N`, N steps, for a move |
| **seen** | the capture | a move's control is in a captured frame; a flow's whole witness was replayed, each step on the control it names; a place's window was rendered |
| **assumed** | the claim is an `assume` | always: it is stated, never proved |

Which kinds each claim can have; any it lacks is a gap:

| Claim | proved | fuzzed | tested | seen | assumed |
|---|---|---|---|---|---|
| move | ✓ | ✓ | ✓ | ✓ | |
| flow | ✓ | | ✓ | ✓ | |
| invariant | ✓ | ✓ | ✓ | | |
| assume | | ✓ (trusted base) | | | ✓ |
| place | | | | ✓ | |

Flows aren't fuzzed: their witnesses are proved live. Invariants aren't seen: a screenshot can't
show that something holds in every state.

A **fail** is: a named theorem missing from the audit or using another axiom; a fuzz failure (with
its replay command); a conformance failure; or a flow whose witness step names a control the
captured app doesn't show, although the witness is proved live.

### How a claim reads

Every claim shows all its evidence. It also *reads as* one word, so the map can be scanned:

| Reads as | When |
|---|---|
| `retired` | the claim is retired: it shows its reason, has no evidence and no gaps, and its ledger hash isn't compared |
| `broken` | any of its evidence failed |
| `assumed` | an assumption (even when the trusted-base fuzzer checked it: that shows as a `fuzzed N` chip beside it) |
| the strongest kind it passes | `proved`, else `fuzzed`, `tested`, `seen` |
| `untested` | a live claim with no evidence at all |

So a proved invariant reads as proved, and a move that is only seen reads as seen. Proved and
fuzzed are about the Lean model; tested and seen are about the app. A proof says more, but only
conformance reaches through the host, which is why a claim keeps every chip and not just the top
one: a move is fully covered when it is proved, fuzzed, tested and seen.

Findings that aren't a kind of evidence go with the claim and into the gaps: a claim missing from
`claims.lock`, or a statement hash that differs from the lock (its meaning changed and the change
wasn't accepted).

## Pages

`dist/` is a static folder with relative links:

| Page | Shows |
|---|---|
| `index.html` | the **summary**: per kind of evidence, how many claims have it of those that can, and how many failed; how the claims read, as a bar; what the build had (audit, fuzz, conformance, capture). Then the **gaps**, failures first, one row per cause with every claim it touches; then every claim, grouped by page, with one column per kind of evidence |
| `<place>.html` | one per place: the window as the app starts, pinned; each move with its does and sees, its evidence and what each rests on, its theorems, its source, and before and after screenshots from a step that performed it; each flow that starts there, with its witness (linking to the moves) and a filmstrip of the replay |
| `guarantees.html` | invariants and assumptions |
| `elsewhere.html` | moves and flows that name no place, if any |
| `evidence.html` | one row per claim with every kind of evidence, its theorems and its ledger state; the ladder |
| `evidence.json` | the same rows, the counts and the gaps, for anything that wants its own view |

A flow lives on the page of its place, or of the place of its first witness step. A move can recur
in many flows (and twice in one), so a flow's witness links to its moves rather than repeating
them.

The build fails if a claim's id is on no page.

**Look.** The pages use the site's palette and type (`site/public/index.html`): the night colours,
Pixelify Sans for headings and labels, a serif for prose, stepped corners on panels and frames,
and the site's `icon.svg`, which the build copies into `dist/`. Each kind of evidence has one
colour everywhere it appears (a filled chip when it passes, a dashed empty chip for a gap, red
for a failure). Served from the site, the headings get the meadow's sprigs from `/scene.js`;
opened from disk they don't, and nothing else changes.

## Inputs from other workstreams

**Conformance** (`build/conformance/<App>.json`, docs/conformance.md). The map reads only
`claims`:

```json
{"runs": 1000, "commit": "abc1234",
 "claims": {"^1": {"pass": true, "runs": 812}, "^2": {"pass": false, "note": "Reset stayed visible"}}}
```

**Fuzz** (`build/fuzz/<App>.json`, docs/fuzz.md): `mode`, `seed`, `iterations`, and per claim
`pass` (`true`, `false`, or `null` with a `note`), `sequences`, `steps` and `failure`.

**Trusted base** (`build/fuzz/trusted.json`, `make fuzz-trusted`; docs/fuzz.md, "Trusted base").
The map reads `checks`: each check lists the `assume` claims it is evidence for (`claims`), with
`pass` (`null` when it ran no cases), `cases`, `suite` and the first `failures`. An assumption is
`fuzzed N` when every check naming it passed, N being their cases together; `fuzz fails`, with
the `CairnFuzzTrusted --replay` command, when one failed; and a gap when no check names it (an
app's own assumptions, such as Counter's ^7) or its check ran no cases.

The trusted base's assumptions (`Cairn.Fuzz.Trusted.Claims`) belong to no app, so they get a
map of their own: `make map-trusted` exports that module's claims and builds
`build/map/Trusted/dist/` with no capture (`cairn-map.ts build --app Trusted --name "Trusted
base"`).

## What is not yet evidenced

- **Seen is the Lean model's own frames,** rendered by the real renderer, not the running host:
  no window, no accessibility mirror, no AppKit event path. The capture clicks through the app's
  hit testing, so a control that is covered or mis-laid fails to act. Conformance covers the
  host.
- **`blur` and the rarer text operations** (word and caret movement, marked text, cut, copy)
  are not replayed by the capture yet; a witness that uses one stops there and the flow is only
  partly seen (a gap).
- **Presence and pressability** theorems are per app and not linked to claims in the export, so
  they aren't part of a claim's `proved` (`Counter.reset_present_iff_enabled` exists, but only the
  audit sees it). The fuzzer checks both for every move.
- **Model-checked** (M1 item 7) has no source; fuzzing is the nearest.
- **Prose isn't checked:** `does` and `sees` are shown as written; nothing proves `sees` matches
  `post` (docs/claims.md).
- **Kernel replay** is whole-build (`make kernel` in `make check`), not per theorem.

## Publishing

`build/map/<App>/dist/` is not committed. `make site-maps` copies each app's in `MAP_APPS` into
`site/public/map/<app>/`, and the trusted base's into `site/public/map/trusted/`, where the site
links to them; the lead deploys from main (docs/media.md).

Every retired claim is still declared (`retire` leaves a tombstone in its module), so it shows on
its app's map as retired, with its reason: on its place's page, on the guarantees page, or, for a
move or flow that names no place, at the foot of the index.

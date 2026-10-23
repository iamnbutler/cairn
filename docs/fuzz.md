# Fuzzing

Every app built with Cairn gets claim-driven randomized testing, in the spirit of GPUI's
`#[gpui::test(iterations = N)]`: random operations from a seeded generator, checked against the
app's claims after every step, with failing seeds replayed and shrunk. It needs no per-app code
beyond the claims the app already makes.

```sh
make fuzz APP=Basics N=1000          # = cd lean && lake exe fuzz Basics --iterations 1000
lake exe fuzz Basics --seed 1234 --iterations 1 --steps 80 -v   # replay one seed, step by step
```

Code: `lean/Cairn/Fuzz/` and `lean/FuzzMain.lean`. Output: `build/fuzz/<App>.json`.

## What the claims give the fuzzer

| From | Used as |
|---|---|
| the machine's moves, each with `enabled` and its triggers | the alphabet, filtered to what is enabled in the current state |
| each `invariant`'s generated `check` (below) | an oracle after every step |
| each move's `enabled` against the frame | **presence**: a control `^N#k` is in the laid tree iff `^N` is enabled for `k` |
| `Layout.Check` and hit testing | **pressable**: at sizes at or above the minimum, every enabled pointer move's control is hit at its centre, and `checkPressable` accepts the tree |
| purity of `update`, `view`, `layout` | determinism: a seed replays a run exactly |

The fuzzer finds every `Machine` in the `Examples` modules at compile time (`fuzz_targets%` in
`Cairn/Fuzz/Collect.lean`), with its moves, invariants and the `App` built from it, so a new app
is fuzzable as soon as `Examples.lean` imports it. An app with a machine and no `App` (Counter,
still on the spike's frame v0) is fuzzed at the model level only: actions straight into
`machine.update`, checked against its invariants.

**Runnable invariants.** `invariant` now also generates `name.check : S → Bool :=
fun s => decide (holds s)` when `Decidable` can be synthesized for `holds s` (unfolding the
definitions at the head of its body). An invariant without one is reported as "not runnable".
`check` is `decide`, so it agrees with `holds` by construction.

## What is generated

A run is `--iterations N` sequences of `--steps K` operations. Each sequence starts from the
app's `init` with its own window size and text metrics:

- **Window size:** random, at least the app's minimum. The minimum is the root's preferred size
  in the current state (`measure`), or the app's `Custom.minSize`. A resize operation picks a
  new size at or above the current minimum; one in twenty goes below it to exercise clipping
  (pressability is not checked there, and the skip is counted).
- **Text metrics:** a random `TextMetrics` that is `Valid` by construction (prefix sums of
  non-negative per-scalar widths, chosen per font from the seed, some zero for combining marks;
  random ascent and descent), or `TextMetrics.mono` in one sequence in eight.

Each operation is one of:

| Operation | Weight | Performed as (app level) |
|---|---|---|
| `act a`: an action of an enabled move, for an enabled key | ~70% | the events a person would use: a press is move, down, up at the control's centre; a double press adds a second down with `clicks = 2`; `edit`, `submit`, `cancel` click the field unless it has focus, then send the text event or key (Enter, Escape); `blur` focuses the field, then Tab |
| `click p`, `move p` at a random point | ~12% | pointer events, whatever is there |
| `tab`, `shift-Tab`, a bare key (Enter, Escape, Backspace, arrows) | ~10% | key events |
| `resize`, `pointerExit`, `windowFocus` | ~8% | window events |

Keys for keyed moves come from the frame (every `^N#k` on screen), plus keys seen earlier in the
run and one past the largest, so "enabled but missing" is caught too.

**Text edits** use the default generator unless the app supplies one: inserts drawn from words,
blanks, emoji with modifiers and ZWJ sequences (`👍🏽`, `👨‍👩‍👧`), combining marks (`e` +
U+0301), CJK, long strings; deletes and word deletes; caret and word moves, with and without
extend; select all; copy, cut, paste; undo, redo; and IME compositions (one to three
`setMarked` steps, then a commit `insert` or `unmark`), each step its own event.

**Custom generators.** An app may define `fuzz : Cairn.Fuzz.Custom State` in its namespace
(`Cairn.Fuzz.Custom` is a pure module, so the app library still doesn't link `Lean`):

```lean
def fuzz : Cairn.Fuzz.Custom State where
  edits := fun s id => if id = 101 then some (Cairn.Fuzz.Gen.oneOf [imeKana, emojiBurst]) else none
  minSize := fun _ => some ⟨360, 240⟩
  budgetNs := 4_000_000
```

`edits` returns a generator of `TextOp` scripts for a field's `edit` moves; `none` keeps the
default.

## What is checked, after every step

1. **Invariants:** every runnable invariant's `check` on the app state.
2. **Performed:** an `act a` delivered `a` (the runtime's `route` returned it). A click at an
   enabled control's centre that delivers anything else is a pressability failure of that move.
3. **Presence** for every move and candidate key.
4. **Pressable** when the window is at or above the minimum: `hitTest` at the centre of each
   enabled pointer move's control returns it, and `checkPressable && controlsNonempty` holds
   (so the app's pressability proof at that size can be `by decide +kernel`).
5. **Frame-time budget:** wall-clock time of `Runtime.step` (update, view, layout, settle) per
   step, against `--budget-ms` (default 8, a 120 Hz frame). Over-budget states are reported with
   their seed and step, but never fail a run: timing is not deterministic.

Moves' `post`s and the invariants are proved, so checks 1 and 2 at the model level should never
fail; they are cheap and guard the machinery. Presence and pressability are proved per app and
per state, if at all, so that is where the fuzzer earns its keep.

## Seeds and replay

The PRNG is SplitMix64 (`Cairn/Fuzz/Rng.lean`, core only, no Plausible). Like GPUI, a run with
`--seed S --iterations N` runs the sequences with seeds `S, S+1, …, S+N−1`, and every failure
prints its own seed: `--seed <that> --iterations 1` replays it exactly. `SEED` and `ITERATIONS`
environment variables set the defaults. The default seed is 0, so `make check` is
deterministic; pass `--seed random` to start from the clock.

## Shrinking

A failure is a check kind on a claim (say "presence ^104#3"). Shrinking is delta debugging
(ddmin) over the sequence's operations: try removing chunks, halving the chunk size down to
one, keeping any shorter sequence that still fails the same check on the same claim, then a
final pass removing single operations. Operations are self-contained (an `act` names its
control and text op; a resize names its size), so a subsequence replays without the seed; an
`act` whose control isn't on screen is skipped. The window size and metrics stay fixed.

The shrunk sequence is printed three ways:

- as a **ready-to-paste `flow`** with the next free id from `claims.lock`, whose `witness` is the
  actions the runtime delivered during the shrunk replay, minus those no move accepts (no-ops in
  the model), so `live` holds. The `goal` is a template: `check s = true` for an invariant; for
  presence and pressability, a statement over `layout` of the app's view, which the fix should
  make true. The flow gives the regression a durable id;
- as **sequence JSON** in `build/fuzz/<App>.json` (below);
- step by step with `-v`.

## Output: `build/fuzz/<App>.json`

```json
{"app": "Basics", "module": "Examples.Basics", "seed": 0, "iterations": 1000, "steps": 50,
 "sequences": 1000, "stepsRun": 50000, "seconds": 3.2, "budgetMs": 8,
 "claims": {"^101": {"kind": "move", "pass": true, "steps": 9120, "sequences": 1000,
                     "checks": {"performed": 9120, "presence": 50000, "pressable": 0}},
            "^105": {"kind": "invariant", "pass": true, "steps": 50000, "sequences": 1000},
            "^107": {"kind": "flow", "pass": null}},
 "failures": [{"check": "presence", "claim": 104, "seed": 17, "step": 31,
               "message": "…", "sequence": {…}, "flow": "flow ^110 …"}],
 "budget": {"maxMs": 0.4, "over": []}}
```

**Sequence JSON** is meant for J's conformance driver to replay a fuzz sequence on the real app:

```json
{"app": "Basics", "seed": 17, "window": {"w": 512, "h": 640},
 "metrics": {"kind": "random", "seed": 9001},
 "steps": [{"trigger": "edit", "ref": "^101", "claim": 101, "key": 0,
            "op": {"kind": "insert", "text": "é"}},
           {"trigger": "press", "ref": "^102", "claim": 102, "key": 0},
           {"event": "click", "x": 40, "y": 300, "clicks": 1, "hit": "^103#1"},
           {"event": "key", "key": "tab", "shift": true},
           {"event": "resize", "w": 600, "h": 420}]}
```

Action steps have exactly the shape of a flow's witness in `lake exe claims` (`trigger`, `ref`,
`claim`, `key`, `op`), which the map capture already replays, with `op` extended to every
`TextOp` (`extend`, `selStart`, `selLen`). Raw pointer steps carry the point and the control it
hit in the model (`hit`), so a driver whose metrics differ (Core Text, not the fuzzer's) can
retarget by ref.

## Evidence on the map

`tools/map` reads `build/fuzz/<App>.json` and adds a **fuzzed** column between proved and seen:
pass, fail, not run, or n/a (places, assumptions, flows). A failure is a finding: the step is
`broken` with the failure as a gap. The map skill's status ladder (`planned` → `untested` →
`visual` → `tested`) has no rung for "a model run checked it", so fuzzing doesn't move a status
up; it shows on the Evidence page, in `evidence.json` and in each step's evidence line.

## Limits

- It fuzzes the Lean model and runtime, not the host: no AppKit, Core Text or Metal. J's
  conformance driver covers the running app, and can replay fuzz sequences.
- Flows are not fuzzed (their witnesses are proved live); they are n/a.
- Presence assumes every move has a control while enabled. A move meant to be keyboard-only
  would need an opt-out in `Custom`.
- Wall-clock budget checks depend on the machine; they report, they don't fail.

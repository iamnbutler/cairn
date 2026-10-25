# TodoMVC: input → frame at 100, 1,000 and 10,000 nodes

A record from when TodoMVC was in this repository. TodoMVC and its bench are in
iamnbutler/cairn_examples now; Cairn's own input → frame bench is the fixture's (`make bench`,
which runs `cairn bench` on test/fixture).

`make bench` ran `CairnTodo --bench` (release, `LEAN_ABORT_ON_NONLINEAR=1`, which never
aborted). It uses the app's real exports and the v1 codec, with no threads. Each sample has
three parts:

- **step**: Swift encodes the events, then `cairn_app_step` runs route, `update`, `view`,
  layout with Core Text metrics, and settle.
- **frame encode**: `cairn_app_frame` runs `Frame.ofLaid` and the v1 encoding.
- **decode**: Swift decodes the frame.

The bench adds `n` todos by typing "Todo i" and Enter, in a window tall enough for every row
(the proofs' `height s`). It then times 50 samples of each input, after 10 warm-up samples.
Three runs on an Apple M4 Max, macOS 27, 2026-10-23. Other agents' builds kept the load
average at 7–21. "Nodes" counts accessibility nodes, about 5 per todo, so 20, 200 and 2,000
todos are the 100, 1,000 and 10,000 node points. 100 and 1,000 todos are included for
comparison with Basics.

| Todos | AX nodes | Draws | Frame | Type one character, p50 (p95) | of which step / encode / decode | Click a checkbox, p50 (p95) |
|---:|---:|---:|---:|---:|---:|---:|
| 20 | 113 | 213 | 10 KB | 0.22–0.23 ms (0.28–0.29) | 0.18 / 0.04 / 0.004 | 0.44–0.45 ms (0.46–0.50) |
| 100 | 513 | 933 | 46 KB | 0.72–0.76 ms (0.76–0.83) | 0.54 / 0.18 / 0.015 | 1.55–1.58 ms (1.59–1.67) |
| 200 | 1,013 | 1,833 | 90 KB | 1.44–1.48 ms (1.48–1.56) | 1.06 / 0.35 / 0.03 | 2.96–3.03 ms (3.11–3.24) |
| 1,000 | 5,013 | 9,033 | 446 KB | 7.0–7.3 ms (7.4–7.5) | 5.2 / 1.8 / 0.13 | 14.5–14.9 ms (15.2–15.4) |
| 2,000 | 10,013 | 18,033 | 896 KB | 14.3–14.8 ms (15.0–15.3) | 10.7 / 3.6 / 0.28 | 29.4–30.2 ms (30.7–32.1) |

Adding the todos one Enter at a time took 4.7–5.0 ms for 20, 56–58 ms for 100, 212–218 ms for
200, 5.3–5.4 s for 1,000 and 21.6–21.8 s for 2,000. This is quadratic, because each add re-runs
the view and layout over the whole list.

## Reading

- **Linear, about 1.45 µs per AX node per keystroke**, the same at 1,000 and 10,000 nodes. There
  is no cliff and nothing nonlinear (`LEAN_ABORT_ON_NONLINEAR` would have aborted on a copied
  array).
- **Inside a 120 Hz frame (8.3 ms) up to about 1,000 todos for a keystroke, and about 500 for a
  click.** A click is two passes: the press on pointer down, the toggle on pointer up. At 100
  todos a keystroke is 0.75 ms.
- **The step is about three quarters of the cost**, and Core Text is about half of the step. A
  diagnostic run (not committed) swapped the app's metrics for `TextMetrics.mono` and cut the
  step at 2,000 todos from 10.9 to 4.8 ms (keystroke 9.0 ms). Every text node calls
  `cairn_text_metrics`. The host already caches shaped lines (`TextSystem.shape`), so what
  remains is per-call cost: UTF-8 decoding, a locked dictionary lookup, building the reply,
  and Lean decoding and normalising it. A Lean-side cache of measured strings would remove most
  of it, but that cache would have to live in the runtime state.

## Basics' 7.4 ms per keystroke at 1,000 items

That is the same cost per node as here. Basics has 4,005 AX nodes at 1,000 items (1.85 µs per
node). TodoMVC at 1,000 todos has 5,013 nodes and takes 7.0–7.3 ms. Nothing in either app is
accidentally slow, and there is no cheap local fix: each change re-runs `view`, measures every
string, lays out every row and re-encodes the whole frame. The fixes are structural: the
metrics cache above, reusing unchanged subtrees' encoding (`bench/frame.md`), and laying out
only visible rows.

## Is visible-row-only layout worth it before scrolling exists?

No. The view has no scrolling, so a 560×720 window shows 11 todos, and a todo past the 11th can
be neither seen nor clicked. Laying out only the rows on screen would make 1,000 todos fast, but
1,000 todos aren't usable anyway. In every state a user can work with (at most about 15 todos
in a tall window), a keystroke takes under 0.3 ms.

It would also cost evidence. `presence` says a row's controls are in the frame and the
accessibility tree exactly when the move is enabled, and VoiceOver users reach off-screen rows
through that tree. Culling rows would weaken the theorem to "on screen", which needs a
viewport in the model. Build it together with a scroll container, which has to define that
viewport anyway. Then the presence theorem can be restated over the viewport, and the
pressable theorem's `height s` condition can become the viewport's height.

# Layout benchmark

`cd lean && lake build bench && .lake/build/bin/bench` (also run by `make bench`). It times
`Cairn.Layout.layout TextMetrics.mono` on three shapes of tree, 50 runs each after 5 warm-up
runs, with a different window width every run so nothing is hoisted out of the loop, and a
checksum over every rect so nothing is skipped. Layout only: no frame encoding.

- **flat column**: one `fill` column of `n` fixed-size buttons (the spike's shape).
- **todo rows**: a padded, clipping column of TodoMVC-like rows of six nodes each: the row, a
  checkbox, a text label, a `fill` spacer, and a delete button holding a text label.
- **nested**: `n` boxes each holding the next, with padding, ending in a text: the deepest tree.

## Numbers

M4 Max, 2026-10-23, release build (Lake's default `-O3`), on a machine shared with other
builds (load average 20–48 during the runs; repeated runs varied by about ±10%).

| Shape | Nodes | Time | Per node |
|---|---:|---:|---:|
| flat column | 101 | 0.032 ms | 0.32 µs |
| flat column | 1,001 | 0.34 ms | 0.34 µs |
| flat column | 10,001 | 3.2 ms | 0.32 µs |
| todo rows | 97 | 0.028 ms | 0.29 µs |
| todo rows | 997 | 0.29 ms | 0.30 µs |
| todo rows | 9,997 | 3.1 ms | 0.31 µs |
| nested | 101 | 0.028 ms | 0.27 µs |
| nested | 1,001 | 0.27 ms | 0.27 µs |
| nested | 10,001 | 2.8 ms | 0.28 µs |

Linear, about 0.3 µs per node for both passes. The spike's trivial column measured about
0.38 µs per node for layout *and* encoding together (rerun alongside: 0.04 / 0.41 / 4.1 ms at
100 / 1,000 / 10,000 boxes), so real layout costs about what the spike's placeholder did, and
layout plus encoding will be roughly double it. At 10,000 nodes that is about 3 ms of layout,
inside the 4 ms budget but not by much; TodoMVC frames are a few hundred nodes (≈0.1 ms).

Text nodes measure with `TextMetrics.mono`, which builds an offsets array per string; Core
Text metrics will cost more per text node and are F's to cache.

## Wrapped text

`bench` also lays out one `Node.para` of `n` words (1–10 letters each, so about 6.5 scalars a
word) as the whole window, at widths 200, 400 and 800, with `TextMetrics.mono`. A window resize
re-runs exactly this: the string is unchanged, so the host's shaping is cached and only Lean's
breaking and layout run again.

| Words | Scalars | Width | Lines | Time |
|---:|---:|---:|---:|---:|
| 100 | 650 | 200 / 400 / 800 | 27 / 12 / 6 | 0.030 / 0.025 / 0.023 ms |
| 1,000 | 6,500 | 200 / 400 / 800 | 267 / 117 / 58 | 0.31 / 0.26 / 0.25 ms |
| 10,000 | 65,000 | 200 / 400 / 800 | 2,667 / 1,167 / 572 | 3.0 / 2.6 / 2.4 ms |

Linear in the text, about 45 ns a scalar, with a little more per line. The first version was
quadratic (1.3 ms at 1,000 words, 80 ms at 10,000): each line's `slice` dropped from the start
of the string. `Text.Wrap.mapSlices` is still that specification, and the compiler runs
`mapSlicesFast` (`@[csimp]`, proved equal), which keeps a cursor into the text.

With Core Text, `CairnFuzzTrusted --bench-wrap` (release; 1,000 words of English, about 5,500
scalars, 13 pt system font, medians of 25 fresh strings):

| Step | 200 pt (192 lines) | 400 pt (89 lines) | 800 pt (43 lines) |
|---|---:|---:|---:|
| Shape the whole string once (`TextSystem.shape`, cold) | 3.9 ms | 4.1 ms | 4.1 ms |
| Lean: break and lay out with `TextMetrics.host` (string cached) | 0.76 ms | 0.68 ms | 0.64 ms |
| Shape each line for painting (cold) | 4.8 ms | 4.6 ms | 4.4 ms |

The Lean row goes through the trusted-fuzz export, which also computes the lines a second time
for its report, so it overstates layout a little. Two host costs were quadratic before this
measurement and are fixed:

- `TextMetrics.host` decoded the host's reply with `ByteArray.data`, which the compiler
  implements as a copy of the whole array, once per byte: 395 ms for this paragraph. It now
  indexes the `ByteArray` directly (0.7 ms).
- `TextSystem.shape` asked `CTLineGetOffsetForStringIndex` for every caret, and that call walks
  the line: 60 ms. On lines with no right-to-left run it now takes the carets from one
  `CTLineEnumerateCaretOffsets` pass (4 ms in all). The two agree exactly on 158,000 random
  strings across fonts, clusters and fallback runs, and `MetricsTests` checks it; right-to-left
  lines and boundaries inside clusters still use the per-index call.

So a 1,000-word paragraph costs about 9 ms the first frame it appears (shaping the string and
then its lines). While the window resizes, the whole string stays cached and Lean re-breaks it
in under 1 ms, but a new width gives new line strings, which the renderer shapes cold: up to
about 5 ms more when every line changes. Lines are cached like any text (8,192 lines, then
cleared). Painting each line from the whole string's glyphs instead would remove that, but would
need a new draw variant; not done.

## Stack and copies

- Recursion is structural over the tree and over each child list (`measureList`,
  `arrangeList`, `Line.go` are not tail-recursive), so stack use grows with nesting depth and
  with the number of siblings in one container. In practice: `bench 1000000` (a column of a
  million buttons, and a million-deep nesting) runs on the main thread, and
  `bench --task-depth 300000` lays out a 300,000-deep tree on a Lean task thread, without
  overflowing. Real views are a few dozen levels deep. The host runs Lean on a thread with a
  64 MB stack anyway (research/lean/).
- `LEAN_ABORT_ON_NONLINEAR=1 .lake/build/bin/bench` completes, paragraphs included: layout builds fresh lists and
  never updates an array in place, so there is nothing to copy.

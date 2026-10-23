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

## Stack and copies

- Recursion is structural over the tree and over each child list (`measureList`,
  `arrangeList`, `Line.go` are not tail-recursive), so stack use grows with nesting depth and
  with the number of siblings in one container. In practice: `bench 1000000` (a column of a
  million buttons, and a million-deep nesting) runs on the main thread, and
  `bench --task-depth 300000` lays out a 300,000-deep tree on a Lean task thread, without
  overflowing. Real views are a few dozen levels deep. The host runs Lean on a thread with a
  64 MB stack anyway (research/lean/).
- `LEAN_ABORT_ON_NONLINEAR=1 .lake/build/bin/bench` completes: layout builds fresh lists and
  never updates an array in place, so there is nothing to copy.

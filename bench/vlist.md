# Virtual lists

`cd lean && lake build bench && .lake/build/bin/bench --vlist` (also run by `make bench`). It
times whole runtime steps (`Runtime.step`: route, view, layout, `settle` and the runtime's record
of the list, `VList.record`) on an app whose window is one virtual list (`VList.node`, docs/layout.md,
"Virtual lists") of `n` rows in an 800 × 600 window, with `TextMetrics.mono`. Each row is a
button holding a text label, 24 to 48 points high (`24 + 8·(key mod 4)`, as the fixture's), so
the list's estimate is wrong for three rows in four and every step records heights and corrects
the offset. A checksum over every rect of the laid tree is taken inside the timing.

- **scroll**: wheel steps of 300 points, down and back up, up to 100 each way (fewer for a short
  list, so that every step moves it), new rows laid on every step; 200 steps, the first 10
  dropped.
- **up from the end**: one wheel step far past the end of the list (it clamps there), then
  300-point steps back up, 200 of them (fewer for a short list).
- **insert at the head**: the app's keys gain a new key at index 0 (the array is built before the
  clock starts) and the runtime settles: view, layout, record, with the anchor holding the rows on
  screen still. 50 inserts, the first 5 dropped.
- **plain scroll box**: the same rows as children of an ordinary scroll box (`UI.scrolling`), all
  of them laid on every step, for comparison.

## Numbers

Apple M4 Max (Mac16,6), 2026-10-25, release build (Lake's default `-O3`),
`LEAN_ABORT_ON_NONLINEAR=1`, load average about 4 from other agents' builds. Two runs agreed
within 5%; this is the second.

| Rows | Scroll p50 / p95 | Up from the end p50 / p95 | Insert at the head p50 / p95 | Heights kept |
|---:|---:|---:|---:|---:|
| 100 | 0.062 / 0.065 ms | 0.062 / 0.064 ms | 0.061 / 0.063 ms | 100 |
| 1,000 | 0.161 / 0.165 ms | 0.157 / 0.166 ms | 0.164 / 0.178 ms | 528 |
| 10,000 | 0.164 / 0.170 ms | 0.166 / 0.176 ms | 0.170 / 0.175 ms | 527 |
| 100,000 | 0.169 / 0.176 ms | 0.173 / 0.178 ms | 0.171 / 0.177 ms | 527 |

| Rows | Plain scroll box, scroll p50 / p95 |
|---:|---:|
| 100 | 0.061 / 0.063 ms |
| 1,000 | 0.674 / 0.706 ms |
| 10,000 | 6.86 / 7.01 ms |

Flat in the number of rows: a step costs the same at 1,000 rows as at 100,000, about 0.17 ms,
or 2% of the 8 ms frame budget. A plain scroll box lays every row on every step and is linear,
about 0.7 µs per row: 6.9 ms at 10,000 rows, nearly the whole budget, and over it beyond.

What a step costs grows with the heights the runtime keeps, not with the list: each step aligns
the kept rows to the keys, builds their prefix sums, merges the new ones in and compares the
record, a few passes over them (about 0.3 µs a row in all). The runtime keeps the heights of the
rows within `VList.keepSpan` (500) rows of those laid, so that is at most about 1,000 rows plus
the window; a list of 100 rows keeps all of them and costs less. Before the bound, a list whose
every height was known cost 2.7 ms a step at 10,000 rows and 25 ms at 100,000.

Two costs are linear in the list and are not in these numbers:

- **The keys.** The view is given the keys as an array and reads only the window of it, but the
  app builds that array: keep it in the app's state (the fixture does) rather than building it in
  `view`. An insert at the head is `#[k] ++ keys`, a copy of the array, in the app's `update`.
- **Keys that move other than all together.** When the keys change so that the kept rows are
  neither where they were nor all shifted by the same amount (rows inserted at the head), the view
  looks each key up among the kept rows: `n log k`, once, in the step where the keys changed. An
  insert at the tail of the fixture's list moves the end line's key by one and takes this path
  when the end line's height is kept.

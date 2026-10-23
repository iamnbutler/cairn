# Fuzz throughput

`lake exe fuzz <App> --seed 0 --iterations N --steps K` (docs/fuzz.md), release build of the
fuzz exe, Apple M4 Max, macOS 27, 2026-10-23, other agents' builds running. Each runtime step is
the operation's events through `Runtime.step` (route, update, view, layout, settle) plus the
checks: every runnable invariant, presence of every move and probed key, and, at sizes at or
above the minimum, a hit test per enabled pointer control and `checkPressable`.

| App | Mode | Sequences × steps | Time | Sequences/s | Steps/s | Slowest step | Pressability skipped | Failures |
|---|---|---|---:|---:|---:|---:|---:|---:|
| Basics | runtime | 1,000 × 50 | 2.04 s | 490 | 24,546 | 0.95 ms | 5,869 of 50,000 | 0 |
| Basics | runtime | 2,000 × 200 | 16.95 s | 117 | 23,598 | 0.17 ms | 53,115 of 400,000 | 0 |
| Basics | runtime, random seed | 2,000 × 100 | | | 23,627 | | | 0 |
| Counter | runtime | 1,000 × 50 | 1.25 s | 798 | 39,907 | 0.04 ms | 4,277 of 50,000 | 0 |
| Counter | runtime | 10,000 × 200 | 46.9 s | 213 | 42,669 | 0.92 ms | 162,838 of 2,000,000 | 0 |

Counter's rows were re-run when it moved to the v1 ABI and got an `App`; before that it was
fuzzed at the model level only (1,000 × 50 in 0.041 s, 1.23 million steps/s).

Reading:

- **About 24,000 steps a second through the runtime**, flat in sequence length: longer
  sequences grow the list (more rows to lay out and probe), but Basics stays small.
- The model alone was about 30–50 times faster (Counter's old model-only rows); the view, layout
  and the per-step checks dominate.
- The slowest step varies between runs (0.1–3 ms) with machine load; nothing came near the 8 ms
  budget.
- About one step in eight runs below the view's minimum window (resizes go below it one time in
  twenty, and a growing list raises the minimum), where pressability isn't checked.
- `make fuzz-quick` (both apps, 200 × 50) takes about 1 s plus 1.4 s to link the exe.

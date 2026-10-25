# Fuzz throughput

Runs on the example apps while they were in this repository, with `lake exe fuzz` of the time.
They are in iamnbutler/cairn_examples now (`make fuzz` there); Cairn's `make fuzz-quick` fuzzes
test/fixture with `cairn fuzz`.

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
- `make fuzz-quick` then (both apps, 200 × 50) took about 1 s plus 1.4 s to link the exe.

## With the host (#181)

`lake exe fuzz <App> --seed 7000 --iterations 3000 --steps 300`, release build, Apple M4 Max,
macOS 27, 2026-10-25, other agents' builds running. Each sequence boots at a random start time;
the host takes a share of the steps (docs/fuzz.md, "The host"): it answers requests late, out
of order, failed or after a cancel, fires timers, advances the clock, sends subscription events
(some after a stop) and evicts images.

| App | Steps | Time | Steps/s | Slowest step | Failures |
|---|---:|---:|---:|---:|---:|
| Counter | 900,000 | 23.0 s | 39,137 | 0.07 ms | 0 |
| Basics | 900,000 | 140.9 s | 6,388 | 7.38 ms | 0 |
| Todo | 900,000 | 54.3 s | 16,586 | 0.65 ms | 0 |
| Clock | 900,000 | 59.8 s | 15,049 | 1.17 ms | 0 |
| Tray | 900,000 | 20.2 s | 44,570 | 0.87 ms | 0 |
| Gallery | 900,000 | 164.0 s | 5,489 | 0.94 ms | 0 |
| Fixture | 900,000 | 126.4 s | 7,119 | 0.21 ms | 0 |

What the host did:

| App | Requests | Cancelled | Answered | Failed | Answers after cancel | Stray | Wakes | Timers due | Sub events (after stop) | Evictions | Max outstanding |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Clock | 232,712 | 0 | 214,423 | 35,817 | 0 | 7,397 | 53,831 | 101,466 | 73,796 (0) | 0 | 26 |
| Tray | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 65,020 (8,524) | 0 | 0 |
| Gallery | 270,385 | 103,464 | 163,597 | 24,975 | 89,126 | 11,299 | 0 | 0 | 0 | 60,563 | 6 |
| Fixture | 0 | 0 | 0 | 0 | 0 | 0 | 62,088 | 69,602 | 0 | 0 | 0 |

Counter, Basics and Todo make no requests and start no timers; the host only moves their clock
(about 30,000 clock steps each). Gallery also had 20,640 loads finish before their reply.

Reading:

- Basics and Todo are slower than in the table above: the lists grow over 300 steps rather than
  50–200, and every step lays them out and probes them.
- Gallery never goes over 6 outstanding loads: `maxInFlight` caps it, and the host never sees
  more.

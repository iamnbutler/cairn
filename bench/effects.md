# Effects: latency and timers

How long the outside world takes to reach a Lean app through the host (docs/effects.md).
Apple M4 Max, macOS 27, Swift 6 (Xcode), Lean 4.35.0, 2026-10-23, debug host build, measured by
the Clock app's self test (`cd host && swift run CairnClock --selftest`, part of
`make selftest`), which drives the real host threads (main, Lean, world, wake) with no window
on screen.

## Request round trip

A click on Load (^405), through to the frame that shows the file's contents: the click's
events are queued, Lean steps them and emits `request id (readFile …)`, the frame is
published, `World` runs the handler on a global queue (a 2-byte file), the reply is queued as
an event, Lean steps it, and the next frame shows "Loaded 1 laps". 40 trips:

| | p50 | p90 | max |
|---|---:|---:|---:|
| click → `readFile` → reply → frame | 1.50 ms | 1.97 ms | 6.57 ms |

That is two Lean steps and two frame encodes and decodes, plus the file read and three queue
hops.

## Timers

How late after its deadline the clock that fires a `setTimer` timer arrives: Clock's 100 ms
tick while running, 30 deadlines, read by polling every 0.5 ms with a millisecond clock, so an
upper bound:

| Wake mechanism | p50 | p90 |
|---|---:|---:|
| `NSCondition.wait(until:)` on the Lean thread (first version) | about 8 ms | |
| strict `DispatchSourceTimer` (`Engine.scheduleWake`, now) | 1 ms | 2 ms |

The condition's timed wait is subject to timer coalescing; a `.strict` dispatch timer with
zero leeway is not. Measured directly (outside Cairn), a strict timer for a 100 ms deadline ran
about 0.09 ms late. The trusted-base fuzzer's `clock.wake` counts lateness per case (docs/fuzz.md).

`every` subscriptions use dispatch timers with 1 ms leeway on the `cairn.world` queue; they are
for redrawing, not for keeping time (the clock before each tick is the truth).

## Size

`make size` (bench/size.md), release, stripped:

| App | Stripped |
|---|---:|
| CairnCounter | 2,586,784 B |
| CairnBasics | 2,637,560 B |
| CairnTodo | 2,689,208 B |
| CairnClock | 2,638,408 B |

Clock (timers, an `every` subscription, two file requests, the runtime's effect paths) is
51,624 B (2.0%) above Counter, about the size of Basics; every app stays under the 5 MB limit.

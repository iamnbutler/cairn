# Surfaces: the overlay at 50 Hz, and the menu

Whether a waveform drawn from Lean primitives (24 bars as rects, docs/surfaces.md decision 5)
keeps up with a 50 Hz tick, and what the menu path costs. Apple M4 Max, macOS 27, Swift 6
(Xcode), Lean 4.35.0, 2026-10-23, debug host build.

## The overlay

Measured by Tray's self test (`cd host && swift run CairnTray --selftest`, then part of
`make selftest`; Tray and its self test are in iamnbutler/cairn_examples now): the real host threads
(main, Lean, world, wake) with `SurfaceHost` detached (nothing on screen). The overlay is shown, its
`every 20` subscription ticks, and each tick is a Lean step that redraws 24 bars and re-wraps a
growing caption (`Node.para`, two lines, keep tail). Ticks are timed where each frame is published,
on the Lean thread, over 2 s. Three runs:

| | run 1 | run 2 | run 3 |
|---|---:|---:|---:|
| ticks published | 50.1 Hz | 50.1 Hz | 50.0 Hz |
| tick → tick p50 | 19.70 ms | 19.66 ms | 20.38 ms |
| tick → tick p90 | 25.09 ms | 26.12 ms | 23.69 ms |
| tick → tick max | 27.55 ms | 28.24 ms | 26.79 ms |
| Lean step + frame + decode, p50 | 0.78 ms | 1.16 ms | 1.27 ms |
| Lean step + frame + decode, p99 | 2.20 ms | 1.59 ms | 1.74 ms |

So the budget is spent on waiting, not computing: a tick costs about 1 ms of Lean and decoding
in a 20 ms period. The spread around 20 ms is the world queue's timer (1 ms leeway, not strict),
not the pipeline. Before the caption wrapped (one `Draw.text`), step + frame + decode was
0.16–0.29 ms p50; wrapping and keep-tail cost the rest.

An earlier version of the self test timed ticks by polling the frame for "tick N" and reported a
max of about 220 ms. That was the measurement: when the wrap put a line break between "tick" and
its number, the poll missed ten ticks. It now joins the lines first.

Not measured here: drawing. The panel's canvas goes through the same `MetalRenderer` as a window
(bench/render.md); a 320×~110 canvas of 24 rects and two text runs is well inside a frame.

## The menu

| | |
|---|---:|
| `NSMenu.performActionForItem(at:)`, detached menu | about 60 ms per call |
| `NSApp.sendAction` for comparison | about 3 µs |
| conformance step (one `menuSelect` through `performActionForItem`, then frame, `menu` and `surfaces` reads) | p50 51.4 ms, p90 54.4 ms, max 62.4 ms |
| conformance on Tray, `N=200` (docs/conformance.md) | 2,404 steps, 87.8 s |
| trusted fuzz `SurfacesSuite`, quick (`--n 500`) | about 5.4 s |

`performActionForItem` dominates both the conformance step and the fuzz suite, which is why the
fuzz suite chooses an item in only a third of its updates. In the running app a person's click
goes through the same call once, so 60 ms is not on any hot path.

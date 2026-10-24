# Yap on Cairn: levels at 50 Hz, the menu, size

Apple M4 Max, macOS 27, Swift 6 (Xcode), Lean 4.35.0, 2026-10-23. docs/yap.md describes the app.

## Levels at 50 Hz

Measured by the self test (`cd host && swift run CairnYap --selftest`, debug host build): the
real host threads (main, Lean, world) with the surfaces detached and a fake microphone. During a
hold, the test feeds 150 buffers of 20 ms in real time, one every 20 ms, as the microphone does.
Each buffer is a `record` event: the world's level meter cuts it into one 20 ms window, and a
Lean step runs `receive` (the chunker, the overlay's bars), the view (the menu and the overlay:
120 bars and the preview paragraph) and the frame encoding. Three runs:

| | run 1 | run 2 | run 3 |
|---|---:|---:|---:|
| buffers fed / time | 150 / 2.98 s | 150 / 2.98 s | 150 / 2.99 s |
| frames published | 164 | 163 | 164 |
| Lean step + frame + decode, p50 | 0.62 ms | 0.46 ms | 0.62 ms |
| Lean step + frame + decode, p95 | 1.13 ms | 1.03 ms | 1.12 ms |
| Lean step + frame + decode, max | 1.87 ms | 1.67 ms | 2.01 ms |
| surface apply on main (menu + overlay), p50 | 0.25 ms | 0.16 ms | 0.24 ms |
| surface apply on main, max | 1.09 ms | 1.15 ms | 1.06 ms |

So a level event costs about 0.5–0.6 ms of Lean and decoding (p50) and 0.2 ms on the main
thread in a 20 ms period: under 5% of one core while recording. More frames than buffers is the
clock and replies arriving in their own batches.

## The menu

The menu is rebuilt from Lean's records on every frame, but `MenuHost` only replaces items when
their shapes change (an item added, removed or changing kind); otherwise it updates titles,
states and enablement in place. Over the whole self test, eight frames changed the shapes (the
first menu, Recent Transcripts filling, the status lines coming and going):

| | run 1 | run 2 | run 3 |
|---|---:|---:|---:|
| apply with a rebuild, p50 | 0.92 ms | 0.72 ms | 0.73 ms |
| apply with a rebuild, max | 70.2 ms | 11.0 ms | 9.4 ms |

The max is the first menu, built while AppKit loads its menu classes and SF Symbols; after
that a rebuild is under a millisecond. The Lean side of the menu (`menuItems`) is in the step
times above, since the view is computed on every step.

## Size

`make size` (release, stripped; bench/size.md):

| | Bytes | |
|---|---:|---:|
| CairnYap, stripped | 3,277,816 (3.28 MB) | |
| before strip | 4,991,832 | under `SIZE_LIMIT` (5,000,000 stripped) |
| Lean runtime: Init, Std | 1,168,440 | 35.6% |
| Lean runtime: leanrt, libuv, libgmp | 434,955 | 13.3% |
| Cairn (Lean) | 350,157 | 10.7% |
| the app's library (`libcairn_app_yap`) | 384,089 | 11.7% |
| Swift host (CairnHost 419,789, CairnFrame 112,143, CairnYap 87,228, CairnRender 81,822) | 701,563 | 21.4% |
| Metal shader source | 3,753 | 0.1% |
| linker, other | 234,859 | 7.2% |

The signed bundle `build/apps/Yap (Cairn).app` (`make yap`) is 4.8 MB on disk; its executable is
the unstripped release binary, 4,981,536 bytes.

## Fuzzing and conformance

| | |
|---|---:|
| `yapfuzz`, host mode (`step`), 1,000 × 300 | 303,492 steps in 1.37 s, about 220,000 steps/s |
| `yapfuzz`, app mode (`receive`, `menuStep`), 1,000 × 300 | 300,000 steps in about 1.4 s |
| `make conformance APP=Yap N=200` | 200 walks, 2,403 steps, flows 2/2; p50 51.6 ms per step (the menu's `performActionForItem`, bench/surfaces.md) |

## Not measured yet

Key-up to typed against the original Yap with the same audio, and idle CPU and memory: these
need the real app with the microphone and OpenAI, on a day of use.

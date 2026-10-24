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

## The overlay

The overlay is drawn as the original's is (docs/yap.md, "Overlay parity"): the tape is a Metal
painter fed the levels and cuts, and the view is laid out twice per frame while the text eases
(the resting view at the old and new text, to find the heights). `CAIRN_BENCH=1 swift run -c
release CairnYap --overlay-scenes tools/overlay-parity/scenes/sample.json <dir>` times each scene
300 times: the Lean frame (`cairn_yap_overlay_frame`: view, layout, encoding) and an offscreen 2x
render of it, at rest and halfway through the 0.15 s ease.

| scene | Lean frame p50 / p95 / max | render p50 / p95 / max |
|---|---:|---:|
| failed, no text, rest | 0.038 / 0.042 / 0.107 ms | 0.720 / 0.897 / 1.308 ms |
| failed, two lines, rest | 0.055 / 0.061 / 0.091 ms | 0.864 / 1.011 / 1.304 ms |
| failed, two lines, easing | 0.091 / 0.097 / 0.205 ms | 0.917 / 1.055 / 1.381 ms |
| listening, 300 characters, rest | 0.080 / 0.086 / 0.128 ms | 0.969 / 1.088 / 1.470 ms |
| listening, 300 characters, easing | 0.127 / 0.133 / 0.194 ms | 1.034 / 1.197 / 1.543 ms |
| typed, 300 characters, easing | 0.126 / 0.134 / 0.169 ms | 1.008 / 1.177 / 1.609 ms |

Easing costs about 0.05 ms of Lean per frame (the two extra measures). The render includes
waiting for the GPU and reading the image back, which the on-screen path does not do. With the
overlay on frame v4 the self test's levels run (above) measured 0.30 ms p50, 0.74 ms p95 and
1.49 ms max for Lean step + frame + decode, and 0.12 ms p50, 0.91 ms max for the surface apply.

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
| CairnYap, stripped | 3,641,304 (3.64 MB) | |
| before strip | 5,551,544 | under `SIZE_LIMIT` (5,000,000 stripped) |
| Lean runtime: Init, Std | 1,172,540 | 32.2% |
| Lean runtime: leanrt, libuv, libgmp | 436,898 | 12.0% |
| Cairn (Lean) | 363,420 | 10.0% |
| the app's library (`libcairn_app_yap`) | 570,029 | 15.7% |
| Swift host (CairnHost 426,916, CairnYap 134,152, CairnRender 130,818, CairnFrame 123,736, CairnYapPaint 11,080) | 827,287 | 22.7% |
| Metal shader source | 10,779 | 0.3% |
| linker, other | 260,351 | 7.2% |

That is 363,488 bytes more than Yap as it first landed (3,277,816, #48). Frame v4 and the
changes since #48 (#53, #56) bring it to 3,553,976; the overlay itself adds 87,328 (the view and
its ease in the app's library, the tape painter and the parity tools in the host).

At #48 the signed bundle `build/apps/Yap (Cairn).app` (`make yap`) is 4.8 MB on disk; its executable is
the unstripped release binary, 4,981,536 bytes.

## Fuzzing and conformance

| | |
|---|---:|
| `yapfuzz`, host mode (`step`), 1,000 × 300 | 303,492 steps in 1.37 s, about 220,000 steps/s |
| `yapfuzz`, app mode (`receive`, `menuStep`), 1,000 × 300 | 300,000 steps in about 1.4 s |
| `make conformance APP=Yap N=200` | 200 walks, 2,403 steps, flows 2/2; p50 51.6 ms per step (the menu's `performActionForItem`, bench/surfaces.md) |

## Not measured yet

Against the original Yap with the same synthetic audio and stubbed OpenAI and typing (key up to
typed, idle CPU and memory, the overlay's frame pacing, launch): see
[yap-instruments.md](yap-instruments.md). Still not measured: the real microphone and network,
on a day of use.

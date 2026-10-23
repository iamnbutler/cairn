# Renderer benchmark

`make bench` (the `RenderBench` suite: `CAIRN_BENCH=1 swift test -c release -Xswiftc
-enable-testing --filter RenderBench`). Each frame is painted at 2x into a 2400×1600
`bgra8Unorm` texture (a 1200×800 pt window). Median of 50 frames after 5 warm-up frames, three
runs, Apple M4 Max, macOS 27, 2026-10-23.

- **CPU**: `Renderer.draw` from call to commit: building instances and batches, atlas lookups,
  text shaping on a cache miss, filling the pooled instance buffer, encoding and committing.
- **GPU**: `gpuEndTime − gpuStartTime` of the command buffer (clear, vertex and fragment work).

| Frame | CPU (ms) | GPU (ms) | Batches |
|---|---:|---:|---:|
| 1,000 rects (⅓ plain, ⅓ rounded, ⅓ rounded + border) | 0.02–0.03 | 0.22 | 1 |
| 10,000 rects (same mix) | 0.10–0.12 | 0.52 | 1 |
| 1,000 text runs ("Todo item N", 13 pt, ⅕ bold), lines cached | 0.53–0.62 | 0.33 | 2 |
| 1,000 text runs, every string new each frame | 23.6–23.8 | 0.37 | 2 |

Reading:

- Rects are cheap: about 10 ns of CPU per rect, and the GPU time is dominated by filling the
  full-window background at 2x (0.22 ms with 1k small rects on top).
- Cached text costs about 0.5 µs per run (≈ 12 glyphs: a dictionary lookup per glyph plus the
  line lookup under the lock).
- A line cache miss costs about 24 µs (one `CTLine` plus reading its runs). In the app, Lean
  measures every string during layout (`TextMetrics.host`) before the render thread draws it, so
  the miss is paid on the Lean thread and the render thread hits the cache. A frame where 1,000
  strings change at once would spend ~24 ms shaping on the Lean thread; typing changes one.
- New glyphs are rasterised once per (font, glyph, subpixel bin, scale); the warm-up frames
  absorb that, so the rasterisation cost is not in these numbers.

For comparison, the Lean side (spike numbers, docs/spike-boundary.md) spends 0.4 ms on layout
and encoding at 1,000 nodes and 3.7–4.0 ms at 10,000.

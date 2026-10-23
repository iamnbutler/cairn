# Frame encoding benchmark

`make bench-frame`: `framecorpus bench build/corpus 100` (Lean, compiled, mean of 100 runs after
5 warm-up runs), then the `DecodeBench` suite (`CAIRN_BENCH=1 swift test -c release
-Xswiftc -enable-testing --filter DecodeBench`, mean and best of repeated decodes). Three runs
each, Apple M4 Max, macOS 27, 2026-10-23, with other agents' builds running (load average
6–12), so treat the ranges as upper bounds.

The frame is `benchLaid n` in `lean/FrameCorpus.lean`: a clipped window holding `n / 2` rows,
each a rounded box with a `listItem` control and a text "Item i". That is `n + 2` draws (one
rect and one text per row, plus a push and pop) and `n` accessibility nodes, every node with a
label string.

| Nodes | Bytes | `Frame.ofLaid` (Lean) | `encodeFrame` (Lean) | Decode, whole frame (Swift) | Decode, draws only (Swift) |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 89,742 | 0.062–0.066 ms | 0.27–0.28 ms | 0.019–0.020 ms | 0.007 ms |
| 10,000 | 911,742 | 0.66–0.71 ms | 2.67–2.82 ms | 0.184–0.188 ms | 0.066–0.069 ms |

Reading:

- **Encoding is about 90 bytes and 0.27 µs per node.** Most of it is `lean_byte_array_push`, one
  call per byte (the builder writes each `u32` as four pushes). Lengths are computed up front
  (`Len`), so the buffer is allocated once at its final size and never copied.
- **Earlier version: 4.4 ms at 10,000 nodes.** Reducing `Int` coordinates `% 2^32` and comparing
  them with `2^32` went through GMP for every field: Lean's `Int` is boxed outside 32 bits.
  Converting through `UInt32` (`i32Word`, proved equal to the arithmetic specification) halved
  it.
- **Swift decoding is 10–15× faster than Lean encoding**, about 20 ns per node, and about 0.2 GB/s
  of frame. The draws alone (what the render thread reads) take a third of that.
- **UTF-8 validation.** `String(validating:as:)` made decoding 0.69–0.81 ms at 10,000 nodes.
  The decoder now uses `String(decoding:as:)`, which is about 5× faster but repairs bad input
  with U+FFFD, and checks validity by comparing the result's UTF-8 with the input
  (`memcmp`): 0.18 ms, still strict.
- For comparison, the spike's v0 path (docs/spike-boundary.md) spent 3.7–4.0 ms on layout and
  encoding at 10,000 nodes, with no text, no strings and a much smaller accessibility record.

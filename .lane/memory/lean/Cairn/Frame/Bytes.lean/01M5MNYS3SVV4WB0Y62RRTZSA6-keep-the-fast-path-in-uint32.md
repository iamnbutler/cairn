---
id: 01M5MNYS3SVV4WB0Y62RRTZSA6
anchor: def i32Word
created: 2026-10-23T15:27:01Z
norm: '1'
---

Keep the fast path in UInt32: Int % 2^32 and comparisons with 2^32 go through GMP (Int is boxed outside 32 bits) and doubled encodeFrame time (bench/frame.md).

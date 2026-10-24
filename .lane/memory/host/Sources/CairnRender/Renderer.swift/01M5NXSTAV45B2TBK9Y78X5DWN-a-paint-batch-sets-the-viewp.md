---
id: 01M5NXSTAV45B2TBK9Y78X5DWN
anchor: painterPipeline
created: 2026-10-24T03:03:22Z
norm: '1'
supersedes: 01M5NVS4KM050Y7TA231M741NX
---

A paint batch sets the viewport to the box and the scissor to box ∩ clip, then must restore the full viewport and rebind the vertex viewport bytes; render.paint.bounds (^1004) fuzzes the scissor.

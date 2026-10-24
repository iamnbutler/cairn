---
id: 01M5NVS4KM050Y7TA231M741NX
anchor: painterPipeline
created: 2026-10-24T02:28:02Z
norm: '1'
---

A paint batch sets the viewport to the box and the scissor to box ∩ clip, then must restore the full viewport and rebind the vertex viewport bytes; render.paint.bounds (^1003) fuzzes the scissor.

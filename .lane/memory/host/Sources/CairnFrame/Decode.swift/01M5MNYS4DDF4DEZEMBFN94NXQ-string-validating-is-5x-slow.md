---
id: 01M5MNYS4DDF4DEZEMBFN94NXQ
anchor: 'String(decoding:'
created: 2026-10-23T15:27:01Z
norm: '1'
---

String(validating:) is ~5x slower; String(decoding:) repairs invalid UTF-8, so the memcmp against the input is what keeps the decoder strict. Don't drop it.

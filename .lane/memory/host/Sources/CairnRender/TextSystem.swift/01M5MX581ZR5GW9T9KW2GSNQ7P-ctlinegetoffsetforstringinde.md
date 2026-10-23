---
id: 01M5MX581ZR5GW9T9KW2GSNQ7P
anchor: caret
created: 2026-10-23T17:32:53Z
norm: '1'
---

CTLineGetOffsetForStringIndex returns 0 for real carets (before a trailing control; after some fallback runs); caret() falls back to the first glyph at or after the index. Fuzzed by CairnFuzzTrusted text.metrics.carets (^907).

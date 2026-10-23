---
id: 01M5MMNBPJ1DNMVXB7GMRTV451
anchor: '@file'
created: 2026-10-23T15:04:24Z
norm: '1'
sig: c4acdce8272c4814
body_hash: 18e89b0fa16df18b
raw_hash: df9803f4c6ca58f7
lines: 1-122
---

Metrics and drawing must read the same cached CTLine per (font, string); never measure prefixes (kerning) and map scalar boundaries to UTF-16 by summing utf16 counts (mid-surrogate queries return 0).

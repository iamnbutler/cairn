---
id: 01M5MMNBPJ1DNMVXB7GMRTV451
anchor: '@file'
created: 2026-10-23T15:04:24Z
norm: '1'
sig: c4acdce8272c4814
body_hash: 10b367aef01b0e2d
raw_hash: 00319ca7360871bd
vouched: 2026-10-23T17:42:16Z
lines: 1-122
---

Metrics and drawing must read the same cached CTLine per (font, string); never measure prefixes (kerning) and map scalar boundaries to UTF-16 by summing utf16 counts (mid-surrogate queries return 0).

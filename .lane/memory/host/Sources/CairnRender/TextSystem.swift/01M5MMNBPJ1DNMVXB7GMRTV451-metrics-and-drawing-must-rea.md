---
id: 01M5MMNBPJ1DNMVXB7GMRTV451
anchor: '@file'
created: 2026-10-23T15:04:24Z
norm: '1'
sig: c4acdce8272c4814
body_hash: e2a62f5b3bc184ad
raw_hash: 9184fa2ae65114db
vouched: 2026-10-23T22:35:31Z
lines: 1-122
---

Metrics and drawing must read the same cached CTLine per (font, string); never measure prefixes (kerning) and map scalar boundaries to UTF-16 by summing utf16 counts (mid-surrogate queries return 0).

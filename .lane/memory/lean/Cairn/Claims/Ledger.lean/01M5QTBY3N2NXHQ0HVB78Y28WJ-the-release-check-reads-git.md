---
id: 01M5QTBY3N2NXHQ0HVB78Y28WJ
anchor: '@file'
created: 2026-10-24T20:41:50Z
norm: '1'
sig: 382e720f4ce152d8
body_hash: 32b10ff97625cd01
raw_hash: 1d428977d4ab76bc
lines: 1-273
---

the release check reads git tags and cairn.toml beside the lock; with neither (a shallow clone, no tags) it passes silently, so a CI that runs make check needs tags fetched

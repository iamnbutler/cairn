---
id: 01M5QTBY3N2NXHQ0HVB78Y28WJ
anchor: '@file'
created: 2026-10-24T20:41:50Z
norm: '1'
sig: 382e720f4ce152d8
body_hash: 5d822ed26d48cbd8
raw_hash: b1f5eecb78806384
vouched: 2026-10-25T22:08:15Z
lines: 1-273
---

the release check reads git tags and cairn.toml beside the lock; with neither (a shallow clone, no tags) it passes silently, so a CI that runs make check needs tags fetched

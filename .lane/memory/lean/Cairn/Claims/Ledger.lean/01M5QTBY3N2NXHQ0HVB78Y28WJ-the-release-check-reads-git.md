---
id: 01M5QTBY3N2NXHQ0HVB78Y28WJ
anchor: '@file'
created: 2026-10-24T20:41:50Z
norm: '1'
sig: 382e720f4ce152d8
body_hash: b753c430b46d9230
raw_hash: 98b62e66d60eb193
vouched: 2026-10-25T01:17:56Z
lines: 1-273
---

the release check reads git tags and cairn.toml beside the lock; with neither (a shallow clone, no tags) it passes silently, so a CI that runs make check needs tags fetched

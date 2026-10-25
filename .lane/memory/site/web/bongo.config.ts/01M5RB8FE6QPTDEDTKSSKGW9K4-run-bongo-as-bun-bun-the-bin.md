---
id: 01M5RB8FE6QPTDEDTKSSKGW9K4
anchor: '@file'
created: 2026-10-25T01:37:02Z
norm: '1'
sig: 5b05b4f75a5503f9
body_hash: 8c2760de12d7c6c1
raw_hash: d64810960182c4c7
vouched: 2026-10-25T01:55:02Z
lines: 1-78
---

Run bongo as `bun --bun`: the bin runs under Node, and lib/docs.ts uses Bun.markdown. bongo empties public/ on a failed build, so it never writes into site/public; make site-dist merges the two.

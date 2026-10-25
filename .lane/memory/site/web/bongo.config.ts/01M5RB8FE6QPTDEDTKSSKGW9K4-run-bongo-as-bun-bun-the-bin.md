---
id: 01M5RB8FE6QPTDEDTKSSKGW9K4
anchor: '@file'
created: 2026-10-25T01:37:02Z
norm: '1'
sig: 5b05b4f75a5503f9
body_hash: c696dc313307cd9c
raw_hash: e7b27cecc5c6d1f7
vouched: 2026-10-25T02:04:00Z
lines: 1-78
---

Run bongo as `bun --bun`: the bin runs under Node, and lib/docs.ts uses Bun.markdown. bongo empties public/ on a failed build, so it never writes into site/public; make site-dist merges the two.

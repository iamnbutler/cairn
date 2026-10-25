---
id: 01M5RB8FE6QPTDEDTKSSKGW9K4
anchor: '@file'
created: 2026-10-25T01:37:02Z
norm: '1'
sig: 5b05b4f75a5503f9
body_hash: dea3cdff422d75c0
raw_hash: b58825b963761835
vouched: 2026-10-25T03:03:37Z
lines: 1-78
---

Run bongo as `bun --bun`: the bin runs under Node, and lib/docs.ts uses Bun.markdown. bongo empties public/ on a failed build, so it never writes into site/public; make site-dist merges the two.

---
id: 01M5RB8FE6QPTDEDTKSSKGW9K4
anchor: '@file'
created: 2026-10-25T01:37:02Z
norm: '1'
---

Run bongo as `bun --bun`: the bin runs under Node, and lib/docs.ts uses Bun.markdown. bongo empties public/ on a failed build, so it never writes into site/public; make site-dist merges the two.

---
id: 01M5RB7H0XC1PJ3WSDQYW7K8GN
anchor: $loaders
created: 2026-10-25T01:36:31Z
norm: '1'
---

Run bongo as `bun --bun`: the bin runs under Node, and lib/docs.ts uses Bun.markdown. bongo empties public/ on a failed build, so it never writes into site/public; make site-dist merges the two.

---
id: 01M5VPHD6TSPMBDQ7CTVMHEH6G
anchor: def fixUI
created: 2026-10-26T08:51:53Z
norm: '1'
supersedes: 01M5TM8TW1SNAW2SGFRBW7BWGW
---

fixUI clamps UI.scroll against the scrollers of the tree just laid and drops offsets whose box is gone, except boxes the app keeps (App.keepScroll), whose offset and list heights move to UI.kept/keptLists and come back when the box does; Clamped/step_clamped rest on this being the only place the slow path sets scroll. UI.same must compare scroll, kept and keptLists, or a step takes the fast path and never relays out.

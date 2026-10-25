---
id: 01M5TM8TW1SNAW2SGFRBW7BWGW
anchor: def fixUI
created: 2026-10-25T22:53:00Z
norm: '1'
---

fixUI clamps UI.scroll against the scrollers of the tree just laid and drops offsets whose box is gone; Clamped/step_clamped rest on this being the only place the slow path sets scroll. UI.same must compare scroll, or a wheel step takes the fast path and never relays out.

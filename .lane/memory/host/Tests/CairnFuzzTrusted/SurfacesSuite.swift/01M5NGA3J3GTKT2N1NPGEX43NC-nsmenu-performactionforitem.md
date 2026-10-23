---
id: 01M5NGA3J3GTKT2N1NPGEX43NC
anchor: performActionForItem
created: 2026-10-23T23:07:35Z
norm: '1'
---

NSMenu.performActionForItem(at:) costs about 60 ms per call on a detached menu (sendAction about 3 µs), so menu.select is sampled in a third of updates; choosing every item made the quick run take 142 s.

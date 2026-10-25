---
id: 01M5RPFSR0VK37SNPSDZ336BQW
anchor: func setDrawn
created: 2026-10-25T04:53:17Z
norm: '1'
---

The store trims only on put, setDrawn and setBudget; after a removal it may stay over budget holding the last put entry until the next trim (images.cache's oracle allows exactly that)

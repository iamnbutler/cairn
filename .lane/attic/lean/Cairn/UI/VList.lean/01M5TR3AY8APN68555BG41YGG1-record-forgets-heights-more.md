---
id: 01M5TR3AY8APN68555BG41YGG1
anchor: def keepSpan
created: 2026-10-25T23:59:54Z
norm: '1'
---

record forgets heights more than keepSpan rows from the window, so a step stays flat however much of the list has been seen (bench/vlist.md: 25 ms at 100k with every height kept). Forgotten rows go back to the estimate; the anchor correction absorbs the difference.

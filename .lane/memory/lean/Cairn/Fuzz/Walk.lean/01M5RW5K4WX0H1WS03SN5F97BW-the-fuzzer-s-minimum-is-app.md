---
id: 01M5RW5K4WX0H1WS03SN5F97BW
anchor: '@file'
created: 2026-10-25T06:32:34Z
norm: '1'
sig: 94daed292dbe59a1
body_hash: fb5aade3245b7c4c
raw_hash: d414086723bf7033
vouched: 2026-10-25T22:23:06Z
lines: 1-577
---

The fuzzer's minimum is App.minSize when nonzero (the host clamps the window to it, trusted ^1010); the measured preferred size is only the fallback. Gallery's view reads ui.size, so its measured size tracks the window and is no floor at all.

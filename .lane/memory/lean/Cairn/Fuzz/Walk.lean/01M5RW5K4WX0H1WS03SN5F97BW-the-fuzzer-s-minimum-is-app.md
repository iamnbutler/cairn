---
id: 01M5RW5K4WX0H1WS03SN5F97BW
anchor: '@file'
created: 2026-10-25T06:32:34Z
norm: '1'
---

The fuzzer's minimum is App.minSize when nonzero (the host clamps the window to it, trusted ^1010); the measured preferred size is only the fallback. Gallery's view reads ui.size, so its measured size tracks the window and is no floor at all.

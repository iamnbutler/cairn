---
id: 01M5TJJ0P9PMGB5ZC4H6GKD3TF
anchor: def checks
created: 2026-10-25T22:23:04Z
norm: '1'
---

Controls whose visible part (rect ∩ clip) is empty are scrolled out: no ops, candidates or pressable check for them. The pressable gate uses controlRectsNonempty (rect-based): scrolled-out rows have nonempty rects but empty visible parts.

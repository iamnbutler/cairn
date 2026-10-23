---
id: 01M5MSNHA4856X9X5YXA7MZ52C
anchor: func key
created: 2026-10-23T16:31:53Z
norm: '1'
---

Synthesized key events must match the keyboard's charactersIgnoringModifiers too: AppKit's key bindings read it, so Shift-Tab with '\t' there becomes insertTab: (forward), not insertBacktab:. Found by conformance (walk-1-66).

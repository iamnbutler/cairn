---
id: 01M5P5Y2WPSHW6GRVARYYEECC9
anchor: caret
created: 2026-10-24T05:25:30Z
norm: '1'
---

A tracked line's carets never come from Core Text (it centres them in the tracking gap and misplaces them beside control glyphs): caret(u) is the furthest pen end (pos + advance) of glyphs with index < u. Untracked lines keep Core Text's carets. Fuzzed by text.metrics.carets (^907), docs/fuzz.md finding 11.

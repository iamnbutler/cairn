---
id: 01M5W7CM7W00X6VMPPDPY4TX4X
anchor: def anchorAt
created: 2026-10-26T13:46:22Z
norm: '1'
---

A clamped correction holds the kept row (Anchor.hold) instead of re-anchoring on the row at the clamped offset; Runtime.steps lets holds go (State.shown) at the end of each batch. Hold-forever fails the fuzz anchor check across batches (Sky seed 130 step 235: a box grew then shrank, and the list scrolled back); no hold fails it within one (#271). Anything that folds step over a batch must apply State.shown.

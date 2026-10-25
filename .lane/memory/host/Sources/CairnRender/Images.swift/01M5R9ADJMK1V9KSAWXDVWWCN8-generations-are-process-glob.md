---
id: 01M5R9ADJMK1V9KSAWXDVWWCN8
anchor: lastGeneration
created: 2026-10-25T01:03:09Z
norm: '1'
---

Generations are process-global, not per store: the renderer caches textures by source+generation, and per-store counters let a second store's entry reuse a stale texture (render.image.pixels caught it).

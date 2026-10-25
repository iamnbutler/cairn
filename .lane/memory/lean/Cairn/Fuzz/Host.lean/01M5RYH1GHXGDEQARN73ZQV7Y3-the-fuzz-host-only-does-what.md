---
id: 01M5RYH1GHXGDEQARN73ZQV7Y3
anchor: def genHost
created: 2026-10-25T07:13:46Z
norm: '1'
---

The fuzz host only does what the trusted claims allow (^908, ^909, ^914, ^1006, ^1009, ^1011): no duplicate replies to live ids, no wrong-shaped replies, no clock going back. Off-contract 'stray' replies only go to ids the runtime doesn't hold, so a failure is never a host artefact. Keep it that way, or failures stop meaning app bugs.

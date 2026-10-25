---
id: 01M5TF8XDWQPK1T5EB0QK44R6Z
anchor: def checks
created: 2026-10-25T21:25:40Z
norm: '1'
---

The 'secure' check looks for Text.planted as text and as hex: Dump prints bytes (request bodies) as hex, so a text-only search misses an unredacted body (found by mutating the fixture's redact to false).

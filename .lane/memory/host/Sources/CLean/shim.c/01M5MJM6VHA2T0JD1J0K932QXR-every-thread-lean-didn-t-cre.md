---
id: 01M5MJM6VHA2T0JD1J0K932QXR
anchor: fn lean_initialize_thread
created: 2026-10-23T14:28:49Z
norm: '1'
---

Every thread Lean didn't create must call cairn_lean_thread_begin before any Lean call; these runtime symbols aren't in lean.h (4.35).

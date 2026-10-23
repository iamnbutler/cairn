---
id: 01M5MJM6VHA2T0JD1J0K932QXR
anchor: fn lean_initialize_thread
created: 2026-10-23T14:28:49Z
norm: '1'
sig: e13355173d7e9b66
body_hash: e3b0c44298fc1c14
raw_hash: d9ef54b158c036d7
lines: 7-7
---

Every thread Lean didn't create must call cairn_lean_thread_begin before any Lean call; these runtime symbols aren't in lean.h (4.35).

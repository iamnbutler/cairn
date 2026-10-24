---
id: 01M5MW48P751BSHQFC7W98X654
anchor: function evaluate
created: 2026-10-23T17:14:52Z
norm: '1'
sig: 8c45d9a82d1603d7
body_hash: 0ef237e778134eec
raw_hash: 693786d1cb85bb71
lines: 116-252
---

A model-mode fuzz run (an app with no App, like Counter on frame v0) reports every move as pass:null 'not run': presence and pressability need a frame, so moves have no checks there. Only invariants are fuzzed.

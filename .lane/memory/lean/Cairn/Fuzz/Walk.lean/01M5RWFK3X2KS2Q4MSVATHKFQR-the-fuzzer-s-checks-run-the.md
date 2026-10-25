---
id: 01M5RWFK3X2KS2Q4MSVATHKFQR
anchor: def checks
created: 2026-10-25T06:38:01Z
norm: '1'
supersedes: 01M5MT8H24F9MP63NMW6BGS678
---

The fuzzer's checks run the Lean model and runtime with its own TextMetrics, never Core Text; a pass is not evidence about the host. Pressability is only checked at windows at or above Target.minSize: the fuzz config's, else App.minSize (the host enforces it, trusted ^1010), else the view's measured size.

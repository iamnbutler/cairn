---
id: 01M5MPD2G1WTBAC2AY36GSFSVH
anchor: '@file'
created: 2026-10-23T15:34:50Z
norm: '1'
sig: e3b0c44298fc1c14
body_hash: 9f6c4f1d2a53751e
raw_hash: 3f571a940d32ee36
lines: 1-30
---

App objects reference the commands' full/meta initializers even though the host only runs runtime_initialize_*; the weak stubs resolve them without libLean.

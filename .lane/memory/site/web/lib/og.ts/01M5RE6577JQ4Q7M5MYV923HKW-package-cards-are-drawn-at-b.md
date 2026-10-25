---
id: 01M5RE6577JQ4Q7M5MYV923HKW
anchor: '@file'
created: 2026-10-25T02:28:12Z
norm: '1'
sig: e3b0c44298fc1c14
body_hash: 9779825fd7c51f46
raw_hash: a72f50e4d9935206
vouched: 2026-10-25T02:39:15Z
lines: 1-41
---

package cards are drawn at build, not in the Worker: satori 0.33+ compiles its inlined harfbuzz wasm from bytes, which Workers forbid, and pre-harfbuzz satori lays text out differently

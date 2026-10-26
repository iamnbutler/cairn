---
id: 01M5VNKSJXNM03P7YV9KBZVPSP
anchor: '@file'
created: 2026-10-26T08:35:42Z
norm: '1'
sig: 3af71adb278ad4af
body_hash: 491142cd13f131ec
raw_hash: 1abb6551f4142d7e
lines: 1-168
---

libStd.a must stay in the libtool merge: Cairn.Optimistic imports Std.Data.TreeMap, and without it every app's link fails on _runtime_initialize_Std_* (the linker keeps only reached members)

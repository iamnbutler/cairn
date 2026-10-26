---
id: 01M5VNKSJXNM03P7YV9KBZVPSP
anchor: '@file'
created: 2026-10-26T08:35:42Z
norm: '1'
---

libStd.a must stay in the libtool merge: Cairn.Optimistic imports Std.Data.TreeMap, and without it every app's link fails on _runtime_initialize_Std_* (the linker keeps only reached members)

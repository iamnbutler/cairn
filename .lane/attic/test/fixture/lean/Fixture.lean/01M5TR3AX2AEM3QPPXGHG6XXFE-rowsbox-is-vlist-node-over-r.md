---
id: 01M5TR3AX2AEM3QPPXGHG6XXFE
anchor: def rowsBox
created: 2026-10-25T23:59:54Z
norm: '1'
supersedes: 01M5TM8TWF7H91QKDJ5MXPP925
---

rowsBox is VList.node over rowsList (scrollRef rowsRef, ^14's ref): the ref keys both the runtime's offset and its recorded heights (UI.lists). The end line is the key-0 row, last in s.keys, so it is laid (and ^16 appears) only near the end; role .text keeps it out of Tab order (the Tab tests filter it with notRow). New rows take keys from s.nextKey, never 0.

---
id: 01M5TM8TWF7H91QKDJ5MXPP925
anchor: def rowsBox
created: 2026-10-25T22:53:00Z
norm: '1'
---

rowsBox carries scrollRef := rowsRef (^14's ref): without it the runtime owns no offset and the box sits at the view's value forever. The end line must stay a child of rowsBox (^16 appears only when scrolled to the end) and role .text so it's not focusable (the Tab-order tests filter it with notRow).

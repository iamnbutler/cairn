---
id: 01M5RMNH4MZE5TNKWN3SE9NRNF
anchor: func apply
created: 2026-10-25T04:21:27Z
norm: '1'
---

apply runs on every applied frame and grows a window smaller than the minimum back to it: code that sizes the window with setContentSize/setFrame below the minimum fights it. Resize as a drag does, proposing through windowWillResize first (Gallery's demos, drag(_:to:)).

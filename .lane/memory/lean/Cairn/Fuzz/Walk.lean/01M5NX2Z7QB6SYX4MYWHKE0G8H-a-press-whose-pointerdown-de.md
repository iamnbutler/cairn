---
id: 01M5NX2Z7QB6SYX4MYWHKE0G8H
anchor: def checks
created: 2026-10-24T02:50:53Z
norm: '1'
---

A press whose pointerDown delivers a blur and leaves the control away from the point is a T33 dropped click (Runtime.click_presses's hypothesis fails): counted as droppedT33, never a 'performed' failure. Don't narrow it to Todo; don't drop the blur condition (a control moving on pointerDown alone is still a bug).

---
id: 01M5RWFTV9TWKJT8S0P1595MCA
anchor: func runMain
created: 2026-10-25T06:38:09Z
norm: '1'
---

NSWindow.sendEvent delivers no mouse events to a window that was never shown (every click came back missing), so the suite routes each event with hitTest on the content's superview and calls the view's handler, as sendEvent would. Don't switch to sendEvent without showing the window.

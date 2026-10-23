---
id: 01M5NGA3H8075NY9YN01W95309
anchor: func configure
created: 2026-10-23T23:07:35Z
norm: '1'
---

AppKit reports an item inside a disabled submenu as isEnabled == false whatever its own flag; the fuzz oracle and the conformance model use the effective flag (AND along the path). Lean never disables a submenu.

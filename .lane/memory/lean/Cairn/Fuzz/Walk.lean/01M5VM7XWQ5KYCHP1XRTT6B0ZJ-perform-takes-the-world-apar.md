---
id: 01M5VM7XWQ5KYCHP1XRTT6B0ZJ
anchor: '@file'
created: 2026-10-26T08:11:45Z
norm: '1'
---

perform takes the World apart before hostStep and hostStep returns the server's world even when the move can't happen: any other live reference makes Server.handle copy the world (LEAN_ABORT_ON_NONLINEAR=1 aborts).

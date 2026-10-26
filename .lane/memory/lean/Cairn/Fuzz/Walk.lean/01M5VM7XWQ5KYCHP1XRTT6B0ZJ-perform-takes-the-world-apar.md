---
id: 01M5VM7XWQ5KYCHP1XRTT6B0ZJ
anchor: '@file'
created: 2026-10-26T08:11:45Z
norm: '1'
sig: 94daed292dbe59a1
body_hash: 9b972cc24edd10ed
raw_hash: fe8c299bdaf965f4
vouched: 2026-10-26T09:31:42Z
lines: 1-1253
---

perform takes the World apart before hostStep and hostStep returns the server's world even when the move can't happen: any other live reference makes Server.handle copy the world (LEAN_ABORT_ON_NONLINEAR=1 aborts).

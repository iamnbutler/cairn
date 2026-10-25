---
id: 01M5RYH1H3KAMJQE1WFKTBBG0W
anchor: def perform
created: 2026-10-25T07:13:46Z
norm: '1'
---

Every operation's batch starts with the host clock (^908); the host absorbs each step's effects (requests, cancels) and the fuzzer clears rt.subCmds after each step, since step only appends to it. Replays of host ops whose request/sub/wake isn't there are skipped (ran := false), like a missing control.

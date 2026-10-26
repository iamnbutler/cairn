---
id: 01M5V8XDQ4H4FSNCQHESTCWQBY
anchor: '@file'
created: 2026-10-26T04:53:46Z
norm: '1'
sig: c4acdce8272c4814
body_hash: ba9f10211313e03b
raw_hash: 42a3f0b49b970df0
lines: 1-532
---

the concurrency check runs in a child process and the parent deletes its items: a deadlocked process can't clean up, and only the same executable may delete the items it made

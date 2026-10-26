---
id: 01M5VWA9EW05ST8DBX5XHD37YJ
anchor: '@file'
created: 2026-10-26T10:32:51Z
norm: '1'
sig: c4acdce8272c4814
body_hash: 9249a040aec37c7c
raw_hash: 3212c6da45132c16
lines: 1-341
---

a wake timer's handler can already be on its way when scheduleWake cancels it; wakeGen makes a replaced timer's handler a no-op, and the held flag is read with the batch so a held empty batch is skipped

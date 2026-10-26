---
id: 01M5V8XDPJ6HSH0BDHVD75BWMT
anchor: '@file'
created: 2026-10-26T04:53:46Z
norm: '1'
sig: c4acdce8272c4814
body_hash: 47ef95df13e18ebf
raw_hash: 5ab6ffa68fc42aa2
lines: 1-340
---

every Security call goes through KeychainStore.serialized (one queue per process, not per store): concurrent delete and read on one service deadlock inside Security (#237)

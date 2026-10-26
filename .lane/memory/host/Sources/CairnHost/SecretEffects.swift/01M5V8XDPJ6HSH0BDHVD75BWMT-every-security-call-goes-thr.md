---
id: 01M5V8XDPJ6HSH0BDHVD75BWMT
anchor: '@file'
created: 2026-10-26T04:53:46Z
norm: '1'
sig: c4acdce8272c4814
body_hash: 80cda3d99548a99d
raw_hash: 0fa108390c169c7f
vouched: 2026-10-26T06:39:50Z
lines: 1-340
---

every Security call goes through KeychainStore.serialized (one queue per process, not per store): concurrent delete and read on one service deadlock inside Security (#237)

---
id: 01M5TF8XE9A0BV4SQQVT958DTM
anchor: import Cairn.Text.Field
created: 2026-10-25T21:25:40Z
norm: '1'
---

Dump is linked into the trusted fuzz library (libcairn_trusted_fuzz.a); importing Cairn.Text.Proofs here breaks its link (_initialize_cairn_Cairn_Text_Proofs). Theorems Dump needs live in Text/Field.lean.

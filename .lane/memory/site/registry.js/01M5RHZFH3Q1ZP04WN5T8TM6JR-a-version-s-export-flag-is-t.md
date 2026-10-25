---
id: 01M5RHZFH3Q1ZP04WN5T8TM6JR
anchor: function remote
created: 2026-10-25T03:34:28Z
norm: '1'
sig: 98ed04ac526b9a81
body_hash: 97835ab3490cf90d
raw_hash: 07ea6f2f1a57994c
lines: 40-86
---

A version's export flag is three-way: true fetches …/claims/export, false skips the request, and missing (a registry from before nextpm#28) fetches and treats a 404 as no export. Pages must still render from claims.lock rows alone, because the site deploys independently of the registry.

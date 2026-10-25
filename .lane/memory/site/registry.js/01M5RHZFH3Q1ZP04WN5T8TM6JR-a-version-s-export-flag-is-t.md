---
id: 01M5RHZFH3Q1ZP04WN5T8TM6JR
anchor: function remote
created: 2026-10-25T03:34:28Z
norm: '1'
---

A version's export flag is three-way: true fetches …/claims/export, false skips the request, and missing (a registry from before nextpm#28) fetches and treats a 404 as no export. Pages must still render from claims.lock rows alone, because the site deploys independently of the registry.

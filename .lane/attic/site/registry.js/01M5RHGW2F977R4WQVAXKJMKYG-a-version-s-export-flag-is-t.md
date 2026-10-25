---
id: 01M5RHGW2F977R4WQVAXKJMKYG
anchor: exported(
created: 2026-10-25T03:26:29Z
norm: '1'
---

A version's export flag is three-way: true fetches the export, false skips the request, and missing (a registry from before nextpm#28) fetches and treats a 404 as no export. Pages must render from claims.lock rows alone, because the site deploys independently of the registry.

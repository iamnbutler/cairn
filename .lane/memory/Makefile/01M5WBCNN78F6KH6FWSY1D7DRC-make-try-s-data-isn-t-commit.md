---
id: 01M5WBCNN78F6KH6FWSY1D7DRC
anchor: 'try:'
created: 2026-10-26T14:56:18Z
norm: '1'
---

make try's data isn't committed or built at deploy: tools/try/put.ts uploads it to R2 under content-hashed keys and site/public/try/apps.json points at it; rerun both and commit apps.json when TRY_REV moves

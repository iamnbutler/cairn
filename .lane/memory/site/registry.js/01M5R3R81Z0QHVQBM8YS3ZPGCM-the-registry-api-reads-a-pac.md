---
id: 01M5R3R81Z0QHVQBM8YS3ZPGCM
anchor: function remote
created: 2026-10-24T23:25:51Z
norm: '1'
sig: 98ed04ac526b9a81
body_hash: cddde5f96a499876
raw_hash: f8de1b7e1b19c431
lines: 37-75
supersedes: 01M5R2NQYWPZ49W3J4MFV3K2XY
---

The registry API reads a package only as <owner>/<name>; the site finds a name's owner with GET /api/v1/names/<name> (nextpm), 404 meaning the registry doesn't hold it. Don't go back to an exact match in ?q= search: a package missing from the search index couldn't be shown.

---
title: Claim pages
nav: Claim pages
eyebrow: Evidence
lede: Every claim a package makes, grouped by place, each on a page of its own, generated from what it published.
---

Every package on the registry has claim pages: each version's claims, grouped by the place
(window) they belong to, and a page for each claim with what you do and see, a flow's steps, its
evidence theorems and where it's defined. They are rendered from the claims export that
`cairn publish` sends with each version, checked by the registry against the version's
`claims.lock`. Nothing on them is written by hand. [The evidence ladder](/docs/reference/evidence/)
explains what each kind of evidence means.

Cairn's own examples and trusted base are claims of the `cairn` package:

| Place | What it covers |
|---|---|
| [Counter](/packages/cairn/claims/3/) | ^1–^7: two moves, two flows, an assumption and a retired claim |
| [Basics](/packages/cairn/claims/106/) | ^101–^109: a field, a keyed list and an invariant |
| [TodoMVC](/packages/cairn/claims/201/) | ^201–^224: the full TodoMVC spec |
| [The trusted base](/packages/cairn/claims/#assumptions) | the host's assumptions, ^9xx and ^10xx |

The pages show the evidence the export holds: proofs and their axioms, assumptions, flow
witnesses, retired and moved ids. Fuzzing, conformance and screenshots need a build that runs
the app, and a claim lists them as not shown yet until CI publishes them. A version published
before the export existed shows its ledger alone.

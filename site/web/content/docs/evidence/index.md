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

Cairn's own claims are its trusted base, in the `cairn` package. Every app's are its own
package's ([apps on Cairn](/docs/examples/)):

| Place | What it covers |
|---|---|
| [The trusted base](/packages/cairn/claims/#assumptions) | the host's assumptions, cairn^7, cairn^214, ^9xx and ^10xx |
| [Counter](/packages/cairn_examples/claims/3/) | cairn_examples^1–^6: two moves, two flows and a retired claim |
| [Basics](/packages/cairn_examples/claims/106/) | cairn_examples^101–^109: a field, a keyed list and an invariant |
| [TodoMVC](/packages/cairn_examples/claims/201/) | cairn_examples^201–^225: the full TodoMVC spec |
| [Clock](/packages/cairn_examples/claims/406/) | cairn_examples^401–^409: time, timers and files |
| [Tray](/packages/cairn_examples/claims/450/) | cairn_examples^450–^462: a menu bar item, a submenu and an overlay panel |
| [Gallery](/packages/cairn_examples/claims/503/) | cairn_examples^501–^513: images and a grid that fits the window |
| [Pairs](/packages/pairs/claims/1/) | pairs^1–^32: a deal of the pack, two cards up at most, and every game can be won |
| [Yap](/packages/yap/claims/301/) | yap^301–^399: a menu bar menu, an overlay and the dictation machine |

The pages show the evidence the export holds: proofs and their axioms, assumptions, flow
witnesses, retired and moved ids. Fuzzing, conformance and screenshots need a build that runs
the app, and a claim lists them as not shown yet until CI publishes them. A version published
before the export existed shows its ledger alone.

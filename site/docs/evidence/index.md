---
title: The example apps' maps
nav: The maps
eyebrow: Evidence
lede: Every claim each example makes, with its evidence and screenshots, generated from the build.
---

Each map is built from an app's claims and whatever evidence the build had: the axiom audit,
fuzzing, conformance runs against the running app, and screenshots from the app's own frames.
Nothing on a map is written by hand. [The evidence ladder](/docs/reference/evidence/) explains what each
kind of evidence means.

| Map | What it covers |
|---|---|
| [Counter](/map/counter/) | ^1–^7: two moves, two flows, an assumption and a retired claim |
| [Basics](/map/basics/) | ^101–^109: a field, a keyed list and an invariant |
| [TodoMVC](/map/todo/) | ^201–^224: the full TodoMVC spec |
| [The trusted base](/map/trusted/) | the host's assumptions, each with the fuzz check that gathers its evidence |

The maps are snapshots: they show the evidence from the last time they were built, which is
printed on each. Clock, Tray and Yap don't have published maps yet.

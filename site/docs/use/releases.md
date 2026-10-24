---
title: Release notes and compatibility
nav: Release notes
eyebrow: Use
status: todo
lede: What changed in each version of Cairn, and what an app can rely on across versions.
---

Apps outside this repository depend on Cairn at a tag, `vX.Y.Z` (pre-releases `vX.Y.Z-rc.N`), in
both their lakefile and their `Package.swift`: one tag pins the Lean package, the Swift library
products and Cairn's claims. The first app to do so is Yap (issue #75), at `v0.1.0-rc.1`.

What a version promises: Cairn's `claims.lock` at the tag is its contract. Every `cairn^N` in it
keeps its meaning in later versions or is retired, never renumbered or reused. The host protocol's
versions are in the frame format. The Lean API has no stability promise before 1.0.

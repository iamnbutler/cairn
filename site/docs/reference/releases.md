---
title: Release notes and compatibility
nav: Release notes
eyebrow: Reference
lede: What changed in each version of Cairn, and what an app can rely on across versions.
---

An app depends on Cairn at a tag, `vX.Y.Z`, in both its lakefile and its `Package.swift`. One tag
pins the Lean package, the Swift library products and Cairn's claims. Release candidates are
tags too (`vX.Y.Z-rc.N`), which an app can pin while it tries a change, but only final versions
are published.

## What a version promises

- **Claims.** Cairn's `claims.lock` at the tag is its contract. Every `cairn^N` in it keeps its
  meaning in later versions, or is retired; it is never renumbered or reused.
- **The host protocol.** The frame format carries its own version.
- **The Lean API** has no stability promise before 1.0.
- **The toolchain.** An app uses the Lean toolchain in Cairn's `lean/lean-toolchain` at the tag
  (`v4.35.0` for every release so far), because Lake shares compiled modules only between
  identical toolchains.

## v0.1.2

24 October 2026, at commit `597dea8`.

- **Libraries and apps.** `cairn.toml` has a `kind`: `"lib"`, which other packages can depend
  on, or `"bin"`, an app, which nothing can. It defaults to `"lib"`, and Cairn is one.
  `cairn new --lib` or `--bin` picks it, and `cairn new` asks with neither. `cairn publish`
  sends it, and `/packages/` lists apps under their own tab.
- **No uploaded docs.** `cairn publish` no longer runs `cairn doc` or sends docs, and
  `--no-docs` is gone. HTML from a publisher would run as the registry's site, so a registry
  will build docs from the source instead, as docs.rs does.
- **Retiring a claim needs a major version.** `lake exe ledger check` and `update` compare
  `claims.lock` with the last release's, found from the highest final `v<version>` tag that
  isn't after `cairn.toml`'s version. A claim that release had active can be retired, or moved,
  only in a new major version, or a new minor one while at 0.x. See
  [`retire`](/docs/reference/claims/#retire).

No claim was retired or changed, and the Swift libraries are the same, so moving from v0.1.1 is
a change of tag in the lakefile and `Package.swift`. An app that uses `cairn new` or
`cairn publish` needs the `cairn` tool from this tag.

## v0.1.1

24 October 2026, at commit `ea72e75`.

- **`cairn doc` works in an app's own repository.** In v0.1.0 it read its stylesheet and icon
  from the package it was documenting rather than from its own checkout of Cairn, so it failed
  for every package but Cairn itself.
- **The `cairn` command** is in this release, in `tools/cairn`: `new`, `add`, `build`, `doc`,
  `publish` and `login`. See [the cairn tool](/docs/reference/cairn-tool/).

Nothing in the Lean package, the Swift libraries or `claims.lock` changed, so moving from v0.1.0
is a change of tag in the lakefile and `Package.swift`, and nothing else.

## v0.1.0

24 October 2026, at commit `13ddd6c`. The first release.

- **Cairn is a package.** An app in its own repository requires the Lean package from git with
  the tag and the `lean` subdirectory, and the Swift package at the same version. The root
  `Package.swift` has library products only (`CLean`, `CairnFrame`, `CairnRender`, `CairnHost`
  and `CairnCapture`). None of them use `unsafeFlags`, which SwiftPM refuses in a dependency, and
  none of them link Lean. Lean's C header is committed, so a checkout builds without a
  toolchain step.
- **One link step.** `bin/cairn-link` merges Lean's runtime, Cairn's Lean library and the app's
  own into one static library for the host, and refuses a result with two `cairn_app_init`s.
  An app runs it from its Lake checkout of Cairn, and Cairn's own build uses it too.
- **Claim ids are scoped by package.** Cairn's are `cairn^N`. An app sets its own scope in its
  lakefile, and its ids are then `yap^311` and so on. See
  [Scopes](/docs/reference/claims/#scopes).
- **Yap moved out** to its own repository, `yap-cairn`, the first app to depend on Cairn this
  way. Its Lean, proofs, fuzzers, Swift host and benches left with it. Cairn's `claims.lock`
  marks its 44 ids `moved:yap`, so they stay issued and can't come back.

At this tag Cairn's `claims.lock` lists 146 ids: 100 active, 2 retired and 44 moved to Yap.

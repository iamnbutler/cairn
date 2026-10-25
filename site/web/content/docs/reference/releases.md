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

- **Claims.** Cairn's `claims.lock` at the tag is its contract; [the id promise](#the-id-promise)
  below says exactly what that means.
- **The host protocol.** The frame format carries its own version.
- **The Lean API** has no stability promise before 1.0.
- **The toolchain.** An app uses the Lean toolchain in Cairn's `lean/lean-toolchain` at the tag
  (`v4.35.0` for every release so far), because Lake shares compiled modules only between
  identical toolchains.

## The id promise

A claim id is how everything else refers to a claim: an app's flows, its docs, an issue, a
review, another package. So an id is a promise about meaning, and the ledger (`lake exe ledger
check`, part of `make check`) enforces it on every change. Ids are scoped by package:
`cairn^212` and `yap^212` are different claims.

**What holds, from the release that issues an id onward:**

- **An id is issued once.** It is never renumbered, never reused for another claim, and never
  changes kind. `claims.lock` keeps one line per id ever issued and never removes one.
- **Its meaning doesn't change quietly.** The ledger hashes each claim's formal statement and the
  definitions it uses. A change to either, or to the title, is reported and has to be accepted
  with `lake exe ledger update --accept`, so it shows in review. Cairn's rule is that a new
  meaning gets a new id; acceptance is for a statement written differently that says the same.
- **It goes away only by retiring.** A retired id stays in the lock, with its kind, its title
  and the reason, and can't come back. Retiring a claim the last release had active needs a new
  major version, or a new minor version while at 0.x.
- **An id that leaves with an app stays issued.** It is marked `moved:<scope>` where it was, and
  lives on under the app's own scope.

**What can change in any release:**

- **How a claim is proved, and the code behind it.** Proofs, `apply`, and the names of bound
  variables aren't in the hash, so refactoring a handler doesn't touch its claim.
- **The prose.** `does` and `sees` can be reworded to say the same thing more clearly.
- **Its evidence.** What a claim reads as depends on the build that computed it. See
  [how much to trust a claim](/docs/reference/trust/).

## v0.2.1

25 October 2026.

- **Requests in flight.** At most `App.maxInFlight` (6) `http`, `upload` and `loadImage`
  requests are with the host at once; the rest queue in order. The new `cancelRequest` effect
  drops a queued request, or cancels a sent one, whose single answer then reaches no app.
  `Cairn.Runtime.InFlight` proves the cap is never exceeded, every queued request is eventually
  sent or cancelled, and a cancelled id never delivers. `Cairn.UI.Images` has `cancel`,
  `cancelAll` and `cancelWhere`. The frame format is version 6: `cancelRequest` is effect 7. The
  host's side is the trusted claim `cairn^1009`.
- **A grid that follows the window.** `Cairn.UI.Grid` lays out equal cards in as many columns of
  `minWidth` as fit the box's width, at least one, and shrinks them together when the rows would
  be too tall. It is proved for every size and card count: the cells stay inside the box, keep
  reading order and never overlap. The Gallery example uses it (`cairn^509`, `cairn^510`).
- **More of the `cairn` tool.** `cairn fuzz`, `claims`, `bench`, `size` and `conformance` run
  the per-app tools on any app package, as `cairn build` does. `test/fixture` is Cairn's own
  fixture app, with its own scope and ledger, and `make check` runs against it.
- **Claim pages.** `cairn publish` also sends the claims export (`cairn claims --ledger`) when the
  registry takes one, and the site renders every package's claims grouped by place, with a page
  per claim. The maps (`/map/<app>/`) redirect to them.

No claim was retired, moved or changed, so it is a patch release. Six claims are new:
`cairn^506`–`cairn^510` (Gallery) and `cairn^1009`. Moving from v0.2.0 is a change of tag in the
lakefile and `Package.swift`, unless an app builds frames by hand, which are now version 6.

## v0.2.0

24 October 2026, at commit `16b70b8`.

- **Images.** `Node.image` shows a picture in a fixed box whose size layout knows before any
  pixels arrive, and the `loadImage` effect asks the host for one, from a file or an `http`/`https`
  URL. The host decodes and paints; Lean never holds pixels. `Cairn.UI.Images` is the table an app
  keeps, and only the reply to a source's latest load counts. The frame format is version 5: an
  `image` draw and the `loadImage` request. Three trusted claims cover the host's side
  (`cairn^1006`–`cairn^1008`), and the Gallery example (`swift run CairnGallery`) shows six tiles
  with Reload and Fit. See [Effects](/docs/guide/effects/).
- **`import Cairn` links.** The `Cairn` module now imports exactly the `Cairn` library, what
  `bin/cairn-link` links, and `meta`-imports the claim commands, so an app can start with
  `public import Cairn`. The old umbrella that imported everything, proofs and tools included, is
  `CairnAll`; the ledger and the audit read it. An app that imports it doesn't link.
- **`cairn new --bin` makes a working app**: a window with a count and a Count button, its
  exports, a `Package.swift` and a host with `--selftest`. `cairn build` finds a Cairn required by
  path.
- **cairn-link links each dependency's `libs`** from its `cairn.toml`, rather than Cairn's library
  by name, so a library such as `cairn_json` is linked by naming its own. Cairn's `cairn.toml`
  says `libs = ["Cairn"]`.

- **`cairn^213` is retired and reissued as `cairn^225`**, with the same meaning: the TodoMVC
  example's rows are the todos the filter accepts. Its statement hash changed when `Style` gained
  its image field, and the registry keeps a published claim's statement, so the claim needed a new
  id. Retiring a released claim needs a new minor version while at 0.x, so this is 0.2.0 and not
  0.1.4. The tag `v0.1.4` exists, but the registry refused it for this reason and it was never
  published; use `v0.2.0`.

Eight claims are new besides `cairn^225`: `cairn^501`–`cairn^505` (Gallery) and
`cairn^1006`–`cairn^1008`. The shims from v0.1.3 are still there. Moving from v0.1.3 is a change
of tag in the lakefile and `Package.swift`, unless an app imports `Cairn` for the proofs or
tools, which are now in `CairnAll`, builds frames by hand, which are now version 5, or cites
`cairn^213`.

## v0.1.3

24 October 2026, at commit `aea142c`.

- **Three modules moved, with shims.** `Cairn.Frame.Boundary` is now `Cairn.Abi`,
  `Cairn.Runtime.Hit` is `Cairn.UI.Hit` and `Cairn.Text.Metrics` is `Cairn.Font`. The old names
  still work: each is a one-line module that imports the new one, until 0.2.0. `make lint` now
  fails on any cycle between directories in `lean/`, and there are none.
- **The `Cairn` library is only what apps link.** It holds the 31 modules `bin/cairn-link`
  archives into an app. Proofs, claims, fuzzing and tools are their own Lake libraries:
  `CairnProofs`, `CairnClaims`, `CairnFuzz` (was `Fuzz`), `CairnTools`, and `CairnTrusted` (was
  `TrustedClaims`). `libcairn_Cairn.a` goes from 3.67 to 2.78 MB and `libcairn_lean.a` from
  20.84 to 19.94 MB. The host now initializes Lean through `initialize_cairn_Cairn_Abi`.
- **One public registry.** The `cairn` tool uses `https://cairn.registry.nexthub.sh` by default
  (`CAIRN_REGISTRY` overrides it). `add`, `build` and `doc` need no login, and `cairn login` is
  needed only to publish. `cairn publish` publishes under `--owner`, or the token's own login.
- **Owners by name.** `cairn add <name>` finds a package's owner with
  `GET /api/v1/names/<name>`, not a search. `cairn publish` sends `swift`, whether the tag has a
  `Package.swift`, and a package page shows the `.package(url:)` line only when it does.

No claim was retired or changed. Moving from v0.1.2 is a change of tag in the lakefile and
`Package.swift`, unless an app names the `Fuzz` or `TrustedClaims` libraries, which are now
`CairnFuzz` and `CairnTrusted`. Yap moved with only its tag changed.

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

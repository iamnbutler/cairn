---
title: Shipping
nav: Shipping
eyebrow: The Cairn Book · Chapter 6
lede: Checking an app, putting it in a signed bundle, and publishing its map.
---

:::note Today
Everything here runs through the Cairn repository's Makefile, for apps that live in the
repository. The `cairn` tool that will do it for an app in its own repository is planned in
[issue #75](https://github.com/iamnbutler/cairn/issues/75); see [the cairn tool](/docs/use/cairn-tool/).
:::

## Check it

`make check` is what every change must pass. It lints for banned constructs, builds everything,
audits every theorem's axioms, replays every declaration through the kernel, checks the claim
ledger, runs the Swift tests and each app's self test, fuzzes every app briefly, and checks binary
sizes:

<!-- include Makefile#make-check -->

### The self test

Each app's executable has a `--selftest` mode: it runs the real host, with its threads and
accessibility mirror, but no window, and drives the app through its controls. Counter's checks
presence through accessibility, the way an assistive app would see it:

<!-- include host/Sources/CairnCounter/main.swift#counter-selftest -->

### Fuzzing and conformance

`make fuzz APP=<App>` generates random sequences of moves from the claims and checks every claim's
`post`, every invariant, and presence and pressability, after every step. `make conformance
APP=<App>` replays sequences against the running app through its debug socket and compares it
with the Lean model at every step. Conformance needs one small file per app, under
`tools/conformance/lean/Conformance/Apps/`.

<!-- include Makefile#make-fuzz -->

## Size

A Cairn app should be a few megabytes. The commands that declare claims need Lean's compiler at
build time, and linking the compiler into an app makes it about 100 MB, so apps only `meta import`
them. `make size` builds each app for release and fails past 5 MB:

<!-- include Makefile#make-size -->

## Bundle and sign

`make bundle APP=<App>` writes a `.app` bundle. Per-app `Info.plist` and entitlements go in
`host/Bundles/<App>/`:

<!-- include Makefile#make-bundle -->

Yap shows a release build signed with a stable identity. Signing with the same identity every
time matters: macOS grants permissions such as Accessibility and the microphone to the code
signature, so a differently signed build is a new app and has to be granted again. Its package's
`make yap` finds the first valid Apple Development identity with `security find-identity` and
passes it to Cairn's `tools/bundle/bundle.sh`, which an app outside this repository runs from its
Lake checkout of Cairn.

## Publish the map

The map is a set of pages generated from an app's claims and the build's evidence: one row per
claim, its proofs, fuzz and conformance results, and screenshots taken from the app's own frames.
Nothing on it is written by hand. See [the evidence ladder](/docs/use/evidence/).

<!-- include Makefile#make-map -->

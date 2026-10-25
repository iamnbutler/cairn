---
title: Shipping
nav: Shipping
eyebrow: Building an app · Chapter 6
lede: Checking an app, putting it in a signed bundle, and publishing it with its claim pages.
---

<bongo:note label="Today">
The checks and bundles here run through the Cairn repository's Makefile, for the apps
that live in it. An app in its own repository builds with `cairn build`, but checking and bundling
it from the `cairn` tool are still planned; Yap's repository has its own make targets
that call Cairn's tools. See [the cairn tool](/docs/reference/cairn-tool/).
</bongo:note>

## Check it

`make check` is what every change must pass. It lints for banned constructs, builds everything,
audits every theorem's axioms, replays every declaration through the kernel, checks the claim
ledger, runs the Swift tests and each app's self test, fuzzes every app briefly, and checks binary
sizes:

<bongo:include src="Makefile#make-check" />

### The self test

Each app's executable has a `--selftest` mode: it runs the real host, with its threads and
accessibility mirror, but no window, and drives the app through its controls. Counter's checks
presence through accessibility, the way an assistive app would see it:

<bongo:include src="host/Sources/CairnCounter/main.swift#counter-selftest" />

### Fuzzing and conformance

`make fuzz APP=<App>` generates random sequences of moves from the claims and checks every claim's
`post`, every invariant, and presence and pressability, after every step. `make conformance
APP=<App>` replays sequences against the running app through its debug socket and compares it
with the Lean model at every step. Conformance needs one small module per app,
`lean/Examples/<App>/Conformance.lean`. In an app's own repository, `cairn fuzz` and `cairn
conformance` do the same (see [the cairn tool](/docs/reference/cairn-tool/)).

<bongo:include src="Makefile#make-fuzz" />

## Size

A Cairn app should be a few megabytes. The commands that declare claims need Lean's compiler at
build time, and linking the compiler into an app makes it about 100 MB, so apps only `meta import`
them. `make size` builds each app for release and fails past 5 MB:

<bongo:include src="Makefile#make-size" />

## Bundle and sign

`make bundle APP=<App>` writes a `.app` bundle. Per-app `Info.plist` and entitlements go in
`host/Bundles/<App>/`:

<bongo:include src="Makefile#make-bundle" />

Yap shows a release build signed with a stable identity. Signing with the same identity every
time matters: macOS grants permissions such as Accessibility and the microphone to the code
signature, so a differently signed build is a new app and has to be granted again. Its package's
`make yap` finds the first valid Apple Development identity with `security find-identity` and
passes it to Cairn's `tools/bundle/bundle.sh`, which an app outside this repository runs from its
Lake checkout of Cairn.

## Publish it

`cairn publish` sends a tagged version to the registry with its claims export, and the site
renders its [claim pages](/docs/evidence/) from that: every claim, grouped by place, with its
proofs, a flow's steps and where it's defined. Nothing on them is written by hand. See
[the evidence ladder](/docs/reference/evidence/) and [the cairn tool](/docs/reference/cairn-tool/).

---
title: Shipping
nav: Shipping
eyebrow: Building an app · Chapter 6
lede: Checking an app, putting it in a signed bundle, and publishing it with its claim pages.
---

<bongo:note label="Today">
An app checks and bundles itself with [the cairn tool](/docs/reference/cairn-tool/), from anywhere
in its package. The lint, axiom audit and kernel replay that Cairn's `make check` runs have no
`cairn check` yet; an app's own Makefile calls Cairn's tools for them, as Yap's and the
[example apps'](/docs/examples/) do.
</bongo:note>

## Check it

`make check` is what every change to Cairn must pass. It lints for banned constructs, builds
everything, audits every theorem's axioms, replays every declaration through the kernel, checks
the claim ledger, runs the Swift tests, and runs the per-app checks on the fixture: its self test,
a short fuzz, its binary size and its own ledger.

<bongo:include src="Makefile#make-check" />

### The self test

An app's executable has a `--selftest` mode: it runs the real host, with its threads and
accessibility mirror, but no window, and drives the app through its controls. The fixture's
checks presence through accessibility, the way an assistive app would see it:

<bongo:include src="test/fixture/Sources/Fixture/main.swift#fixture-selftest" />

and waits for the timer Flash set to come back through the host's clock:

<bongo:include src="test/fixture/Sources/Fixture/main.swift#fixture-selftest-timer" />

### Fuzzing and conformance

`cairn fuzz` generates random sequences of moves from the claims and checks every claim's `post`,
every invariant, and presence and pressability, after every step. `cairn conformance` replays
sequences against the running app through its debug socket and compares it with the Lean model at
every step. Each needs a little of the package: a fuzz executable over `fuzz_targets%`, and a
generator module, `<App>.Conformance`. The fixture's lakefile declares both:

<bongo:include src="test/fixture/lean/lakefile.lean#fixture-lakefile-checks" />

Cairn's `make check` runs `cairn fuzz --iterations 200` on the fixture. Conformance opens the
app's window, so it isn't in `make check`.

## Size

A Cairn app should be a few megabytes. The commands that declare claims need Lean's compiler at
build time, and linking the compiler into an app makes it about 100 MB, so apps only `meta import`
them. `cairn size` builds the app for release, attributes its bytes, and fails past 5 MB:

<bongo:include src="Makefile#make-size" />

## Bundle and sign

`cairn bundle` writes a `.app` bundle, `build/apps/<Name>.app`, from a release build. The
package's `bundle/Info.plist` and `bundle/entitlements.plist` go in it when they exist. `--sign`
signs it with an identity; without it the bundle is signed ad hoc.

Yap shows a release build signed with a stable identity. Signing with the same identity every
time matters: macOS grants permissions such as Accessibility and the microphone to the code
signature, so a differently signed build is a new app and has to be granted again. Its package's
`make yap` finds the first valid Apple Development identity with `security find-identity` and
passes it to Cairn's bundle script, `tools/bundle/bundle.sh`, which `cairn bundle` runs.

## Publish it

`cairn publish` sends a tagged version to the registry with its claims export, and the site
renders its [claim pages](/docs/evidence/) from that: every claim, grouped by place, with its
proofs, a flow's steps and where it's defined. Nothing on them is written by hand. See
[the evidence ladder](/docs/reference/evidence/) and [the cairn tool](/docs/reference/cairn-tool/).

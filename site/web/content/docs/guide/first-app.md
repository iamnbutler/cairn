---
title: Your first app
nav: Your first app
eyebrow: Building an app · Chapter 1
lede: What a Cairn app is made of, how to run one, and how to start your own.
---

## The pieces

A Cairn app has two halves.

- **Lean** holds everything that has meaning: the app's state, the moves a person can make, the
  view, the claims and their proofs. All of it is pure functions: no `IO`, no floating point in
  anything a theorem talks about.
- **Swift** is the host. It owns the window, turns mouse and keyboard input into events, runs the
  effects Lean asks for (write a file, play a sound), mirrors the frame to accessibility, and
  paints with Metal. It has no application logic.

Between them, two byte buffers cross on every step: a batch of events going in, and a frame coming
out. The [host protocol](/docs/internals/host-protocol/) describes them.

To see one before installing anything, [try Counter in the browser](/try/counter/): every
frame there is one its Lean code drew, and every control shows its claim.

## What you need

- A Mac on macOS 27 with Xcode, for Swift 6 and the Metal toolchain.
- Lean 4 through elan. The repository pins the version in `lean/lean-toolchain`.
- bun, for the tools that build these docs.
- The Cairn repository: `git clone https://github.com/iamnbutler/cairn`.
- [The cairn tool](/docs/reference/cairn-tool/), built from the checkout:

<bongo:include src="docs/cli.md#cli-install" />

## Running one

The repository's own app is `test/fixture`, which Cairn's checks run on. It is laid out the way an
app in its own repository is, and built with the `cairn` tool; the only difference is that it
requires the checkout it is in, by path. `make fixture-build` builds Cairn's Lean, the `cairn`
tool, and then the fixture with `cairn build`:

<bongo:include src="Makefile#make-fixture" />

Then `cd test/fixture && swift run Fixture` opens it in a window. The first build in a fresh
checkout takes a while; later ones are incremental.

## The fixture, from the top

The fixture's state is a list of items, the id the next item gets, the New item field, and
whether the Flash note shows. Its controls are named by **control refs**: the claim id of the move
they perform, and a key (0 for a control there is one of; an item's checkbox uses the item's id).

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-state" />

The window is a **place**, a claim of its own, so moves can say where they appear:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-place" />

Then the moves. Each says in plain words what the person does (`does`) and sees (`sees`), and in
Lean what pressing it does (`apply`) and must achieve (`post`), with a proof (`sound`). Add:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-add-item" />

`add` is an ordinary function on the state:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-add" />

The app's behaviour is built from its moves and nothing else. `moves%` collects every move
declared in the namespace, and `receive` hears the timer Flash sets
([chapter 5](/docs/guide/effects/)):

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-machine" />

The view is a function from the state (and the UI state: hover, focus, window size) to a tree of
boxes and text. Each item's row is in the tree only while the item is in the list, and its
checkbox and delete button with it:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-view" />

Finally the app: the machine, one window showing the view, and every claim the app makes.

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-claims" />

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-app" />

## The host side

The Lean app is compiled to a static library that exports three C functions: start, step and
frame. A small module holds them:

<bongo:include src="test/fixture/lean/Fixture/Abi.lean#fixture-abi" />

The Swift executable names those functions, and hands them to the generic host. The module
initializer, `runtime_initialize_fixture_Fixture_Abi`, is declared in a small C target of the
app's own, `CFixture`:

<bongo:include src="test/fixture/Sources/Fixture/main.swift#fixture-leanapp" />

<bongo:include src="test/fixture/Sources/Fixture/main.swift#fixture-main" />

That is the whole of the app's Swift that isn't a test; the rest of its `main.swift` is
`--selftest`, `--bench` and `--close-test` ([chapter 6](/docs/guide/shipping/)). Everything else
(threads, input, text input, accessibility, painting) is the shared host, `CairnHost`.

The lakefile names the package, which is also the claim scope (the fixture's ids are
`fixture^N`), and the library `cairn build` links:

<bongo:include src="test/fixture/lean/lakefile.lean#fixture-lakefile" />

`Package.swift` builds the host and links that library from `.cairn/lib/`:

<bongo:include src="test/fixture/Package.swift#package-fixture" />

## An app in its own repository

An app lives in a repository of its own and depends on a tagged release of Cairn, the way
the [example apps](/docs/examples/) do. One tag pins both halves: the Lean package and the Swift
libraries. Start one with [the cairn tool](/docs/reference/cairn-tool/).

`cairn new hello --bin` makes `hello/` with a `cairn.toml`, an empty `claims.lock`, and a `lean/`
whose lakefile sets the claim scope to `hello`, so the app's ids are `hello^1`, `hello^2`, and so
on. The app is a working one, laid out like the fixture: a window with a count and a Count button
(a place, `hello^1`, and a move, `hello^2`), its exports in `lean/Hello/Abi.lean`, a
`Package.swift` and a host whose `--selftest` runs it headlessly. Its Lean files start with
`public import Cairn`, which brings in everything an app links, the claim commands included.
`cairn new hello --lib` makes a library instead, with no host.

`cairn add cairn` points the lakefile and `cairn.toml` at Cairn's latest release in the
registry and prints the line for `Package.swift`. An app can also require Cairn from git at a
tag:

<bongo:include src="docs/package.md#package-lakefile" />

Then depend on the same tag in `Package.swift`, and link the library that the build makes:

<bongo:include src="docs/package.md#package-manifest" />

`cairn build` builds the Lean, links it with Cairn's runtime into one static library in
`.cairn/lib/`, and builds the host. By hand, that is:

<bongo:include src="docs/package.md#package-build" />

The app's `main.swift` hands its three exports to the host, as the fixture's does above, and
`swift run Hello` opens it. `cairn fuzz`, `cairn bench`, `cairn size`, `cairn conformance` and
`cairn bundle` check and ship it from anywhere in the package ([chapter 6](/docs/guide/shipping/)).

## Claim ids

Ids are scoped per package, so an app numbers from ^1. The fixture's are `fixture^1` to
`fixture^9`, in `test/fixture/claims.lock`; the template's are `hello^1` and `hello^2`. Cairn's own
are `cairn^N`: the trusted base's assumptions, ^7, ^214, ^900 and up. Claims that move to another package
take their numbers with them: one that was `cairn^2` becomes `<scope>^2`.

Give a new claim an id the package hasn't used (look in `claims.lock`), then record it from the
package's `lean/` directory, and commit `claims.lock` with the claim. For the fixture:
`lake exe ledger update --scope fixture --root Checks --lock ../claims.lock`.

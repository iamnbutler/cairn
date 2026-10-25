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

## What you need

- A Mac on macOS 27 with Xcode, for Swift 6 and the Metal toolchain.
- Lean 4 through elan. The repository pins the version in `lean/lean-toolchain`.
- bun, for the tools that build maps and these docs.
- The Cairn repository. It isn't public yet.

`make build` builds the Lean libraries and the Swift host. `make demo DEMO=CairnCounter` opens
Counter in a window. The first build in a fresh checkout takes a while; later ones are
incremental.

## Counter, from the top

Counter's state is one number. Its two controls are named by **control refs**: the claim id of the
move they perform, and a key (0 here; a list item would use its own id).

<!-- include lean/Examples/Counter.lean#counter-state -->

The window is a **place**, a claim of its own, so moves can say where they appear:

<!-- include lean/Examples/Counter.lean#counter-place -->

Then the two moves. Increment is always available; Reset only when there is something to reset.
Each says in plain words what the person does (`does`) and sees (`sees`), and in Lean what
pressing it does (`apply`) and must achieve (`post`), with a proof (`sound`):

<!-- include lean/Examples/Counter.lean#counter-reset -->

The app's behaviour is built from its moves and nothing else. `moves%` collects every move
declared in the namespace:

<!-- include lean/Examples/Counter.lean#counter-machine -->

The view is a function from the state (and the UI state: hover, focus, window size) to a tree of
boxes and text. Reset's button is only in the tree when Reset is enabled:

<!-- include lean/Examples/Counter.lean#counter-view -->

Finally the app: the machine, one window showing the view, and every claim the app makes.

<!-- include lean/Examples/Counter.lean#counter-claims -->

<!-- include lean/Examples/Counter.lean#counter-app -->

## The host side

The Lean app is compiled to a static library that exports three C functions: start, step and
frame. A small module holds them:

<!-- include lean/Examples/Counter/Abi.lean#counter-abi -->

The Swift executable names those functions, and hands them to the generic host:

<!-- include host/Sources/CairnCounter/main.swift#counter-leanapp -->

<!-- include host/Sources/CairnCounter/main.swift#counter-main -->

That is the whole of the app's Swift that isn't a test. Everything else (threads, input, text
input, accessibility, painting) is the shared host, `CairnHost`.

## An app in its own repository

An app lives in a repository of its own and depends on a tagged release of Cairn, the way
[Yap](/docs/examples/yap/) does. One tag pins both halves: the Lean package and the Swift
libraries. Start one with [the cairn tool](/docs/reference/cairn-tool/).

`cairn new hello` makes `hello/` with a `cairn.toml`, an empty `claims.lock`, and a `lean/`
whose lakefile sets the claim scope to `hello`, so the app's ids are `hello^1`, `hello^2`, and so
on. It also writes a `Package.swift` for the host. `cairn new hello --lib` makes a library
instead, with no host.

`cairn add cairn` points the lakefile and `cairn.toml` at Cairn's latest release in the
registry and prints the line for `Package.swift`. An app can also require Cairn from git at a
tag, as Yap's lakefile does:

<!-- include docs/package.md#package-lakefile -->

Then depend on the same tag in `Package.swift`, and link the library that the build makes:

<!-- include docs/package.md#package-manifest -->

`cairn build` builds the Lean, links it with Cairn's runtime into one static library in
`.cairn/lib/`, and builds the host. By hand, that is:

<!-- include docs/package.md#package-build -->

The app's `main.swift` hands its three exports to the host, as Counter's does above. The app
declares those exports in a small C target of its own. Cairn's tools (the claim ledger, the
axiom audit, the bundle script) run from the app's Lake directory against its own modules.

## An app beside the examples

To work on Cairn itself, or to try something quickly without a package, add an app to the
Cairn repository beside the examples. It goes in five places:

1. **The Lean module**, `lean/Examples/<App>.lean`, written like Counter: a `module` that
   `public import`s the runtime and only `meta import`s the claim commands, so the commands stay
   out of the binary. Add an import of it to `lean/Examples.lean`, so the ledger and the axiom
   audit see its claims.
2. **Its exports**, `cairn_app_init`, `cairn_app_step` and `cairn_app_frame`, as in Counter's
   `Abi` module above.
3. **A library of its own** in `lean/lakefile.lean`. Each app gets one, because every app exports
   the same three symbols:

<!-- include lean/lakefile.lean#lakefile-counter -->

4. **The Makefile's app list**, which copies each app's library where the host links it:

<!-- include Makefile#make-apps -->

5. **A Swift executable** in `host/Package.swift`, linking that library, and its `main.swift` as
   above:

<!-- include host/Package.swift#package-counter -->

Then give your claims ids nobody has used (look in `claims.lock`), build with `make build`, record
the new ids with `cd lean && lake exe ledger update`, and commit `claims.lock` with the app. Run
it with `make demo DEMO=Cairn<App>`.

Pick ids in a range of their own: the examples use ^1–^7 (Counter), ^101–^109 (Basics), ^201–^224
(TodoMVC), ^401–^409 (Clock) and ^450 onwards (Tray); the trusted base uses ^900 and up, and
^301–^399 moved with Yap to its own package. Ids are scoped per package: these are all `cairn^N`.
An app in its own repository has its own scope (`yap^301`), so it can number from ^1.

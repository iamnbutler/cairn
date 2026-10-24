---
title: The cairn tool
nav: The cairn tool
eyebrow: Use
lede: The command line for Cairn packages. It starts a package, adds dependencies, builds, documents and publishes; checking, running and shipping are still the repository's make targets.
---

:::note What works today
`cairn` has six commands: `new`, `add`, `build`, `doc`, `publish` and `login`. They have unit
tests and have been run against a stand-in registry, but not against a deployed one, because
there is no public Cairn registry yet ([issue #97](https://github.com/iamnbutler/cairn/issues/97)).
Until there is, `cairn add` and `cairn publish` have nowhere to go, and an app requires Cairn
from git at a tag instead ([how](/docs/book/first-app/#an-app-in-its-own-repository)). Nothing
installs `cairn` yet; build it from a Cairn checkout.
:::

## Building it

`cairn` is its own Swift package in Cairn's `tools/cairn`, with no dependencies:

<!-- include docs/cli.md#cli-install -->

## Commands

| Command | What it does |
|---|---|
| `cairn new <name> [--lib]` | starts a package in a new directory: `cairn.toml`, an empty `claims.lock`, and `lean/` with a lakefile that sets the claim scope to `<name>` and requires Cairn. An app also gets `Package.swift` and `Sources/`; `--lib` makes a library without them. |
| `cairn add <name>[@<range>]` | adds a dependency from the registry to `cairn.toml` and the lakefile, replacing a `require … from git` of it. It prints the `Package.swift` line rather than editing Swift. With no range it uses `^` and the latest release. |
| `cairn build [--release]` | `lake cache get` (prebuilt Lean from the registry, when it has it), `lake build`, Cairn's `cairn-link` to merge the Lean into one static library in `.cairn/lib/`, then `swift build`. |
| `cairn doc [--private] [--open]` | the package's API docs, in `build/doc/<name>/`, the same pages as [Cairn's own](/docs/api/), with every claim on its module's page. |
| `cairn publish [--dry-run]` | publishes the commit at the tag `v<version>`, which must be HEAD with a clean tree: its source, its `claims.lock` and its prebuilt Lean. The registry refuses a version that drops, renumbers or redefines a claim id. It takes no docs from a publisher; they will be built from the source ([issue #94](https://github.com/iamnbutler/cairn/issues/94)). |
| `cairn login <url>` | checks a registry token, read from standard input, and saves it. `cairn credential get` hands it to git for that registry's host only, so SwiftPM can clone packages. |

`cairn.toml` names the package, its version and the Lean libraries to link. Its `name` has to
match the lakefile's package name and the claim scope, and `cairn build` and `cairn publish`
check that all three agree.

## Planned commands

These still run as make targets, from the root of the Cairn repository, for the apps that live
in it:

| Command | What it will do | Today |
|---|---|---|
| `cairn run` | open the app in a window | `make demo DEMO=Cairn<App>` |
| `cairn check` | everything a change must pass | `make check` |
| `cairn map` | build the app's map | `make map APP=<App>` |
| `cairn fuzz` | claim-driven fuzzing | `make fuzz APP=<App>` |
| `cairn conform` | replay the model against the running app | `make conformance APP=<App>` |
| `cairn bundle --sign` | a signed `.app` | `make bundle APP=<App> SIGN=<identity>`, or Cairn's `tools/bundle/bundle.sh` from an app's own repository |
| `cairn doctor` | check the toolchain | none |

## The make targets, today

Run them from the root of the Cairn repository. Each is shown as it is in the Makefile.

### Build and run

`make build` builds the Lean libraries and the Swift host.

<!-- include Makefile#make-demo -->

### Check

<!-- include Makefile#make-check -->

<!-- include Makefile#make-selftest -->

### Fuzz and conformance

<!-- include Makefile#make-fuzz -->

<!-- include Makefile#make-conformance -->

### Maps

<!-- include Makefile#make-map -->

### Ship

<!-- include Makefile#make-bundle -->

<!-- include Makefile#make-size -->

---
title: The cairn tool
nav: The cairn tool
eyebrow: Reference
lede: The command line for Cairn packages. It starts a package, adds dependencies, builds, checks, bundles, documents and publishes it.
---

<bongo:note label="What works today">
`cairn` starts, builds, documents and publishes a package (`new`, `add`, `build`, `doc`,
`publish`, `login`), and checks and bundles an app (`fuzz`, `claims`, `bench`, `size`,
`conformance`, `bundle`), with unit tests.
Cairn has one public registry, `https://cairn.registry.nexthub.sh`: anyone can read it, and
publishing takes a token. It holds no prebuilt Lean yet, so the first `cairn build` compiles
Cairn. Nothing installs `cairn` yet; build it from a Cairn checkout.
</bongo:note>

## Building it

`cairn` is its own Swift package in Cairn's `tools/cairn`, with no dependencies:

<bongo:include src="docs/cli.md#cli-install" />

## Commands

| Command | What it does |
|---|---|
| `cairn new <name> [--lib\|--bin]` | starts a package in a new directory: `cairn.toml` with its `kind`, an empty `claims.lock`, and `lean/` with a lakefile that sets the claim scope to `<name>` and requires Cairn. Its Lean module does `public import Cairn`. An app (`--bin`) is a working one: a window with a count and a Count button (place `^1`, move `^2`), its exports in `lean/<Module>/Abi.lean`, `Package.swift`, a C target declaring its initializer, and a host with `--selftest`; a library (`--lib`) gets none of the Swift. With neither flag it asks which. |
| `cairn add [<owner>/]<name>[@<range>]` | adds a dependency from the registry to `cairn.toml` and the lakefile, replacing a `require … from git` of it. It prints the `Package.swift` line rather than editing Swift. With no range it uses `^` and the latest release, and with no owner it looks up the name's owner. It needs no login. |
| `cairn build [--release]` | `lake cache get` (prebuilt Lean from the registry, when it has it), `lake build`, Cairn's `cairn-link` to merge the Lean into one static library in `.cairn/lib/`, then `swift build`. |
| `cairn doc [--private] [--open]` | the package's API docs, in `build/doc/<name>/`, the same pages as [Cairn's own](/docs/api/), with every claim on its module's page. |
| `cairn publish [--owner <login>] [--dry-run]` | publishes the commit at the tag `v<version>`, which must be HEAD with a clean tree: its source, its `claims.lock` and its prebuilt Lean. It publishes under the login your token belongs to, or under an Org you can write to with `--owner`; a name's first publish makes that account its owner. The registry refuses a version that drops, renumbers or redefines a claim id. It takes no docs from a publisher; they will be built from the source ([issue #94](https://github.com/iamnbutler/cairn/issues/94)). |
| `cairn login` | checks a nexthub token with `package:write`, read from standard input, and saves it. Only `cairn publish` needs it: anyone reads the registry, and Lake, git and SwiftPM fetch from it with no credential. |

`cairn` uses the public registry, `https://cairn.registry.nexthub.sh`. `CAIRN_REGISTRY` points it
at another, such as a local nextpm, and `CAIRN_TOKEN` gives a token without `cairn login`, as CI
needs.

`cairn.toml` names the package, its version and the Lean libraries to link. Its `name` has to
match the lakefile's package name and the claim scope, and `cairn build` and `cairn publish`
check that all three agree.

## Checks

Cairn's per-app tools run on any app package, from anywhere in it; Cairn's own `make check` runs
them on its test app, test/fixture. Each writes under the package's `build/`.

| Command | What it does |
|---|---|
| `cairn fuzz [<target>…] [--iterations N] [--seed S] [--steps K]` | claim-driven fuzzing into `build/fuzz/`. The package declares a `lean_exe fuzz` whose `main` runs `Cairn.Fuzz.main fuzz_targets%` |
| `cairn claims [<module>…] [--out FILE]` | every claim of the package as JSON |
| `cairn bench [--product P]` | a release build, then the app's own `--bench` |
| `cairn size [--product P]… [--limit BYTES]` | the stripped release binary, attributed, and a guard at 5 MB |
| `cairn conformance [--module M] [--n N]` | the Lean model replayed against the running app through its debug socket. The package has a generator module, `<App>.Conformance` |
| `cairn bundle [--sign ID] [--name N]` | a release build wrapped in `build/apps/<N>.app`, with the package's `bundle/Info.plist` and `bundle/entitlements.plist` when it has them; signed with `--sign`, else ad hoc |

A package of several apps, like the [example apps](/docs/examples/), picks one with `--app <App>`
for `build`, `bench`, `size`, `conformance` and `bundle`. Running an app is still SwiftPM's:
`swift run <Product>` after `cairn build`.

## Cairn's own checks

`cairn run`, `cairn check` and `cairn doctor` are planned. Until `cairn check` lands, the lint,
axiom audit and kernel replay run from the Cairn repository's Makefile, and so do Cairn's own
checks. Run them from the root of the repository; each is shown as it is in the Makefile.

<bongo:include src="Makefile#make-check" />

The per-app checks run on test/fixture with the commands above:

<bongo:include src="Makefile#make-fixture" />

<bongo:include src="Makefile#make-selftest" />

<bongo:include src="Makefile#make-size" />

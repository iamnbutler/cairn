# Cairn as a package

An app built on Cairn lives in its own repository and depends on a tagged Cairn release, the way
any Lean or Swift package depends on another: no paths into the cairn tree. Yap was the first app
moved out ([iamnbutler/yap-cairn](https://github.com/iamnbutler/yap-cairn), #75). This page is
what that took and what a new app needs.

## What a version is

A version is a git tag `vX.Y.Z` on this repository (pre-releases `vX.Y.Z-rc.N`). One tag pins
both halves:

- **Lean**: the Lake package in `lean/`, required with a subdirectory.
- **Swift**: the root `Package.swift`, with the library products `CLean`, `CairnFrame`,
  `CairnRender`, `CairnHost` and `CairnCapture`. None of them use `unsafeFlags`, which SwiftPM
  refuses in a versioned dependency, and none of them link Lean. Lean's header is committed in
  `host/Sources/CLean/vendor/`, so a checkout builds without a toolchain step.
- **Claims**: `claims.lock` at the tag is Cairn's contract: every `cairn^N` it lists keeps its
  meaning in later versions, or is retired (docs/claims.md).

The toolchain is the one in `lean/lean-toolchain`. An app uses the same one: Lake shares `.olean`
files only between identical toolchains, and lean.h matches it.

## An app's files

```
lean/lakefile.lean     package <name>, require cairn, the app's libraries
lean/lean-toolchain    Cairn's toolchain at the tag
lean/<App>/…           the app (Lean modules)
Package.swift          at the repository root (SwiftPM resolves git dependencies only there)
host/Sources/…         the Swift executable, the app's C exports, its painters
claims.lock            the app's own claim ids
cairn.toml             name, version, libs and paths for the `cairn` CLI (docs/cli.md)
```

`cairn.toml`'s `name` has to match the lakefile's package name and its claim
scope. Cairn's own `cairn.toml` sits at this repository's root.

The lakefile:

```lean
package yap where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩,
    ⟨`weak.cairn.claims.scope, "yap"⟩]

require cairn from git "https://github.com/iamnbutler/cairn" @ "v0.1.0" / "lean"

@[default_target]
lean_lib Yap where
  roots := #[`Yap.Abi, `Yap]
  defaultFacets := #[LeanLib.staticFacet]
```

`cairn.claims.scope` names the package the claims belong to; use the package name. It needs the
`weak.` prefix because Lake passes it to every module, and only the modules that use the claim
commands know the option.

The manifest:

```swift
let lib = Context.packageDirectory + "/.cairn/lib"
// dependencies:
.package(url: "https://github.com/iamnbutler/cairn", exact: "0.1.0"),
// the app's executable:
.executableTarget(name: "CairnYap",
    dependencies: ["CYap", .product(name: "CairnHost", package: "cairn"), /* … */],
    linkerSettings: [.unsafeFlags(["-L" + lib, "-lyap"])]),
```

`unsafeFlags` are fine here, because the app is the root package. The app declares its own Lean
exports in a small C target (`runtime_initialize_<package>_<Module>` and anything `@[export]`ed);
Cairn's CLean declares the runtime and the v1 app ABI (`cairn_app_init`, `step`, `frame`).

## Building

```
cd lean && lake build
cd lean && .lake/packages/cairn/bin/cairn-link --lib Yap --out ../.cairn/lib/libyap.a
swift build
```

`bin/cairn-link` merges into one static library: Lean's runtime (`libInit`, `libleanrt`, `libuv`,
`libgmp`), Cairn's Lean library, `claims_meta.o` (weak stand-ins for the claim commands'
initializers, docs/claims.md "Linking") and the app's libraries. It refuses a library with two
`cairn_app_init`s. Cairn's own Makefile builds `build/lib/libcairn_lean.a` with it too. The
`cairn` CLI's `build` runs these three steps (lake, cairn-link, swift).

Cairn's tools run from the app's Lake directory, against the app's modules:

| | |
|---|---|
| `lake exe ledger check --scope yap --root Checks --lock ../claims.lock` | the app's ids |
| `lake exe audit Checks` | axioms of every theorem in the app and the Cairn it uses |
| `lake check --inadvisably-no-sandbox` | kernel replay |
| `lake exe claims Yap` | claims as JSON, with `"scope"` and `"qualified"` (`yap^301`) |
| `.lake/packages/cairn/tools/bundle/bundle.sh` | the app bundle, from `host/Bundles/<App>/` |

A consumer can't add executables to Cairn's lakefile, so a fuzzer over the app's moves is the
app's own `lean_exe` (`fuzz_targets%` from `Cairn.Fuzz.Collect` works in any package).

## Claims across packages

Ids are scoped by package: Cairn's assumption about the microphone is `cairn^1005`, Yap's own
is `yap^348`. Inside a package a bare `^N` is its own scope. Each package keeps one
`claims.lock` for its own scope, written by `ledger update --scope <name>`. When claims moved
with an app (Yap's 301–351 and 399), the lock they left marks them `moved:yap`
(`ledger move yap <id>…`), so the ids stay issued here and can't return. See docs/claims.md,
"Scopes".

## Host capabilities and painters

Effects are Cairn's: `Cairn.Request`, `Cairn.Sub` and the Swift `World` that runs them. An app
can't add its own effect kind yet. Every capability Yap uses (record, globalKey, typeText,
upload, watchFile, …) is upstream, with an `assume` claim in `Cairn.Fuzz.Trusted.Claims` and a
fuzz suite. An app that needs a new capability adds it here, upstream, and an app's own
assumptions about Cairn's effects (Yap's `^348` about `cairn^1005`) are claims in the app's
scope. Whether apps should be able to declare their own effects is an open question (the
follow-up issue on host capability extension points).

Painters are app code. A `paint` draw names a painter, and the app registers it before its first
frame with `Painters.register(name, Painter(...))` (CairnRender). Yap's tape painter lives in
the Yap repository. A copy of it stays here as the fixture for `cairn^1004`'s fuzz suite.

# The `cairn` command

`cairn` builds, documents and publishes Cairn packages. It's a thin wrapper: Lake builds the
Lean, `bin/cairn-link` (docs/package.md) links it, SwiftPM builds the host, `tools/doc` writes
the docs, and a Cairn package registry stores what you publish. That registry is nextpm's
`cairn` kind (nextpm `docs/adr/0005-cairn-kind.md`). It is its own SwiftPM package in
`tools/cairn`, with no dependencies:

```
cd tools/cairn && swift build -c release   # .build/release/cairn
cd tools/cairn && swift test
```

Status: started. `new`, `add`, `build`, `doc`, `publish`, `login` and `credential` work, with
unit tests, and `add` and `publish --dry-run` have been run against a stand-in registry. Not
yet: a run against a deployed registry, `cairn run`, `check`, `map`, `fuzz` and the rest of the
planned commands in site/docs/use/cairn-tool.md, and installing it (a release binary or
`mint`/Homebrew).

## A package

```
cairn.toml        name, version, the Lean libraries to link, dependencies
claims.lock       every claim id the package has issued
lean/             the Lake package (lakefile, lean-toolchain, modules)
Package.swift     the Swift host (an app), linking .cairn/lib/lib<name>.a
```

### cairn.toml

```toml
[package]
name = "yap"                 # the Lake package's name and the claim scope: yap^301
version = "0.1.0"            # strict semver; a pre-release like 0.1.0-rc.1 is fine
description = "Dictation for the Mac"
license = "MIT"
lean = "lean"                # the Lake package's directory (default "lean")
libs = ["Yap"]               # the Lean libraries cairn-link merges into the app's library
swift = "."                  # where Package.swift is (default ".")
claims = "claims.lock"       # (default)

[dependencies]
cairn = "^0.1.0"
```

Unknown tables and keys are errors. Three names must agree, and `cairn build` and
`cairn publish` check that they do: cairn.toml's `name`, the lakefile's package name, and the
`cairn.claims.scope` option when the lakefile sets it.

## Commands

| Command | What it does |
|---|---|
| `cairn new <name> [--lib]` | writes `cairn.toml`, `claims.lock`, `lean/` (a lakefile.lean that sets the claim scope and requires Cairn), and for an app `Package.swift` and `Sources/` |
| `cairn add <name>[@<range>]` | adds the dependency to `cairn.toml` and puts `require "<owner>" / "<name>" @ "<range>"` (or a `[[require]]` with `scope` and `version`) in the lakefile, replacing a git require of it. It prints the `Package.swift` line instead of editing Swift. With no range, it uses `^` and the latest release |
| `cairn build [--release]` | `lake cache get`, `lake build`, `cairn-link --lib <libs…> --out .cairn/lib/lib<name>.a`, `swift build` |
| `cairn doc [--private] [--open]` | `lake exe doc --check` and `lake exe claims` on the package's libs, then `tools/doc/cairn-doc.ts` into `build/doc/<name>/`, with each dependency's modules linked to `/docs/<dep>/<version>/` |
| `cairn publish [--no-docs] [--dry-run]` | publishes the commit at tag `v<version>`, which must be HEAD with a clean tree. See below |
| `cairn login <url>` | checks a token (read from stdin) against the registry and saves it to `~/.config/cairn/credentials`, mode 0600 |
| `cairn credential get` | a git credential helper that gives the token to git for the registry's host only, so SwiftPM can clone packages |

`CAIRN_REGISTRY` and `CAIRN_TOKEN` override the saved login, as CI needs.

### One build entry point

`cairn build` runs the same three steps as Cairn's own build: lake, `bin/cairn-link`, swift.
`cairn-link` is the one place that knows how to link Lean into the host. Cairn's Makefile
uses it too (agreed with #75). `cairn build` adds only the cache step and the name check.
`cairn-link` comes from the Cairn checkout that Lake fetched (`lean/.lake/packages/cairn/bin/`),
or from the repository root when the package is Cairn itself.

### Lake and the registry

Lake reads the registry as if it were Reservoir. `cairn` sets
`RESERVOIR_API_URL=https://cairn:<token>@<registry>/api/v1`, because Lake sends no credentials
of its own, and the userinfo becomes Basic auth. It also sets `LAKE_ARTIFACT_CACHE=true`.
`lake cache get` then downloads prebuilt Lean for every dependency at its resolved commit. A
miss isn't an error; Lake builds locally.

### Publishing

1. Check that the names agree, that the tag `v<version>` is HEAD, and that the tree is clean.
2. Ask the registry for the versions it has, and refuse a version it already holds.
3. `git pack-objects --revs` from the tag's commit, excluding every published commit this clone
   has. The registry serves all of a package's packs over git's dumb HTTP protocol, so a clone
   gets the whole history.
4. `cairn doc`, then tar and gzip `dist/`, `doc.json` and `claims.json`, unless `--no-docs`.
5. `PUT /api/v1/packages/<owner>/<name>/versions/<version>`. The body is five sections, each a
   little-endian u32 length and its bytes: metadata JSON, pack, pack index, `claims.lock`, docs.
   The registry checks that the pack holds the commit, that the ledger keeps every earlier
   version's ids, and that the docs paths are safe.
6. `lake build -o outputs.jsonl`, then upload each artifact the map names
   (`PUT …/artifacts/<hash>.art`) and the map itself
   (`PUT …/build-outputs?rev=&platform=&toolchain=`). Lake's `lake cache put` only speaks S3.

## Open questions

- Prebuilt Lean is per platform (`arm64-apple-darwin24.6.0`), and the publisher uploads its own.
  CI that publishes for each macOS version, or trusted publishing from CI, would cover the rest.
- `cairn new` writes placeholder registry lines (`"owner"`, `CAIRN_GIT_URL`) until `cairn add
  cairn` fills them in. It could fill them in itself when a login exists.
- Whether `cairn` should edit `Package.swift`. Today it prints the line.

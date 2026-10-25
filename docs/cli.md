# The `cairn` command

`cairn` builds, documents and publishes Cairn packages. It's a thin wrapper: Lake builds the
Lean, `bin/cairn-link` (docs/package.md) links it, SwiftPM builds the host, `tools/doc` writes
the docs, and the Cairn package registry stores what you publish. There is one public registry,
as crates.io is for Rust: `https://cairn.registry.nexthub.sh`, served by nextpm's `cairn` kind
(nextpm `docs/adr/0005-cairn-kind.md`). Anyone reads it with no login; only publishing needs a
token. `cairn` is its own SwiftPM package in `tools/cairn`, with no dependencies:

<!-- region: cli-install -->
```
cd tools/cairn && swift build -c release   # .build/release/cairn
cd tools/cairn && swift test
```
<!-- endregion: cli-install -->

Status: started. `new`, `add`, `build`, `doc`, `publish` and `login` work, with unit tests,
against the public registry (Cairn 0.2.0 is published there), and so do the checks below
(`fuzz`, `claims`, `bench`, `size`, `conformance`), which Cairn's own `make check` runs on
test/fixture. Not yet: `cairn run`, `check`, `map` and the rest of the planned commands in
site/web/content/docs/reference/cairn-tool.md, and installing it (a release binary or
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
kind = "bin"                 # "lib" or "bin" (default "lib"); the site calls a bin an app
description = "Dictation for the Mac"
license = "MIT"
lean = "lean"                # the Lake package's directory (default "lean")
libs = ["Yap"]               # the Lean libraries cairn-link merges into the app's library,
                             # and into every app that depends on this package
swift = "."                  # where Package.swift is (default ".")
claims = "claims.lock"       # (default)

[dependencies]
cairn = "^0.1.0"
```

`kind` follows Cargo: a `lib` is a library that other packages depend on, and a `bin` is an
app, which nothing can depend on (the registry refuses a version that does). Cairn is a lib and
Yap is a bin. The site's /packages has a Libraries tab and an Apps tab. A package may later hold
both, as a crate can. `cairn publish` sends the kind with the metadata.

Unknown tables and keys are errors. Three names must agree, and `cairn build` and
`cairn publish` check that they do: cairn.toml's `name`, the lakefile's package name, and the
`cairn.claims.scope` option when the lakefile sets it.

## Commands

| Command | What it does |
|---|---|
| `cairn new <name> [--lib\|--bin]` | writes `cairn.toml` with its `kind`, `claims.lock`, `lean/` (a lakefile.lean that sets the claim scope and requires Cairn, and a `module` that does `public import Cairn`), and for an app (`bin`) a working one: a window with a count and a Count button (a place and a move), its exports (`lean/<Module>/Abi.lean`), `Package.swift`, a C target declaring its initializer and a host with `--selftest`. With neither flag it asks which. `make new-check` (in `make check`) builds a new app against the checkout and runs its selftest and ledger |
| `cairn add [<owner>/]<name>[@<range>]` | adds the dependency to `cairn.toml` and puts `require "<owner>" / "<name>" @ "<range>"` (or a `[[require]]` with `scope` and `version`) in the lakefile, replacing a git require of it. It prints the `Package.swift` line instead of editing Swift. With no range, it uses `^` and the latest release. With no owner, it asks the registry for the name's owner (`GET /api/v1/names/<name>`; a name has one owner). It needs no login |
| `cairn build [--release]` | `lake cache get`, `lake build`, `cairn-link --lib <libs…> --out .cairn/lib/lib<name>.a` for an app (cairn-link adds each dependency's `libs`; it comes from the Cairn checkout `lean/lake-manifest.json` names, a fetched one or a `require cairn from "<path>"`), `swift build` |
| `cairn doc [--private] [--open]` | `lake exe doc --check` and `lake exe claims` on the package's libs, then `tools/doc/cairn-doc.ts` into `build/doc/<name>/`, with each dependency's modules linked to `/docs/<dep>/<version>/` |
| `cairn publish [--owner <login>] [--dry-run]` | publishes the commit at tag `v<version>`, which must be HEAD with a clean tree, under `--owner` or else the login the token belongs to. It sends no docs. See below |
| `cairn login` | reads a nexthub token with `package:write` from stdin, checks it with the registry (`GET /-/whoami`), and saves it with the registry's URL to `~/.config/cairn/credentials`, mode 0600. Only `cairn publish` uses it |

`CAIRN_REGISTRY` overrides the registry, for a local nextpm
(`http://cairn.registry.nexthub.localhost:9876`) or a stand-in. A saved token is sent only to the
registry it was saved for. `CAIRN_TOKEN` overrides the saved token, as CI needs.

### Owners

A package's name is unique in the registry, and its first publish fixes its owner: an account's
own login, or an Org the account can write to. Lake asks for `<owner>/<name>`, and git URLs
carry the owner too, so `cairn add` writes the owner into the lakefile.

`cairn publish` publishes under the login the token belongs to, which it asks the registry for
(`GET /-/whoami`; an Org token answers the Org). `--owner <org>` publishes under an Org
instead. The registry refuses (403) a name that another owner holds, and a token that can't
write to the owner.

### One build entry point

`cairn build` runs the same three steps as Cairn's own build: lake, `bin/cairn-link`, swift.
`cairn-link` is the one place that knows how to link Lean into the host. Cairn's Makefile
uses it too (agreed with #75). `cairn build` adds only the cache step and the name check.
`cairn-link` comes from the Cairn checkout that Lake fetched (`lean/.lake/packages/cairn/bin/`).
It links each dependency's `libs` from that dependency's cairn.toml, and the app's own `libs` from
`--lib` (docs/package.md, "Which libraries"). A lib, and an app with no `libs`, skips the link
step: an app links a lib's `libs`, and Cairn's `make lean` writes its own library.

### Checks

The per-app tools that Cairn's Makefile used to run as `make <tool> APP=<App>` on its examples,
run on any app package, from anywhere in it. Each builds what it needs as `cairn build` does,
takes Cairn's scripts from the Cairn checkout Lake uses (as `cairn doc` does), and writes under
the package's `build/`. Cairn's `make check` runs them on test/fixture, its own app, which is a
package of its own that requires the checkout by path.

| Command | What it does |
|---|---|
| `cairn fuzz [<target>…] [--iterations N] [--seed S] [--steps K] [--out DIR] [-v]` | `lake build fuzz`, then the fuzzer (docs/fuzz.md) on every machine `--list` names, or the ones given, into `build/fuzz/<target>.json`. The package declares the executable: `lean_exe fuzz` whose root imports the app, `Cairn.Fuzz.Collect` and `Cairn.Fuzz.Main` and defines `main` over `fuzz_targets%` (test/fixture/lean/FuzzMain.lean) |
| `cairn claims [<module>…] [--out FILE]` | `lake exe claims` on the package's `libs`, or the modules given: every claim as JSON, on stdout or into the file |
| `cairn bench [--product P]` | a release build, then the app's own `<product> --bench` with `LEAN_ABORT_ON_NONLINEAR=1`. The host decides what it measures |
| `cairn size [--product P]… [--limit BYTES]` | a release build of each executable with a link map, stripped into `build/size/` and attributed by Cairn's `tools/size/size.ts` (Lean runtime, Cairn, the app's `libs`, Swift host, shaders); fails over the limit, 5,000,000 bytes by default (bench/size.md) |
| `cairn conformance [--module M] [--product P] [--n N] [--length L] [--seed S]` | the model replayed on the running app (docs/conformance.md): links the generator from the module `M`, by default `<App>.Conformance` with `<App>` the first of `libs`, with the app's merged library and the host's Core Text metrics, then runs Cairn's driver. Writes `build/conformance/<App>.json` and `build/conformance/<App>/report.md`. The app's window opens while it runs |

`--product` defaults to the only executable product of the package's `Package.swift`.
`cairn doc` (above) is the sixth: it already took a package.

### Versions and tags

Only final versions are published. A release candidate such as `v0.1.0-rc.1` is a git tag that
consumers pin directly (`@ "v0.1.0-rc.1"` in the lakefile, `exact:` in SwiftPM), and
`cairn.toml` keeps the version it is heading for. `cairn publish` needs the tag `v<version>` on
HEAD, so it publishes `v0.1.0` and not the candidates before it.

### Lake and the registry

Lake reads the registry as if it were Reservoir. `cairn` sets
`RESERVOIR_API_URL=https://cairn.registry.nexthub.sh/api/v1`, with no credential: Lake, git and
the build cache read the registry as anyone can. The registry passes a package it doesn't hold
to Lean's Reservoir, so one index answers Cairn packages and public Lean ones. `cairn` also
sets `LAKE_ARTIFACT_CACHE=true`. `lake cache get` then downloads prebuilt Lean for every
dependency at its resolved commit. A miss isn't an error; Lake builds locally. SwiftPM clones
`https://cairn.registry.nexthub.sh/git/<owner>/<name>.git` with no credential.

### Publishing

1. Check that the names agree, that the tag `v<version>` is HEAD, and that the tree is clean.
2. Find the owner (`--owner`, else `GET /-/whoami` with the token). Ask the registry for the
   versions it has, and refuse a version it already holds.
3. `git pack-objects --revs` from the tag's commit, excluding every published commit this clone
   has. The registry serves all of a package's packs over git's dumb HTTP protocol, so a clone
   gets the whole history.
4. `PUT /api/v1/packages/<owner>/<name>/versions/<version>` with `Authorization: Bearer
   <token>`, as every write below. The body is five sections, each a
   little-endian u32 length and its bytes: metadata JSON, pack, pack index, `claims.lock`, and
   docs, which is always empty. The metadata's `swift` says whether the tag has a
   `Package.swift` in cairn.toml's `swift` directory; the site prints a SwiftPM line only for a
   version that does. The registry checks that the pack holds the commit and that the
   ledger keeps every earlier version's ids, and answers 400 to a non-empty docs section.
5. `lake build -o outputs.jsonl`, then upload each artifact the map names
   (`PUT …/artifacts/<hash>.art`) and the map itself
   (`PUT …/build-outputs?rev=&platform=&toolchain=`). Lake's `lake cache put` only speaks S3.

### Docs aren't uploaded

A registry never accepts or serves docs a publisher uploads. Docs are HTML, and HTML served
from an upload runs as the serving origin. So `cairn publish`
doesn't run `cairn doc`, nextpm refuses a publish whose docs section isn't empty
(githubnext/nextpm#23), and it has no docs route. The registry will build each version's docs
from its published source with a builder it runs, as docs.rs does for crates. Until then the
site's `/docs/<name>/<version>/` is a placeholder that says so, and `cairn doc` is for local
docs only.

## Open questions

- Prebuilt Lean is per platform (`arm64-apple-darwin24.6.0`), and the publisher uploads its own.
  CI that publishes for each macOS version, or trusted publishing from CI, would cover the rest.
- `cairn new` writes placeholder registry lines (`"owner"`, `CAIRN_GIT_URL`) until `cairn add
  cairn` fills them in. It could fill them in itself, since reading the registry needs no login.
- Whether `cairn` should edit `Package.swift`. Today it prints the line.

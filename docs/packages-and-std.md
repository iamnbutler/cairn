# Packages and the standard library

How Cairn is cut into packages, and what its standard library is. A design: steps 1 and 2 of
the migration (§5) are done, nothing after them is. Measured on `main` at c6176ea (Cairn 0.1.2) and Yap
at 4d69f7f.

## Recommendation

**Cairn stays one registry package, `cairn`, and that package is the standard library.** It keeps
one Lake package, one SwiftPM package, one tag and one claim scope, so every `cairn^N` keeps its
meaning. Inside it, the Lean side is cut into Lake *libraries* by what they are for (linked into
apps, proofs, compile-time commands, trusted claims, fuzzing, tools), and three module moves
remove the directory-level cycles so the layering can be checked. New packages start only where
code doesn't touch the frame format, the ABI or the host: pure-Lean helpers (`cairn_batteries`)
and, once #84 lands, host capabilities an app declares (`cairn_<capability>`). Each of those is
its own repository with its own scope and `claims.lock`.

```
            cairn  (lib: std = core runtime + claim language + host + tools; scope cairn)
           ↗    ↖
cairn_batteries    cairn_<capability>   (later; own repos, own scopes)
           ↖    ↗
         an app (bin), e.g. yap
```

## 1. The graph

Lean refuses import cycles between modules, so the module graph is acyclic by construction. The
cycles are between *directories*. Computed from every `import` in `lean/` (strongly connected
components of the directory graph), there are two components, closed by these edges:

| Cycle | Edges that close it |
|---|---|
| Frame → Runtime → Frame | `Frame.Boundary → Runtime.Abi`; `Runtime.Abi → Frame, Frame.Menu`; `Runtime.Tests → Frame.Boundary` |
| Runtime → Layout → Runtime | `Runtime.Step → Layout.Core`; `Layout.Bridge → Runtime.Hit` |
| Text → UI → Text | `UI.Node → Text.Metrics`; `Text.Wrap, Text.Field → UI.Node` |

(Frame, Layout and Runtime form one component; Frame also reaches Layout through
`Frame.Build → Layout.Facts`.) None of these is a real cycle: each is one module filed in the
"wrong" directory. Three moves, plus pointing the `Cairn.Runtime` umbrella away from the tests that
move, leave the directory graph acyclic (rechecked the same way):

| Move | Why it's in the wrong place |
|---|---|
| `Frame.Boundary`, with `Frame.BoundaryTests` and `Runtime.Tests` → `Cairn.Abi` (+ `Cairn.Abi.Tests`) | It is the top of the app ABI (frame build, events, `Runtime.Abi`, `Text.Host`), not part of the frame format |
| `Runtime.Hit` → `Cairn.UI.Hit` | It imports only `UI.Node`; hit testing is over `Laid`, not the runtime |
| `Text.Metrics` → `Cairn.Font` | `Font` and `TextMetrics` are base vocabulary like `Geometry`; `UI.Node` needs them |

Old names stay as one-line re-exporting modules for a release, since Yap imports
`Cairn.Frame.Boundary` and `docs/plan.md` lists `Text/Metrics.lean` as a contract.

After the moves the layers are:

```
Geometry, Claim, Effects, Font
  → Input, UI (Node, Hit)
  → Text (Wrap, Field, Host), Surface
  → Layout (Core, Facts), App, Claims (Move, Machine, Core)
  → Runtime (World, Step, Abi)
  → Frame (Bytes, Encode, Events, Menu, Build)
  → Abi
proofs (Layout.Proofs/Bridge/Check/Rigid/Para, Runtime.Proofs/WorldProofs, Text.Proofs/WrapProofs,
        Claims.Deliver, Frame.Layout) sit beside the layer they are about
tooling (Claims.Elab/Registry/Tool/Ledger/Export/Release, Doc, Fuzz, Audit) on top; imports Lean
```

**The layers are a chain, not a tree.** An app's `Abi` module imports `Text.Host`,
`Runtime.Abi`, `Frame.Boundary`, `App`, `Layout.Core` and `Claims.Core` (Yap's are exactly these).
Their closure is 26 modules, 6.7k lines, and spans every directory: Geometry, Claim, Effects,
Input, UI, Surface, Text, Layout, App, Claims, Runtime and Frame. `Runtime.Step` lays out every
frame, so Layout is not optional, and `Layout.Core` wraps text, so Text isn't either. A package per
directory (`cairn_layout`, `cairn_text`, …) would be a linear chain of packages that every app
needs all of: one package with extra version numbers.

What *is* separable is by purpose, not topic. Of the 48 modules (12.6k lines) in the `Cairn`
library, 5.6k lines are proofs and tests that no app links, and the claim commands and tools
import `Lean`, which the host must never link.

## 2. One package or several

### Lean: one package

- **One toolchain.** Every package in a Lake workspace builds with the root's toolchain, and
  `.olean`s and the build cache are shared only between identical toolchains (docs/package.md).
  A toolchain bump is a release of every Cairn package at once, whatever their versions say.
- **Build and cache.** Lake builds per module, so an app already compiles only the Cairn modules
  it imports; separate packages wouldn't shrink that. The cost that is real is
  `bin/cairn-link`'s `lake query @cairn/Cairn:static`, which builds and archives all 48 modules.
  Shrinking the `Cairn` library to the linked closure fixes that without a package split.
- **`cairn-link`** merges one Cairn archive by name. Several packages would mean finding every
  transitive dependency's libraries, and any Lean module that lands in two archives (as
  `Cairn.Fuzz.Rng` already sits in the `Todo` library's roots) is a duplicate symbol.
- **Claim scopes.** The framework itself issues no claims. Every one of the 100 active `cairn^N`
  is either an example app's (^1–^462, 60 ids) or a trusted-base `assume` (^901–^1005, 40 ids in
  `Cairn.Fuzz.Trusted.Claims`). Layout, Text, Runtime and Frame would each get an empty ledger.
  The assumptions cover frame decoding, events, text metrics and wrapping, the clock, effects,
  menus, panels and painters: the whole host. Splitting them by package means `ledger move`, which
  the ledger counts as breaking, and Yap's `yap^348` cites `cairn^1005` by name. So the package
  that owns the host keeps the name `cairn`, and the ids stay where they are. (Registry names
  are `[a-z][a-z0-9_]*` and are the scope, so a split scope would be `cairn_layout^N`, never
  `cairn-layout^N`.)
- **Versioning.** Lean and Swift are coupled byte for byte: `Frame.Encode` ↔ CairnFrame's decoder,
  `Runtime.Abi` ↔ CLean, `Effects` ↔ CairnHost's `World`, `Text.Host` ↔ CairnRender's
  `TextSystem`. One tag pins both (docs/package.md). Separate Lean packages would each still need
  a matching Swift tag, so their versions could never move independently.
- **Trusted base and audit.** One `docs/trusted.md`, one `make lint`, one fuzz-trusted harness.
  `lake exe audit` checks theorems in modules rooted at `Cairn`, `Examples` and the app's roots.
  That's sound for dependencies' axioms, since `collectAxioms` is transitive, but `make lint`'s
  ban on `implemented_by`, `native_decide` and friends greps only `lean/Cairn` and
  `lean/Examples`. A third-party library's `@[implemented_by]` changes what runs without
  showing up anywhere. Before any non-Cairn lib is published, the registry's builder should run
  lint and the axiom audit over it and show the result next to its docs.
- **What apps import.** Yap: the six runtime modules above, `meta import Cairn.Claims.Elab`,
  `Cairn.Claims.Deliver` (proofs), and `Cairn.Fuzz.Rng`, `Collect`, `Main` (its fuzz executables).
  The examples import the same, plus the layout proofs (`Cairn.Layout`, `Frame.Layout`,
  `Layout.Rigid`). Nobody imports a subset that a split would make cheaper.

### Swift: one package, several products

SwiftPM resolves a git dependency only from a root `Package.swift`, so several Swift packages
means several repositories. The products already let an app take only what it uses (Yap:
CLean, CairnFrame, CairnRender, CairnHost), the target graph is acyclic
(CairnFrame → CairnRender → CairnHost → CairnCapture, CLean → CairnHost), and every product is
coupled to the Lean side as above. Keep it. CairnCapture is tooling (headless screenshots for the
map); keep it as a product but say so in its doc comment. A capability package after #84 brings
its own Swift product from its own repository.

## 3. The standard library

The pattern in all three references is the same: **what is coupled to the compiler or platform
ships with it and versions with it; everything else is a package.** Rust's `core`/`alloc`/`std`
ship with rustc in one repository and are three crates only because `no_std` targets exist; serde
and regex are crates. Lean's `Init` and `Std` ship with the toolchain, Batteries is a package
pinned per toolchain where things incubate and some later move into `Std`, and Mathlib is a
package on top. SwiftUI is one framework versioned with the SDK; everything else is a SwiftPM
package. Cairn's "compiler" is the frame format, the ABI, the effect set and the host, so std is
what's coupled to those. Cairn has one target (a macOS host), so no `no_std`-style split of core
from std is needed; internal Lake libraries give the same layering.

| Layer | Contents | Where |
|---|---|---|
| core | Geometry, Claim, Font, Input, Effects, UI.Node, UI.Hit, Surface, App, Claims.Move/Machine/Core, Runtime.World/Step/Abi, Frame (format, encode, events, menu, build), Abi | `cairn`, library `Cairn`, linked into every app |
| std (still in `cairn`) | Layout.Core/Facts, Text.Wrap/Field/Host, and the proofs about all of the above | `Cairn` (code), `CairnProofs` (proofs) |
| language | the claim commands (`Claims.Elab`, `Registry`), `meta import`ed | `cairn`, library `CairnClaims` |
| trusted base | the `assume` claims ^901–^1005 and their Swift implementations | `cairn`, library `CairnTrusted`, host products |
| tooling | ledger, claims export, doc export, audit, fuzz walk and driver, conformance, CairnCapture | `cairn`, libraries `CairnFuzz`, `CairnTools` and their `lean_exe`s; never linked |
| batteries | pure Lean that touches no ABI: JSON, dates, case folding | `cairn_batteries` |
| capabilities | an effect, its Swift implementation and its `assume`s | `cairn_<capability>`, after #84 |

Layout and Text stay in std, not batteries: the runtime calls `layout`, and hit testing,
presence theorems and the text-input client are stated over them. Widgets don't exist yet
(`Cairn.UI` is `Node` alone); when they do they're std too, because a widget's behaviour is moves
and presence theorems over Layout. Tooling stays in `cairn` for a reason Rust doesn't have: the
ledger, claim export, doc export and audit load the app's `.olean`s, so they must be Lake
executables in the app's workspace on its toolchain. Living in `cairn` means the docs builder
(#94) runs exactly the version of `doc` that a package's `cairn` resolves to. The `cairn` CLI
(tools/cairn) is the Cargo analogue and ships as a binary, not a registry package.

### What std lacks, judging from Yap

Yap is 11k lines of Lean, and some of it is library code any app would need:

- **Effects an app declares (#84).** `Cairn.Effect` is closed, so Yap's capabilities (`record`,
  `wav`, `forgetClip`, `globalKey`, `typeText`, `upload`, `frontmostApp`) are in Cairn's core
  effect type with their assumes. std needs the extension point: a Lean effect an app's package
  declares, a registration point in CairnHost, and a fuzz-trusted hook for assumes in another
  scope. The existing capabilities stay in std with their ids; new ones go into packages.
- **Graphemes.** `Yap.Graphemes` (370 lines) is Swift's `Character` segmentation, and
  docs/trusted.md says grapheme clusters aren't modelled, so the caret stalls inside "é" written
  as e + U+0301. That belongs in `Cairn.Text`, with Text.Field moving by clusters.
- **JSON and dates.** `Yap.Json` (599 lines) is a total JSON parser and encoder plus date
  arithmetic, needed to read config and write transcripts. The first content of
  `cairn_batteries`, graduating into std if an effect ever speaks JSON.
- **Calendar.** `Yap.Retention` relies on the host turning file names into local-calendar day
  numbers. A clock that only answers milliseconds leaves every app to ask the host for this some
  other way. A std `localDate` reply or effect is the likely fix (uncertain: one app so far).
- **Request bookkeeping.** `Yap.Once` (458 lines) proves each clip is typed at most once under
  late, duplicated and lost replies. The argument (live requests, ids used up by their reply)
  is generic, and a std lemma kit over `Reply` ids would cover it. Uncertain until a second app
  needs it.
- `Yap.Fold` (ICU case folding for one regex) is app code.

## 4. The layout

### `cairn` (lib, this repository, scope `cairn`)

Lake libraries, all in the one package `lean/`:

| Library | Roots | Linked | Imports Lean |
|---|---|---|---|
| `Cairn` | the core and std code above, the linked closure only | yes, by `cairn-link` | no |
| `CairnProofs` | the proof and test modules | no | no |
| `CairnClaims` | `Claims.Elab`, `Claims.Registry` | no (`meta import`) | yes |
| `CairnTrusted` | `Fuzz.Trusted.Claims` (today `TrustedClaims`) | no | compile time |
| `CairnFuzz` | `Fuzz.*` (with `Rng`'s `Custom` hook in `Cairn`, since app modules name it) | no | yes |
| `CairnTools` | `Claims.Tool/Ledger/Export/Release`, `Doc.Export`, `Audit` | no | yes |
| `Examples`, per-app libs | as today; not published as packages | — | — |

Arrows: `CairnProofs`, `CairnClaims`, `CairnFuzz` → `Cairn`; `CairnTools` → `CairnClaims`;
`CairnTrusted` → `Cairn` + `CairnClaims` (meta). Module names don't change apart from the three
moves, so `import`s in apps keep working. Swift products as today. `cairn.toml`'s
`libs = ["Cairn"]`.

### `cairn_batteries` (lib, own repository, scope `cairn_batteries`)

`require cairn`; pure Lean, no Swift product, no `@[extern]`. Starts from `Yap.Json`. Released on
its own cadence, but once per Cairn toolchain bump at least.

### `cairn_<capability>` (lib, own repository each, own scope)

After #84: a Lean effect module, a Swift product depending on `cairn`'s CairnHost, its `assume`s
in its own scope and a fuzz-trusted suite. `cairn` keeps every capability it has today.

Every published package carries its own `claims.lock`, so the registry can derive the minimum
semver bump from the ledger diff (it already refuses retired ids without a major, docs/claims.md).

## 5. Migration

Yap pins `v0.1.2` exactly, so nothing on `main` breaks it. Each step below is a release Yap can
take with no source change, or a one-line one.

1. **Moves with shims** (0.1.3). `Cairn.Abi`, `Cairn.UI.Hit`, `Cairn.Font`; the old modules
   re-export them. Add a lint that fails on a directory-level cycle. No claim changes. Done:
   `make lint` runs `tools/lint/dircycles.ts`, which skips the three shims.
2. **Libraries** (0.1.3 or 0.1.4). Narrow `Cairn` to the linked closure; add `CairnProofs`,
   `CairnClaims`, `CairnFuzz`, `CairnTools`, rename `TrustedClaims` to `CairnTrusted`. Take
   `Cairn.Fuzz.Rng` out of the `Todo` library's roots. The `Cairn.lean` umbrella keeps importing
   everything for the ledger and audit roots. Check `libcairn_lean.a` shrinks (20.8 MB today, 15
   of it `libInit`). Yap bumps its tag and builds unchanged. Done: `Cairn` is 31 modules
   (the shims and `Fuzz.Rng` included), `libcairn_Cairn.a` 3.7 → 2.8 MB and `libcairn_lean.a`
   20.8 → 19.9 MB; `Frame.Dump` went to `TrustedFuzz`, `ClaimsTests` stays, `CairnTools` isn't a
   default target (`make kernel` would import its four `main`s together), and the host now runs
   `initialize_cairn_Cairn_Abi`, since the `Cairn` umbrella imports the proofs.
3. **`cairn-link` links dependencies' `libs`.** Instead of `@cairn/Cairn:static` by name, it
   links each dependency's `libs` from its `cairn.toml`. `cairn` declares `libs = ["Cairn"]`. Yap
   gets the same archive. Run #86 (an outside package builds against Cairn) with Yap as the
   outside package from here on.
4. **Drop the shims** in the next 0.x minor (0.2.0). Yap changes one import
   (`Cairn.Frame.Boundary` → `Cairn.Abi`).
5. **Examples get their own scope (#88), before 1.0.** `ledger move examples …` for ^1–^462 in a
   0.x minor, so that std's ledger holds only std's promises: today retiring a Todo move counts
   as a breaking change to Cairn. After 1.0 that move costs a major.
6. **#84**, then the first capability package. **`cairn_batteries`** when a second app needs
   JSON: move `Yap.Json` there and have Yap require it.

## 6. Registry, `cairn.toml` and `cairn add`

- **Names.** `cairn` is std and stays a lib. `std` is reserved by the registry, so std is never
  named `std`. The registry should reserve the `cairn_` prefix for Cairn's owner, so
  `cairn_batteries` and `cairn_<capability>` can't be squatted (a nextpm change).
- **One package per repository.** `cairn publish` needs `cairn.toml` at the root and the tag
  `v<version>` on HEAD, and SwiftPM needs the root `Package.swift`. Several packages in one
  repository would need per-package tags and manifests in subdirectories; nothing here needs that.
- **`cairn.toml`.** Unchanged for apps. A lib's `libs` becomes meaningful to its consumers: it is
  what `cairn-link` merges. The registry metadata already carries `libs`.
- **`cairn add <name>`.** Writes the Lake `require` as today. For a package with a Swift product
  it should print the product too, which needs the products in the registry metadata (a new
  field; today it prints only the `.package` line).

## Uncertain

- Whether `lake update` rewrites the root's `lean-toolchain` from a dependency's in our toolchain
  (v4.35.0). Either way all packages end up on one toolchain; the question is only who moves it.
- The calendar and request-bookkeeping gaps are judged from one app.
- Whether `Rng`'s `Custom` (a fuzz hook typed in app modules) belongs in `Cairn` or should become a
  field the fuzzer finds by name. Kept in `Cairn` above because `Examples.Todo` names it today.

import Lake
open Lake DSL

package cairn where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

/-- C glue for `Cairn.Text.Host`'s `@[extern]` metrics (see lean/c/text_host.c). It defines the
host's `cairn_text_metrics` weakly, so executables link without the Swift host. -/
target text_host.o pkg : System.FilePath := do
  let src ← inputTextFile <| pkg.dir / "c" / "text_host.c"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString]
  buildO (pkg.buildDir / "c" / "text_host.o") src weakArgs #["-O2", "-fPIC"] "cc"

@[default_target]
lean_lib Cairn where
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[text_host.o]

/-- A weak stand-in for the claim commands' full initializer, so the host links apps that
`meta import` them without libLean (see lean/c/claims_meta.c). -/
target claims_meta.o pkg : System.FilePath := do
  let src ← inputTextFile <| pkg.dir / "c" / "claims_meta.c"
  let args := #["-I", (← getLeanIncludeDir).toString]
  buildO (pkg.buildDir / "c" / "claims_meta.o") src args #["-O2", "-fPIC"] "cc"

/-- Every example app and its proofs (`Examples.lean`): what the ledger, the axiom audit and the
kernel replay read. The host links the per-app libraries below, never this one. -/
@[default_target]
lean_lib Examples

/-- Tests for the claim commands. Not imported by `Cairn` or `Examples`, so their ids stay out of
the ledger. -/
@[default_target]
lean_lib ClaimsTests where
  roots := #[`Cairn.Claims.Tests]

/-- The trusted base's `assume` claims (`Cairn.Fuzz.Trusted.Claims`). They use the claim commands
(`import Lean` at compile time), so they stay out of `Cairn`, which the host links; the ledger
reads them as a root. -/
@[default_target]
lean_lib TrustedClaims where
  roots := #[`Cairn.Fuzz.Trusted.Claims]

/-- `lake exe ledger check|update`: guards `claims.lock` (see docs/claims.md). -/
lean_exe ledger where
  root := `Cairn.Claims.Ledger
  supportInterpreter := true

/-- `lake exe claims <Module>…`: every claim as JSON, for the map. -/
lean_exe claims where
  root := `Cairn.Claims.Export
  supportInterpreter := true

/-- `lake exe doc [--check] <Module>…`: modules, declarations, signatures and doc comments as JSON,
for `make doc` (docs/doc.md); `--check` runs the doc tests. -/
lean_exe doc where
  root := `Cairn.Doc.Export
  supportInterpreter := true

/-! One static library per app, and each host executable links exactly one (`make lean`,
host/Package.swift): v1 apps all export `cairn_app_init/step/frame`, so two in one binary would
clash. Each needs `claims_meta.o` (docs/claims.md, "Linking"). The host calls the app module's
`runtime_initialize_*`. -/

-- region: lakefile-counter
/-- Counter: its exports (`Examples.Counter.Abi`) and the app. The exports are a separate module
so that executables linking all of `Examples` (the fuzzer) don't get two `cairn_app_init`s. -/
@[default_target]
lean_lib Counter where
  roots := #[`Examples.Counter.Abi, `Examples.Counter]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]
-- endregion: lakefile-counter

/-- Basics (`Examples.Basics`). -/
@[default_target]
lean_lib Basics where
  roots := #[`Examples.Basics]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

/-- TodoMVC (workstream I): its exports (`Examples.Todo.Abi`), the app, model and view. The exports
are a separate module so that executables linking all of `Examples` (the fuzzer) don't get two
`cairn_app_init`s. -/
@[default_target]
lean_lib Todo where
  roots := #[`Examples.Todo.Abi, `Examples.Todo, `Examples.Todo.Model, `Examples.Todo.View,
    `Cairn.Fuzz.Rng]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

/-- Clock (workstream Q, docs/effects.md): its exports (`Examples.Clock.Abi`) and the app. -/
@[default_target]
lean_lib Clock where
  roots := #[`Examples.Clock.Abi, `Examples.Clock]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

/-- Tray (workstream S, docs/surfaces.md): a menu bar item and an overlay panel. -/
@[default_target]
lean_lib Tray where
  roots := #[`Examples.Tray.Abi, `Examples.Tray]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

/-- Yap on Cairn (workstream W, docs/yap.md): the dictation machine as a menu bar app with an
overlay. -/
@[default_target]
lean_lib Yap where
  roots := #[`Examples.Yap.Abi, `Examples.Yap]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

lean_exe bench where
  root := `Bench

lean_exe audit where
  root := `Audit
  supportInterpreter := true

lean_exe framecorpus where
  root := `FrameCorpus

/-- The conformance generator (tools/conformance, docs/conformance.md): walks an app's model and
writes move sequences with the frames the app must show. One module per app under
`Conformance.Apps`; `make conformance` links one with that app's library and the host's Core
Text metrics. Never linked into the host. -/
@[default_target]
lean_lib Conformance where
  srcDir := "../tools/conformance/lean"
  globs := #[.submodules `Conformance]

/-- The fuzzer (docs/fuzz.md): generators, the walk, the checks and shrinking. Not linked into
any host binary. -/
@[default_target]
lean_lib Fuzz where
  roots := #[`Cairn.Fuzz]

/-- `lake exe fuzz <App> [--seed S] [--iterations N] [--steps K]` (docs/fuzz.md). -/
lean_exe fuzz where
  root := `FuzzMain

/-- `lake exe yapfuzz [--seed S] [--iterations N] [--steps K] [--out DIR]`: Yap's dictation
machine against a random host (`Examples/Yap/Fuzz.lean`). -/
lean_exe yapfuzz where
  root := `YapFuzz

/-- Lean's side of the trusted-base fuzzer (docs/fuzz.md, "Trusted base"): generators, the
proved decoders' verdicts and a one-field app, exported over C for the Swift executable
`cairn-fuzz-trusted`, which links this next to `libcairn_lean.a`. No `import Lean`. It carries
its own copy of `Cairn.Fuzz.Rng`, which `libcairn_lean.a` doesn't contain. -/
@[default_target]
lean_lib TrustedFuzz where
  roots := #[`Cairn.Fuzz.Trusted.Export]
  globs := #[.one `Cairn.Fuzz.Trusted.Export, .one `Cairn.Fuzz.Trusted.Gen, .one `Cairn.Fuzz.Rng]
  defaultFacets := #[LeanLib.staticFacet]

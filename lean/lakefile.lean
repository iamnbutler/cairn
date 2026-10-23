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

/-- `lake exe ledger check|update`: guards `claims.lock` (see docs/claims.md). -/
lean_exe ledger where
  root := `Cairn.Claims.Ledger
  supportInterpreter := true

/-- `lake exe claims <Module>…`: every claim as JSON, for the map. -/
lean_exe claims where
  root := `Cairn.Claims.Export
  supportInterpreter := true

/-! One static library per app, and each host executable links exactly one (`make lean`,
host/Package.swift): v1 apps all export `cairn_app_init/step/frame`, so two in one binary would
clash. Each needs `claims_meta.o` (docs/claims.md, "Linking"). The host calls the app module's
`runtime_initialize_*`. -/

/-- The spike's Counter (`Examples.Counter`, `cairn_counter_*`, frame v0). -/
@[default_target]
lean_lib Counter where
  roots := #[`Examples.Counter]
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

/-- Basics (`Examples.Basics`), the first app on the v1 ABI. -/
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

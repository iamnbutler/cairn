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

<<<<<<< HEAD
/-- A weak stand-in for the claim commands' full initializer, so the host links apps that
`meta import` them without libLean (see lean/c/claims_meta.c). -/
target claims_meta.o pkg : System.FilePath := do
  let src ← inputTextFile <| pkg.dir / "c" / "claims_meta.c"
  let args := #["-I", (← getLeanIncludeDir).toString]
  buildO (pkg.buildDir / "c" / "claims_meta.o") src args #["-O2", "-fPIC"] "cc"

=======
/-- The spike's Counter (`Examples.Counter`, `cairn_counter_*`, frame v0). -/
>>>>>>> 647b394 (Basics on the v1 ABI: app, per-app libraries, FrameV1Codec, selftest, Pressable checker)
@[default_target]
lean_lib Examples where
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_meta.o]

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

/-! One library per v1 app. Every v1 app exports the same `cairn_app_init/step/frame`, so each
gets its own static library and each host executable links exactly one (`make lean`,
host/Package.swift). Its proofs are a separate root: built and audited, never linked. -/

@[default_target]
lean_lib Basics where
  roots := #[`Examples.Basics]
  defaultFacets := #[LeanLib.staticFacet]

@[default_target]
lean_lib BasicsProofs where
  roots := #[`Examples.Basics.Proofs]

lean_exe bench where
  root := `Bench

lean_exe audit where
  root := `Audit
  supportInterpreter := true

lean_exe framecorpus where
  root := `FrameCorpus

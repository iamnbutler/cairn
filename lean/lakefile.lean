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

/-- A weak stand-in for `Cairn.Claims`' initializer, so the host links apps that use the claim
commands without libLean (see lean/Cairn/Claims/host_init.c). -/
target claims_host_init.o pkg : System.FilePath := do
  let src ← inputTextFile <| pkg.dir / "Cairn" / "Claims" / "host_init.c"
  let args := #["-I", (← getLeanIncludeDir).toString]
  buildO (pkg.buildDir / "c" / "claims_host_init.o") src args #["-O2", "-fPIC"] "cc"

@[default_target]
lean_lib Cairn where
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[text_host.o]

@[default_target]
lean_lib Examples where
  defaultFacets := #[LeanLib.staticFacet]
  moreLinkObjs := #[claims_host_init.o]

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

lean_exe bench where
  root := `Bench

lean_exe audit where
  root := `Audit
  supportInterpreter := true

lean_exe framecorpus where
  root := `FrameCorpus

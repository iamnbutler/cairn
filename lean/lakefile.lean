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

@[default_target]
lean_lib Examples where
  defaultFacets := #[LeanLib.staticFacet]

lean_exe bench where
  root := `Bench

lean_exe audit where
  root := `Audit
  supportInterpreter := true

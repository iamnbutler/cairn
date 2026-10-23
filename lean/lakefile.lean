import Lake
open Lake DSL

package cairn where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

@[default_target]
lean_lib Cairn where
  defaultFacets := #[LeanLib.staticFacet]

@[default_target]
lean_lib Examples where
  defaultFacets := #[LeanLib.staticFacet]

lean_exe bench where
  root := `Bench

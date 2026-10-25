import Lake
open Lake DSL

/-- A library with a machine of its own, as cairn_atproto has (../README.md). -/
package fuzzdep where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`weak.cairn.claims.scope, "fuzzdep"⟩]

require cairn from "../../../lean"

@[default_target]
lean_lib Dep

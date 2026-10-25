import Lake
open Lake DSL

/-- An app that imports a dependency's machine (../README.md). -/
package fuzzapp where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`weak.cairn.claims.scope, "fuzzapp"⟩]

require cairn from "../../../lean"
require fuzzdep from "../dep"

@[default_target]
lean_lib App

/-- Checks that two of the app's machines with one target name are refused (Clash.lean). -/
@[default_target]
lean_lib Clash

lean_exe fuzz where
  root := `FuzzMain

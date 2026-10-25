import Lake
open Lake DSL

-- region: fixture-lakefile
/-- Cairn's fixture app (../README.md). The package name is the claim scope: its claims are
`fixture^N`, in ../claims.lock, never in Cairn's. -/
package fixture where
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩,
    ⟨`weak.cairn.claims.scope, "fixture"⟩]

-- This checkout's Cairn, not a release: the fixture tests the tree it is in.
require cairn from "../../../lean"

/-- The app and its exports (`Fixture.Abi`), which `cairn build` links (bin/cairn-link). -/
@[default_target]
lean_lib Fixture where
  roots := #[`Fixture.Abi, `Fixture]
  defaultFacets := #[LeanLib.staticFacet]
-- endregion: fixture-lakefile

/-- The app with its tests (`Checks.lean`): what the ledger and the axiom audit read. Never
linked. -/
@[default_target]
lean_lib Checks

-- region: fixture-lakefile-checks
/-- `cairn conformance`'s generator entry point (Cairn's docs/conformance.md). Declared after
`Fixture`, whose root would otherwise claim it. -/
lean_lib FixtureConformance where
  roots := #[`Fixture.Conformance]

/-- `cairn fuzz`: Cairn's claim-driven fuzzer on the app (Cairn's docs/fuzz.md). -/
lean_exe fuzz where
  root := `FuzzMain
-- endregion: fixture-lakefile-checks

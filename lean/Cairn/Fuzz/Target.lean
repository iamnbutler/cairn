import Cairn.Fuzz.Rng
import Cairn.Claims.Core

/-! # What the fuzzer knows about an app

A `Target` bundles a machine (and the `App` built from it, if any) with what the claims say
about it. `fuzz_targets%` (`Cairn.Fuzz.Collect`) builds one per machine in the app's
modules (and its dependencies') at compile time, so an app needs no fuzz code of its own. -/

namespace Cairn.Fuzz
open Cairn Cairn.Claims

/-- An invariant, with its runnable check if it has one (`invariant` generates `check` when its
statement is decidable). -/
structure InvCheck (S : Type) where
  info : ClaimInfo
  /-- The invariant's declaration, relative to the app's namespace (for printed flows). -/
  decl : String
  check : Option (S → Bool)

structure Target where
  /-- `Fixture`: what `lake exe fuzz` is given. A dependency's has its package in front,
  `cairn_atproto/Claims`. -/
  name : String
  /-- `Fixture`, the machine's module. -/
  module : String
  /-- The machine's Lake package (`fixture`), or `""` if Lake named none. -/
  package : String := ""
  /-- Whether the machine is a dependency's rather than the fuzz executable's own package's: run
  only when named, or with `--deps`. -/
  dependency : Bool := false
  /-- The namespace the claims live in, for printed flows. -/
  ns : String
  /-- The machine's and the app's declarations, relative to `ns`. -/
  machineDecl : String
  appDecl : Option String
  S : Type
  machine : Machine S
  app : Option (App S)
  /-- Claim ids of the keyed moves (`^N#k`). -/
  keyed : List ClaimId
  invariants : List (InvCheck S)
  /-- Every claim the app's module declares, retired ones included. -/
  claims : List ClaimInfo
  custom : Custom S := {}

/-- The app's server, or `Server.empty` (no world, nothing handled). -/
def Target.srv (t : Target) : Server t.S := t.custom.server.getD Server.empty

/-- What the app's server holds (`Unit` without one). -/
abbrev Target.W (t : Target) : Type := t.srv.W

end Cairn.Fuzz

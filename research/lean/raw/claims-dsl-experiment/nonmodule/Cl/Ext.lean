import Lean
open Lean

structure ClaimEntry where
  id : Nat
  title : String
  decl : Name
  module : Name
deriving Inhabited, Repr

structure ClaimState where
  byId : Std.HashMap Nat ClaimEntry := {}
  dups : Array (ClaimEntry × ClaimEntry) := #[]
deriving Inhabited

def ClaimState.add (s : ClaimState) (e : ClaimEntry) : ClaimState :=
  match s.byId[e.id]? with
  | some old => { s with dups := s.dups.push (old, e) }
  | none => { s with byId := s.byId.insert e.id e }

initialize claimExt : SimplePersistentEnvExtension ClaimEntry ClaimState ←
  registerSimplePersistentEnvExtension {
    addEntryFn := ClaimState.add
    addImportedFn := fun mods => mods.foldl (fun s es => es.foldl ClaimState.add s) {}
  }

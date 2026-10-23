module

public meta import Lean
public meta import Cairn.Claim

/-! The claim registry: an environment extension holding one entry per claim declared by the
claim commands, in this module and every module it imports. The commands consult it for the
compile-time checks; `lake exe ledger` and `lake exe claims` read it from the imported
environment.

Compile time only (imports `Lean`); see `Cairn.Claims` for why that matters. -/

public meta section

namespace Cairn.Claims
open Lean

def _root_.Cairn.ClaimKind.name : ClaimKind → String
  | .move => "move" | .flow => "flow" | .invariant => "invariant"
  | .assume => "assume" | .place => "place"

def _root_.Cairn.ClaimKind.ofName? : String → Option ClaimKind
  | "move" => some .move | "flow" => some .flow | "invariant" => some .invariant
  | "assume" => some .assume | "place" => some .place
  | _ => none

/-- One claim as the registry records it. -/
structure Entry where
  info : ClaimInfo
  /-- The namespace the claim was declared in; `claims%` and `moves%` collect by it. -/
  ns : Name
  /-- The declaration holding the claim (a `Move`, `Flow`, `Invariant`, `Assumption`, `Place`,
  or a bare `ClaimInfo` for a retired id). -/
  decl : Name
  /-- The `ClaimInfo` constant. -/
  infoDecl : Name
  module : Name
  /-- Declarations whose definitions are the claim's formal statement. The ledger hashes them
  (and what they unfold to in Cairn's own modules) to notice a change of meaning. -/
  statement : Array Name := #[]
  /-- The evidence: a role (`sound press`, `reaches`, `step`, …) and the theorem proving it. -/
  evidence : Array (String × Name) := #[]
  /-- Moves: the triggers answered, and whether controls are keyed. -/
  triggers : Array String := #[]
  keyed : Bool := false
  /-- Flows: the claim ids of the moves the witness passes through, in order. -/
  passes : Array ClaimId := #[]
  /-- Flows and invariants: the machine they are stated against. -/
  machine : Option Name := none
  /-- Assumptions: the runnable check that gathers evidence for it (a check name in the trusted
  fuzzer's report, `build/fuzz/trusted.json`; docs/fuzz.md, "Trusted base"). -/
  check : Option String := none
deriving Inhabited

def Entry.label (e : Entry) : String :=
  s!"^{e.info.id} {e.info.kind.name} “{e.info.title}” ({e.decl}, module {e.module})"

structure State where
  byId : Std.HashMap ClaimId Entry := {}
  /-- Pairs of imported claims with the same id (modules that never import each other). -/
  clashes : Array (Entry × Entry) := #[]
  /-- Entries declared in this module, in order. -/
  here : Array Entry := #[]
deriving Inhabited

def State.add (st : State) (e : Entry) : State :=
  match st.byId[e.info.id]? with
  | some old => { st with clashes := st.clashes.push (old, e) }
  | none => { st with byId := st.byId.insert e.info.id e }

initialize registry : SimplePersistentEnvExtension Entry State ←
  registerSimplePersistentEnvExtension {
    addEntryFn := fun st e => { st.add e with here := st.here.push e }
    addImportedFn := fun mods => mods.foldl (fun st es => es.foldl State.add st) {}
  }

/-- Namespaces collected in this module by `moves%` (first) and `claims%` (second). A move
declared in the first afterwards would never be dispatched, and a claim declared in the second
would be missing from the app's claims, so the commands refuse both. -/
initialize sealedExt : EnvExtension (NameSet × NameSet) ← registerEnvExtension (pure ({}, {}))

def entries (env : Environment) : Array Entry :=
  let st := registry.getState env
  st.byId.fold (fun acc _ e => acc.push e) #[] |>.qsort (·.info.id < ·.info.id)

def lookup? (env : Environment) (id : ClaimId) : Option Entry :=
  (registry.getState env).byId[id]?

def clashes (env : Environment) : Array (Entry × Entry) := (registry.getState env).clashes

/-- Every entry, including both sides of any clash, for tools that report on the whole set. -/
def allEntries (env : Environment) : Array Entry :=
  let es := entries env
  (clashes env).foldl (fun acc (_, b) => acc.push b) es |>.qsort (·.info.id < ·.info.id)

end Cairn.Claims

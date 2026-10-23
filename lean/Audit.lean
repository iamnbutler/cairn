import Lean

/-! `lake exe audit`: every theorem in Cairn's own modules may depend only on Lean's three
standard axioms. Fails on `sorryAx`, `Lean.ofReduceBool` (from `native_decide`), or any axiom
we declared ourselves. -/

open Lean

def allowed : List Name := [``propext, ``Classical.choice, ``Quot.sound]

def ours (env : Environment) (n : Name) : Bool :=
  match env.getModuleIdxFor? n with
  | some idx =>
    let m := env.header.moduleNames[idx.toNat]!
    m.getRoot == `Cairn || m.getRoot == `Examples
  | none => false

def main (args : List String) : IO UInt32 := do
  let roots := if args.isEmpty then [`Cairn, `Examples, `Examples.Basics.Proofs] else args.map String.toName
  initSearchPath (← findSysroot)
  let env ← importModules (roots.map ({ module := · })).toArray {} (trustLevel := 1024)
  let mut checked := 0
  let mut bad : Array String := #[]
  for (n, ci) in env.constants.toList do
    unless ours env n do continue
    if n.isInternal then continue
    match ci with
    | .thmInfo _ | .axiomInfo _ =>
      checked := checked + 1
      let (axs, _) ← (collectAxioms n : CoreM _).toIO { fileName := "audit", fileMap := default } { env }
      let extra := axs.toList.filter (· ∉ allowed)
      unless extra.isEmpty do
        bad := bad.push s!"{n}: {extra}"
    | _ => pure ()
  for b in bad do IO.eprintln s!"axiom audit: {b}"
  IO.println s!"axiom audit: {checked} theorems checked, {bad.size} with disallowed axioms"
  return if bad.isEmpty && checked > 0 then 0 else 1

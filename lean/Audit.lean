import Lean

/-! `lake exe audit [--json PATH] [Module…]`: every theorem in Cairn's own modules may depend
only on Lean's three standard axioms. Fails on `sorryAx`, `Lean.ofReduceBool` (from
`native_decide`), or any axiom we declared ourselves.

With `--json PATH` it also writes every theorem it checked, with its disallowed axioms, as
`{"allowed": [...], "theorems": {"<name>": {"ok": true, "extraAxioms": []}, …}}`. The map
(`tools/map`) reads it to mark a claim's evidence proved. -/

open Lean

def allowed : List Name := [``propext, ``Classical.choice, ``Quot.sound]

def ours (env : Environment) (n : Name) : Bool :=
  match env.getModuleIdxFor? n with
  | some idx =>
    let m := env.header.moduleNames[idx.toNat]!
    m.getRoot == `Cairn || m.getRoot == `Examples
  | none => false

/-- Split `--json PATH` out of the arguments. -/
def jsonPath : List String → Option String × List String
  | "--json" :: p :: rest => let (_, r) := jsonPath rest; (some p, r)
  | a :: rest => let (j, r) := jsonPath rest; (j, a :: r)
  | [] => (none, [])

def main (args : List String) : IO UInt32 := do
  let (json, args) := jsonPath args
  let roots := if args.isEmpty then [`Cairn, `Examples] else args.map String.toName
  initSearchPath (← findSysroot)
  let env ← importModules (roots.map ({ module := · })).toArray {} (trustLevel := 1024)
  let mut checked := 0
  let mut bad : Array String := #[]
  let mut results : Array (String × Json) := #[]
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
      if json.isSome then
        results := results.push (n.toString, Json.mkObj [("ok", extra.isEmpty),
          ("extraAxioms", toJson (extra.map (·.toString)))])
    | _ => pure ()
  for b in bad do IO.eprintln s!"axiom audit: {b}"
  IO.println s!"axiom audit: {checked} theorems checked, {bad.size} with disallowed axioms"
  if let some p := json then
    IO.FS.writeFile p (Json.mkObj [("roots", toJson (roots.map (·.toString))),
      ("allowed", toJson (allowed.map (·.toString))),
      ("theorems", Json.mkObj results.toList)]).compress
  return if bad.isEmpty && checked > 0 then 0 else 1

import Cl.Ext
open Lean Elab Command

/-- `move 12 "title" where <decl body>` -/
syntax (name := moveCmd) "move " num str " := " term : command

@[command_elab moveCmd] def elabMove : CommandElab := fun stx => do
  let id := stx[1].isNatLit?.get!
  let title := stx[2].isStrLit?.get!
  let st := claimExt.getState (← getEnv)
  if let some old := st.byId[id]? then
    throwErrorAt stx[1] m!"claim ^{id} already issued to {old.decl} in {old.module}"
  let declName := (← getEnv).mainModule ++ Name.mkSimple s!"claim_{id}"
  let body : TSyntax `term := ⟨stx[4]⟩
  elabCommand (← `(def $(mkIdent declName) := $body))
  modifyEnv fun env => claimExt.addEntry env { id, title, decl := declName, module := env.mainModule }

syntax (name := checkClaims) "#check_claims" : command
@[command_elab checkClaims] def elabCheck : CommandElab := fun _ => do
  let st := claimExt.getState (← getEnv)
  for (a, b) in st.dups do
    logError m!"claim ^{a.id} issued twice: {a.module} and {b.module}"
  logInfo m!"{st.byId.size} claims, {st.dups.size} duplicates"

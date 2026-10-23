module
public meta import Lean
open Lean Elab Command

public meta structure ClaimEntry where
  id : Nat
  decl : Name
deriving Inhabited

public meta initialize claimExt : SimplePersistentEnvExtension ClaimEntry (Array ClaimEntry) ←
  registerSimplePersistentEnvExtension {
    addEntryFn := Array.push
    addImportedFn := fun mods => mods.foldl (· ++ ·) #[]
  }

syntax (name := moveCmd) "move " num " := " term : command

@[command_elab moveCmd] public meta def elabMove : CommandElab := fun stx => do
  let id := stx[1].isNatLit?.get!
  if (claimExt.getState (← getEnv)).any (·.id == id) then
    throwErrorAt stx[1] m!"claim ^{id} already issued"
  let declName := Name.mkSimple s!"claim_{id}"
  elabCommand (← `(public def $(mkIdent declName) := $(⟨stx[3]⟩)))
  modifyEnv fun env => claimExt.addEntry env { id, decl := declName }

import Lean
open Lean
initialize myExt : SimplePersistentEnvExtension Nat (List Nat) ←
  registerSimplePersistentEnvExtension { addEntryFn := fun s e => e :: s, addImportedFn := fun _ => [] }
run_cmd modifyEnv fun env => myExt.addEntry env 1

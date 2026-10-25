import Cairn.Claims.Core
import Cairn.Claims.Elab

/-! The app's machine, in a module that ends in `Claims` like the dependency's. -/

namespace App
open Cairn Cairn.Claims

structure State where
  n : Nat := 0

move ^1 bump (s : State) "Bump the app" where
  does "Bump."
  sees "The count goes up."
  on press
    apply := { s with n := s.n + 1 }
    post s' := s'.n = s.n + 1
    sound := by intro s; rfl

def machine : Machine State := { init := {}, moves := moves% }

end App

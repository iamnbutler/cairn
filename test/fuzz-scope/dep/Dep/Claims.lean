import Cairn.Claims.Core
import Cairn.Claims.Elab

/-! The dependency's machine, in a module that ends in `Claims` like the app's. -/

namespace Dep
open Cairn Cairn.Claims

structure State where
  n : Nat := 0

move ^1 bump (s : State) "Bump" where
  does "Bump."
  sees "The count goes up."
  on press
    apply := { s with n := s.n + 1 }
    post s' := s'.n = s.n + 1
    sound := by intro s; rfl

def machine : Machine State := { init := {}, moves := moves% }

end Dep

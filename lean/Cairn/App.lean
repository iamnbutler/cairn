module

public import Cairn.UI.Node
public import Cairn.Input
public import Cairn.Claim

/-! An app is its state, its view, and its moves. The runtime (`Cairn.Runtime`) owns
interaction state (hover, press, focus, window size), turns events into actions by hit testing
the laid-out frame, and calls `update`. -/

@[expose] public section


namespace Cairn

/-- Interaction state the runtime owns and the view may read (hover reveals, focus rings). -/
structure UI where
  size : Size := ⟨800, 600⟩
  hover : Option ControlRef := none
  pressed : Option ControlRef := none
  focus : Option ControlRef := none
  windowFocused : Bool := true
deriving Repr, DecidableEq, Inhabited

structure App (S : Type) where
  init : S
  view : S → UI → Node
  update : S → Action → S × List Effect
  /-- Every claim the app makes, from the claim commands. -/
  claims : List ClaimInfo

end Cairn

/-- `==` on `UI` is the lawful one from `DecidableEq`, so proofs can use it. -/
example : LawfulBEq Cairn.UI := inferInstance

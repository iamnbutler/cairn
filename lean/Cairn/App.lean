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
  /-- A person's moves: every action names a control on screen. -/
  update : S → Action → S × List Effect
  /-- The outside world: the clock, timers, replies and subscription events
  (docs/effects.md). Ignored by default. -/
  receive : S → Msg → S × List Effect := fun s _ => (s, [])
  /-- The outside inputs the app wants in this state. The runtime diffs them after every
  delivery and starts and stops subscriptions to match. -/
  subscriptions : S → List Sub := fun _ => []
  /-- Effects to run once, when the first clock arrives (so timers start from a real time). -/
  initEffects : List Effect := []
  /-- Every claim the app makes, from the claim commands. -/
  claims : List ClaimInfo
  /-- The control that has keyboard focus at launch, if it is focusable there. -/
  initFocus : Option ControlRef := none

end Cairn

/-- `==` on `UI` is the lawful one from `DecidableEq`, so proofs can use it. -/
example : LawfulBEq Cairn.UI := inferInstance

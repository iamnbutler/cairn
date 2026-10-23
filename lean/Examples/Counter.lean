module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.Spike.Frame

/-! The boundary spike's app: a counter with two moves, declared with the claim commands.

- ^1 Increment: always enabled.
- ^2 Reset: enabled only when the count is above zero.

`update` is derived from the moves (`machine.update`), so a click on anything that is not a
control of ^1 or ^2 changes nothing. The spike's own event handling (`handle`) hit-tests and
turns a click into `press ^N`. -/

@[expose] public section

namespace Examples.Counter
open Cairn.Claims Cairn.Spike

structure State where
  count : Nat := 0
  width : Int := 480
  height : Int := 320
  pressed : Option Nat := none
deriving DecidableEq

def resetEnabled (s : State) : Bool := s.count > 0

place ^3 window "Counter window" where
  does "The spike's window: a bar as long as the count, Increment, and Reset when there is something to reset."

move ^1 increment (s : State) "Increment" in ^3 where
  does "Press Increment."
  sees "The count goes up by one."
  on press
    apply := { s with count := s.count + 1 }
    post s' := s'.count = s.count + 1
    sound := by intro s; rfl

move ^2 reset (s : State) "Reset" in ^3 where
  does "Press Reset."
  sees "The count is zero, and Reset disappears."
  enabled := resetEnabled s
  on press
    apply := { s with count := 0 }
    post s' := s'.count = 0 ∧ resetEnabled s' = false
    sound := by intro s _; exact ⟨rfl, rfl⟩

/-- The counter's behaviour: its moves, from a zero count. -/
def machine : Machine State := { init := {}, moves := moves% }

flow ^4 countToThree "Count to three" for machine where
  does "Press Increment three times."
  sees "The count is three."
  goal s := s.count = 3
  witness press ^1, press ^1, press ^1

flow ^5 startOver "Start over" for machine where
  does "Count up, then press Reset."
  sees "The count is back to zero and Reset is gone."
  goal s := s.count = 0 ∧ resetEnabled s = false
  witness press ^1, press ^1, press ^2

invariant ^6 noPressLeft "Moves never leave a press in progress" for machine where
  does "No move touches the press the spike is tracking, so after any sequence of moves none is in progress."
  holds s := s.pressed = none
  init := rfl
  step := machine.preserves <|
    Move.all_cons (increment.preserves _ fun _ h => h)
      (Move.all_cons (reset.preserves _ fun _ _ h => h) Move.all_nil)

assume ^7 hostClicks "The host reports clicks where they happen" where
  does "The spike host sends a pointer down and up at the logical point the person clicked, in order."

/-- Every claim the counter makes. -/
def claimInfos : List Cairn.ClaimInfo := claims%

/-- What a press on control `^n` does: whatever the move that owns ^n does, if any. -/
def apply (s : State) (n : Nat) : State := (machine.update s (.press { claim := n })).1

example : (apply {} 1).count = 1 := by decide
example : (apply { count := 5 } 2).count = 0 := by decide
example : apply {} 2 = {} := by decide
example : apply { count := 2 } 9 = { count := 2 } := by decide
example : claimInfos.map (·.id) = [1, 2, 3, 4, 5, 6, 7] := by decide

/-- The spike's control ids are exactly the counter's moves. -/
theorem apply_unclaimed (s : State) (n : Nat) (h : n ≠ 1 ∧ n ≠ 2) : apply s n = s := by
  unfold apply
  rw [machine.update_unclaimed]
  intro m hm
  simp only [machine, List.mem_cons, List.not_mem_nil, or_false] at hm
  rcases hm with rfl | rfl
  · show 1 ≠ n; omega
  · show 2 ≠ n; omega

def view (s : State) : List Box :=
  [ { w := 20 * (min s.count 20 : Nat) + 1, h := 20, color := 0x4060ffff,
      label := s!"Count: {s.count}" },
    { w := 160, h := 44, color := 0x30a050ff, claim := some 1, role := .button,
      label := "Increment" } ] ++
  (if resetEnabled s then
    [{ w := 160, h := 44, color := 0xd04040ff, claim := some 2, role := .button,
       label := "Reset" }]
   else [])

def laid (s : State) : List (Rect × Box) := column ⟨40, 40⟩ 16 (view s)

/-- Presence: the control for ^2 is in the frame exactly when reset is enabled. -/
theorem reset_present_iff (s : State) : 2 ∈ claims (laid s) ↔ resetEnabled s = true := by
  unfold laid
  rw [claims_column]
  unfold view
  cases h : resetEnabled s <;> simp

/-- Presence, stated against the move: ^2's control is on screen exactly when the move is
enabled. -/
theorem reset_present_iff_enabled (s : State) : 2 ∈ claims (laid s) ↔ reset.enabled s = true :=
  reset_present_iff s

/-- A click is a press and release on the same control. -/
def handle (s : State) : Event → State
  | .down p => { s with pressed := hitTest (laid s) p }
  | .up p =>
    let hit := hitTest (laid s) p
    let s' := { s with pressed := none }
    if hit.isSome && hit == s.pressed then apply s' (hit.getD 0) else s'
  | .resize w h => { s with width := w, height := h }

@[export cairn_counter_new]
def new (w h : UInt32) : State := { width := w.toNat, height := h.toNat }

@[export cairn_counter_step]
def step (s : State) (events : ByteArray) : State :=
  (decodeEvents events).foldl handle s

@[export cairn_counter_frame]
def frame (s : State) : ByteArray := encode s.width s.height (laid s)

@[export cairn_counter_count]
def count (s : State) : UInt32 := s.count.toUInt32

/-- A benchmark frame: `n` boxes in a column, laid out and encoded. -/
def benchBoxes (n : Nat) : List Box :=
  (List.range n).map fun i =>
    { w := 200, h := 10, color := 0x808080ff, claim := some (i + 1), role := .button,
      label := s!"Row {i}" }

@[export cairn_bench_frame]
def benchFrame (n : UInt32) : ByteArray :=
  encode 800 600 (column ⟨0, 0⟩ 2 (benchBoxes n.toNat))

end Examples.Counter

import Cairn.Spike.Frame

/-! The boundary spike's app: a counter with two moves.

- ^1 Increment: always enabled.
- ^2 Reset: enabled only when the count is above zero. -/

namespace Examples.Counter
open Cairn.Spike

structure State where
  count : Nat := 0
  width : Int := 480
  height : Int := 320
  pressed : Option Nat := none

def resetEnabled (s : State) : Bool := s.count > 0

def apply (s : State) : Nat → State
  | 1 => { s with count := s.count + 1 }
  | 2 => if resetEnabled s then { s with count := 0 } else s
  | _ => s

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

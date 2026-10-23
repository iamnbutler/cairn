module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.App
public import Cairn.Layout.Core

/-! # Counter: two moves on the v1 ABI

The boundary spike's app, now on the interaction runtime like every other app: a bar as long as
the count, the count, Increment, and Reset when there is something to reset. Declared with the
claim commands (docs/claims.md): `update` is `machine.update`, built from the two moves and
nothing else, so a press on anything that is not a control of ^1 or ^2 changes nothing.

| Id | Kind | What |
|---|---|---|
| ^1 | move | Increment: always enabled |
| ^2 | move | Reset: enabled only when the count is above zero |
| ^3 | place | the window |
| ^4, ^5 | flow | count to three; count up, then reset |
| ^6 | invariant | no move leaves a press in progress |
| ^7 | assumption | the host reports clicks where they happen |

Theorems about the view (presence of ^2, pressability) are in `Examples.Counter.Proofs`; runtime
checks in `Examples.Counter.Tests`; the v1 exports in `Examples.Counter.Abi`; the host side is
`host/Sources/CairnCounter`. -/

@[expose] public section

namespace Examples.Counter
open Cairn Cairn.Claims

structure State where
  count : Nat := 0
  /-- A press in progress, as the counter's own state records it. Since the move to the v1
  runtime nothing sets it: the runtime tracks presses itself (`UI.pressed`), and ^6 says no move
  ever leaves one here. Kept because ^6 is stated over it. -/
  pressed : Option Nat := none
deriving Repr, DecidableEq, Inhabited

def resetEnabled (s : State) : Bool := s.count > 0

def incrementRef : ControlRef := ⟨1, 0⟩
def resetRef : ControlRef := ⟨2, 0⟩

place ^3 window "Counter window" where
  does "The counter's window: a bar as long as the count, Increment, and Reset when there is something to reset."

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
  does "No move touches the press the counter's state records, so after any sequence of moves none is in progress."
  holds s := s.pressed = none
  init := rfl
  step := machine.preserves <|
    Move.all_cons (increment.preserves _ fun _ h => h)
      (Move.all_cons (reset.preserves _ fun _ _ h => h) Move.all_nil)

assume ^7 hostClicks "The host reports clicks where they happen" where
  does "The host sends a pointer down and up at the logical point the person clicked, in order."

/-- Every claim the counter makes. -/
def claimInfos : List ClaimInfo := claims%

/-- What a press on control `^n` does: whatever the move that owns ^n does, if any. -/
def apply (s : State) (n : Nat) : State := (machine.update s (.press { claim := n })).1

example : (apply {} 1).count = 1 := by decide
example : (apply { count := 5 } 2).count = 0 := by decide
example : apply {} 2 = {} := by decide
example : apply { count := 2 } 9 = { count := 2 } := by decide
example : claimInfos.map (·.id) = [1, 2, 3, 4, 5, 6, 7] := by decide

/-- The counter's control ids are exactly its moves: a press on any other claim changes
nothing. -/
theorem apply_unclaimed (s : State) (n : Nat) (h : n ≠ 1 ∧ n ≠ 2) : apply s n = s := by
  unfold apply
  rw [machine.update_unclaimed]
  intro m hm
  simp only [machine, List.mem_cons, List.not_mem_nil, or_false] at hm
  rcases hm with rfl | rfl
  · show 1 ≠ n; omega
  · show 2 ≠ n; omega

/-! ## View -/

def bg : Color := ⟨246, 246, 248, 255⟩
def ink : Color := ⟨28, 28, 30, 255⟩
def blue : Color := ⟨64, 96, 255, 255⟩
def green : Color := ⟨48, 160, 80, 255⟩
def greenDark : Color := ⟨36, 128, 62, 255⟩
def red : Color := ⟨208, 64, 64, 255⟩
def redDark : Color := ⟨172, 44, 44, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩
def focusRing : Color := ⟨0, 122, 255, 255⟩

/-- The bar's width: 20 points per count, up to 20. -/
def barWidth (n : Nat) : Nat := 20 * min n 20

def countLabel (n : Nat) : String := s!"Count: {n}"

/-- A 160×44 button for `r`, darker under the pointer, with a ring when it has focus. It clips
its label, so its size never depends on the text (the view is rigid: `Cairn.Layout.FitsIn`). -/
def button (ui : UI) (r : ControlRef) (label : String) (fill hover : Color) : Node :=
  .box { width := .fixed 160, height := .fixed 44, radius := 6, align := .center,
         justify := .center, clip := true,
         background := some (if ui.hover = some r then hover else fill),
         border := if ui.focus = some r then some ⟨2, focusRing⟩ else none }
    (some { ref := r, label := label })
    [.text { font := { size := 15, weight := 600 }, color := white } label]

/-- A bar as long as the count. -/
def bar (n : Nat) : Node :=
  .box { width := .fixed (barWidth n), height := .fixed 20, background := some blue } none []

/-- The count, in a clipped 20-point row. -/
def countRow (n : Nat) : Node :=
  .box { width := .fill, height := .fixed 20, clip := true } none
    [.text { font := { size := 15 }, color := ink } (countLabel n)]

def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨40, 40, 40, 40⟩, gap := 16,
         background := some bg, clip := true } none
    ([ bar s.count,
       countRow s.count,
       button ui incrementRef "Increment" green greenDark ] ++
     (if resetEnabled s then [button ui resetRef "Reset" red redDark] else []))

def app : App State := machine.toApp view claimInfos

end Examples.Counter

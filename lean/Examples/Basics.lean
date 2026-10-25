module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.App
public import Cairn.Text.Field
public import Cairn.Text.Host
public import Cairn.Layout.Core
public import Cairn.Runtime.Abi
public import Cairn.Abi

/-! # Basics: the first app on the v1 ABI

A heading, a wrapped paragraph of instructions, a text field, an Add button, a list of items (each with a checkbox and a delete
button) and a footer counting the items left. Declared with the claim commands
(docs/claims.md): `update` is `machine.update`, built from the four moves and nothing else.

| Id | Kind | What |
|---|---|---|
| ^101 | move | the "New item" field: edits, and Enter adds |
| ^102 | move | Add |
| ^103 | move, keyed | an item's checkbox, `^103#k` for item `k` |
| ^104 | move, keyed | an item's delete button, `^104#k` |
| ^105 | invariant | the count of items left is the number of items not done, ids are unique |
| ^106 | place | the window |
| ^107–^109 | flow | add and finish, blank adds nothing, add then delete |

Item ids start at 1, so keyed controls never use key 0. Theorems about the view (presence,
pressability, the footer) are in `Examples.Basics.Proofs`; runtime checks in
`Examples.Basics.Tests`; the host side is `host/Sources/CairnBasics`. -/

@[expose] public section

namespace Examples.Basics
open Cairn Cairn.Claims

/-- The field's placeholder and accessibility label. -/
def placeholder : String := "New item"

-- region: basics-state
structure Item where
  id : Nat
  text : String
  done : Bool := false
deriving Repr, BEq, DecidableEq, Inhabited

structure State where
  items : List Item := []
  /-- The id the next item gets. -/
  nextId : Nat := 1
  /-- How many items are not done. Kept by the moves (not recomputed by `view`); invariant
  ^105 says it is always right. -/
  left : Nat := 0
  field : Text.Field := Text.Field.empty placeholder
deriving Repr, DecidableEq, Inhabited

def fieldRef : ControlRef := ⟨101, 0⟩
def addRef : ControlRef := ⟨102, 0⟩
def toggleRef (k : Nat) : ControlRef := ⟨103, k⟩
def deleteRef (k : Nat) : ControlRef := ⟨104, k⟩
-- endregion: basics-state

/-! ## The model -/

/-- Whitespace for trimming: the field never holds line breaks, so this is spaces and tabs
(and anything else `Char.isWhitespace` accepts). -/
def isBlank (c : Char) : Bool := c.isWhitespace

/-- The field's text without leading and trailing whitespace. -/
def trimmed (t : List Char) : List Char :=
  ((t.dropWhile isBlank).reverse.dropWhile isBlank).reverse

-- region: basics-add
/-- Add the field's trimmed text as a new item and clear the field; nothing when it's blank. -/
def add (s : State) : State :=
  if trimmed s.field.text = [] then s
  else
    { s with items := s.items ++ [{ id := s.nextId, text := String.ofList (trimmed s.field.text) }],
             nextId := s.nextId + 1, left := s.left + 1,
             field := Text.Field.empty placeholder }

/-- What Add (and Enter in the field) must do: nothing on blank text; otherwise append the
trimmed text as a new, not-done item and clear the field. -/
def Added (s s' : State) : Prop :=
  if trimmed s.field.text = [] then s' = s
  else s'.items = s.items ++ [{ id := s.nextId, text := String.ofList (trimmed s.field.text) }] ∧
    s'.field.text = []

theorem add_added (s : State) : Added s (add s) := by
  unfold Added add
  by_cases h : trimmed s.field.text = []
  · simp only [h, ↓reduceIte]
  · simp only [h, ↓reduceIte]; exact ⟨trivial, rfl⟩
-- endregion: basics-add

/-- Whether item `k` exists. -/
def has (s : State) (k : Nat) : Bool := s.items.any (·.id == k)

def flip (k : Nat) (i : Item) : Item := if i.id = k then { i with done := !i.done } else i

def toggle (k : Nat) (s : State) : State :=
  match s.items.find? (·.id = k) with
  | none => s
  | some it =>
    { s with items := s.items.map (flip k), left := if it.done then s.left + 1 else s.left - 1 }

-- region: basics-delete
def delete (k : Nat) (s : State) : State :=
  match s.items.find? (·.id = k) with
  | none => s
  | some it =>
    { s with items := s.items.filter (·.id ≠ k), left := if it.done then s.left else s.left - 1 }
-- endregion: basics-delete

theorem toggle_items (k : Nat) (s : State) (h : has s k = true) :
    (toggle k s).items = s.items.map (flip k) := by
  unfold toggle
  split
  · rename_i hn
    simp only [has, List.any_eq_true, beq_iff_eq] at h
    obtain ⟨x, hx, rfl⟩ := h
    simp only [List.find?_eq_none, decide_eq_true_eq] at hn
    exact absurd rfl (hn x hx)
  · rfl

theorem delete_items (k : Nat) (s : State) (h : has s k = true) :
    (delete k s).items = s.items.filter (·.id ≠ k) := by
  unfold delete
  split
  · rename_i hn
    simp only [has, List.any_eq_true, beq_iff_eq] at h
    obtain ⟨x, hx, rfl⟩ := h
    simp only [List.find?_eq_none, decide_eq_true_eq] at hn
    exact absurd rfl (hn x hx)
  · rfl

/-! ## The invariant's pieces -/

/-- The number of items not done. -/
def undone : List Item → Nat
  | [] => 0
  | i :: is => (if i.done then 0 else 1) + undone is

/-- Ids strictly increase along the list, starting above `lo` (so they are distinct). -/
def Ascending (lo : Nat) : List Item → Prop
  | [] => True
  | i :: is => lo < i.id ∧ Ascending i.id is

/-- `Ascending` is decidable, so ^105 gets a runnable `check` (docs/fuzz.md). -/
instance Ascending.decidable : (lo : Nat) → (xs : List Item) → Decidable (Ascending lo xs)
  | _, [] => isTrue trivial
  | lo, i :: is =>
    have := Ascending.decidable i.id is
    inferInstanceAs (Decidable (lo < i.id ∧ Ascending i.id is))

-- region: basics-inv
/-- ^105's statement: the count is right, and ids are distinct, positive and below `nextId`
(which is positive). -/
def Inv (s : State) : Prop :=
  s.left = undone s.items ∧ Ascending 0 s.items ∧ (∀ i ∈ s.items, i.id < s.nextId) ∧ 0 < s.nextId
-- endregion: basics-inv

theorem undone_append (xs ys : List Item) : undone (xs ++ ys) = undone xs + undone ys := by
  induction xs with
  | nil => simp [undone]
  | cons x xs ih => simp only [List.cons_append, undone, ih]; omega

theorem Ascending.lt : ∀ {lo : Nat} {xs : List Item}, Ascending lo xs → ∀ j ∈ xs, lo < j.id
  | _, [], _, j, hj => by simp at hj
  | _, x :: xs, ⟨h1, h2⟩, j, hj => by
    rcases List.mem_cons.mp hj with rfl | hj
    · exact h1
    · exact Nat.lt_trans h1 (Ascending.lt h2 j hj)

theorem Ascending.mono : ∀ {a b : Nat} {xs : List Item}, b ≤ a → Ascending a xs → Ascending b xs
  | _, _, [], _, _ => trivial
  | _, _, _ :: _, hab, ⟨h1, h2⟩ => ⟨Nat.lt_of_le_of_lt hab h1, h2⟩

theorem Ascending.append : ∀ {lo : Nat} {xs : List Item} {y : Item},
    Ascending lo xs → lo < y.id → (∀ j ∈ xs, j.id < y.id) → Ascending lo (xs ++ [y])
  | _, [], _, _, hy, _ => ⟨hy, trivial⟩
  | _, x :: xs, y, ⟨h1, h2⟩, _, hall => by
    refine ⟨h1, Ascending.append h2 (hall x (List.mem_cons_self ..)) fun j hj => ?_⟩
    exact hall j (List.mem_cons_of_mem _ hj)

theorem Ascending.filter (p : Item → Bool) : ∀ {lo : Nat} {xs : List Item},
    Ascending lo xs → Ascending lo (xs.filter p)
  | _, [], _ => trivial
  | _, x :: xs, ⟨h1, h2⟩ => by
    simp only [List.filter_cons]
    split
    · exact ⟨h1, Ascending.filter p h2⟩
    · exact Ascending.filter p (Ascending.mono (Nat.le_of_lt h1) h2)

theorem flip_id (k : Nat) (i : Item) : (flip k i).id = i.id := by
  unfold flip; split <;> rfl

theorem Ascending.map_flip (k : Nat) : ∀ {lo : Nat} {xs : List Item},
    Ascending lo xs → Ascending lo (xs.map (flip k))
  | _, [], _ => trivial
  | _, x :: xs, ⟨h1, h2⟩ => by
    refine ⟨by rw [flip_id]; exact h1, ?_⟩
    rw [flip_id]; exact Ascending.map_flip k h2

theorem map_flip_of_lt (k : Nat) : ∀ (xs : List Item), (∀ j ∈ xs, k < j.id) → xs.map (flip k) = xs
  | [], _ => rfl
  | x :: xs, h => by
    have hx : x.id ≠ k := Nat.ne_of_gt (h x (List.mem_cons_self ..))
    simp only [List.map_cons, flip, hx, ↓reduceIte,
      map_flip_of_lt k xs fun j hj => h j (List.mem_cons_of_mem _ hj)]

theorem filter_of_lt (k : Nat) : ∀ (xs : List Item), (∀ j ∈ xs, k < j.id) →
    xs.filter (fun i => decide (i.id ≠ k)) = xs
  | [], _ => rfl
  | x :: xs, h => by
    have hx : x.id ≠ k := Nat.ne_of_gt (h x (List.mem_cons_self ..))
    simp only [List.filter_cons, hx, ne_eq, not_false_eq_true, decide_true, ↓reduceIte,
      filter_of_lt k xs fun j hj => h j (List.mem_cons_of_mem _ hj)]

theorem undone_toggle (k : Nat) : ∀ {lo : Nat} {xs : List Item} {it : Item}, Ascending lo xs →
    xs.find? (fun i => decide (i.id = k)) = some it →
    undone (xs.map (flip k)) + (if it.done then 0 else 1) = undone xs + (if it.done then 1 else 0)
  | _, [], _, _, h => by simp at h
  | _, x :: xs, it, ⟨_, h2⟩, h => by
    by_cases hx : x.id = k
    · rw [List.find?_cons_of_pos (by simpa using hx), Option.some.injEq] at h
      subst h
      have hrest := map_flip_of_lt k xs (hx ▸ Ascending.lt h2)
      simp only [List.map_cons, flip, hx, ↓reduceIte, undone, hrest]
      cases x.done <;> simp <;> omega
    · rw [List.find?_cons_of_neg (by simpa using hx)] at h
      have ih := undone_toggle k h2 h
      simp only [List.map_cons, flip, hx, ↓reduceIte, undone]
      omega

theorem undone_delete (k : Nat) : ∀ {lo : Nat} {xs : List Item} {it : Item}, Ascending lo xs →
    xs.find? (fun i => decide (i.id = k)) = some it →
    undone (xs.filter (fun i => decide (i.id ≠ k))) + (if it.done then 0 else 1) = undone xs
  | _, [], _, _, h => by simp at h
  | _, x :: xs, it, ⟨_, h2⟩, h => by
    by_cases hx : x.id = k
    · rw [List.find?_cons_of_pos (by simpa using hx), Option.some.injEq] at h
      subst h
      have hrest := filter_of_lt k xs (hx ▸ Ascending.lt h2)
      simp only [List.filter_cons, hx, ne_eq, not_true_eq_false, decide_false, Bool.false_eq_true,
        ↓reduceIte, hrest, undone]
      omega
    · rw [List.find?_cons_of_neg (by simpa using hx)] at h
      have ih := undone_delete k h2 h
      rw [List.filter_cons_of_pos (by simpa using hx)]
      simp only [undone]
      omega

theorem add_inv {s : State} (h : Inv s) : Inv (add s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  unfold add
  by_cases ht : trimmed s.field.text = []
  · simp only [ht, ↓reduceIte]; exact ⟨hl, ha, hb, hn⟩
  · simp only [ht, ↓reduceIte]
    refine ⟨?_, Ascending.append ha hn hb, ?_, Nat.succ_pos _⟩
    · simp only [undone_append, undone, Bool.false_eq_true, ↓reduceIte]; omega
    · intro i hi
      simp only [List.mem_append, List.mem_singleton] at hi
      rcases hi with hi | rfl
      · exact Nat.lt_succ_of_lt (hb i hi)
      · exact Nat.lt_succ_self _

theorem toggle_inv (k : Nat) {s : State} (h : Inv s) : Inv (toggle k s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  unfold toggle
  split
  · exact ⟨hl, ha, hb, hn⟩
  · rename_i it hf
    have hu := undone_toggle k ha hf
    refine ⟨?_, Ascending.map_flip k ha, ?_, hn⟩
    · show (if it.done then s.left + 1 else s.left - 1) = _
      cases hd : it.done <;> simp only [hd, Bool.false_eq_true, ↓reduceIte] at hu ⊢ <;> omega
    · intro i hi
      obtain ⟨j, hj, rfl⟩ := List.mem_map.mp hi
      rw [flip_id]; exact hb j hj

theorem delete_inv (k : Nat) {s : State} (h : Inv s) : Inv (delete k s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  unfold delete
  split
  · exact ⟨hl, ha, hb, hn⟩
  · rename_i it hf
    have hu := undone_delete k ha hf
    refine ⟨?_, Ascending.filter _ ha, ?_, hn⟩
    · show (if it.done then s.left else s.left - 1) = _
      cases hd : it.done <;> simp only [hd, Bool.false_eq_true, ↓reduceIte] at hu ⊢ <;> omega
    · intro i hi
      exact hb i (List.mem_filter.mp hi).1

/-! ## Claims -/

place ^106 window "Basics window" where
  does "The window: a heading, the New item field and Add, the list of items, and the count of items left."

-- region: basics-type-item
move ^101 typeItem (s : State) "Type a new item" in ^106 where
  does "Type in the New item field, and press Enter."
  sees "The text appears in the field; Enter adds it like Add does."
  on edit (op : TextOp)
    emit := ({ s with field := (Text.Field.apply op s.field).1 }, (Text.Field.apply op s.field).2)
    post s' := s'.field = (Text.Field.apply op s.field).1 ∧ s'.items = s.items ∧
      s'.left = s.left ∧ s'.nextId = s.nextId
    sound := by intro s op; exact ⟨rfl, rfl, rfl, rfl⟩
  on submit
    apply := add s
    post s' := Added s s'
    sound := by intro s; exact add_added s
-- endregion: basics-type-item

move ^102 addItem (s : State) "Add" in ^106 where
  does "Press Add."
  sees "The field's text, trimmed, is added at the end of the list and the field is cleared. Blank text changes nothing."
  on press
    apply := add s
    post s' := Added s s'
    sound := by intro s; exact add_added s

-- region: basics-toggle
move ^103 toggleItem (s : State) (k : Nat) "Toggle an item" in ^106 where
  does "Press an item's checkbox."
  sees "The item is marked done, or not done again, and the count of items left follows."
  enabled := has s k
  on press
    apply := toggle k s
    post s' := s'.items = s.items.map (flip k)
    sound := by intro s k h; exact toggle_items k s h
-- endregion: basics-toggle

move ^104 deleteItem (s : State) (k : Nat) "Delete an item" in ^106 where
  does "Press an item's delete button."
  sees "The item is gone, and its checkbox and delete button with it."
  enabled := has s k
  on press
    apply := delete k s
    post s' := s'.items = s.items.filter (·.id ≠ k)
    sound := by intro s k h; exact delete_items k s h

/-- Basics' behaviour: its four moves, from an empty list. -/
def machine : Machine State := { init := {}, moves := moves% }

-- region: basics-invariant
invariant ^105 itemsLeft "Items left" for machine where
  does "The footer's count equals the number of items not done, and item ids stay distinct, in every reachable state."
  holds s := Inv s
  init := ⟨rfl, trivial, fun _ h => by simp only [machine, List.not_mem_nil] at h, Nat.one_pos⟩
  step := machine.preserves <|
    Move.all_cons (typeItem.preserves _ (fun _ _ h => h) fun _ h => add_inv h)
      (Move.all_cons (addItem.preserves _ fun _ h => add_inv h)
      (Move.all_cons (toggleItem.preserves _ fun _ k _ h => toggle_inv k h)
      (Move.all_cons (deleteItem.preserves _ fun _ k _ h => delete_inv k h) Move.all_nil)))
-- endregion: basics-invariant

-- region: basics-flows
flow ^107 addAndFinish "Add two items and finish one" for machine where
  does "Type milk and press Enter, type eggs and press Add, then check milk."
  sees "Two items, milk done, and one item left."
  goal s := s.items.map (·.text) = ["milk", "eggs"] ∧ s.items.map (·.done) = [true, false] ∧
    s.left = 1
  witness edit ^101 (.insert "milk"), submit ^101, edit ^101 (.insert " eggs "), press ^102,
    press ^103#1

flow ^108 blankAddsNothing "Blank text adds nothing" for machine where
  does "Type spaces, then press Enter and Add."
  sees "The list stays empty."
  goal s := s.items = [] ∧ s.left = 0
  witness edit ^101 (.insert "   "), submit ^101, press ^102

flow ^109 addThenDelete "Add an item, then delete it" for machine where
  does "Type milk, press Add, then press milk's delete button."
  sees "The list is empty again, and nothing is left."
  goal s := s.items = [] ∧ s.left = 0 ∧ s.nextId = 2
  witness edit ^101 (.insert "milk"), press ^102, press ^104#1
-- endregion: basics-flows

/-- Every claim Basics makes. -/
def claimInfos : List ClaimInfo := claims%

example : claimInfos.map (·.id) = [101, 102, 103, 104, 105, 106, 107, 108, 109] := by decide

/-! ## View -/

def bg : Color := ⟨246, 246, 248, 255⟩
def ink : Color := ⟨28, 28, 30, 255⟩
def muted : Color := ⟨120, 120, 128, 255⟩
def accent : Color := ⟨0, 122, 255, 255⟩
def accentDark : Color := ⟨0, 96, 214, 255⟩
def line : Color := ⟨206, 206, 212, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩

def body : Font := { size := 15 }

/-- A focus ring when `r` has keyboard focus. -/
def ring (ui : UI) (r : ControlRef) (otherwise : Option Border := none) : Option Border :=
  if ui.focus = some r then some ⟨2, accent⟩ else otherwise

def leftLabel (n : Nat) : String := if n = 1 then "1 item left" else s!"{n} items left"

def heading : Node := .text { font := { size := 22, weight := 700 }, color := ink } "Basics"

-- region: basics-intro
/-- Wrapped text (`Node.para`): Lean breaks it to the window's width, so it rewraps as the
window resizes. -/
def intro : Node :=
  .para { font := { size := 13 }, color := muted } {}
    "Type an item and press Enter or Add. Check an item off when it is done, or delete it. \
     This paragraph is broken into lines by Lean, from Core Text's measurement of the whole \
     string, so it rewraps as the window resizes."
-- endregion: basics-intro

-- region: basics-input-row
def inputRow (s : State) (ui : UI) : Node :=
  .box { axis := .row, width := .fill, gap := 8, align := .center } none
    [ .field { width := .fill, padding := ⟨6, 8, 6, 8⟩, background := some white, radius := 6,
               border := ring ui fieldRef (some ⟨1, line⟩) }
        { font := body, color := ink }
        { ref := fieldRef, role := .textField, label := placeholder }
        (s.field.view (ui.focus = some fieldRef)),
      .box { padding := ⟨6, 16, 6, 16⟩, radius := 6, border := ring ui addRef,
             background := some (if ui.hover = some addRef then accentDark else accent) }
        (some { ref := addRef, label := "Add" })
        [.text { font := { body with weight := 600 }, color := white } "Add"] ]
-- endregion: basics-input-row

def itemRow (ui : UI) (it : Item) : Node :=
  .box { axis := .row, width := .fill, height := .fixed 36, gap := 10, align := .center,
         padding := ⟨0, 8, 0, 10⟩, background := some white, radius := 6 } none
    [ .box { width := .fixed 18, height := .fixed 18, radius := 4, align := .center,
             justify := .center,
             background := some (if it.done then accent else white),
             border := ring ui (toggleRef it.id) (if it.done then none else some ⟨1, line⟩) }
        (some { ref := toggleRef it.id, role := .checkbox, label := it.text,
                checked := some it.done })
        (if it.done then [.text { font := { size := 12, weight := 700 }, color := white } "✓"]
         else []),
      .text { font := body, color := if it.done then muted else ink } it.text,
      .box { width := .fill } none [],
      .box { padding := ⟨3, 8, 3, 8⟩, radius := 4, border := ring ui (deleteRef it.id),
             background := some (if ui.hover = some (deleteRef it.id) then ⟨255, 226, 226, 255⟩
                                 else ⟨240, 240, 242, 255⟩) }
        (some { ref := deleteRef it.id, label := s!"Delete {it.text}" })
        [.text { font := { size := 13 }, color := ⟨200, 40, 40, 255⟩ } "Delete"] ]

def footer (s : State) : String := leftLabel s.left

-- region: basics-view
def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨20, 20, 20, 20⟩, gap := 12,
         background := some bg, clip := true } none
    [ heading,
      intro,
      inputRow s ui,
      .box { width := .fill, gap := 4 } none (s.items.map (itemRow ui)),
      .text { font := { size := 13 }, color := muted } (footer s) ]
-- endregion: basics-view

def app : App State := machine.toApp [.window 106 "Basics" view] claimInfos

/-! ## The app ABI (docs/runtime.md) -/

/-- Core Text metrics in the running app (the Swift host links `cairn_text_metrics`). -/
def cfg : Runtime.Config := { metrics := TextMetrics.host }

@[export cairn_app_init]
def appInit (w h scalePercent : UInt32) : Runtime.State State :=
  Runtime.initState app cfg w h scalePercent

@[export cairn_app_step]
def appStep (s : Runtime.State State) (events : ByteArray) : Runtime.State State :=
  Runtime.stepBytes app cfg Frame.boundary s events

@[export cairn_app_frame]
def appFrame (s : Runtime.State State) : ByteArray := Runtime.frameBytes Frame.boundary s

end Examples.Basics

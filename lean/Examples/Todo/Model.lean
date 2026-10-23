module

public import Cairn.Text.Field

/-! # TodoMVC: the model

The state and what each move does to it, with no view and no claims; `Examples.Todo`
declares the claims over these functions. The lemmas here are what the invariant ^212 needs:
the cached count of active todos stays right, and todo ids stay strictly increasing (so
distinct) and below `nextId`. -/

@[expose] public section

namespace Examples.Todo
open Cairn

/-- The new-todo field's placeholder (T3). -/
def newPlaceholder : String := "What needs to be done?"

structure Todo where
  id : Nat
  title : String
  completed : Bool := false
deriving Repr, BEq, DecidableEq, Inhabited

/-- The three filters, in the order the footer shows them (T39). -/
inductive Filter where
  | all | active | completed
deriving Repr, BEq, DecidableEq, Inhabited

/-- Which todos a filter lists (T40). -/
def Filter.shows : Filter → Todo → Bool
  | .all, _ => true
  | .active, t => !t.completed
  | .completed, t => t.completed

def Filter.label : Filter → String
  | .all => "All"
  | .active => "Active"
  | .completed => "Completed"

/-- The todo being edited and its edit field. One `Option` in the state, so at most one todo is
ever in edit mode (T26). -/
structure Editing where
  id : Nat
  field : Text.Field
deriving Repr, DecidableEq, Inhabited

structure State where
  todos : List Todo := []
  /-- The id the next todo gets; ids are never reused (T24). -/
  nextId : Nat := 1
  /-- How many todos are active. Kept by the moves, not recomputed by the view; invariant ^212
  says it is always right. -/
  left : Nat := 0
  filter : Filter := .all
  newField : Text.Field := Text.Field.empty newPlaceholder
  editing : Option Editing := none
deriving Repr, DecidableEq, Inhabited

/-! ## Queries -/

/-- The todos the current filter lists, in creation order (T40). -/
def visible (s : State) : List Todo := s.todos.filter s.filter.shows

/-- Todo `k` exists and the filter lists it. -/
def shown (s : State) (k : Nat) : Bool := (visible s).any (·.id == k)

def editingId (s : State) : Option Nat := s.editing.map (·.id)

/-- Todo `k` is listed and in edit mode. -/
def isEditing (s : State) (k : Nat) : Bool := decide (editingId s = some k)

/-- Every todo is completed (toggle-all reads checked, T15). -/
def allDone (s : State) : Bool := s.todos.all (·.completed)

/-- Some todo is completed (Clear completed is shown, T37). -/
def anyDone (s : State) : Bool := s.todos.any (·.completed)

/-- The number of active todos. -/
def active : List Todo → Nat
  | [] => 0
  | t :: ts => (if t.completed then 0 else 1) + active ts

/-! ## Moves -/

def isBlank (c : Char) : Bool := c.isWhitespace

/-- Text without leading and trailing whitespace. -/
def trimmed (t : List Char) : List Char :=
  ((t.dropWhile isBlank).reverse.dropWhile isBlank).reverse

/-- Enter in the new-todo field: append the trimmed text as an active todo and clear the field;
nothing at all when it is blank (T6–T8). -/
def add (s : State) : State :=
  if trimmed s.newField.text = [] then s
  else
    { s with todos := s.todos ++ [{ id := s.nextId, title := String.ofList (trimmed s.newField.text) }],
             nextId := s.nextId + 1, left := s.left + 1,
             newField := Text.Field.empty newPlaceholder }

def setDone (v : Bool) (t : Todo) : Todo := { t with completed := v }

/-- Mark every todo completed, or every todo active when all are completed already (T16). -/
def toggleAll (s : State) : State :=
  let v := !allDone s
  { s with todos := s.todos.map (setDone v), left := if v then 0 else s.todos.length }

def flip (k : Nat) (t : Todo) : Todo := if t.id = k then { t with completed := !t.completed } else t

def toggle (k : Nat) (s : State) : State :=
  match s.todos.find? (·.id = k) with
  | none => s
  | some t =>
    { s with todos := s.todos.map (flip k), left := if t.completed then s.left + 1 else s.left - 1 }

def delete (k : Nat) (s : State) : State :=
  match s.todos.find? (·.id = k) with
  | none => s
  | some t =>
    { s with todos := s.todos.filter (·.id ≠ k),
             left := if t.completed then s.left else s.left - 1 }

/-- Enter edit mode for todo `k`, with its title in the edit field (T20, T25). -/
def startEdit (k : Nat) (s : State) : State :=
  match s.todos.find? (·.id = k) with
  | none => s
  | some t => { s with editing := some { id := k, field := Text.Field.ofString t.title } }

/-- A text operation in the edit field. -/
def editApply (op : TextOp) (s : State) : State × List Effect :=
  match s.editing with
  | some e =>
    ({ s with editing := some { e with field := (Text.Field.apply op e.field).1 } },
     (Text.Field.apply op e.field).2)
  | none => (s, [])

def rename (k : Nat) (title : String) (t : Todo) : Todo :=
  if t.id = k then { t with title } else t

/-- Leave edit mode keeping the edit: the trimmed text becomes the title, and blank text deletes
the todo (T28–T30). -/
def commit (s : State) : State :=
  match s.editing with
  | none => s
  | some e =>
    if trimmed e.field.text = [] then { delete e.id s with editing := none }
    else { s with todos := s.todos.map (rename e.id (String.ofList (trimmed e.field.text))),
                  editing := none }

/-- Leave edit mode discarding the edit (T31). -/
def cancel (s : State) : State := { s with editing := none }

def setFilter (f : Filter) (s : State) : State := { s with filter := f }

/-- Remove every completed todo, over all todos, keeping the rest in order (T38). -/
def clearCompleted (s : State) : State := { s with todos := s.todos.filter (!·.completed) }

/-! ## What the moves do, as statements -/

/-- What Enter in the new-todo field must do (T6–T9, T11). -/
def Added (s s' : State) : Prop :=
  if trimmed s.newField.text = [] then s' = s
  else s'.todos = s.todos ++ [{ id := s.nextId, title := String.ofList (trimmed s.newField.text) }] ∧
    s'.newField.text = [] ∧ s'.filter = s.filter ∧ s'.editing = s.editing

theorem add_added (s : State) : Added s (add s) := by
  unfold Added add
  by_cases h : trimmed s.newField.text = []
  · simp only [h, ↓reduceIte]
  · simp only [h, ↓reduceIte]; exact ⟨trivial, rfl, trivial, trivial⟩

/-- What committing an edit of todo `k` must do (T28–T30): the title becomes the trimmed text,
or the todo is deleted when that is blank; edit mode ends; nothing else changes. -/
def Committed (k : Nat) (s s' : State) : Prop :=
  ∀ e, s.editing = some e →
    (if trimmed e.field.text = [] then s'.todos = s.todos.filter (·.id ≠ k)
     else s'.todos = s.todos.map (rename k (String.ofList (trimmed e.field.text)))) ∧
    s'.editing = none ∧ s'.newField = s.newField ∧ s'.filter = s.filter

/-- Whether todo `k` exists. -/
def has (s : State) (k : Nat) : Bool := s.todos.any (·.id == k)

theorem find_some_of_has {s : State} {k : Nat} (h : has s k = true) :
    ∃ t, s.todos.find? (fun t => decide (t.id = k)) = some t := by
  simp only [has, List.any_eq_true, beq_iff_eq] at h
  obtain ⟨x, hx, rfl⟩ := h
  cases hf : s.todos.find? (fun t => decide (t.id = x.id)) with
  | none =>
    simp only [List.find?_eq_none, decide_eq_true_eq] at hf
    exact absurd rfl (hf x hx)
  | some t => exact ⟨t, rfl⟩

theorem toggle_todos (k : Nat) (s : State) (h : has s k = true) :
    (toggle k s).todos = s.todos.map (flip k) := by
  obtain ⟨t, ht⟩ := find_some_of_has h
  unfold toggle; rw [ht]

theorem delete_todos (k : Nat) (s : State) (h : has s k = true) :
    (delete k s).todos = s.todos.filter (·.id ≠ k) := by
  obtain ⟨t, ht⟩ := find_some_of_has h
  unfold delete; rw [ht]

theorem delete_frame (k : Nat) (s : State) :
    (delete k s).newField = s.newField ∧ (delete k s).filter = s.filter ∧
      (delete k s).editing = s.editing ∧ (delete k s).nextId = s.nextId := by
  unfold delete; split <;> exact ⟨rfl, rfl, rfl, rfl⟩

theorem toggle_frame (k : Nat) (s : State) :
    (toggle k s).newField = s.newField ∧ (toggle k s).filter = s.filter ∧
      (toggle k s).editing = s.editing ∧ (toggle k s).nextId = s.nextId := by
  unfold toggle; split <;> exact ⟨rfl, rfl, rfl, rfl⟩

theorem has_of_find {s : State} {k : Nat} {t : Todo}
    (h : s.todos.find? (fun t => decide (t.id = k)) = some t) : t ∈ s.todos ∧ t.id = k := by
  have hm := List.mem_of_find?_eq_some h
  have hp := List.find?_some h
  simp only [decide_eq_true_eq] at hp
  exact ⟨hm, hp⟩

/-- What a double-click on todo `k`'s title must do (T25, T27): edit mode for `k` with its title
in the field, and nothing else changes. -/
def Started (k : Nat) (s s' : State) : Prop :=
  ∃ t ∈ s.todos, t.id = k ∧ s'.editing = some { id := k, field := Text.Field.ofString t.title } ∧
    s'.todos = s.todos ∧ s'.left = s.left ∧ s'.filter = s.filter ∧ s'.newField = s.newField

theorem startEdit_started (k : Nat) (s : State) (h : has s k = true) : Started k s (startEdit k s) := by
  obtain ⟨t, ht⟩ := find_some_of_has h
  obtain ⟨hm, hk⟩ := has_of_find ht
  unfold startEdit; rw [ht]
  exact ⟨t, hm, hk, rfl, rfl, rfl, rfl, rfl⟩

theorem commit_committed (k : Nat) (s : State) (h : editingId s = some k) :
    Committed k s (commit s) := by
  intro e he
  have hk : e.id = k := by simp only [editingId, he, Option.map_some, Option.some.injEq] at h; exact h
  subst hk
  unfold commit; rw [he]
  by_cases hb : trimmed e.field.text = []
  · simp only [hb, ↓reduceIte]
    obtain ⟨h1, h2, -, -⟩ := delete_frame e.id s
    refine ⟨?_, trivial, h1, h2⟩
    unfold delete; split
    · rename_i hn
      -- No such todo: filtering it out changes nothing.
      simp only [List.find?_eq_none, decide_eq_true_eq] at hn
      exact (List.filter_eq_self.2 fun t ht => by simpa using hn t ht).symm
    · rfl
  · simp only [hb, ↓reduceIte]; exact ⟨trivial, trivial, trivial, trivial⟩

theorem has_of_shown {s : State} {k : Nat} (h : shown s k = true) : has s k = true := by
  simp only [shown, visible, List.any_eq_true, List.mem_filter, beq_iff_eq] at h
  obtain ⟨t, ⟨ht, -⟩, rfl⟩ := h
  simp only [has, List.any_eq_true, beq_iff_eq]; exact ⟨t, ht, rfl⟩

theorem editApply_post (op : TextOp) (s : State) :
    (∀ e, s.editing = some e →
        (editApply op s).1.editing = some { e with field := (Text.Field.apply op e.field).1 }) ∧
      (editApply op s).1.todos = s.todos ∧ (editApply op s).1.left = s.left ∧
      (editApply op s).1.newField = s.newField ∧ (editApply op s).1.filter = s.filter := by
  unfold editApply
  split
  · rename_i e he
    refine ⟨fun e' he' => ?_, rfl, rfl, rfl, rfl⟩
    rw [he] at he'; cases he'; rfl
  · rename_i he
    refine ⟨fun e he' => ?_, rfl, rfl, rfl, rfl⟩
    rw [he] at he'; cases he'

/-! ## The invariant's pieces -/

/-- Ids strictly increase along the list, starting above `lo` (so they are distinct). -/
def Ascending (lo : Nat) : List Todo → Prop
  | [] => True
  | t :: ts => lo < t.id ∧ Ascending t.id ts

/-- ^212's statement: the count of active todos is right, and ids are distinct, positive and
below `nextId`. -/
def Inv (s : State) : Prop :=
  s.left = active s.todos ∧ Ascending 0 s.todos ∧ (∀ t ∈ s.todos, t.id < s.nextId) ∧ 0 < s.nextId

theorem active_append (xs ys : List Todo) : active (xs ++ ys) = active xs + active ys := by
  induction xs with
  | nil => simp only [List.nil_append, active, Nat.zero_add]
  | cons x xs ih => simp only [List.cons_append, active, ih]; omega

theorem Ascending.lt : ∀ {lo : Nat} {xs : List Todo}, Ascending lo xs → ∀ j ∈ xs, lo < j.id
  | _, [], _, j, hj => by simp only [List.not_mem_nil] at hj
  | _, x :: xs, ⟨h1, h2⟩, j, hj => by
    rcases List.mem_cons.mp hj with rfl | hj
    · exact h1
    · exact Nat.lt_trans h1 (Ascending.lt h2 j hj)

theorem Ascending.mono : ∀ {a b : Nat} {xs : List Todo}, b ≤ a → Ascending a xs → Ascending b xs
  | _, _, [], _, _ => trivial
  | _, _, _ :: _, hab, ⟨h1, h2⟩ => ⟨Nat.lt_of_le_of_lt hab h1, h2⟩

theorem Ascending.append : ∀ {lo : Nat} {xs : List Todo} {y : Todo},
    Ascending lo xs → lo < y.id → (∀ j ∈ xs, j.id < y.id) → Ascending lo (xs ++ [y])
  | _, [], _, _, hy, _ => ⟨hy, trivial⟩
  | _, x :: xs, y, ⟨h1, h2⟩, _, hall => by
    refine ⟨h1, Ascending.append h2 (hall x (List.mem_cons_self ..)) fun j hj => ?_⟩
    exact hall j (List.mem_cons_of_mem _ hj)

theorem Ascending.filter (p : Todo → Bool) : ∀ {lo : Nat} {xs : List Todo},
    Ascending lo xs → Ascending lo (xs.filter p)
  | _, [], _ => trivial
  | _, x :: xs, ⟨h1, h2⟩ => by
    simp only [List.filter_cons]
    split
    · exact ⟨h1, Ascending.filter p h2⟩
    · exact Ascending.filter p (Ascending.mono (Nat.le_of_lt h1) h2)

/-- A map that keeps every id keeps the list ascending. -/
theorem Ascending.map (f : Todo → Todo) (hf : ∀ t, (f t).id = t.id) : ∀ {lo : Nat} {xs : List Todo},
    Ascending lo xs → Ascending lo (xs.map f)
  | _, [], _ => trivial
  | _, x :: xs, ⟨h1, h2⟩ => by
    refine ⟨by rw [hf]; exact h1, ?_⟩
    rw [hf]; exact Ascending.map f hf h2

theorem flip_id (k : Nat) (t : Todo) : (flip k t).id = t.id := by
  unfold flip; split <;> rfl

theorem rename_id (k : Nat) (title : String) (t : Todo) : (rename k title t).id = t.id := by
  unfold rename; split <;> rfl

theorem rename_completed (k : Nat) (title : String) (t : Todo) :
    (rename k title t).completed = t.completed := by
  unfold rename; split <;> rfl

theorem map_flip_of_lt (k : Nat) : ∀ (xs : List Todo), (∀ j ∈ xs, k < j.id) → xs.map (flip k) = xs
  | [], _ => rfl
  | x :: xs, h => by
    have hx : x.id ≠ k := Nat.ne_of_gt (h x (List.mem_cons_self ..))
    simp only [List.map_cons, flip, hx, ↓reduceIte,
      map_flip_of_lt k xs fun j hj => h j (List.mem_cons_of_mem _ hj)]

theorem filter_of_lt (k : Nat) : ∀ (xs : List Todo), (∀ j ∈ xs, k < j.id) →
    xs.filter (fun t => decide (t.id ≠ k)) = xs
  | [], _ => rfl
  | x :: xs, h => by
    have hx : x.id ≠ k := Nat.ne_of_gt (h x (List.mem_cons_self ..))
    simp only [List.filter_cons, hx, ne_eq, not_false_eq_true, decide_true, ↓reduceIte,
      filter_of_lt k xs fun j hj => h j (List.mem_cons_of_mem _ hj)]

theorem active_toggle (k : Nat) : ∀ {lo : Nat} {xs : List Todo} {it : Todo}, Ascending lo xs →
    xs.find? (fun t => decide (t.id = k)) = some it →
    active (xs.map (flip k)) + (if it.completed then 0 else 1) =
      active xs + (if it.completed then 1 else 0)
  | _, [], _, _, h => by simp only [List.find?_nil, reduceCtorEq] at h
  | _, x :: xs, it, ⟨_, h2⟩, h => by
    by_cases hx : x.id = k
    · rw [List.find?_cons_of_pos (by simpa using hx), Option.some.injEq] at h
      subst h
      have hrest := map_flip_of_lt k xs (hx ▸ Ascending.lt h2)
      simp only [List.map_cons, flip, hx, ↓reduceIte, active, hrest]
      cases x.completed <;> simp only [Bool.not_false, Bool.not_true, ↓reduceIte,
        Bool.false_eq_true] <;> omega
    · rw [List.find?_cons_of_neg (by simpa using hx)] at h
      have ih := active_toggle k h2 h
      simp only [List.map_cons, flip, hx, ↓reduceIte, active]
      omega

theorem active_delete (k : Nat) : ∀ {lo : Nat} {xs : List Todo} {it : Todo}, Ascending lo xs →
    xs.find? (fun t => decide (t.id = k)) = some it →
    active (xs.filter (fun t => decide (t.id ≠ k))) + (if it.completed then 0 else 1) = active xs
  | _, [], _, _, h => by simp only [List.find?_nil, reduceCtorEq] at h
  | _, x :: xs, it, ⟨_, h2⟩, h => by
    by_cases hx : x.id = k
    · rw [List.find?_cons_of_pos (by simpa using hx), Option.some.injEq] at h
      subst h
      have hrest := filter_of_lt k xs (hx ▸ Ascending.lt h2)
      simp only [List.filter_cons, hx, ne_eq, not_true_eq_false, decide_false, Bool.false_eq_true,
        ↓reduceIte, hrest, active]
      omega
    · rw [List.find?_cons_of_neg (by simpa using hx)] at h
      have ih := active_delete k h2 h
      rw [List.filter_cons_of_pos (by simpa using hx)]
      simp only [active]
      omega

theorem active_setDone (v : Bool) : ∀ xs : List Todo,
    active (xs.map (setDone v)) = if v then 0 else xs.length
  | [] => by cases v <;> rfl
  | x :: xs => by
    simp only [List.map_cons, active, setDone, active_setDone v xs, List.length_cons]
    cases v <;> simp only [Bool.false_eq_true, ↓reduceIte] <;> omega

theorem active_rename (k : Nat) (title : String) : ∀ xs : List Todo,
    active (xs.map (rename k title)) = active xs
  | [] => rfl
  | x :: xs => by
    simp only [List.map_cons, active, rename_completed, active_rename k title xs]

theorem active_clear : ∀ xs : List Todo, active (xs.filter (!·.completed)) = active xs
  | [] => rfl
  | x :: xs => by
    cases h : x.completed
    · rw [List.filter_cons_of_pos (by simp [h])]
      simp only [active, h, active_clear xs]
    · rw [List.filter_cons_of_neg (by simp [h])]
      simp only [active, h, active_clear xs, ↓reduceIte, Nat.zero_add]

theorem add_inv {s : State} (h : Inv s) : Inv (add s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  unfold add
  by_cases ht : trimmed s.newField.text = []
  · simp only [ht, ↓reduceIte]; exact ⟨hl, ha, hb, hn⟩
  · simp only [ht, ↓reduceIte]
    refine ⟨?_, Ascending.append ha hn hb, ?_, Nat.succ_pos _⟩
    · simp only [active_append, active, Bool.false_eq_true, ↓reduceIte]; omega
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
    have hu := active_toggle k ha hf
    refine ⟨?_, Ascending.map _ (flip_id k) ha, ?_, hn⟩
    · show (if it.completed then s.left + 1 else s.left - 1) = _
      cases hd : it.completed <;> simp only [hd, Bool.false_eq_true, ↓reduceIte] at hu ⊢ <;> omega
    · intro i hi
      obtain ⟨j, hj, rfl⟩ := List.mem_map.mp hi
      rw [flip_id]; exact hb j hj

theorem delete_inv (k : Nat) {s : State} (h : Inv s) : Inv (delete k s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  unfold delete
  split
  · exact ⟨hl, ha, hb, hn⟩
  · rename_i it hf
    have hu := active_delete k ha hf
    refine ⟨?_, Ascending.filter _ ha, ?_, hn⟩
    · show (if it.completed then s.left else s.left - 1) = _
      cases hd : it.completed <;> simp only [hd, Bool.false_eq_true, ↓reduceIte] at hu ⊢ <;> omega
    · intro i hi
      exact hb i (List.mem_filter.mp hi).1

theorem toggleAll_inv {s : State} (h : Inv s) : Inv (toggleAll s) := by
  obtain ⟨_, ha, hb, hn⟩ := h
  refine ⟨?_, Ascending.map (setDone (!allDone s)) (fun _ => rfl) ha, ?_, hn⟩
  · simp only [toggleAll, active_setDone]
  · intro i hi
    obtain ⟨j, hj, rfl⟩ := List.mem_map.mp (show i ∈ s.todos.map _ from hi)
    exact hb j hj

theorem commit_inv {s : State} (h : Inv s) : Inv (commit s) := by
  unfold commit
  split
  · exact h
  · rename_i e _
    split
    · obtain ⟨hl, ha, hb, hn⟩ := delete_inv e.id h
      exact ⟨hl, ha, hb, hn⟩
    · obtain ⟨hl, ha, hb, hn⟩ := h
      refine ⟨?_, Ascending.map _ (rename_id _ _) ha, ?_, hn⟩
      · simp only [active_rename, hl]
      · intro i hi
        obtain ⟨j, hj, rfl⟩ := List.mem_map.mp hi
        rw [rename_id]; exact hb j hj

theorem clear_inv {s : State} (h : Inv s) : Inv (clearCompleted s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  refine ⟨?_, Ascending.filter _ ha, fun i hi => hb i (List.mem_filter.mp hi).1, hn⟩
  simp only [clearCompleted, active_clear, hl]

theorem startEdit_inv (k : Nat) {s : State} (h : Inv s) : Inv (startEdit k s) := by
  unfold startEdit; split
  · exact h
  · exact h

theorem editApply_inv (op : TextOp) {s : State} (h : Inv s) : Inv (editApply op s).1 := by
  unfold editApply; split
  · exact h
  · exact h

theorem init_inv : Inv ({} : State) :=
  ⟨rfl, trivial, fun _ h => by simp only [List.not_mem_nil] at h, Nat.one_pos⟩

end Examples.Todo

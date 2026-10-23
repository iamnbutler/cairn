import Cairn.Text.Field

/-! # Theorems about `Cairn.Text.Field`

1. **In bounds.** `Field.wf_empty`, `Field.wf_ofString`, `Field.wf_apply`, `Field.wf_applyAll`,
   `Field.wf_reachable`, `Field.view_wf`: caret, anchor, marked range and every undo and redo
   entry stay within `0 … length`, from any well-formed field, for every op.
2. **Round trip.** `Field.insert_deleteBackward`, `Field.insert_deleteBackward'`: typing `s` at
   a collapsed caret, then deleting backward `s.length` times, restores the text and selection.
3. **Undo.** `Field.undo_apply` (one edit, outside a typing run or composition),
   `Field.undo_typing_run` (a run of coalesced typing), `Field.undo_composition` (a whole IME
   composition), `Field.redo_undo`.
4. **Selection replace.** `Field.insert_replaces_selection`, `Field.insert_replaces_selection'`.
5. **Copy is pure.** `Field.apply_copy`, `Field.selected_spec`.
6. **Movement never edits.** `Field.apply_movement_text`.
7. **Single line.** `Field.singleLine_apply`, `Field.view_no_newline` (and `WF.single`). -/

namespace Cairn.Text

/-! ## Lists -/

theorem span_le (p : Char → Bool) : ∀ l : List Char, span p l ≤ l.length
  | [] => by simp [span]
  | c :: cs => by
    have := span_le p cs
    simp only [span, List.length_cons]
    split <;> omega

theorem wordLeft_le (t : List Char) (i : Nat) : wordLeft t i ≤ i := by
  simp only [wordLeft]; omega

theorem le_wordRight (t : List Char) (i : Nat) : i ≤ wordRight t i := by
  simp only [wordRight]; omega

theorem wordRight_le (t : List Char) (i : Nat) (h : i ≤ t.length) : wordRight t i ≤ t.length := by
  simp only [wordRight]
  have h1 := span_le (fun c => !isWordChar c) (t.drop i)
  have h2 := span_le isWordChar ((t.drop i).drop (span (fun c => !isWordChar c) (t.drop i)))
  simp only [List.length_drop] at h1 h2
  omega

theorem length_splice (t s : List Char) (a b : Nat) (hab : a ≤ b) (hb : b ≤ t.length) :
    (splice t a b s).length = a + s.length + (t.length - b) := by
  simp only [splice, List.length_append, List.length_take, List.length_drop]
  omega

theorem singleLine_splice {t s : List Char} (a b : Nat) (ht : SingleLine t) (hs : SingleLine s) :
    SingleLine (splice t a b s) := by
  intro c hc
  simp only [splice, List.mem_append] at hc
  rcases hc with (hc | hc) | hc
  · exact ht c (List.mem_of_mem_take hc)
  · exact hs c hc
  · exact ht c (List.mem_of_mem_drop hc)

theorem singleLine_nil : SingleLine [] := by intro c hc; simp at hc

theorem singleLine_flatten (c : Char) : isLineBreak (flatten c) = false := by
  unfold flatten
  split
  · rfl
  · rename_i hc; simpa using hc

theorem singleLine_clean (s : String) : SingleLine (clean s) := by
  intro c hc
  obtain ⟨d, _, rfl⟩ := List.mem_map.1 hc
  exact singleLine_flatten d

theorem length_clean (s : String) : (clean s).length = s.length := by
  simp [clean, String.length_toList]

theorem map_flatten_of_singleLine : ∀ {l : List Char}, SingleLine l → l.map flatten = l
  | [], _ => rfl
  | c :: cs, h => by
    have hc : flatten c = c := by simp [flatten, h c (by simp)]
    have ht : SingleLine cs := fun d hd => h d (List.mem_cons_of_mem c hd)
    simp only [List.map_cons, hc, map_flatten_of_singleLine ht]

theorem clean_of_singleLine {s : String} (h : SingleLine s.toList) : clean s = s.toList :=
  map_flatten_of_singleLine h

namespace Field

/-! ## Well-formedness of the primitives -/

theorem wf_empty (p : String) : (empty p).WF := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp [empty, singleLine_nil]

theorem wf_ofString (s p : String) : (ofString s p).WF := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> simp [ofString, singleLine_clean]

theorem snapshot_wf {f : Field} (h : f.WF) : f.snapshot.WF :=
  ⟨h.caret_le, h.anchor_le, h.single⟩

theorem lo_le_hi (f : Field) : f.lo ≤ f.hi := by simp only [lo, hi]; omega

theorem hi_le {f : Field} (h : f.WF) : f.hi ≤ f.text.length := by
  have := h.caret_le; have := h.anchor_le; simp only [hi]; omega

theorem target_wf {f : Field} (h : f.WF) : f.target.1 ≤ f.target.2 ∧ f.target.2 ≤ f.text.length := by
  unfold target
  cases hm : f.marked with
  | none => exact ⟨lo_le_hi f, hi_le h⟩
  | some m => exact h.marked_le m.1 m.2 hm

@[simp] theorem edit_text (f : Field) (t c a p ty) : (f.edit t c a p ty).text = t := by
  unfold edit; split <;> simp_all
@[simp] theorem edit_caret (f : Field) (t c a p ty) : (f.edit t c a p ty).caret = c := by
  unfold edit; split <;> rfl
@[simp] theorem edit_anchor (f : Field) (t c a p ty) : (f.edit t c a p ty).anchor = a := by
  unfold edit; split <;> rfl
@[simp] theorem edit_marked (f : Field) (t c a p ty) : (f.edit t c a p ty).marked = none := by
  unfold edit; split <;> rfl

theorem wf_edit {f : Field} (h : f.WF) {t : List Char} {c a : Nat} (p ty : Bool)
    (ht : SingleLine t) (hc : c ≤ t.length) (ha : a ≤ t.length) : (f.edit t c a p ty).WF := by
  refine ⟨by simpa using hc, by simpa using ha, by simp, by simpa using ht, ?_, ?_⟩
  · unfold edit
    split
    · exact h.undo_wf
    · intro s hs
      cases p
      · exact h.undo_wf s hs
      · simp only [ite_true, List.mem_cons] at hs
        rcases hs with rfl | hs
        · exact snapshot_wf h
        · exact h.undo_wf s hs
  · unfold edit
    split
    · exact h.redo_wf
    · intro s hs; simp at hs

theorem wf_moveTo {f : Field} (h : f.WF) {i : Nat} (hi : i ≤ f.text.length) (ext : Bool) :
    (f.moveTo i ext).WF := by
  refine ⟨hi, ?_, by simp [moveTo], h.single, h.undo_wf, h.redo_wf⟩
  cases ext <;> simp [moveTo, hi, h.anchor_le]

theorem wf_deleteRange {f : Field} (h : f.WF) {a b : Nat} (hab : a ≤ b) (hb : b ≤ f.text.length)
    (co : Bool := false) : (f.deleteRange a b co).WF := by
  apply wf_edit h _ _ (singleLine_splice a b h.single singleLine_nil) <;>
    rw [length_splice _ _ _ _ hab hb] <;> simp

theorem wf_deleteSelOr {f : Field} (h : f.WF) {a b : Nat} (hab : a ≤ b) (hb : b ≤ f.text.length)
    (co : Bool := false) : (f.deleteSelOr a b co).WF := by
  unfold deleteSelOr
  split
  · exact wf_deleteRange h (lo_le_hi f) (hi_le h)
  · exact wf_deleteRange h hab hb co

theorem wf_insert {f : Field} (h : f.WF) (s : String) : (f.insert s).WF := by
  obtain ⟨hab, hb⟩ := target_wf h
  simp only [insert]
  apply wf_edit h _ _ (singleLine_splice _ _ h.single (singleLine_clean s)) <;>
    rw [length_splice _ _ _ _ hab hb] <;> omega

theorem wf_paste {f : Field} (h : f.WF) (s : String) : (f.paste s).WF := by
  obtain ⟨hab, hb⟩ := target_wf h
  simp only [paste]
  apply wf_edit h _ _ (singleLine_splice _ _ h.single (singleLine_clean s)) <;>
    rw [length_splice _ _ _ _ hab hb] <;> omega

theorem mem_push {p : Prop} [Decidable p] {t x : Snapshot} {l : List Snapshot}
    (h : t ∈ (if p then x :: l else l)) : t = x ∨ t ∈ l := by
  split at h
  · simpa using h
  · exact Or.inr h

theorem mem_clear {p : Prop} [Decidable p] {t : Snapshot} {l : List Snapshot}
    (h : t ∈ (if p then [] else l)) : t ∈ l := by
  split at h
  · simp at h
  · exact h

theorem wf_setMarked {f : Field} (h : f.WF) (s : String) (i n : Nat) : (f.setMarked s i n).WF := by
  obtain ⟨hab, hb⟩ := target_wf h
  have hlen := length_splice f.text (clean s) _ _ hab hb
  refine ⟨?_, ?_, ?_, singleLine_splice _ _ h.single (singleLine_clean s), ?_, ?_⟩
  · simp only [setMarked]; omega
  · simp only [setMarked]; omega
  · intro x y hm
    simp only [setMarked] at hm
    by_cases hn : (clean s).length = 0
    · simp [hn] at hm
    · simp only [hn, ite_false, Option.some.injEq, Prod.mk.injEq] at hm
      simp only [setMarked]
      omega
  · intro t ht
    rcases mem_push ht with rfl | ht
    · exact snapshot_wf h
    · exact h.undo_wf t ht
  · intro t ht
    exact h.redo_wf t (mem_clear ht)

theorem wf_undo {f : Field} (h : f.WF) : (f.undo).1.WF := by
  unfold undo
  split
  · exact h
  · rename_i s rest hs
    have hsw := h.undo_wf s (by simp [hs])
    refine ⟨hsw.1, hsw.2.1, by simp, hsw.2.2, fun t ht => h.undo_wf t (by simp [hs, ht]), ?_⟩
    intro t ht
    simp only [List.mem_cons] at ht
    rcases ht with rfl | ht
    · exact snapshot_wf h
    · exact h.redo_wf t ht

theorem wf_redo {f : Field} (h : f.WF) : (f.redo).1.WF := by
  unfold redo
  split
  · exact h
  · rename_i s rest hs
    have hsw := h.redo_wf s (by simp [hs])
    refine ⟨hsw.1, hsw.2.1, by simp, hsw.2.2, ?_, fun t ht => h.redo_wf t (by simp [hs, ht])⟩
    intro t ht
    simp only [List.mem_cons] at ht
    rcases ht with rfl | ht
    · exact snapshot_wf h
    · exact h.undo_wf t ht

/-! ## 1. Well-formedness is invariant -/

/-- Every op keeps every index (caret, anchor, marked range, and every undo and redo entry)
within `0 … length`, and the text a single line. -/
theorem wf_apply (op : TextOp) {f : Field} (h : f.WF) : (apply op f).1.WF := by
  have hc := h.caret_le
  have ha := h.anchor_le
  have hlh := lo_le_hi f
  have hh := hi_le h
  have hlo : f.lo ≤ f.text.length := by omega
  cases op with
  | insert s => exact wf_insert h s
  | deleteBackward => exact wf_deleteSelOr h (by omega) hc true
  | deleteForward =>
    exact wf_deleteSelOr h (by simp only [len]; omega) (by simp only [len]; omega) true
  | deleteWordBackward => exact wf_deleteSelOr h (wordLeft_le _ _) hc
  | deleteWordForward =>
    have := le_wordRight f.text f.caret
    exact wf_deleteSelOr h (by simp only [len]; omega) (by simp only [len]; omega)
  | moveLeft ext =>
    simp only [apply]; split
    · exact wf_moveTo h hlo _
    · exact wf_moveTo h (by omega) _
  | moveRight ext =>
    simp only [apply]; split
    · exact wf_moveTo h hh _
    · exact wf_moveTo h (by simp only [len]; omega) _
  | moveWordLeft ext =>
    simp only [apply]
    exact wf_moveTo h (Nat.le_trans (wordLeft_le _ _) (by split <;> omega)) _
  | moveWordRight ext => exact wf_moveTo h (by simp only [len]; omega) _
  | moveHome ext => exact wf_moveTo h (Nat.zero_le _) _
  | moveEnd ext => exact wf_moveTo h (Nat.le_refl _) _
  | setCaret i ext => exact wf_moveTo h (by simp only [len]; omega) _
  | selectAll =>
    exact ⟨Nat.le_refl _, Nat.zero_le _, (fun _ _ hm => nomatch hm), h.single, h.undo_wf, h.redo_wf⟩
  | setMarked s i n => exact wf_setMarked h s i n
  | unmark => exact ⟨hc, ha, (fun _ _ hm => nomatch hm), h.single, h.undo_wf, h.redo_wf⟩
  | cut =>
    simp only [apply]; split
    · exact wf_deleteRange h hlh hh
    · exact h
  | copy => exact h
  | paste s => exact wf_paste h s
  | undo => exact wf_undo h
  | redo => exact wf_redo h

theorem wf_applyAll : ∀ (ops : List TextOp) {f : Field}, f.WF → (f.applyAll ops).WF
  | [], _, h => h
  | op :: ops, _, h => wf_applyAll ops (wf_apply op h)

/-- Every field reachable from an empty one is well-formed. -/
theorem wf_reachable (p : String) (ops : List TextOp) : ((empty p).applyAll ops).WF :=
  wf_applyAll ops (wf_empty p)

/-- What the view layer is given is in bounds too. -/
theorem view_wf {f : Field} (h : f.WF) (focused : Bool) :
    (f.view focused).caret ≤ (f.view focused).text.length ∧
    (f.view focused).anchor ≤ (f.view focused).text.length ∧
    ∀ a b, (f.view focused).marked = some (a, b) → a ≤ b ∧ b ≤ (f.view focused).text.length := by
  simp only [view, textString, String.length_ofList]
  exact ⟨h.caret_le, h.anchor_le, h.marked_le⟩

/-! ## 7. Single line -/

theorem singleLine_apply (op : TextOp) {f : Field} (h : f.WF) : SingleLine (apply op f).1.text :=
  (wf_apply op h).single

theorem view_no_newline {f : Field} (h : f.WF) (focused : Bool) :
    '\n' ∉ (f.view focused).text.toList := by
  intro hm
  simp only [view, textString, String.toList_ofList] at hm
  have := h.single _ hm
  simp [isLineBreak] at this

/-! ## 6. Movement never edits -/

def _root_.Cairn.TextOp.isMovement : TextOp → Bool
  | .moveLeft _ | .moveRight _ | .moveWordLeft _ | .moveWordRight _ | .moveHome _ | .moveEnd _
  | .setCaret _ _ | .selectAll => true
  | _ => false

theorem apply_movement_text (op : TextOp) (hop : op.isMovement) (f : Field) :
    (apply op f).1.text = f.text ∧ (apply op f).2 = [] := by
  cases op <;> simp [TextOp.isMovement] at hop <;> simp only [apply] <;>
    (try split) <;> simp [moveTo]

/-- Unmark and copy don't edit either. -/
theorem apply_unmark_text (f : Field) : (apply .unmark f).1.text = f.text := rfl

/-! ## 5. Copy is pure -/

theorem apply_copy (f : Field) :
    apply .copy f =
      (f, if f.lo < f.hi then [.setClipboard (String.ofList f.selected)] else []) := rfl

/-- The copied string is exactly `text[lo, hi)`. -/
theorem selected_spec {f : Field} (h : f.WF) :
    f.text.take f.lo ++ f.selected ++ f.text.drop f.hi = f.text ∧
    f.selected.length = f.hi - f.lo := by
  have := hi_le h
  have := lo_le_hi f
  constructor
  · have hd : f.text.drop f.hi = (f.text.drop f.lo).drop (f.hi - f.lo) := by
      rw [List.drop_drop]; congr 1; omega
    simp only [selected, List.append_assoc, hd, List.take_append_drop]
  · simp [selected]; omega

/-! ## 4. Selection replace -/

/-- Inserting over a selection (with no composition) gives `before ++ s ++ after`, with line
breaks removed from `s`, and the caret after `s`. -/
theorem insert_replaces_selection (f : Field) (s : String) (hm : f.marked = none) :
    (apply (.insert s) f).1.text = f.text.take f.lo ++ clean s ++ f.text.drop f.hi ∧
    (apply (.insert s) f).1.caret = f.lo + (clean s).length ∧
    (apply (.insert s) f).1.anchor = f.lo + (clean s).length := by
  simp [apply, insert, target, hm, splice]

/-- The same, for a string with no line breaks: exactly `before ++ s ++ after`. -/
theorem insert_replaces_selection' (f : Field) (s : String) (hm : f.marked = none)
    (hs : SingleLine s.toList) :
    (apply (.insert s) f).1.text = f.text.take f.lo ++ s.toList ++ f.text.drop f.hi := by
  rw [(insert_replaces_selection f s hm).1, clean_of_singleLine hs]

/-! ## 2. Insert / delete round trip -/

theorem deleteBackward_collapsed (g : Field) (A B : List Char) (x : Char)
    (ht : g.text = A ++ x :: B) (hc : g.caret = A.length + 1) (ha : g.anchor = g.caret) :
    (apply .deleteBackward g).1.text = A ++ B ∧ (apply .deleteBackward g).1.caret = A.length ∧
    (apply .deleteBackward g).1.anchor = A.length := by
  have hlo : g.lo = A.length + 1 := by simp [lo, ha, hc]
  have hhi : g.hi = A.length + 1 := by simp [hi, ha, hc]
  simp only [apply, deleteSelOr, hlo, hhi, Nat.lt_irrefl, ite_false, deleteRange, edit_text,
    edit_caret, edit_anchor, splice, hc, ht, Nat.add_sub_cancel, List.append_nil]
  refine ⟨?_, ?_, ?_⟩ <;> simp [List.drop_append]

theorem iterate_deleteBackward (B : List Char) :
    ∀ (u A : List Char) (g : Field), g.text = A ++ u ++ B → g.caret = A.length + u.length →
      g.anchor = g.caret →
      (iterate .deleteBackward u.length g).text = A ++ B ∧
      (iterate .deleteBackward u.length g).caret = A.length ∧
      (iterate .deleteBackward u.length g).anchor = A.length
  | [], A, g, ht, hc, ha => by simp_all [iterate]
  | x :: u, A, g, ht, hc, ha => by
    obtain ⟨h1, h2, h3⟩ := iterate_deleteBackward B u (A ++ [x]) g (by simp [ht])
      (by simp [hc]; omega) ha
    simp only [List.length_cons, iterate]
    exact deleteBackward_collapsed _ A B x (by simp [h1]) (by simp [h2]) (by rw [h3, h2])

/-- Typing a non-empty string at a collapsed caret, then deleting backward once per scalar,
restores the text and the caret. -/
theorem insert_deleteBackward {f : Field} (h : f.WF) (s : String) (hc : f.anchor = f.caret)
    (hm : f.marked = none) :
    let g := iterate .deleteBackward (clean s).length (apply (.insert s) f).1
    g.text = f.text ∧ g.caret = f.caret ∧ g.anchor = f.anchor := by
  intro g
  have hlo : f.lo = f.caret := by simp [lo, hc]
  have hhi : f.hi = f.caret := by simp [hi, hc]
  obtain ⟨h1, h2, h3⟩ := insert_replaces_selection f s hm
  simp only [hlo, hhi] at h1 h2 h3
  have hA : (f.text.take f.caret).length = f.caret := by simp [Nat.min_eq_left h.caret_le]
  obtain ⟨r1, r2, r3⟩ := iterate_deleteBackward (f.text.drop f.caret) (clean s)
    (f.text.take f.caret) _ h1 (by rw [h2, hA]) (by rw [h3, h2])
  refine ⟨by rw [r1, List.take_append_drop], by rw [r2, hA], by rw [r3, hA, hc]⟩

/-- The same in terms of the string typed: `s.length` deletions (each line break in `s` became
one space, so the count is unchanged). For `s` without line breaks, the text in between is
exactly `before ++ s ++ after` (`insert_replaces_selection'`). -/
theorem insert_deleteBackward' {f : Field} (h : f.WF) (s : String) (hc : f.anchor = f.caret)
    (hm : f.marked = none) :
    let g := iterate .deleteBackward s.length (apply (.insert s) f).1
    g.text = f.text ∧ g.caret = f.caret ∧ g.anchor = f.anchor := by
  have := insert_deleteBackward h s hc hm
  rw [length_clean] at this
  exact this

/-! ## 3. Undo restores -/

def _root_.Cairn.TextOp.isHistory : TextOp → Bool
  | .undo | .redo => true
  | _ => false

theorem edit_undoStack_of_ne (f : Field) {t : List Char} (c a ty) (ht : t ≠ f.text) :
    (f.edit t c a true ty).undoStack = f.snapshot :: f.undoStack := by
  simp [edit, ht]

/-- An edit that changes the text and starts a new undo step pushes exactly the state before
it. -/
theorem apply_pushes (op : TextOp) (f : Field) (hop : op.isHistory = false)
    (htyping : f.typing = false) (hm : f.marked = none) (hch : (apply op f).1.text ≠ f.text) :
    (apply op f).1.undoStack = f.snapshot :: f.undoStack := by
  cases op with
  | insert s =>
    simp only [apply, insert, hm, htyping, Option.isNone_none, Bool.false_and, Bool.not_false,
      Bool.true_and] at hch ⊢
    exact edit_undoStack_of_ne f _ _ _ (by simpa using hch)
  | paste s =>
    simp only [apply, paste, hm, Option.isNone_none] at hch ⊢
    exact edit_undoStack_of_ne f _ _ _ (by simpa using hch)
  | deleteBackward | deleteForward | deleteWordBackward | deleteWordForward =>
    simp only [apply, deleteSelOr, deleteRange, htyping, Bool.and_false, Bool.not_false] at hch ⊢
    split <;> split at hch <;> (try contradiction) <;>
      exact edit_undoStack_of_ne f _ _ _ (by simpa using hch)
  | cut =>
    simp only [apply, deleteRange] at hch ⊢
    split <;> split at hch <;> (try contradiction)
    exact edit_undoStack_of_ne f _ _ _ (by simpa using hch)
  | setMarked s i n =>
    simp only [apply, setMarked, hm] at hch ⊢
    simp [hch]
  | moveLeft | moveRight | moveWordLeft | moveWordRight | moveHome | moveEnd | setCaret
  | selectAll =>
    exact absurd (apply_movement_text _ rfl f).1 hch
  | unmark | copy => exact absurd rfl hch
  | undo | redo => simp [TextOp.isHistory] at hop

/-- **Undo restores.** After an op that changes the text, from a field that is not mid-typing
(`typing = false`) and not composing (`marked = none`), undo restores the text and the
selection exactly, ends any composition, and can be redone. -/
theorem undo_apply (op : TextOp) (f : Field) (hop : op.isHistory = false)
    (htyping : f.typing = false) (hm : f.marked = none) (hch : (apply op f).1.text ≠ f.text) :
    let g := (apply op f).1.undo
    g.1.text = f.text ∧ g.1.caret = f.caret ∧ g.1.anchor = f.anchor ∧ g.1.marked = none ∧
    g.1.undoStack = f.undoStack ∧ g.2 = [] := by
  intro g
  have hp := apply_pushes op f hop htyping hm hch
  simp [g, undo, hp, snapshot]

/-- Undo restores whatever is on top of the undo stack. -/
theorem undo_of_stack (k : Field) {s : Snapshot} {rest : List Snapshot}
    (h : k.undoStack = s :: rest) :
    k.undo.1.text = s.text ∧ k.undo.1.caret = s.caret ∧ k.undo.1.anchor = s.anchor := by
  simp [undo, h]

/-- Ops that join an open typing step. -/
def _root_.Cairn.TextOp.isTyping : TextOp → Bool
  | .insert _ | .deleteBackward | .deleteForward => true
  | _ => false

/-- One typing op at a collapsed caret that changes the text: it leaves the caret collapsed,
no composition, the typing step open, and pushes the state before it only if no typing step was
open. -/
theorem typing_step (op : TextOp) (g : Field) (hop : op.isTyping) (hm : g.marked = none)
    (hc : g.anchor = g.caret) (hch : (apply op g).1.text ≠ g.text) :
    (apply op g).1.typing = true ∧ (apply op g).1.marked = none ∧
    (apply op g).1.anchor = (apply op g).1.caret ∧
    (apply op g).1.undoStack = (if g.typing then g.undoStack else g.snapshot :: g.undoStack) := by
  have hlo : g.lo = g.caret := by simp [lo, hc]
  have hhi : g.hi = g.caret := by simp [hi, hc]
  cases op with
  | insert s =>
    simp only [apply, insert, target, hm, hlo, hhi, Option.getD_none, edit_text] at hch ⊢
    simp only [edit, hch, ite_false, Option.isNone_none, beq_self_eq_true, Bool.and_true,
      Bool.true_and, true_and]
    cases g.typing <;> rfl
  | deleteBackward | deleteForward =>
    simp only [apply, deleteSelOr, hlo, hhi, Nat.lt_irrefl, ite_false, deleteRange,
      edit_text] at hch ⊢
    simp only [edit, hch, ite_false, Bool.true_and, true_and]
    cases g.typing <;> rfl
  | _ => simp [TextOp.isTyping] at hop

/-- Every op in `ops` changes the text when applied in turn. -/
def ChangesEach : Field → List TextOp → Prop
  | _, [] => True
  | g, op :: ops => (apply op g).1.text ≠ g.text ∧ ChangesEach (apply op g).1 ops

theorem typing_run (ops : List TextOp) (g : Field) (s : Snapshot) (rest : List Snapshot)
    (hops : ∀ o ∈ ops, o.isTyping) (hch : ChangesEach g ops) (ht : g.typing = true)
    (hm : g.marked = none) (hc : g.anchor = g.caret) (hu : g.undoStack = s :: rest) :
    (g.applyAll ops).undoStack = s :: rest := by
  induction ops generalizing g with
  | nil => exact hu
  | cons op ops ih =>
    obtain ⟨h1, h2, h3, h4⟩ := typing_step op g (hops op (by simp)) hm hc hch.1
    exact ih (apply op g).1 (fun o ho => hops o (by simp [ho])) hch.2 h1 h2 h3
      (by rw [h4, ht, hu]; rfl)

/-- **Coalesced typing.** A run of typing (inserts, and single-scalar deletes) at a collapsed
caret, each step changing the text, is one undo step: undo after the whole run restores the
text and selection from before its first keystroke. -/
theorem undo_typing_run (f : Field) (op : TextOp) (ops : List TextOp)
    (hop : op.isTyping) (hops : ∀ o ∈ ops, o.isTyping) (htyping : f.typing = false)
    (hm : f.marked = none) (hc : f.anchor = f.caret) (hch : ChangesEach f (op :: ops)) :
    let g := (f.applyAll (op :: ops)).undo.1
    g.text = f.text ∧ g.caret = f.caret ∧ g.anchor = f.anchor := by
  obtain ⟨h1, h2, h3, h4⟩ := typing_step op f hop hm hc hch.1
  rw [htyping] at h4
  have hu := typing_run ops (apply op f).1 f.snapshot f.undoStack hops hch.2 h1 h2 h3
    (by simpa using h4)
  exact undo_of_stack _ (by simpa [applyAll] using hu)

/-- **Composition is one undo step.** From a field with no composition, a composition (one or
more non-empty `setMarked`) and its commit (`unmark`) undo back to the field before it. -/
theorem undo_composition (f : Field) (hm : f.marked = none) (s : String) (i n : Nat)
    (more : List (String × Nat × Nat)) (hs : 0 < s.length) (hmore : ∀ x ∈ more, 0 < x.1.length) :
    let ops := (TextOp.setMarked s i n :: more.map (fun x => .setMarked x.1 x.2.1 x.2.2)) ++
      [.unmark]
    let g := (f.applyAll ops).undo.1
    g.text = f.text ∧ g.caret = f.caret ∧ g.anchor = f.anchor := by
  intro ops g
  -- After the first `setMarked`, a composition is open and the state before it is on top.
  have first : ((apply (.setMarked s i n) f).1.marked.isSome = true) ∧
      (apply (.setMarked s i n) f).1.undoStack = f.snapshot :: f.undoStack := by
    have hn : (clean s).length ≠ 0 := by rw [length_clean]; omega
    simp [apply, setMarked, hm, hn]
  have step : ∀ (k : Field) (x : String × Nat × Nat), 0 < x.1.length → k.marked.isSome = true →
      (apply (.setMarked x.1 x.2.1 x.2.2) k).1.marked.isSome = true ∧
      (apply (.setMarked x.1 x.2.1 x.2.2) k).1.undoStack = k.undoStack := by
    intro k x hx hk
    have hn : (clean x.1).length ≠ 0 := by rw [length_clean]; omega
    have hk' : k.marked.isNone = false := by cases h : k.marked <;> simp_all
    simp [apply, setMarked, hn, hk']
  have run : ∀ (l : List (String × Nat × Nat)) (k : Field), (∀ x ∈ l, 0 < x.1.length) →
      k.marked.isSome = true →
      (k.applyAll (l.map (fun x => .setMarked x.1 x.2.1 x.2.2))).undoStack = k.undoStack := by
    intro l
    induction l with
    | nil => intro k _ _; rfl
    | cons x l ih =>
      intro k hl hk
      obtain ⟨a1, a2⟩ := step k x (hl x (by simp)) hk
      simp only [List.map_cons, applyAll, List.foldl_cons] at ih ⊢
      rw [ih _ (fun y hy => hl y (by simp [hy])) a1, a2]
  have hu := run more _ hmore first.1
  rw [first.2] at hu
  have hops : f.applyAll ops = (apply .unmark (((apply (.setMarked s i n) f).1).applyAll
      (more.map (fun x => .setMarked x.1 x.2.1 x.2.2)))).1 := by
    simp only [ops, applyAll, List.cons_append, List.foldl_cons, List.foldl_append,
      List.foldl_nil]
  have := undo_of_stack (f.applyAll ops) (by rw [hops]; exact hu)
  exact this

/-- **Redo undoes undo.** After an undo, redo restores the text and selection undo replaced. -/
theorem redo_undo (f : Field) (hu : f.undoStack ≠ []) :
    let g := (f.undo.1).redo.1
    g.text = f.text ∧ g.caret = f.caret ∧ g.anchor = f.anchor := by
  cases h : f.undoStack with
  | nil => exact absurd h hu
  | cons t rest => simp [undo, redo, h, snapshot]

end Field
end Cairn.Text

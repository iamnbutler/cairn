import Cairn.Text.Field

/-! # Theorems about `Cairn.Text.Field`

1. `Field.wf_empty`, `Field.wf_ofString`, `Field.wf_apply`, `Field.wf_applyAll`: every index
   stays within `0 … length`, from any well-formed field, for every op.
2. `Field.insert_deleteBackward`: insert then delete backward restores the text and caret.
3. `Field.undo_apply`, `Field.undo_apply_coalesced`, `Field.redo_undo`: undo after an edit.
4. `Field.insert_replaces_selection`: insert over a selection is `before ++ s ++ after`.
5. `Field.apply_copy`: copy changes nothing and emits exactly the selected text.
6. `Field.apply_movement_text`: movement never edits.
7. `Field.singleLine_apply`, `Field.view_no_newline`: the text never holds a line break. -/

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

theorem singleLine_clean (s : String) : SingleLine (clean s) := by
  intro c hc
  simp only [clean, List.mem_filter, Bool.not_eq_true'] at hc
  exact hc.2

theorem clean_of_singleLine {s : String} (h : SingleLine s.toList) : clean s = s.toList := by
  simp only [clean]
  exact List.filter_eq_self.2 (fun c hc => by simp [h c hc])

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

theorem wf_deleteRange {f : Field} (h : f.WF) {a b : Nat} (hab : a ≤ b) (hb : b ≤ f.text.length) :
    (f.deleteRange a b).WF := by
  apply wf_edit h _ _ (singleLine_splice a b h.single singleLine_nil) <;>
    rw [length_splice _ _ _ _ hab hb] <;> simp

theorem wf_deleteSelOr {f : Field} (h : f.WF) {a b : Nat} (hab : a ≤ b) (hb : b ≤ f.text.length) :
    (f.deleteSelOr a b).WF := by
  unfold deleteSelOr
  split
  · exact wf_deleteRange h (lo_le_hi f) (hi_le h)
  · exact wf_deleteRange h hab hb

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
  | deleteBackward => exact wf_deleteSelOr h (by omega) hc
  | deleteForward =>
    exact wf_deleteSelOr h (by simp only [len]; omega) (by simp only [len]; omega)
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

/-- The same for a string without line breaks, deleting `s.length` times. -/
theorem insert_deleteBackward' {f : Field} (h : f.WF) (s : String) (hc : f.anchor = f.caret)
    (hm : f.marked = none) (hs : SingleLine s.toList) :
    let g := iterate .deleteBackward s.length (apply (.insert s) f).1
    g.text = f.text ∧ g.caret = f.caret := by
  have := insert_deleteBackward h s hc hm
  rw [clean_of_singleLine hs, String.length_toList] at this
  exact ⟨this.1, this.2.1⟩

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
    simp only [apply, deleteSelOr, deleteRange] at hch ⊢
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

/-- **Coalesced typing.** Typing at a collapsed caret right after typing joins the open undo
step: the undo stack is unchanged, so undo goes back to the same state it would have before
this keystroke, i.e. to before the whole run of typing. -/
theorem undo_apply_coalesced (f : Field) (s : String) (htyping : f.typing = true)
    (hm : f.marked = none) (hc : f.anchor = f.caret) :
    (apply (.insert s) f).1.undoStack = f.undoStack ∧
    (((apply (.insert s) f).1.undo).1.text = (f.undo).1.text ∨ f.undoStack = []) ∧
    (((apply (.insert s) f).1.undo).1.caret = (f.undo).1.caret ∨ f.undoStack = []) ∧
    (((apply (.insert s) f).1.undo).1.anchor = (f.undo).1.anchor ∨ f.undoStack = []) := by
  have hs : (apply (.insert s) f).1.undoStack = f.undoStack := by
    simp only [apply, insert, hm, htyping, lo, hi, hc, Option.isNone_none, Nat.min_self,
      Nat.max_self, beq_self_eq_true, Bool.and_self, Bool.not_true, Bool.true_and, edit]
    split <;> rfl
  refine ⟨hs, ?_⟩
  cases hu : f.undoStack with
  | nil => simp
  | cons t rest => simp [undo, hs, hu]

/-- **Redo undoes undo.** After an undo, redo restores the text and selection undo replaced. -/
theorem redo_undo (f : Field) (hu : f.undoStack ≠ []) :
    let g := (f.undo.1).redo.1
    g.text = f.text ∧ g.caret = f.caret ∧ g.anchor = f.anchor := by
  cases h : f.undoStack with
  | nil => exact absurd h hu
  | cons t rest => simp [undo, redo, h, snapshot]

end Field
end Cairn.Text

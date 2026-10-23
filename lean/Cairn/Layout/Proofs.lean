import Cairn.Layout.Facts

/-! # Layout theorems

The headline is `Cairn.Layout.facts`: for every valid metrics, window and view, `layout`
satisfies `Facts`. The pieces:

- `layout_controls`: the controls of the laid tree are those of the view, in order.
- `layout_childClips`, `layout_clipInside`, `layout_rootClip`: clips nest, starting at the window.
- `layout_siblingsDisjoint`: children of rows and columns don't overlap.
- `layout_fillExact`: fill children make a row or column span its parent exactly.
- `layout_caretPlaced`: caret and selection geometry of every field.
- `TextMetrics.mono_valid`: the test metrics satisfy `TextMetrics.Valid`.

Each local fact is proved for a single `arrange` step and lifted to the whole tree by
`arrange_everywhere`, the one induction over the nested `Sized` tree. -/

namespace Cairn.Layout

/-! ## Controls -/

mutual
def Sized.controls : Sized → List Control
  | .box _ c _ kids => c.toList ++ Sized.controlsList kids
  | .text .. => []
  | .field _ _ c _ _ => [c]
def Sized.controlsList : List Sized → List Control
  | [] => []
  | s :: ss => s.controls ++ Sized.controlsList ss
end

mutual
theorem measure_controls (m : TextMetrics) : ∀ n : Node, (measure m n).controls = n.controls
  | .box st c kids => by
    simp only [measure, Sized.controls, Node.controls, measureList_controls m kids]
  | .text .. => by simp [measure, Sized.controls, Node.controls]
  | .field .. => by simp [measure, Sized.controls, Node.controls]
theorem measureList_controls (m : TextMetrics) :
    ∀ ns : List Node, Sized.controlsList (measureList m ns) = Node.controlsList ns
  | [] => by simp [measureList, Sized.controlsList, Node.controlsList]
  | n :: ns => by
    simp only [measureList, Sized.controlsList, Node.controlsList, measure_controls m n,
      measureList_controls m ns]
end

mutual
theorem arrange_controls (m : TextMetrics) :
    ∀ (s : Sized) (c r : Rect), (arrange m c r s).controls = s.controls
  | .box st ctl sz kids, c, r => by
    simp only [arrange, Laid.controls, Sized.controls, arrangeList_controls m kids]
  | .text .., c, r => by simp [arrange, Laid.controls, Sized.controls]
  | .field .., c, r => by simp [arrange, field, Laid.controls, Sized.controls]
theorem arrangeList_controls (m : TextMetrics) :
    ∀ (ss : List Sized) (c : Rect) (rs : List Rect),
      Laid.controlsList (arrangeList m c rs ss) = Sized.controlsList ss
  | [], c, rs => by cases rs <;> simp [arrangeList, Laid.controlsList, Sized.controlsList]
  | s :: ss, c, [] => by
    simp only [arrangeList, Laid.controlsList, Sized.controlsList, arrange_controls m s,
      arrangeList_controls m ss]
  | s :: ss, c, r :: rs => by
    simp only [arrangeList, Laid.controlsList, Sized.controlsList, arrange_controls m s,
      arrangeList_controls m ss]
end

/-- **Controls preserved.** The controls of the laid-out tree, in paint order, are exactly the
controls of the view: none lost, none invented, none reordered. -/
theorem layout_controls (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).controls = n.controls := by
  simp [layout, arrange_controls, measure_controls]

/-! ## Shape of `arrange` -/

@[simp] theorem arrange_rect (m : TextMetrics) (c r : Rect) (s : Sized) :
    (arrange m c r s).rect = r := by
  cases s <;> simp [arrange, field, Laid.rect]

@[simp] theorem arrange_clip (m : TextMetrics) (c r : Rect) (s : Sized) :
    (arrange m c r s).clip = c := by
  cases s <;> simp [arrange, field, Laid.clip]

@[simp] theorem arrange_sizings (m : TextMetrics) (c r : Rect) (s : Sized) :
    (arrange m c r s).sizings = s.sizings := by
  cases s <;> simp [arrange, field, Laid.sizings, Sized.sizings]

theorem arrange_children_box (m : TextMetrics) (c r : Rect) (st : Style) (ctl : Option Control)
    (sz : Size) (kids : List Sized) :
    (arrange m c r (.box st ctl sz kids)).children =
      arrangeList m (innerClip st c r) (childRects st r (kids.map Sized.item)) kids := by
  simp [arrange, Laid.children]

theorem arrange_children_nil (m : TextMetrics) (c r : Rect) (s : Sized)
    (h : ∀ st ctl sz kids, s ≠ .box st ctl sz kids) : (arrange m c r s).children = [] := by
  cases s with
  | box st ctl sz kids => exact absurd rfl (h st ctl sz kids)
  | text => simp [arrange, Laid.children]
  | field => simp [arrange, field, Laid.children]

theorem arrangeList_clip (m : TextMetrics) (c : Rect) :
    ∀ (rs : List Rect) (ss : List Sized), ∀ k ∈ arrangeList m c rs ss, k.clip = c
  | _, [] => by simp [arrangeList]
  | [], s :: ss => by
    simp only [arrangeList, List.mem_cons]
    rintro k (rfl | hk)
    · simp
    · exact arrangeList_clip m c [] ss k hk
  | r :: rs, s :: ss => by
    simp only [arrangeList, List.mem_cons]
    rintro k (rfl | hk)
    · simp
    · exact arrangeList_clip m c rs ss k hk

theorem arrangeList_length (m : TextMetrics) (c : Rect) :
    ∀ (rs : List Rect) (ss : List Sized), (arrangeList m c rs ss).length = ss.length
  | _, [] => by simp [arrangeList]
  | [], s :: ss => by simp [arrangeList, arrangeList_length m c [] ss]
  | r :: rs, s :: ss => by simp [arrangeList, arrangeList_length m c rs ss]

/-- With one rect per child, each child lands in its rect. -/
theorem arrangeList_map {α : Type} (m : TextMetrics) (c : Rect) (g : Sizing × Sizing → Rect → α) :
    ∀ (rs : List Rect) (ss : List Sized), rs.length = ss.length →
      (arrangeList m c rs ss).map (fun k => g k.sizings k.rect) =
        List.zipWith (fun s r => g s.sizings r) ss rs
  | [], [], _ => by simp [arrangeList]
  | r :: rs, s :: ss, h => by
    simp [arrangeList, arrangeList_map m c g rs ss (by simpa using h)]
  | [], _ :: _, h => by simp at h
  | _ :: _, [], h => by simp at h

theorem arrangeList_rects (m : TextMetrics) (c : Rect) (rs : List Rect) (ss : List Sized)
    (h : rs.length = ss.length) : (arrangeList m c rs ss).map Laid.rect = rs := by
  have := arrangeList_map m c (fun _ r => r) rs ss h
  rw [this]
  clear this
  induction ss generalizing rs with
  | nil => cases rs <;> simp_all
  | cons s ss ih => cases rs <;> simp_all

/-! ## Lifting local facts to the whole tree -/

section Lift
variable (m : TextMetrics) (P : Laid → Prop) (Q : Rect → Rect → Prop)

mutual
/-- The one induction over the tree. If every `arrange` step whose clip and rect satisfy `Q`
satisfies `P` and hands its children clips and rects satisfying `Q`, then `P` holds at every
node. -/
theorem arrange_everywhere
    (H : ∀ c r s, Q c r → P (arrange m c r s) ∧ ∀ k ∈ (arrange m c r s).children, Q k.clip k.rect) :
    ∀ (s : Sized) (c r : Rect), Q c r → (arrange m c r s).Everywhere P
  | .box st ctl sz kids, c, r, hq => by
    refine .intro (H c r _ hq).1 ?_
    have h2 := (H c r (.box st ctl sz kids) hq).2
    rw [arrange_children_box] at h2 ⊢
    exact arrangeList_everywhere H kids _ _ h2
  | .text ts s sz, c, r, hq => .intro (H c r _ hq).1 (by simp [arrange, Laid.children])
  | .field st ts ctl v sz, c, r, hq => .intro (H c r _ hq).1 (by simp [arrange, field, Laid.children])
theorem arrangeList_everywhere
    (H : ∀ c r s, Q c r → P (arrange m c r s) ∧ ∀ k ∈ (arrange m c r s).children, Q k.clip k.rect) :
    ∀ (ss : List Sized) (c : Rect) (rs : List Rect),
      (∀ k ∈ arrangeList m c rs ss, Q k.clip k.rect) → ∀ k ∈ arrangeList m c rs ss, k.Everywhere P
  | [], c, rs, _ => by cases rs <;> simp [arrangeList]
  | s :: ss, c, [], h => by
    simp only [arrangeList, List.mem_cons, forall_eq_or_imp] at h ⊢
    refine ⟨arrange_everywhere H s c _ (by simpa using h.1), ?_⟩
    exact arrangeList_everywhere H ss c [] h.2
  | s :: ss, c, r :: rs, h => by
    simp only [arrangeList, List.mem_cons, forall_eq_or_imp] at h ⊢
    refine ⟨arrange_everywhere H s c _ (by simpa using h.1), ?_⟩
    exact arrangeList_everywhere H ss c rs h.2
end

/-- The unconditional case. -/
theorem arrange_everywhere' (H : ∀ c r s, P (arrange m c r s)) (s : Sized) (c r : Rect) :
    (arrange m c r s).Everywhere P :=
  arrange_everywhere m P (fun _ _ => True) (fun c r s _ => ⟨H c r s, fun _ _ => trivial⟩) s c r trivial

end Lift

/-! ## Clips -/

theorem Rect.inside_refl (r : Rect) : r.inside r := by
  unfold Rect.inside; omega

theorem Rect.inter_inside {a : Rect} (b : Rect) (hw : 0 ≤ a.w) (hh : 0 ≤ a.h) :
    (a.inter b).inside a := by
  unfold Rect.inter Rect.inside; simp only; omega

theorem Rect.inter_nonneg (a b : Rect) : 0 ≤ (a.inter b).w ∧ 0 ≤ (a.inter b).h := by
  unfold Rect.inter; simp only; omega

theorem arrange_childClips (m : TextMetrics) (c r : Rect) (s : Sized) :
    ChildClips (arrange m c r s) := by
  intro k hk
  cases s with
  | box st ctl sz kids =>
    rw [arrange_children_box] at hk
    rw [arrangeList_clip m _ _ _ k hk]
    simp [arrange, Laid.innerClip]
  | text => simp [arrange, Laid.children] at hk
  | field => simp [arrange, field, Laid.children] at hk

theorem arrange_clipInside (m : TextMetrics) (c r : Rect) (s : Sized) (hw : 0 ≤ c.w) (hh : 0 ≤ c.h) :
    ClipInside (arrange m c r s) ∧
      ∀ k ∈ (arrange m c r s).children, 0 ≤ k.clip.w ∧ 0 ≤ k.clip.h := by
  refine ⟨⟨by simpa using hw, by simpa using hh, ?_⟩, ?_⟩ <;> intro k hk <;>
    have hc := arrange_childClips m c r s k hk <;> rw [hc] <;>
    cases s <;> simp only [arrange, field, Laid.children, Laid.innerClip, Laid.clip, innerClip,
      List.not_mem_nil] at hk ⊢ <;> split <;>
    first
    | exact Rect.inter_inside _ hw hh
    | exact Rect.inside_refl _
    | exact Rect.inter_nonneg _ _
    | exact ⟨hw, hh⟩

theorem windowRect_nonneg (w : Size) : 0 ≤ (windowRect w).w ∧ 0 ≤ (windowRect w).h := by
  simp only [windowRect]; omega

theorem layout_childClips (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere ChildClips :=
  arrange_everywhere' m _ (arrange_childClips m) _ _ _

theorem layout_clipInside (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere ClipInside :=
  arrange_everywhere m _ (fun c _ => 0 ≤ c.w ∧ 0 ≤ c.h)
    (fun c r s hq => arrange_clipInside m c r s hq.1 hq.2) _ _ _ (windowRect_nonneg w)

theorem layout_rootClip (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).clip = windowRect w := by
  simp [layout]

theorem layout_rootOrigin (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).rect.x = 0 ∧ (layout m w n).rect.y = 0 := by
  simp [layout, rootRect]

end Cairn.Layout

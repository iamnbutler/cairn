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

/-- A wrapped text's lines are text, so they have no controls. -/
theorem paraLines_controls (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String) :
    Sized.controlsList (paraLines m ts wr aw s) = [] := by
  simp only [paraLines, Text.Wrap.mapSlices]
  generalize Text.Wrap.lines _ _ _ _ = ls
  induction ls with
  | nil => simp only [List.map_nil, Sized.controlsList]
  | cons p ls ih => simp only [List.map_cons, Sized.controlsList, Sized.controls, ih,
      List.append_nil]

mutual
theorem measure_controls (m : TextMetrics) (aw : Int) :
    ∀ n : Node, (measure m aw n).controls = n.controls
  | .box st c kids => by
    simp only [measure, Sized.controls, Node.controls, measureList_controls m _ kids]
  | .text .. => by simp only [measure, Sized.controls, Node.controls]
  | .para .. => by simp only [measure, Sized.controls, Node.controls, paraLines_controls,
      Option.toList, List.append_nil]
  | .field .. => by simp only [measure, Sized.controls, Node.controls]
theorem measureList_controls (m : TextMetrics) (aw : Int) :
    ∀ ns : List Node, Sized.controlsList (measureList m aw ns) = Node.controlsList ns
  | [] => by simp only [measureList, Sized.controlsList, Node.controlsList]
  | n :: ns => by
    simp only [measureList, Sized.controlsList, Node.controlsList, measure_controls m aw n,
      measureList_controls m aw ns]
end

mutual
theorem arrange_controls (m : TextMetrics) :
    ∀ (s : Sized) (c r : Rect), (arrange m c r s).controls = s.controls
  | .box st ctl sz kids, c, r => by
    simp only [arrange, Laid.controls, Sized.controls, arrangeList_controls m kids]
  | .text .., c, r => by simp only [arrange, Laid.controls, Sized.controls]
  | .field .., c, r => by simp only [arrange, field, Laid.controls, Sized.controls]
theorem arrangeList_controls (m : TextMetrics) :
    ∀ (ss : List Sized) (c : Rect) (rs : List Rect),
      Laid.controlsList (arrangeList m c rs ss) = Sized.controlsList ss
  | [], c, rs => by cases rs <;> simp only [arrangeList, Laid.controlsList, Sized.controlsList]
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
  simp only [layout, arrange_controls, measure_controls]

/-! ## Shape of `arrange` -/

@[simp] theorem arrange_rect (m : TextMetrics) (c r : Rect) (s : Sized) :
    (arrange m c r s).rect = r := by
  cases s <;> simp only [Laid.rect, arrange, field]

@[simp] theorem arrange_clip (m : TextMetrics) (c r : Rect) (s : Sized) :
    (arrange m c r s).clip = c := by
  cases s <;> simp only [Laid.clip, arrange, field]

@[simp] theorem arrange_sizings (m : TextMetrics) (c r : Rect) (s : Sized) :
    (arrange m c r s).sizings = s.sizings := by
  cases s <;> simp only [Laid.sizings, arrange, Sized.sizings, field]

theorem arrange_children_box (m : TextMetrics) (c r : Rect) (st : Style) (ctl : Option Control)
    (sz : Size) (kids : List Sized) :
    (arrange m c r (.box st ctl sz kids)).children =
      arrangeList m (innerClip st c r) (childRects st r (kids.map Sized.item)) kids := by
  simp only [Laid.children, arrange]

theorem arrange_children_nil (m : TextMetrics) (c r : Rect) (s : Sized)
    (h : ∀ st ctl sz kids, s ≠ .box st ctl sz kids) : (arrange m c r s).children = [] := by
  cases s with
  | box st ctl sz kids => exact absurd rfl (h st ctl sz kids)
  | text => simp only [Laid.children, arrange]
  | field => simp only [Laid.children, arrange, field]

theorem arrangeList_clip (m : TextMetrics) (c : Rect) :
    ∀ (rs : List Rect) (ss : List Sized), ∀ k ∈ arrangeList m c rs ss, k.clip = c
  | _, [] => by simp only [arrangeList, List.not_mem_nil, false_implies, implies_true]
  | [], s :: ss => by
    simp only [arrangeList, List.mem_cons]
    rintro k (rfl | hk)
    · simp only [arrange_clip]
    · exact arrangeList_clip m c [] ss k hk
  | r :: rs, s :: ss => by
    simp only [arrangeList, List.mem_cons]
    rintro k (rfl | hk)
    · simp only [arrange_clip]
    · exact arrangeList_clip m c rs ss k hk

theorem arrangeList_length (m : TextMetrics) (c : Rect) :
    ∀ (rs : List Rect) (ss : List Sized), (arrangeList m c rs ss).length = ss.length
  | _, [] => by simp only [arrangeList, List.length_nil]
  | [], s :: ss => by simp only [arrangeList, List.length_cons, arrangeList_length m c [] ss]
  | r :: rs, s :: ss => by simp only [arrangeList, List.length_cons, arrangeList_length m c rs ss]

/-- With one rect per child, each child lands in its rect. -/
theorem arrangeList_map {α : Type} (m : TextMetrics) (c : Rect) (g : Sizing × Sizing → Rect → α) :
    ∀ (rs : List Rect) (ss : List Sized), rs.length = ss.length →
      (arrangeList m c rs ss).map (fun k => g k.sizings k.rect) =
        List.zipWith (fun s r => g s.sizings r) ss rs
  | [], [], _ => by simp only [arrangeList, List.map_nil, List.zipWith_nil_right]
  | r :: rs, s :: ss, h => by
    simp only [arrangeList, List.map_cons, arrange_sizings, arrange_rect,
      arrangeList_map m c g rs ss (by simpa only [List.length_cons,
          Nat.add_right_cancel_iff] using h),
      List.zipWith_cons_cons]
  | [], _ :: _, h => by simp only [List.length_nil, List.length_cons, Nat.right_eq_add,
      Nat.add_eq_zero_iff, List.length_eq_zero_iff,
    Nat.succ_ne_self, and_false] at h
  | _ :: _, [], h => by simp only [List.length_cons, List.length_nil, Nat.add_eq_zero_iff,
      List.length_eq_zero_iff, Nat.succ_ne_self,
    and_false] at h

theorem arrangeList_rects (m : TextMetrics) (c : Rect) (rs : List Rect) (ss : List Sized)
    (h : rs.length = ss.length) : (arrangeList m c rs ss).map Laid.rect = rs := by
  have := arrangeList_map m c (fun _ r => r) rs ss h
  rw [this]
  clear this
  induction ss generalizing rs with
  | nil => cases rs <;> simp_all only [List.length_nil, List.zipWith_nil_right, List.length_cons,
      Nat.add_eq_zero_iff, List.length_eq_zero_iff, Nat.succ_ne_self, and_false]
  | cons s ss ih => cases rs <;> simp_all only [List.length_nil, List.length_cons,
      Nat.right_eq_add, Nat.add_eq_zero_iff, List.length_eq_zero_iff, Nat.succ_ne_self, and_false,
      Nat.add_right_cancel_iff, List.zipWith_cons_cons]

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
  | .text ts s sz, c, r, hq => .intro (H c r _ hq).1 (by simp only [Laid.children, arrange,
      List.not_mem_nil, false_implies, implies_true])
  | .field st ts ctl v sz, c, r, hq => .intro (H c r _ hq).1 (by simp only [Laid.children,
      arrange, field, List.not_mem_nil, false_implies, implies_true])
theorem arrangeList_everywhere
    (H : ∀ c r s, Q c r → P (arrange m c r s) ∧ ∀ k ∈ (arrange m c r s).children, Q k.clip k.rect) :
    ∀ (ss : List Sized) (c : Rect) (rs : List Rect),
      (∀ k ∈ arrangeList m c rs ss, Q k.clip k.rect) → ∀ k ∈ arrangeList m c rs ss, k.Everywhere P
  | [], c, rs, _ => by cases rs <;> simp only [arrangeList, List.not_mem_nil, false_implies,
      implies_true]
  | s :: ss, c, [], h => by
    simp only [arrangeList, List.mem_cons, forall_eq_or_imp] at h ⊢
    refine ⟨arrange_everywhere H s c _ (by simpa only [arrange_clip, arrange_rect] using h.1), ?_⟩
    exact arrangeList_everywhere H ss c [] h.2
  | s :: ss, c, r :: rs, h => by
    simp only [arrangeList, List.mem_cons, forall_eq_or_imp] at h ⊢
    refine ⟨arrange_everywhere H s c _ (by simpa only [arrange_clip, arrange_rect] using h.1), ?_⟩
    exact arrangeList_everywhere H ss c rs h.2
end

/-- The unconditional case. -/
theorem arrange_everywhere' (H : ∀ c r s, P (arrange m c r s)) (s : Sized) (c r : Rect) :
    (arrange m c r s).Everywhere P :=
  arrange_everywhere m P (fun _ _ => True) (fun c r s _ => ⟨H c r s,
      fun _ _ => trivial⟩) s c r trivial

end Lift

/-! ## Clips -/

theorem Rect.inside_refl (r : Rect) : r.inside r := by
  unfold Rect.inside; omega

theorem Rect.inside_trans {a b c : Rect} (hab : a.inside b) (hbc : b.inside c) : a.inside c := by
  unfold Rect.inside at *; omega

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
    simp only [Laid.innerClip, arrange]
  | text => simp only [Laid.children, arrange, List.not_mem_nil] at hk
  | field => simp only [Laid.children, arrange, field, List.not_mem_nil] at hk

theorem arrange_clipInside (m : TextMetrics) (c r : Rect) (s : Sized) (hw : 0 ≤ c.w) (hh : 0 ≤ c.h) :
    ClipInside (arrange m c r s) ∧
      ∀ k ∈ (arrange m c r s).children, 0 ≤ k.clip.w ∧ 0 ≤ k.clip.h := by
  refine ⟨⟨by simpa only [arrange_clip] using hw, by simpa only [arrange_clip] using hh, ?_⟩,
      ?_⟩ <;> intro k hk <;>
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
  simp only [layout, arrange_clip]

theorem layout_rootOrigin (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).rect.x = 0 ∧ (layout m w n).rect.y = 0 := by
  simp only [layout, rootRect, arrange_rect, and_self]

/-! ## Sizes are non-negative -/

theorem cumShare_mono {L : Int} (hL : 0 ≤ L) (f : Nat) {a b : Nat} (hab : a ≤ b) :
    cumShare L f a ≤ cumShare L f b := by
  unfold cumShare
  rcases Nat.eq_zero_or_pos f with rfl | hf
  · simp only [Int.cast_ofNat_Int, Int.ediv_zero, Std.le_refl]
  · exact Int.ediv_le_ediv (by omega) (Int.mul_le_mul_of_nonneg_left (by omega) hL)

theorem fillShare_nonneg {L : Int} (hL : 0 ≤ L) (f j : Nat) : 0 ≤ fillShare L f j := by
  have := cumShare_mono hL f (Nat.le_add_right j 1)
  unfold fillShare; omega

theorem resolve_nonneg (s : Sizing) (x : Int) : 0 ≤ resolve s x := by
  cases s <;> simp only [resolve, Int.natCast_nonneg] <;> omega

theorem mainBase_nonneg (s : Sizing) (p : Int) : 0 ≤ mainBase s p := by
  cases s <;> simp only [mainBase, Int.natCast_nonneg, Std.le_refl] <;> omega

theorem mainSize_nonneg (h : Bool) {L : Int} (hL : 0 ≤ L) (f j : Nat) (it : Item) :
    0 ≤ mainSize h L f j it := by
  unfold mainSize; split
  · exact fillShare_nonneg hL f j
  · exact mainBase_nonneg _ _

theorem crossPlace_nonneg (al : Align) (c0 : Int) {cc : Int} (hc : 0 ≤ cc) (s : Sizing) (p : Int)
    (b : Bool) : 0 ≤ (crossPlace al c0 cc s p b).2 := by
  unfold crossPlace; simp only; split <;> (try split) <;> omega

theorem spacing_nonneg (j : Align) (gap : Nat) (free : Int) (k i : Nat) :
    0 ≤ spacing j gap free k i := by
  unfold spacing; split
  · split
    · have := fillShare_nonneg (L := free) (by omega) (k - 1) i; omega
    · omega
  · omega

/-- Start of a rect along the main axis. -/
def mainStart (h : Bool) (r : Rect) : Int := if h then r.x else r.y

@[simp] theorem mkRect_mainStart (h : Bool) (p s cp cs : Int) : mainStart h (mkRect h p s cp cs) = p := by
  cases h <;> rfl

@[simp] theorem mkRect_mainOf (h : Bool) (p s cp cs : Int) : mainOf h (mkRect h p s cp cs) = s := by
  cases h <;> rfl

theorem mkRect_nonneg (h : Bool) (p s cp cs : Int) (hs : 0 ≤ s) (hcs : 0 ≤ cs) :
    0 ≤ (mkRect h p s cp cs).w ∧ 0 ≤ (mkRect h p s cp cs).h := by
  cases h <;> simp only [mkRect, Bool.false_eq_true, ↓reduceIte] <;> omega

theorem Line.go_length (ln : Line) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), (ln.go i j pos its).length = its.length
  | [], _, _, _ => rfl
  | _ :: its, _, _, _ => by simp only [go, List.length_cons, Line.go_length ln its]

theorem Line.go_nonneg (ln : Line) (hL : 0 ≤ ln.L) (hcc : 0 ≤ ln.cc) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ r ∈ ln.go i j pos its, 0 ≤ r.w ∧ 0 ≤ r.h
  | [], _, _, _ => by simp only [go, List.not_mem_nil, false_implies, implies_true]
  | it :: its, i, j, pos => by
    simp only [Line.go, List.mem_cons]
    rintro r (rfl | hr)
    · have h1 := mainSize_nonneg ln.horiz hL ln.f j it
      have h2 := crossPlace_nonneg ln.align ln.c0 hcc (it.crossSizing ln.horiz) (it.crossPref ln.horiz) it.stretch
      exact mkRect_nonneg _ _ _ _ _ h1 h2
    · exact Line.go_nonneg ln hL hcc its _ _ _ r hr

theorem Line.go_lower (ln : Line) (hL : 0 ≤ ln.L) (hsp : ∀ i, 0 ≤ ln.spacing i) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ r ∈ ln.go i j pos its, pos ≤ mainStart ln.horiz r
  | [], _, _, _ => by simp only [go, List.not_mem_nil, false_implies, implies_true]
  | it :: its, i, j, pos => by
    simp only [Line.go, List.mem_cons]
    rintro r (rfl | hr)
    · simp only [mkRect_mainStart, Std.le_refl]
    · have := Line.go_lower ln hL hsp its _ _ _ r hr
      have := mainSize_nonneg ln.horiz hL ln.f j it
      have := hsp i
      omega

/-- Along the main axis, each child ends before every later child starts. -/
theorem Line.go_pairwise (ln : Line) (hL : 0 ≤ ln.L) (hsp : ∀ i, 0 ≤ ln.spacing i) :
    ∀ (its : List Item) (i j : Nat) (pos : Int),
      (ln.go i j pos its).Pairwise fun a b =>
        mainStart ln.horiz a + mainOf ln.horiz a ≤ mainStart ln.horiz b
  | [], _, _, _ => by simp only [go, List.Pairwise.nil]
  | it :: its, i, j, pos => by
    simp only [Line.go]
    refine List.pairwise_cons.2 ⟨fun b hb => ?_, Line.go_pairwise ln hL hsp its _ _ _⟩
    have := Line.go_lower ln hL hsp its _ _ _ b hb
    have := hsp i
    simp only [mkRect_mainStart, mkRect_mainOf]
    omega

theorem disjoint_of_main (h : Bool) {a b : Rect}
    (hab : mainStart h a + mainOf h a ≤ mainStart h b) : a.disjoint b := by
  cases h <;> simp only [mainStart, Bool.false_eq_true, ↓reduceIte,
      mainOf] at hab <;> unfold Rect.disjoint <;> omega

theorem leftover_nonneg (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    0 ≤ leftover h st c items := by
  unfold leftover; omega

theorem lineRects_length (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    (lineRects h st c items).length = items.length := by
  simp only [lineRects, Line.go_length]

theorem lineRects_nonneg (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    ∀ r ∈ lineRects h st c items, 0 ≤ r.w ∧ 0 ≤ r.h :=
  Line.go_nonneg _ (leftover_nonneg h st c items) (by simp only [lineOf]; omega) _ _ _ _

theorem lineRects_pairwise (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    (lineRects h st c items).Pairwise fun a b => a.disjoint b :=
  (Line.go_pairwise (lineOf h st c items) (leftover_nonneg h st c items)
    (fun _ => spacing_nonneg _ _ _ _ _) _ _ _ _).imp (disjoint_of_main _)

/-! ### Scrolling moves rects without changing their size -/

@[simp] theorem _root_.Cairn.Rect.scrollBy_w (h : Bool) (o : Int) (q : Rect) :
    (q.scrollBy h o).w = q.w := by
  unfold Rect.scrollBy; split <;> rfl

@[simp] theorem _root_.Cairn.Rect.scrollBy_h (h : Bool) (o : Int) (q : Rect) :
    (q.scrollBy h o).h = q.h := by
  unfold Rect.scrollBy; split <;> rfl

@[simp] theorem mainOf_scrollBy (h h' : Bool) (o : Int) (q : Rect) :
    mainOf h (q.scrollBy h' o) = mainOf h q := by
  unfold mainOf; split <;> simp only [Rect.scrollBy_w, Rect.scrollBy_h]

theorem _root_.Cairn.Rect.scrollBy_disjoint (h : Bool) (o : Int) {a b : Rect}
    (hd : a.disjoint b) : (a.scrollBy h o).disjoint (b.scrollBy h o) := by
  unfold Rect.disjoint at *; unfold Rect.scrollBy
  cases h <;> simp only [Bool.false_eq_true, ↓reduceIte] <;> omega

theorem scrolled_length (st : Style) (rs : List Rect) : (scrolled st rs).length = rs.length := by
  unfold scrolled; split <;> simp only [List.length_map]

theorem mem_scrolled {st : Style} {rs : List Rect} {q : Rect} (hq : q ∈ scrolled st rs) :
    ∃ q' ∈ rs, q.w = q'.w ∧ q.h = q'.h := by
  unfold scrolled at hq; split at hq
  · exact ⟨q, hq, rfl, rfl⟩
  · obtain ⟨q', hq', rfl⟩ := List.mem_map.1 hq
    exact ⟨q', hq', Rect.scrollBy_w _ _ _, Rect.scrollBy_h _ _ _⟩

theorem scrolled_pairwise (st : Style) {rs : List Rect}
    (h : rs.Pairwise fun a b => a.disjoint b) :
    (scrolled st rs).Pairwise fun a b => a.disjoint b := by
  unfold scrolled; split
  · exact h
  · exact List.pairwise_map.2 (h.imp (Rect.scrollBy_disjoint _ _))

theorem scrolled_none {st : Style} (h : st.scroll = none) (rs : List Rect) :
    scrolled st rs = rs := by
  simp only [scrolled, h]

theorem map_mainOf_scrolled (h : Bool) (st : Style) (rs : List Rect) :
    (scrolled st rs).map (mainOf h) = rs.map (mainOf h) := by
  unfold scrolled; split
  · rfl
  · simp only [List.map_map, Function.comp_def, mainOf_scrollBy]

theorem placeRects_length (st : Style) (r : Rect) (items : List Item) :
    (placeRects st r items).length = items.length := by
  unfold placeRects; split <;> simp only [lineRects_length, stackRects, List.length_map]

theorem childRects_length (st : Style) (r : Rect) (items : List Item) :
    (childRects st r items).length = items.length := by
  simp only [childRects, scrolled_length, placeRects_length]

theorem placeRects_nonneg (st : Style) (r : Rect) (items : List Item) :
    ∀ q ∈ placeRects st r items, 0 ≤ q.w ∧ 0 ≤ q.h := by
  unfold placeRects; split
  · exact lineRects_nonneg _ _ _ _
  · exact lineRects_nonneg _ _ _ _
  · simp only [stackRects, List.mem_map]
    rintro q ⟨it, _, rfl⟩
    exact ⟨crossPlace_nonneg _ (r.inset st.padding).x (Int.le_max_left 0 _) _ _ _,
      crossPlace_nonneg _ (r.inset st.padding).y (Int.le_max_left 0 _) _ _ _⟩

theorem childRects_nonneg (st : Style) (r : Rect) (items : List Item) :
    ∀ q ∈ childRects st r items, 0 ≤ q.w ∧ 0 ≤ q.h := by
  intro q hq
  obtain ⟨q', hq', hw, hh⟩ := mem_scrolled hq
  rw [hw, hh]; exact placeRects_nonneg st r items q' hq'

theorem placeRects_line (st : Style) (r : Rect) (items : List Item) (hax : st.axis ≠ .stack) :
    placeRects st r items = lineRects (Axis.horiz st.axis) st (r.inset st.padding) items := by
  unfold placeRects Axis.horiz
  cases h : st.axis <;> simp_all

theorem childRects_pairwise (st : Style) (r : Rect) (items : List Item) (hax : st.axis ≠ .stack) :
    (childRects st r items).Pairwise fun a b => a.disjoint b := by
  unfold childRects
  apply scrolled_pairwise
  rw [placeRects_line st r items hax]
  exact lineRects_pairwise _ _ _ _

theorem kid_rect_mem {m : TextMetrics} {c : Rect} {rs : List Rect} {ss : List Sized}
    (h : rs.length = ss.length) {k : Laid} (hk : k ∈ arrangeList m c rs ss) : k.rect ∈ rs := by
  rw [← arrangeList_rects m c rs ss h]
  exact List.mem_map_of_mem hk

theorem arrange_rectNonneg (m : TextMetrics) (c r : Rect) (s : Sized) (hw : 0 ≤ r.w) (hh : 0 ≤ r.h) :
    RectNonneg (arrange m c r s) ∧ ∀ k ∈ (arrange m c r s).children,
        0 ≤ k.rect.w ∧ 0 ≤ k.rect.h := by
  refine ⟨by simp only [RectNonneg, arrange_rect, hw, hh, and_self], fun k hk => ?_⟩
  cases s with
  | box st ctl sz kids =>
    rw [arrange_children_box] at hk
    exact childRects_nonneg _ _ _ _ (kid_rect_mem (by simp only [childRects_length,
        List.length_map]) hk)
  | text => simp only [Laid.children, arrange, List.not_mem_nil] at hk
  | field => simp only [Laid.children, arrange, field, List.not_mem_nil] at hk

theorem measure_size_nonneg (m : TextMetrics) (aw : Int) (n : Node) :
    0 ≤ (measure m aw n).size.w ∧ 0 ≤ (measure m aw n).size.h := by
  cases n <;> simp only [measure, Sized.size] <;>
    first | exact ⟨resolve_nonneg _ _, resolve_nonneg _ _⟩ | omega

theorem layout_rectNonneg (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere RectNonneg := by
  refine arrange_everywhere m _ (fun _ r => 0 ≤ r.w ∧ 0 ≤ r.h)
    (fun c r s hq => arrange_rectNonneg m c r s hq.1 hq.2) _ _ _ ?_
  have := measure_size_nonneg m (windowRect w).w n
  have := windowRect_nonneg w
  simp only [rootRect]
  constructor <;> split <;> omega

/-! ## Siblings are disjoint -/

theorem arrange_siblingsDisjoint (m : TextMetrics) (c r : Rect) (s : Sized) :
    SiblingsDisjoint (arrange m c r s) := by
  cases s with
  | box st ctl sz kids =>
    simp only [arrange, SiblingsDisjoint]
    intro hax
    have hlen : (childRects st r (kids.map Sized.item)).length = kids.length := by
      simp only [childRects_length, List.length_map]
    have := childRects_pairwise st r (kids.map Sized.item) hax
    rw [← arrangeList_rects m (innerClip st c r) _ kids hlen] at this
    exact List.pairwise_map.mp this
  | text => simp only [SiblingsDisjoint, arrange]
  | field => simp only [SiblingsDisjoint, arrange, field]

/-- **Siblings disjoint.** In every row and column of the laid-out tree, distinct children's
rects are disjoint (earlier children end before later ones start on the main axis). -/
theorem layout_siblingsDisjoint (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere SiblingsDisjoint :=
  arrange_everywhere' m _ (arrange_siblingsDisjoint m) _ _ _

/-- The index form: children `i ≠ j` of a row or column have disjoint rects. -/
theorem SiblingsDisjoint.get {r c : Rect} {st : Style} {ctl : Option Control} {kids : List Laid}
    (h : SiblingsDisjoint (.box r c st ctl kids)) (hax : st.axis ≠ .stack) {i j : Nat}
    (hi : i < kids.length) (hj : j < kids.length) (hij : i ≠ j) :
    kids[i].rect.disjoint kids[j].rect := by
  have hp := List.pairwise_iff_getElem.mp (h hax)
  rcases Nat.lt_or_gt_of_ne hij with hlt | hlt
  · exact hp i j hi hj hlt
  · have := hp j i hj hi hlt
    unfold Rect.disjoint at this ⊢; omega

/-! ## Fill exactness -/

/-- Each child's main-axis sizing paired with its main-axis length. -/
def mainPairs (h : Bool) (its : List Item) (rs : List Rect) : List (Sizing × Int) :=
  List.zipWith (fun it r => (it.mainSizing h, mainOf h r)) its rs

theorem Line.go_fill (ln : Line) :
    ∀ (its : List Item) (i j : Nat) (pos : Int),
      ((mainPairs ln.horiz its (ln.go i j pos its)).filter (!·.1.isFill) |>.map (·.2)).sum =
          baseSum ln.horiz its ∧
      ((mainPairs ln.horiz its (ln.go i j pos its)).map (·.2)).sum =
          baseSum ln.horiz its +
            (cumShare ln.L ln.f (j + fillCount ln.horiz its) - cumShare ln.L ln.f j) ∧
      ((mainPairs ln.horiz its (ln.go i j pos its)).any (·.1.isFill) = true →
          0 < fillCount ln.horiz its)
  | [], _, j, _ => by simp only [mainPairs, go, List.zipWith_nil_right, List.filter_nil,
      List.map_nil, List.sum_nil, baseSum,
    fillCount, List.length_nil, Nat.add_zero, Int.sub_self, Int.add_zero, List.any_nil,
        Bool.false_eq_true,
    Nat.lt_irrefl, imp_self, and_self]
  | it :: its, i, j, pos => by
    obtain ⟨h1, h2, h3⟩ := Line.go_fill ln its (i + 1)
      (if (it.mainSizing ln.horiz).isFill then j + 1 else j)
      (pos + mainSize ln.horiz ln.L ln.f j it + ln.spacing i)
    have hb : baseSum ln.horiz (it :: its) =
        mainBase (it.mainSizing ln.horiz) (it.mainPref ln.horiz) + baseSum ln.horiz its := by
      simp only [baseSum, List.map_cons, List.sum_cons]
    have hf : fillCount ln.horiz (it :: its) =
        (if (it.mainSizing ln.horiz).isFill then 1 else 0) + fillCount ln.horiz its := by
      simp only [fillCount, List.filter_cons]; split <;> simp only [List.length_cons,
          Nat.zero_add] <;> omega
    rw [hb, hf]
    simp only [mainPairs] at h1 h2 h3 ⊢
    simp only [Line.go, List.zipWith_cons_cons, mkRect_mainOf, List.filter_cons, List.map_cons,
      List.sum_cons, List.any_cons]
    generalize List.zipWith _ its _ = rest at h1 h2 h3 ⊢
    unfold mainSize
    cases hs : it.mainSizing ln.horiz <;>
      simp only [hs, Sizing.isFill, mainBase, Bool.not_true, Bool.not_false, ite_true, ite_false,
        Bool.false_eq_true, Bool.true_or, Bool.false_or, Nat.zero_add, Int.zero_add,
        List.map_cons, List.sum_cons] at h1 h2 h3 ⊢
    · exact ⟨by omega, by omega, h3⟩
    · exact ⟨by omega, by omega, h3⟩
    · rw [show j + (1 + fillCount ln.horiz its) = j + 1 + fillCount ln.horiz its by omega]
      unfold fillShare
      exact ⟨h1, by omega, fun _ => by omega⟩

theorem cumShare_full (L : Int) {f : Nat} (hf : 0 < f) : cumShare L f f = L := by
  unfold cumShare; exact Int.mul_ediv_cancel L (by omega)

theorem cumShare_zero (L : Int) (f : Nat) : cumShare L f 0 = 0 := by simp only [cumShare,
    Int.cast_ofNat_Int, Int.mul_zero, Int.zero_ediv]

/-- Fill exactness for one line, in terms of its content box. -/
theorem lineRects_fill (h : Bool) (st : Style) (c : Rect) (items : List Item)
    (hany : (mainPairs h items (lineRects h st c items)).any (·.1.isFill) = true)
    (hle : (((mainPairs h items (lineRects h st c items)).filter (!·.1.isFill)).map (·.2)).sum
      + gaps st.gap items.length ≤ mainOf h c) :
    ((mainPairs h items (lineRects h st c items)).map (·.2)).sum + gaps st.gap items.length =
      mainOf h c := by
  obtain ⟨h1, h2, h3⟩ := Line.go_fill (lineOf h st c items) items 0 0
    ((if h then c.x else c.y) + startOffset st.justify (free h st c items))
  have hF := h3 hany
  simp only [lineRects] at hany hle ⊢
  simp only [lineOf] at h1 h2 hF hle ⊢
  rw [Nat.zero_add, cumShare_full _ hF, cumShare_zero] at h2
  rw [h1] at hle
  rw [h2]
  unfold leftover
  omega

theorem mainOf_inset (h : Bool) (r : Rect) (p : Insets) :
    mainOf h (r.inset p) = mainOf h r - padMain h p := by
  cases h <;> simp only [mainOf, Bool.false_eq_true, ↓reduceIte, Rect.inset, padMain] <;> omega

theorem arrange_fillExact (m : TextMetrics) (c r : Rect) (s : Sized) :
    FillExact (arrange m c r s) := by
  cases s with
  | box st ctl sz kids =>
    simp only [arrange, FillExact]
    intro hax
    have hlen : (childRects st r (kids.map Sized.item)).length = kids.length := by
      simp only [childRects_length, List.length_map]
    have hcr : childRects st r (kids.map Sized.item) =
        scrolled st (lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item)) := by
      rw [childRects, placeRects_line st r _ hax]
    have hps : (arrangeList m (innerClip st c r) (childRects st r (kids.map Sized.item)) kids).map
        (fun k => ((if Axis.horiz st.axis then k.sizings.1 else k.sizings.2),
          mainOf (Axis.horiz st.axis) k.rect)) =
        mainPairs (Axis.horiz st.axis) (kids.map Sized.item)
          (lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item)) := by
      rw [arrangeList_map m _ (fun sz q => ((if Axis.horiz st.axis then sz.1 else sz.2),
        mainOf (Axis.horiz st.axis) q)) _ _ hlen, hcr]
      simp only [mainPairs, Item.mainSizing, List.zipWith_map_left, Sized.item]
      unfold scrolled
      rcases st.scroll with _ | o <;> simp only [List.zipWith_map_right, mainOf_scrollBy]
    rw [hps]
    have hl : (mainPairs (Axis.horiz st.axis) (kids.map Sized.item)
        (lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item))).length =
        (kids.map Sized.item).length := by
      simp only [mainPairs, List.length_zipWith, List.length_map, lineRects_length, Std.le_refl,
          Nat.min_eq_left]
    rw [hl]
    intro hany hle
    have := lineRects_fill (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item) hany
      (by rw [mainOf_inset]; omega)
    rw [mainOf_inset] at this
    omega
  | text => simp only [FillExact, arrange]
  | field => simp only [FillExact, arrange, field]

/-- **Fill exactness.** In every row and column of the laid-out tree with a fill child, if the
other children, gaps and padding fit, then children, gaps and padding span the parent exactly
along the main axis. -/
theorem layout_fillExact (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere FillExact :=
  arrange_everywhere' m _ (arrange_fillExact m) _ _ _

/-! ## Carets and selections -/

theorem offAt_eq (offs : Array Int) {i : Nat} (h : i < offs.size) : offAt offs i = offs[i] := by
  simp only [offAt, h, getElem?_pos, Option.getD_some]

/-- Under valid metrics every caret offset lies between 0 and the text's width. -/
theorem offAt_bounds {m : TextMetrics} (hm : m.Valid) (f : Font) (s : String) (i : Nat) :
    0 ≤ offAt (m.offsets f s) i ∧ offAt (m.offsets f s) i ≤ m.width f s := by
  have hsz := hm.size f s
  have h0 := hm.zero f s
  have hpos : 0 < (m.offsets f s).size := by omega
  have hz : (m.offsets f s)[0] = 0 := by
    rw [Array.getElem?_eq_getElem hpos] at h0; simpa only [Option.some.injEq] using h0
  have hlast : m.width f s = (m.offsets f s)[(m.offsets f s).size - 1] := by
    simp only [TextMetrics.width, Array.back?,
    Array.getElem?_eq_getElem (show (m.offsets f s).size - 1 < (m.offsets f s).size by omega),
        Option.getD_some]
  have hmono := hm.mono f s
  have hl0 := hmono 0 ((m.offsets f s).size - 1) hpos (by omega) (Nat.zero_le _)
  unfold offAt
  by_cases hi : i < (m.offsets f s).size
  · simp only [Array.getElem?_eq_getElem hi, Option.getD_some]
    have := hmono 0 i hpos hi (Nat.zero_le _)
    have := hmono i _ hi (by omega : (m.offsets f s).size - 1 < (m.offsets f s).size) (by omega)
    omega
  · simp only [Array.getElem?_eq_none (by omega : (m.offsets f s).size ≤ i), Option.getD_none]
    rw [show (m.offsets f s).back?.getD 0 = m.width f s from rfl]
    omega

theorem arrange_caretPlaced {m : TextMetrics} (hm : m.Valid) (c r : Rect) (s : Sized) :
    CaretPlaced m (arrange m c r s) := by
  cases s with
  | field st ts ctl v sz =>
    simp only [arrange, field, CaretPlaced]
    have hb := offAt_bounds hm ts.font v.text v.caret
    refine ⟨fun h => by rw [offAt_eq _ h], by omega, by omega, by trivial, by trivial, fun hw => ?_,
      fun he => ?_, fun hne => ?_⟩
    · unfold scrollFor; omega
    · simp only [he, Std.le_refl, Nat.min_eq_left, Nat.max_eq_right, ↓reduceIte]
    · simp only [show ¬ min v.anchor v.caret = max v.anchor v.caret by omega, ite_false]
      exact ⟨_, rfl, rfl, rfl, rfl, by simp only; omega⟩
  | box => simp only [CaretPlaced, arrange]
  | text => simp only [CaretPlaced, arrange]

/-- **Caret placement.** In every field of the laid-out tree, the caret's x is the text origin
plus the caret's offset, lies within the text's extent, and lies inside the content box whenever
the box is at least a point wide; the selection runs between the offsets of its ends. -/
theorem layout_caretPlaced {m : TextMetrics} (hm : m.Valid) (w : Size) (n : Node) :
    (layout m w n).Everywhere (CaretPlaced m) :=
  arrange_everywhere' m _ (arrange_caretPlaced hm) _ _ _

/-! ## The mono metrics are valid -/

theorem _root_.Cairn.TextMetrics.mono_valid : TextMetrics.mono.Valid where
  size f s := by simp only [TextMetrics.mono, Int.natCast_ediv, Int.natCast_mul,
      Int.cast_ofNat_Int, Array.size_map,
    Array.size_range]
  zero f s := by simp only [TextMetrics.mono, Int.natCast_ediv, Int.natCast_mul,
      Int.cast_ofNat_Int, Array.size_map,
    Array.size_range, Nat.zero_lt_succ, getElem?_pos, Array.getElem_map, Array.getElem_range,
        Int.zero_mul]
  mono f s i j hi hj hij := by
    simp only [TextMetrics.mono, Array.getElem_map, Array.getElem_range]
    exact Int.mul_le_mul_of_nonneg_right (by omega) (by omega)
  ascent f := by simp only [TextMetrics.mono]; omega
  descent f := by simp only [TextMetrics.mono]; omega

/-! ## Children that fit stay inside -/

/-- Start and length of a rect across the main axis. -/
def crossStart (h : Bool) (r : Rect) : Int := if h then r.y else r.x
def crossOf (h : Bool) (r : Rect) : Int := if h then r.h else r.w

@[simp] theorem mkRect_crossStart (h : Bool) (p s cp cs : Int) :
    crossStart h (mkRect h p s cp cs) = cp := by cases h <;> rfl

@[simp] theorem mkRect_crossOf (h : Bool) (p s cp cs : Int) :
    crossOf h (mkRect h p s cp cs) = cs := by cases h <;> rfl

@[simp] theorem crossOf_scrollBy (h h' : Bool) (o : Int) (q : Rect) :
    crossOf h (q.scrollBy h' o) = crossOf h q := by
  unfold crossOf; split <;> simp only [Rect.scrollBy_w, Rect.scrollBy_h]

/-- `sp i + sp (i+1) + … + sp (i+n-1)`. -/
def spSum (sp : Nat → Int) : Nat → Nat → Int
  | _, 0 => 0
  | i, n + 1 => sp i + spSum sp (i + 1) n

theorem spSum_nonneg (sp : Nat → Int) (hsp : ∀ i, 0 ≤ sp i) : ∀ i n, 0 ≤ spSum sp i n
  | _, 0 => by simp only [spSum, Std.le_refl]
  | i, n + 1 => by
    have := hsp i; have := spSum_nonneg sp hsp (i + 1) n; simp only [spSum]; omega

theorem spSum_const (sp : Nat → Int) (g : Nat) (hsp : ∀ i, sp i = g) :
    ∀ i n, spSum sp i n = ((g * n : Nat) : Int)
  | _, 0 => by simp only [spSum, Nat.mul_zero, Int.cast_ofNat_Int]
  | i, n + 1 => by
    have := spSum_const sp g hsp (i + 1) n
    simp only [spSum, hsp i, this, Nat.mul_succ]; omega

theorem spSum_tele (sp : Nat → Int) (g : Nat) (F : Nat → Int) (hsp : ∀ i,
    sp i = g + (F (i + 1) - F i)) :
    ∀ i n, spSum sp i n = ((g * n : Nat) : Int) + (F (i + n) - F i)
  | i, 0 => by simp only [spSum, Nat.mul_zero, Int.cast_ofNat_Int, Nat.add_zero, Int.sub_self,
      Int.add_zero]
  | i, n + 1 => by
    have := spSum_tele sp g F hsp (i + 1) n
    simp only [spSum, hsp i, this, Nat.mul_succ]
    rw [show i + 1 + n = i + (n + 1) by omega]; omega

theorem sum_nonneg (l : List Int) (h : ∀ x ∈ l, 0 ≤ x) : 0 ≤ l.sum := by
  induction l with
  | nil => simp only [List.sum_nil, Std.le_refl]
  | cons x xs ih =>
    simp only [List.sum_cons]
    have := h x (.head _); have := ih (fun y hy => h y (.tail _ hy)); omega

theorem Line.go_mainOf_nonneg (ln : Line) (hL : 0 ≤ ln.L) (its : List Item) (i j : Nat) (pos : Int) :
    0 ≤ ((ln.go i j pos its).map (mainOf ln.horiz)).sum := by
  apply sum_nonneg
  intro x hx
  simp only [List.mem_map] at hx
  obtain ⟨r, hr, rfl⟩ := hx
  -- The cross length is irrelevant here, so any non-negative stand-in for `cc` will do.
  induction its generalizing i j pos with
  | nil => simp only [go, List.not_mem_nil] at hr
  | cons it its ih =>
    simp only [Line.go, List.mem_cons] at hr
    rcases hr with rfl | hr
    · simp only [mkRect_mainOf]; exact mainSize_nonneg _ hL _ _ _
    · exact ih _ _ _ hr

/-- Along the main axis, every child ends by the start plus all lengths and spacings. -/
theorem Line.go_upper (ln : Line) (hL : 0 ≤ ln.L) (hsp : ∀ i, 0 ≤ ln.spacing i) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ r ∈ ln.go i j pos its,
      mainStart ln.horiz r + mainOf ln.horiz r ≤
        pos + ((ln.go i j pos its).map (mainOf ln.horiz)).sum + spSum ln.spacing i (its.length - 1)
  | [], _, _, _ => by simp only [go, List.not_mem_nil, List.map_nil, List.sum_nil, Int.add_zero,
      List.length_nil, Nat.zero_le,
    Nat.sub_eq_zero_of_le, false_implies, implies_true]
  | it :: its, i, j, pos => by
    simp only [Line.go, List.mem_cons, List.map_cons, List.sum_cons, mkRect_mainOf]
    rintro r (rfl | hr)
    · simp only [mkRect_mainStart, mkRect_mainOf]
      have := spSum_nonneg _ hsp i ((it :: its).length - 1)
      have := Line.go_mainOf_nonneg ln hL its (i + 1)
        (if (it.mainSizing ln.horiz).isFill then j + 1 else j)
        (pos + mainSize ln.horiz ln.L ln.f j it + ln.spacing i)
      omega
    · have := Line.go_upper ln hL hsp its _ _ _ r hr
      cases its with
      | nil => simp only [go, List.not_mem_nil] at hr
      | cons it' its' =>
        simp only [List.length_cons, Nat.add_sub_cancel, spSum] at this ⊢
        omega

theorem crossPlace_inside (al : Align) (c0 cc : Int) (s : Sizing) (p : Int) (b : Bool)
    (h : (crossPlace al c0 cc s p b).2 ≤ cc) :
    c0 ≤ (crossPlace al c0 cc s p b).1 ∧
      (crossPlace al c0 cc s p b).1 + (crossPlace al c0 cc s p b).2 ≤ c0 + cc := by
  cases al <;> simp only [crossPlace] at h ⊢ <;> omega

theorem Line.go_cross (ln : Line) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ r ∈ ln.go i j pos its,
      crossOf ln.horiz r ≤ ln.cc →
      ln.c0 ≤ crossStart ln.horiz r ∧ crossStart ln.horiz r + crossOf ln.horiz r ≤ ln.c0 + ln.cc
  | [], _, _, _ => by simp only [go, List.not_mem_nil, false_implies, implies_true]
  | it :: its, i, j, pos => by
    simp only [Line.go, List.mem_cons]
    rintro r (rfl | hr)
    · simp only [mkRect_crossStart, mkRect_crossOf]
      exact crossPlace_inside _ _ _ _ _ _
    · exact Line.go_cross ln its _ _ _ r hr

theorem mainPairs_snd (h : Bool) :
    ∀ (its : List Item) (rs : List Rect), its.length = rs.length →
      (mainPairs h its rs).map (·.2) = rs.map (mainOf h)
  | [], [], _ => rfl
  | _ :: its, _ :: rs, hl => by
    have := mainPairs_snd h its rs (by simpa only [List.length_cons,
        Nat.add_right_cancel_iff] using hl)
    simp only [mainPairs] at this
    simp only [mainPairs, List.zipWith_cons_cons, List.map_cons, this]
  | [], _ :: _, hl => by simp only [List.length_nil, List.length_cons, Nat.right_eq_add,
      Nat.add_eq_zero_iff, List.length_eq_zero_iff,
    Nat.succ_ne_self, and_false] at hl
  | _ :: _, [], hl => by simp only [List.length_cons, List.length_nil, Nat.add_eq_zero_iff,
      List.length_eq_zero_iff, Nat.succ_ne_self,
    and_false] at hl

/-- The children's main-axis lengths add up to the space the line uses. -/
theorem lineRects_sum (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    ((lineRects h st c items).map (mainOf h)).sum =
      if fillCount h items = 0 then baseSum h items
      else baseSum h items + leftover h st c items := by
  obtain ⟨_, h2, _⟩ := Line.go_fill (lineOf h st c items) items 0 0
    ((if h then c.x else c.y) + startOffset st.justify (free h st c items))
  rw [mainPairs_snd _ _ _ (by simp only [Line.go_length])] at h2
  simp only [lineRects]
  simp only [lineOf, Nat.zero_add, cumShare_zero] at h2 ⊢
  rw [h2]
  split
  · rename_i hf; rw [hf, cumShare_zero]; omega
  · rename_i hf; rw [cumShare_full _ (by omega)]; omega

theorem lineRects_inside (h : Bool) (st : Style) (c : Rect) (items : List Item)
    (hcross : ∀ r ∈ lineRects h st c items, crossOf h r ≤ crossOf h c)
    (hfit : ((lineRects h st c items).map (mainOf h)).sum + gaps st.gap items.length ≤ mainOf h c) :
    ∀ r ∈ lineRects h st c items, r.inside c := by
  intro r hr
  have hsum := lineRects_sum h st c items
  have hcr := hcross r hr
  have hnn := lineRects_nonneg h st c items r hr
  simp only [lineRects] at hr hfit hsum
  have hL := leftover_nonneg h st c items
  have hsp := fun i => spacing_nonneg st.justify st.gap (free h st c items) items.length i
  have hlow := Line.go_lower _ hL hsp items 0 0 _ r hr
  have hup := Line.go_upper _ hL hsp items 0 0 _ r hr
  have hx := Line.go_cross _ items 0 0 _ r hr
  simp only [lineOf] at hlow hup hx hfit hsum
  have hx := hx (by cases h <;> simp only [crossOf, Bool.false_eq_true,
      ↓reduceIte] at hcr ⊢ <;> omega)
  rw [hsum] at hfit
  rw [hsum] at hup
  -- The spacings add up to the gaps, plus the free space when justified with `stretch`.
  have hfree : 0 ≤ free h st c items := by unfold free; simp only; omega
  have hoff : 0 ≤ startOffset st.justify (free h st c items) := by
    cases st.justify <;> simp only [startOffset] <;> omega
  have hgaps : gaps st.gap items.length = ((st.gap * (items.length - 1) : Nat) : Int) := rfl
  have hspan : startOffset st.justify (free h st c items) +
      spSum (spacing st.justify st.gap (free h st c items) items.length) 0 (items.length - 1)
        ≤ free h st c items + gaps st.gap items.length := by
    by_cases hst : st.justify = .stretch ∧ 0 < free h st c items ∧ 1 < items.length
    · obtain ⟨hj, hpos, hk⟩ := hst
      rw [spSum_tele _ st.gap (cumShare (free h st c items) (items.length - 1)) (fun i => by
        simp only [spacing, hj, hpos, hk, and_self, ↓reduceIte, fillShare])]
      rw [Nat.zero_add, cumShare_full _ (by omega), cumShare_zero, hj]
      simp only [startOffset]; omega
    · rw [spSum_const _ st.gap (fun i => by
        unfold spacing; split
        · rename_i hj; simp only [show ¬ (0 < free h st c items ∧ 1 < items.length) from fun h' => hst ⟨hj, h'⟩, ite_false]
        · rfl)]
      cases hj : st.justify <;> simp only [startOffset] <;> omega
  unfold free at hfree hspan hup hlow hoff
  simp only at hfree hspan hup hlow hoff
  unfold Rect.inside
  cases h <;> simp only [mainStart, mainOf, crossStart, crossOf, ite_true, ite_false,
    Bool.false_eq_true] at hlow hup hx hfit hspan hfree hcr hoff ⊢ <;> omega

theorem stackRects_inside (st : Style) (c : Rect) (items : List Item)
    (hfit : ∀ r ∈ stackRects st c items, r.w ≤ c.w ∧ r.h ≤ c.h) :
    ∀ r ∈ stackRects st c items, r.inside c := by
  intro r hr
  have hf := hfit r hr
  simp only [stackRects, List.mem_map] at hr
  obtain ⟨it, _, rfl⟩ := hr
  simp only at hf
  have := crossPlace_nonneg st.justify c.x (Int.le_max_left 0 c.w) it.width it.size.w it.stretch
  have := crossPlace_nonneg st.align c.y (Int.le_max_left 0 c.h) it.height it.size.h it.stretch
  have hx := crossPlace_inside st.justify c.x (max 0 c.w) it.width it.size.w it.stretch (by omega)
  have hy := crossPlace_inside st.align c.y (max 0 c.h) it.height it.size.h it.stretch (by omega)
  unfold Rect.inside; simp only; omega

theorem arrange_childrenInside (m : TextMetrics) (c r : Rect) (s : Sized) :
    ChildrenInside (arrange m c r s) := by
  cases s with
  | box st ctl sz kids =>
    simp only [arrange, ChildrenInside]
    intro hscroll hsize hfit k hk
    have hlen : (childRects st r (kids.map Sized.item)).length = kids.length := by
      simp only [childRects_length, List.length_map]
    have hrs := arrangeList_rects m (innerClip st c r) _ kids hlen
    have hmem := kid_rect_mem hlen hk
    -- Every child rect belongs to a child, so the size hypothesis covers each rect.
    have hsize' : ∀ q ∈ childRects st r (kids.map Sized.item),
        q.w ≤ (r.inset st.padding).w ∧ q.h ≤ (r.inset st.padding).h := by
      intro q hq
      rw [← hrs] at hq
      simp only [List.mem_map] at hq
      obtain ⟨k', hk', rfl⟩ := hq
      exact hsize k' hk'
    cases hx : st.axis with
    | stack =>
      have e : childRects st r (kids.map Sized.item) =
          stackRects st (r.inset st.padding) (kids.map Sized.item) := by
        simp only [childRects, placeRects, scrolled_none hscroll, hx]
      rw [e] at hmem hsize'
      exact stackRects_inside _ _ _ hsize' _ hmem
    | row | column =>
      have e : childRects st r (kids.map Sized.item) =
          lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item) := by
        simp only [childRects, placeRects, scrolled_none hscroll, hx, Axis.horiz]
      rw [e] at hmem hsize' hrs
      refine lineRects_inside _ st _ _ (fun q hq => ?_) ?_ _ hmem
      · have := hsize' q hq; simp only [crossOf]; split <;> omega
      · have hf := hfit (by simp only [hx, ne_eq, reduceCtorEq, not_false_eq_true])
        rw [e] at hf
        rw [← hrs, List.map_map]
        simpa only [Function.comp_def, List.length_map, ge_iff_le, arrangeList_length] using hf
  | text => simp only [ChildrenInside, arrange]
  | field => simp only [ChildrenInside, arrange, field]

/-- **Children that fit stay inside.** In every container of the laid-out tree, if the children
fit the content box (in size, and along the main axis with gaps), each child's rect is inside
it. -/
theorem layout_childrenInside (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere ChildrenInside :=
  arrange_everywhere' m _ (arrange_childrenInside m) _ _ _

/-! ## Scroll boxes -/

theorem placeRects_scroll (st : Style) (s : Option Int) (r : Rect) (items : List Item) :
    placeRects { st with scroll := s } r items = placeRects st r items := by
  cases st; rfl

/-- A scroll box's children are where the same box without `scroll` puts them (`placeRects`:
in a column, one under the other), moved back by the offset along the box's axis. -/
theorem childRects_scroll {st : Style} {o : Int} (ho : st.scroll = some o) (r : Rect)
    (items : List Item) :
    childRects st r items =
      (childRects { st with scroll := none } r items).map (Rect.scrollBy (Axis.horiz st.axis) o) := by
  simp only [childRects, scrolled, ho, placeRects_scroll]

/-- **Scrolled children.** Every child of a scroll box with offset `o` is laid at the rect the
same box gives it when it doesn't scroll, moved back by `o` along the box's axis: in a column (or
a stack), the same `x`, width and height, and `y` less `o`; in a row, `x` less `o`. -/
theorem arrange_scroll (m : TextMetrics) (c r : Rect) {st : Style} (ctl : Option Control)
    (sz : Size) (kids : List Sized) {o : Int} (ho : st.scroll = some o) :
    (arrange m c r (.box st ctl sz kids)).children.map Laid.rect =
      ((arrange m c r (.box { st with scroll := none } ctl sz kids)).children.map Laid.rect).map
        (Rect.scrollBy (Axis.horiz st.axis) o) := by
  simp only [arrange_children_box]
  rw [arrangeList_rects _ _ _ _ (by simp only [childRects_length, List.length_map]),
    arrangeList_rects _ _ _ _ (by simp only [childRects_length, List.length_map])]
  exact childRects_scroll ho r _

/-- Measuring doesn't read `scroll`: a box measures the same with any offset, or none. -/
theorem measure_scroll (m : TextMetrics) (aw : Int) (st : Style) (s : Option Int)
    (ctl : Option Control) (kids : List Node) :
    measure m aw (.box { st with scroll := s } ctl kids) =
      .box { st with scroll := s } ctl (measure m aw (.box st ctl kids)).size
        (measureList m (innerAvail st aw) kids) := by
  cases st; rfl

/-- In a column, scrolling by `o` moves a rect up by `o` and changes nothing else. -/
theorem scrollBy_column (o : Int) (q : Rect) : q.scrollBy false o = ⟨q.x, q.y - o, q.w, q.h⟩ := rfl

theorem _root_.Cairn.Laid.Everywhere.and {P Q : Laid → Prop} {l : Laid} (hp : l.Everywhere P)
    (hq : l.Everywhere Q) : l.Everywhere fun x => P x ∧ Q x := by
  revert hq
  induction hp with
  | intro hP _ ih => exact fun hq => .intro ⟨hP, hq.here⟩ fun k hk => ih k hk (hq.child hk)

theorem _root_.Cairn.Laid.Everywhere.imp {P Q : Laid → Prop} {l : Laid} (hp : l.Everywhere P)
    (f : ∀ x, P x → Q x) : l.Everywhere Q := by
  induction hp with
  | intro hP _ ih => exact .intro (f _ hP) ih

/-- A fact holding everywhere holds everywhere at every node's subtree. -/
theorem _root_.Cairn.Laid.Everywhere.tails {P : Laid → Prop} {l : Laid} (hp : l.Everywhere P) :
    l.Everywhere fun d => d.Everywhere P := by
  induction hp with
  | intro hP hK ih => exact .intro (.intro hP hK) ih

theorem Rect.inter_inside_of_nonempty {a b : Rect} (h : (a.inter b).nonempty) :
    (a.inter b).inside b := by
  unfold Rect.nonempty Rect.inter at h; unfold Rect.inter Rect.inside; simp only at *; omega

theorem Rect.nonempty_of_inside {a b : Rect} (hi : a.inside b) (h : a.nonempty) : b.nonempty := by
  unfold Rect.inside at hi; unfold Rect.nonempty at *; omega

/-- Clips only shrink going down: below a node whose clip is inside `R`, every clip is. -/
theorem clip_inside_everywhere {R : Rect} {l : Laid} (hE : l.Everywhere ClipInside) :
    l.clip.inside R → l.Everywhere fun d => d.clip.inside R := by
  induction hE with
  | intro hP _ ih =>
    exact fun hR => .intro hR fun k hk => ih k hk (Rect.inside_trans (hP.2.2 k hk) hR)

/-- A nonempty visible part lies inside the node's clip. -/
theorem visible_inside_clip {d : Laid} (h : d.visible.nonempty) : d.visible.inside d.clip :=
  Rect.inter_inside_of_nonempty h

theorem clipContained_of {l : Laid} (hE : l.Everywhere ClipInside) (hcc : ChildClips l) :
    ClipContained l := by
  cases l with
  | box r c st ctl kids =>
    intro hclips k hk
    have hkc : k.clip = c.inter r := by
      rw [hcc k (by simp only [Laid.children, hk])]
      simp only [Laid.innerClip, innerClip, hclips, ↓reduceIte]
    have hkE := hE.child (k := k) (by simp only [Laid.children, hk])
    refine (clip_inside_everywhere (R := k.clip) hkE (Rect.inside_refl _)).imp fun d hd hne => ?_
    have hv := visible_inside_clip hne
    have hK : k.clip.nonempty := Rect.nonempty_of_inside (Rect.inside_trans hv hd) hne
    rw [hkc] at hd hK
    exact Rect.inside_trans (Rect.inside_trans hv hd) (Rect.inter_inside_of_nonempty hK)
  | text => trivial
  | field => trivial

/-- **Clips hold what is under them.** In every box of the laid-out tree that clips, so in
every scroll box, every nonempty visible part of every node below it is inside the box's
rect. -/
theorem layout_clipContained (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere ClipContained :=
  ((layout_clipInside m w n).tails.and (layout_childClips m w n)).imp fun _ h =>
    clipContained_of h.1 h.2

/-! ## Everything together -/

/-- **Layout facts.** For valid metrics, every window and every view, `layout` satisfies all of
`Facts`. -/
theorem facts {m : TextMetrics} (hm : m.Valid) (w : Size) (n : Node) :
    Facts m w n (layout m w n) where
  controls := layout_controls m w n
  rootClip := layout_rootClip m w n
  rootOrigin := layout_rootOrigin m w n
  childClips := layout_childClips m w n
  clipInside := layout_clipInside m w n
  rectNonneg := layout_rectNonneg m w n
  siblingsDisjoint := layout_siblingsDisjoint m w n
  fillExact := layout_fillExact m w n
  childrenInside := layout_childrenInside m w n
  clipContained := layout_clipContained m w n
  caretPlaced := layout_caretPlaced hm w n

/-! ## Images -/

/-- **An image's box doesn't depend on its state.** `Node.image` measures at the size the app
gave it whether it is loading, loaded at any pixel size, or failed, so nothing around it moves
when the pixels arrive or the load fails. -/
theorem measure_image (m : TextMetrics) (aw : Int) (i : Image) :
    (measure m aw (Node.image i)).size = ⟨i.width, i.height⟩ := by
  simp only [Node.image, measure, Sized.size, Image.style, resolve]

/-- An image's size is fixed on both axes, so rows and columns never stretch or shrink it. -/
theorem image_sizings (m : TextMetrics) (aw : Int) (i : Image) :
    (measure m aw (Node.image i)).sizings = (.fixed i.width, .fixed i.height) := by
  simp only [Node.image, measure, Sized.sizings, Image.style]

/-- An image is no control, in any state. -/
theorem controls_image (i : Image) : (Node.image i).controls = [] := by
  unfold Node.image Image.children
  split <;> simp only [Node.controls, Node.controlsList, Option.toList, List.append_nil]

end Cairn.Layout

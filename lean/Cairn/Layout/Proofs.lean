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

/-! ## Sizes are non-negative -/

theorem cumShare_mono {L : Int} (hL : 0 ≤ L) (f : Nat) {a b : Nat} (hab : a ≤ b) :
    cumShare L f a ≤ cumShare L f b := by
  unfold cumShare
  rcases Nat.eq_zero_or_pos f with rfl | hf
  · simp
  · exact Int.ediv_le_ediv (by omega) (Int.mul_le_mul_of_nonneg_left (by omega) hL)

theorem fillShare_nonneg {L : Int} (hL : 0 ≤ L) (f j : Nat) : 0 ≤ fillShare L f j := by
  have := cumShare_mono hL f (Nat.le_add_right j 1)
  unfold fillShare; omega

theorem resolve_nonneg (s : Sizing) (x : Int) : 0 ≤ resolve s x := by
  cases s <;> simp [resolve] <;> omega

theorem mainBase_nonneg (s : Sizing) (p : Int) : 0 ≤ mainBase s p := by
  cases s <;> simp [mainBase] <;> omega

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
  cases h <;> simp [mkRect] <;> omega

theorem Line.go_length (ln : Line) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), (ln.go i j pos its).length = its.length
  | [], _, _, _ => rfl
  | _ :: its, _, _, _ => by simp [Line.go, Line.go_length ln its]

theorem Line.go_nonneg (ln : Line) (hL : 0 ≤ ln.L) (hcc : 0 ≤ ln.cc) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ r ∈ ln.go i j pos its, 0 ≤ r.w ∧ 0 ≤ r.h
  | [], _, _, _ => by simp [Line.go]
  | it :: its, i, j, pos => by
    simp only [Line.go, List.mem_cons]
    rintro r (rfl | hr)
    · have h1 := mainSize_nonneg ln.horiz hL ln.f j it
      have h2 := crossPlace_nonneg ln.align ln.c0 hcc (it.crossSizing ln.horiz) (it.crossPref ln.horiz) it.stretch
      exact mkRect_nonneg _ _ _ _ _ h1 h2
    · exact Line.go_nonneg ln hL hcc its _ _ _ r hr

theorem Line.go_lower (ln : Line) (hL : 0 ≤ ln.L) (hsp : ∀ i, 0 ≤ ln.spacing i) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ r ∈ ln.go i j pos its, pos ≤ mainStart ln.horiz r
  | [], _, _, _ => by simp [Line.go]
  | it :: its, i, j, pos => by
    simp only [Line.go, List.mem_cons]
    rintro r (rfl | hr)
    · simp
    · have := Line.go_lower ln hL hsp its _ _ _ r hr
      have := mainSize_nonneg ln.horiz hL ln.f j it
      have := hsp i
      omega

/-- Along the main axis, each child ends before every later child starts. -/
theorem Line.go_pairwise (ln : Line) (hL : 0 ≤ ln.L) (hsp : ∀ i, 0 ≤ ln.spacing i) :
    ∀ (its : List Item) (i j : Nat) (pos : Int),
      (ln.go i j pos its).Pairwise fun a b =>
        mainStart ln.horiz a + mainOf ln.horiz a ≤ mainStart ln.horiz b
  | [], _, _, _ => by simp [Line.go]
  | it :: its, i, j, pos => by
    simp only [Line.go]
    refine List.pairwise_cons.2 ⟨fun b hb => ?_, Line.go_pairwise ln hL hsp its _ _ _⟩
    have := Line.go_lower ln hL hsp its _ _ _ b hb
    have := hsp i
    simp only [mkRect_mainStart, mkRect_mainOf]
    omega

theorem disjoint_of_main (h : Bool) {a b : Rect}
    (hab : mainStart h a + mainOf h a ≤ mainStart h b) : a.disjoint b := by
  cases h <;> simp [mainStart, mainOf] at hab <;> unfold Rect.disjoint <;> omega

theorem leftover_nonneg (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    0 ≤ leftover h st c items := by
  unfold leftover; omega

theorem lineRects_length (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    (lineRects h st c items).length = items.length := by
  simp [lineRects, Line.go_length]

theorem lineRects_nonneg (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    ∀ r ∈ lineRects h st c items, 0 ≤ r.w ∧ 0 ≤ r.h :=
  Line.go_nonneg _ (leftover_nonneg h st c items) (by simp only [lineOf]; omega) _ _ _ _

theorem lineRects_pairwise (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    (lineRects h st c items).Pairwise fun a b => a.disjoint b :=
  (Line.go_pairwise (lineOf h st c items) (leftover_nonneg h st c items)
    (fun _ => spacing_nonneg _ _ _ _ _) _ _ _ _).imp (disjoint_of_main _)

theorem childRects_length (st : Style) (r : Rect) (items : List Item) :
    (childRects st r items).length = items.length := by
  unfold childRects; split <;> simp [lineRects_length, stackRects]

theorem childRects_nonneg (st : Style) (r : Rect) (items : List Item) :
    ∀ q ∈ childRects st r items, 0 ≤ q.w ∧ 0 ≤ q.h := by
  unfold childRects; split
  · exact lineRects_nonneg _ _ _ _
  · exact lineRects_nonneg _ _ _ _
  · simp only [stackRects, List.mem_map]
    rintro q ⟨it, _, rfl⟩
    exact ⟨crossPlace_nonneg _ (r.inset st.padding).x (Int.le_max_left 0 _) _ _ _,
      crossPlace_nonneg _ (r.inset st.padding).y (Int.le_max_left 0 _) _ _ _⟩

theorem childRects_pairwise (st : Style) (r : Rect) (items : List Item) (hax : st.axis ≠ .stack) :
    (childRects st r items).Pairwise fun a b => a.disjoint b := by
  unfold childRects; split
  · exact lineRects_pairwise _ _ _ _
  · exact lineRects_pairwise _ _ _ _
  · contradiction

theorem kid_rect_mem {m : TextMetrics} {c : Rect} {rs : List Rect} {ss : List Sized}
    (h : rs.length = ss.length) {k : Laid} (hk : k ∈ arrangeList m c rs ss) : k.rect ∈ rs := by
  rw [← arrangeList_rects m c rs ss h]
  exact List.mem_map_of_mem hk

theorem arrange_rectNonneg (m : TextMetrics) (c r : Rect) (s : Sized) (hw : 0 ≤ r.w) (hh : 0 ≤ r.h) :
    RectNonneg (arrange m c r s) ∧ ∀ k ∈ (arrange m c r s).children, 0 ≤ k.rect.w ∧ 0 ≤ k.rect.h := by
  refine ⟨by simp [RectNonneg, hw, hh], fun k hk => ?_⟩
  cases s with
  | box st ctl sz kids =>
    rw [arrange_children_box] at hk
    exact childRects_nonneg _ _ _ _ (kid_rect_mem (by simp [childRects_length]) hk)
  | text => simp [arrange, Laid.children] at hk
  | field => simp [arrange, field, Laid.children] at hk

theorem measure_size_nonneg (m : TextMetrics) (n : Node) :
    0 ≤ (measure m n).size.w ∧ 0 ≤ (measure m n).size.h := by
  cases n <;> simp only [measure, Sized.size] <;>
    first | exact ⟨resolve_nonneg _ _, resolve_nonneg _ _⟩ | omega

theorem layout_rectNonneg (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere RectNonneg := by
  refine arrange_everywhere m _ (fun _ r => 0 ≤ r.w ∧ 0 ≤ r.h)
    (fun c r s hq => arrange_rectNonneg m c r s hq.1 hq.2) _ _ _ ?_
  have := measure_size_nonneg m n
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
      simp [childRects_length]
    have := childRects_pairwise st r (kids.map Sized.item) hax
    rw [← arrangeList_rects m (innerClip st c r) _ kids hlen] at this
    exact List.pairwise_map.mp this
  | text => simp [arrange, SiblingsDisjoint]
  | field => simp [arrange, field, SiblingsDisjoint]

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

end Cairn.Layout

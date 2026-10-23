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
  | [], _, j, _ => by simp [Line.go, mainPairs, baseSum, fillCount]
  | it :: its, i, j, pos => by
    obtain ⟨h1, h2, h3⟩ := Line.go_fill ln its (i + 1)
      (if (it.mainSizing ln.horiz).isFill then j + 1 else j)
      (pos + mainSize ln.horiz ln.L ln.f j it + ln.spacing i)
    have hb : baseSum ln.horiz (it :: its) =
        mainBase (it.mainSizing ln.horiz) (it.mainPref ln.horiz) + baseSum ln.horiz its := by
      simp [baseSum]
    have hf : fillCount ln.horiz (it :: its) =
        (if (it.mainSizing ln.horiz).isFill then 1 else 0) + fillCount ln.horiz its := by
      simp only [fillCount, List.filter_cons]; split <;> simp <;> omega
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

theorem cumShare_zero (L : Int) (f : Nat) : cumShare L f 0 = 0 := by simp [cumShare]

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
  cases h <;> simp [mainOf, padMain, Rect.inset] <;> omega

theorem arrange_fillExact (m : TextMetrics) (c r : Rect) (s : Sized) :
    FillExact (arrange m c r s) := by
  cases s with
  | box st ctl sz kids =>
    simp only [arrange, FillExact]
    intro hax
    have hlen : (childRects st r (kids.map Sized.item)).length = kids.length := by
      simp [childRects_length]
    have hcr : childRects st r (kids.map Sized.item) =
        lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item) := by
      unfold childRects; cases hx : st.axis <;> simp_all [Axis.horiz]
    have hps : (arrangeList m (innerClip st c r) (childRects st r (kids.map Sized.item)) kids).map
        (fun k => ((if Axis.horiz st.axis then k.sizings.1 else k.sizings.2),
          mainOf (Axis.horiz st.axis) k.rect)) =
        mainPairs (Axis.horiz st.axis) (kids.map Sized.item)
          (lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item)) := by
      rw [arrangeList_map m _ (fun sz q => ((if Axis.horiz st.axis then sz.1 else sz.2),
        mainOf (Axis.horiz st.axis) q)) _ _ hlen, hcr]
      simp [mainPairs, List.zipWith_map_left, Item.mainSizing, Sized.item]
    rw [hps]
    have hl : (mainPairs (Axis.horiz st.axis) (kids.map Sized.item)
        (lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item))).length =
        (kids.map Sized.item).length := by
      simp [mainPairs, lineRects_length]
    rw [hl]
    intro hany hle
    have := lineRects_fill (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item) hany
      (by rw [mainOf_inset]; omega)
    rw [mainOf_inset] at this
    omega
  | text => simp [arrange, FillExact]
  | field => simp [arrange, field, FillExact]

/-- **Fill exactness.** In every row and column of the laid-out tree with a fill child, if the
other children, gaps and padding fit, then children, gaps and padding span the parent exactly
along the main axis. -/
theorem layout_fillExact (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere FillExact :=
  arrange_everywhere' m _ (arrange_fillExact m) _ _ _

/-! ## Carets and selections -/

theorem offAt_eq (offs : Array Int) {i : Nat} (h : i < offs.size) : offAt offs i = offs[i] := by
  simp [offAt, h]

/-- Under valid metrics every caret offset lies between 0 and the text's width. -/
theorem offAt_bounds {m : TextMetrics} (hm : m.Valid) (f : Font) (s : String) (i : Nat) :
    0 ≤ offAt (m.offsets f s) i ∧ offAt (m.offsets f s) i ≤ m.width f s := by
  have hsz := hm.size f s
  have h0 := hm.zero f s
  have hpos : 0 < (m.offsets f s).size := by omega
  have hz : (m.offsets f s)[0] = 0 := by
    rw [Array.getElem?_eq_getElem hpos] at h0; simpa using h0
  have hlast : m.width f s = (m.offsets f s)[(m.offsets f s).size - 1] := by
    simp [TextMetrics.width, Array.back?, Array.getElem?_eq_getElem (show (m.offsets f s).size - 1 < (m.offsets f s).size by omega)]
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
    · simp [he]
    · simp only [show ¬ min v.anchor v.caret = max v.anchor v.caret by omega, ite_false]
      exact ⟨_, rfl, rfl, rfl, rfl, by simp only; omega⟩
  | box => simp [arrange, CaretPlaced]
  | text => simp [arrange, CaretPlaced]

/-- **Caret placement.** In every field of the laid-out tree, the caret's x is the text origin
plus the caret's offset, lies within the text's extent, and lies inside the content box whenever
the box is at least a point wide; the selection runs between the offsets of its ends. -/
theorem layout_caretPlaced {m : TextMetrics} (hm : m.Valid) (w : Size) (n : Node) :
    (layout m w n).Everywhere (CaretPlaced m) :=
  arrange_everywhere' m _ (arrange_caretPlaced hm) _ _ _

/-! ## The mono metrics are valid -/

theorem _root_.Cairn.TextMetrics.mono_valid : TextMetrics.mono.Valid where
  size f s := by simp [TextMetrics.mono]
  zero f s := by simp [TextMetrics.mono]
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

/-- `sp i + sp (i+1) + … + sp (i+n-1)`. -/
def spSum (sp : Nat → Int) : Nat → Nat → Int
  | _, 0 => 0
  | i, n + 1 => sp i + spSum sp (i + 1) n

theorem spSum_nonneg (sp : Nat → Int) (hsp : ∀ i, 0 ≤ sp i) : ∀ i n, 0 ≤ spSum sp i n
  | _, 0 => by simp [spSum]
  | i, n + 1 => by
    have := hsp i; have := spSum_nonneg sp hsp (i + 1) n; simp only [spSum]; omega

theorem spSum_const (sp : Nat → Int) (g : Nat) (hsp : ∀ i, sp i = g) :
    ∀ i n, spSum sp i n = ((g * n : Nat) : Int)
  | _, 0 => by simp [spSum]
  | i, n + 1 => by
    have := spSum_const sp g hsp (i + 1) n
    simp only [spSum, hsp i, this, Nat.mul_succ]; omega

theorem spSum_tele (sp : Nat → Int) (g : Nat) (F : Nat → Int) (hsp : ∀ i, sp i = g + (F (i + 1) - F i)) :
    ∀ i n, spSum sp i n = ((g * n : Nat) : Int) + (F (i + n) - F i)
  | i, 0 => by simp [spSum]
  | i, n + 1 => by
    have := spSum_tele sp g F hsp (i + 1) n
    simp only [spSum, hsp i, this, Nat.mul_succ]
    rw [show i + 1 + n = i + (n + 1) by omega]; omega

theorem sum_nonneg (l : List Int) (h : ∀ x ∈ l, 0 ≤ x) : 0 ≤ l.sum := by
  induction l with
  | nil => simp
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
  | nil => simp [Line.go] at hr
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
  | [], _, _, _ => by simp [Line.go]
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
      | nil => simp [Line.go] at hr
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
  | [], _, _, _ => by simp [Line.go]
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
    have := mainPairs_snd h its rs (by simpa using hl)
    simp only [mainPairs] at this
    simp only [mainPairs, List.zipWith_cons_cons, List.map_cons, this]
  | [], _ :: _, hl => by simp at hl
  | _ :: _, [], hl => by simp at hl

/-- The children's main-axis lengths add up to the space the line uses. -/
theorem lineRects_sum (h : Bool) (st : Style) (c : Rect) (items : List Item) :
    ((lineRects h st c items).map (mainOf h)).sum =
      if fillCount h items = 0 then baseSum h items
      else baseSum h items + leftover h st c items := by
  obtain ⟨_, h2, _⟩ := Line.go_fill (lineOf h st c items) items 0 0
    ((if h then c.x else c.y) + startOffset st.justify (free h st c items))
  rw [mainPairs_snd _ _ _ (by simp [Line.go_length])] at h2
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
  have hx := hx (by cases h <;> simp [crossOf] at hcr ⊢ <;> omega)
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
        simp [spacing, hj, hpos, hk, fillShare])]
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
    intro hsize hfit k hk
    have hlen : (childRects st r (kids.map Sized.item)).length = kids.length := by
      simp [childRects_length]
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
          stackRects st (r.inset st.padding) (kids.map Sized.item) := by simp [childRects, hx]
      rw [e] at hmem hsize'
      exact stackRects_inside _ _ _ hsize' _ hmem
    | row | column =>
      have e : childRects st r (kids.map Sized.item) =
          lineRects (Axis.horiz st.axis) st (r.inset st.padding) (kids.map Sized.item) := by
        simp [childRects, hx, Axis.horiz]
      rw [e] at hmem hsize' hrs
      refine lineRects_inside _ st _ _ (fun q hq => ?_) ?_ _ hmem
      · have := hsize' q hq; simp only [crossOf]; split <;> omega
      · have hf := hfit (by simp [hx])
        rw [e] at hf
        rw [← hrs, List.map_map]
        simpa [Function.comp_def, arrangeList_length] using hf
  | text => simp [arrange, ChildrenInside]
  | field => simp [arrange, field, ChildrenInside]

/-- **Children that fit stay inside.** In every container of the laid-out tree, if the children
fit the content box (in size, and along the main axis with gaps), each child's rect is inside
it. -/
theorem layout_childrenInside (m : TextMetrics) (w : Size) (n : Node) :
    (layout m w n).Everywhere ChildrenInside :=
  arrange_everywhere' m _ (arrange_childrenInside m) _ _ _

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
  caretPlaced := layout_caretPlaced hm w n

end Cairn.Layout

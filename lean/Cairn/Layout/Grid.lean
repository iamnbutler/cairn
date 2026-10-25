import Cairn.UI.Grid
import Cairn.Layout.Rigid

/-! # Grids: the theorems

About `Cairn.Grid` (`Cairn/UI/Grid.lean`), for every box size and every number of cards. The
first four are about the arithmetic alone and are proved in `Cairn/UI/Grid.lean` itself, which
apps link, so a claim can cite them; the last three are about the layout pass and are here.

* **Columns** (`columns_pos`, `columns_fits`, `le_columns`, `not_fits_succ`): at least one, and
  the most cards of the minimum width that fit with their gaps. When one fits, every card is
  at least that wide unless the rows had to shrink to fit the height (`minW_le_widthShare`).
* **Aspect** (`cardH_aspect`): a card's height is its width at the aspect ratio plus the
  caption whenever the box is tall enough for the captions.
* **Inside** (`cell_inside`): every card's rect is inside the box.
* **Reading order** (`cell_before`): a later card is in a lower row, or in the same row to the
  right; so **no two cards overlap** (`cell_disjoint`, `rects_pairwise`).
* **Layout** (`cells_rects`): laid out by the ordinary pass, `Grid.node`'s cells land exactly on
  `Grid.rects`, wherever the parent puts the grid; its controls are the cards' in the order of
  the items, at every size (`node_controls`).
* **Hit testing** (`hitTarget_cell`): a point in card `i`'s rect hits what card `i` alone would
  hit: no other card can take it. -/

namespace Cairn.Grid
open Cairn.Layout Cairn.Runtime

variable (g : Grid)

/-! ## Chunks -/

theorem chunksAux_flatten {α : Type} (c : Nat) (hc : 1 ≤ c) :
    ∀ (fuel : Nat) (xs : List α), xs.length ≤ fuel → (chunksAux c fuel xs).flatten = xs
  | 0, [], _ => rfl
  | 0, _ :: _, h => by simp at h
  | _ + 1, [], _ => rfl
  | f + 1, x :: xs, h => by
    simp only [chunksAux, List.flatten_cons]
    rw [chunksAux_flatten c hc f _ (by simp only [List.length_drop, List.length_cons] at h ⊢; omega),
      List.take_append_drop]

/-- **Chunks keep the order**: the rows, read one after another, are the items. -/
theorem chunks_flatten {α : Type} (c : Nat) (hc : 1 ≤ c) (xs : List α) :
    (chunks c xs).flatten = xs := chunksAux_flatten c hc _ xs (Nat.le_refl _)

/-! ## Layout -/

/-- A line of identical items, each `fixed` on both axes, with constant spacing and `start`
alignment: item `q` starts `q` pitches along. -/
theorem Line.go_uniform (ln : Line) (it : Item) (a b gap : Nat)
    (hsp : ∀ i, ln.spacing i = gap) (hm : it.mainSizing ln.horiz = .fixed a)
    (hc : it.crossSizing ln.horiz = .fixed b) (hal : ln.align = .start) :
    ∀ (its : List Item), (∀ x ∈ its, x = it) → ∀ (i j : Nat) (pos : Int),
      ln.go i j pos its =
        (List.range its.length).map fun q =>
          mkRect ln.horiz (pos + ((q * (a + gap) : Nat) : Int)) a ln.c0 b
  | [], _, _, _, _ => rfl
  | x :: xs, hx, i, j, pos => by
    have hxi : x = it := hx x (List.mem_cons_self ..)
    subst hxi
    have ih := Line.go_uniform ln x a b gap hsp hm hc hal xs
      (fun y hy => hx y (List.mem_cons_of_mem _ hy))
    simp only [Line.go, List.length_cons, List.range_succ_eq_map, List.map_cons, List.map_map]
    rw [ih]
    simp only [mainSize, hm, mainBase, crossPlace, hc, hal, hsp, List.cons.injEq]
    refine ⟨by congr 1; omega, List.map_congr_left fun q _ => ?_⟩
    simp only [Function.comp, Nat.succ_mul]
    congr 1
    push_cast; omega

theorem lineRects_uniform (hz : Bool) (st : Style) (content : Rect) (items : List Item) (it : Item)
    (a b : Nat) (hj : st.justify = .start) (hal : st.align = .start)
    (hm : it.mainSizing hz = .fixed a) (hc : it.crossSizing hz = .fixed b)
    (hx : ∀ x ∈ items, x = it) :
    lineRects hz st content items = (List.range items.length).map fun q =>
      mkRect hz ((if hz then content.x else content.y) + ((q * (a + st.gap) : Nat) : Int)) a
        (if hz then content.y else content.x) b := by
  unfold lineRects
  rw [Line.go_uniform _ it a b st.gap (fun i => by simp only [lineOf, spacing, hj]) hm hc
    (by simp only [lineOf, hal]) items hx]
  simp only [startOffset, hj, Int.add_zero, lineOf]

theorem arrangeList_zipWith (m : TextMetrics) (c : Rect) :
    ∀ (rs : List Rect) (ss : List Sized), rs.length = ss.length →
      arrangeList m c rs ss = List.zipWith (arrange m c) rs ss
  | [], [], _ => rfl
  | r :: rs, s :: ss, h => by
    simp only [arrangeList, List.zipWith_cons_cons,
      arrangeList_zipWith m c rs ss (by simpa using h)]
  | [], _ :: _, h => by simp at h
  | _ :: _, [], h => by simp at h

/-- What a cell offers its row: fixed on both axes at the card's size. -/
def cellItem (w h : Nat) : Item := ⟨.fixed w, .fixed h, ⟨w, h⟩, true⟩

theorem cellNode_item (m : TextMetrics) (aw : Int) (w h : Nat) (k : Node) :
    (measure m aw (cellNode w h k)).item = cellItem w h := by
  simp only [cellNode, Layout.measure, measureList, Sized.item, Sized.size, Sized.sizings, resolve,
    cellItem]

theorem rowNode_item (m : TextMetrics) (aw : Int) (W H n : Nat) (cells : List Node) :
    (measure m aw (g.rowNode W H n cells)).item = cellItem (g.usedW W H n) (g.cardH W H n) := by
  simp only [rowNode, rowStyle, Layout.measure, Sized.item, Sized.size, Sized.sizings, resolve, cellItem]

/-- Where row `q` goes, for a grid whose rect starts at `(x, y)`. -/
def rowRect (x y : Int) (W H n q : Nat) : Rect :=
  ⟨x + (g.offset W H n : Int), y + ((q * (g.cardH W H n + g.vgap W H n) : Nat) : Int),
   g.usedW W H n, g.cardH W H n⟩

/-- The cells of a laid-out grid: its rows' children, in order. -/
def cells (l : Laid) : List Laid := l.children.flatMap Laid.children

/-- A row of at most `columns` cells, laid out at row `q`'s rect: its cells land on
`cell (q * columns + k)`. -/
theorem row_rects (m : TextMetrics) (aw : Int) (clip : Rect) (x y : Int) (W H n q : Nat)
    (row : List Node) (hrow : ∀ k ∈ row, ∃ c, k = cellNode (g.cardW W H n) (g.cardH W H n) c)
    (hlen : row.length ≤ g.columns W) :
    (arrange m clip (g.rowRect x y W H n q) (measure m aw (g.rowNode W H n row))).children.map
        Laid.rect = (List.range' (q * g.columns W) row.length).map (g.cell x y W H n) := by
  have hitems : ∀ aw', ∀ it ∈ (measureList m aw' row).map Sized.item,
      it = cellItem (g.cardW W H n) (g.cardH W H n) := by
    intro aw'
    rw [measureList_eq_map, List.map_map]
    intro it hit
    obtain ⟨k, hk, rfl⟩ := List.mem_map.1 hit
    obtain ⟨c, rfl⟩ := hrow k hk
    exact cellNode_item m _ _ _ c
  simp only [rowNode, rowStyle, Layout.measure, arrange_children_box]
  rw [arrangeList_rects]
  · simp only [childRects, placeRects, scrolled]
    rw [lineRects_uniform true _ _ _ (cellItem (g.cardW W H n) (g.cardH W H n)) (g.cardW W H n)
      (g.cardH W H n) rfl rfl rfl rfl (hitems _)]
    rw [List.length_map, measureList_eq_map, List.length_map, List.range'_eq_map_range,
      List.map_map]
    refine List.map_congr_left fun k hk => ?_
    have hk' : k < g.columns W := by
      have := List.mem_range.1 hk; omega
    have hc := columns_pos g W
    have hdiv : (q * g.columns W + k) / g.columns W = q := by
      rw [Nat.add_comm, Nat.add_mul_div_right _ _ (by omega), Nat.div_eq_of_lt hk', Nat.zero_add]
    have hmod : (q * g.columns W + k) % g.columns W = k := by
      rw [Nat.add_comm, Nat.add_mul_mod_self_right, Nat.mod_eq_of_lt hk']
    simp only [Function.comp, mkRect, ↓reduceIte, rowRect, Rect.inset, cell,
      hdiv, hmod, Rect.mk.injEq]
    refine ⟨?_, ?_, trivial, trivial⟩ <;> push_cast <;> omega
  · simp only [childRects, placeRects, scrolled, lineRects, Line.go_length, List.length_map]

theorem chunksAux_length_le {α : Type} (c : Nat) (hc : 1 ≤ c) :
    ∀ (fuel : Nat) (xs : List α) (row : List α), row ∈ chunksAux c fuel xs →
      row.length ≤ c ∧ ∀ k ∈ row, k ∈ xs
  | 0, _, _, h => by simp [chunksAux] at h
  | _ + 1, [], _, h => by simp [chunksAux] at h
  | f + 1, x :: xs, row, h => by
    simp only [chunksAux, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨by simp only [List.length_take]; omega, fun k hk => List.mem_of_mem_take hk⟩
    · obtain ⟨h1, h2⟩ := chunksAux_length_le c hc f _ row h
      exact ⟨h1, fun k hk => List.mem_of_mem_drop (h2 k hk)⟩

/-- Rows laid out from row `q0` on: their cells land on `cell (q0 * columns)` onward. -/
theorem rows_rects (m : TextMetrics) (aw : Int) (clip : Rect) (x y : Int) (W H n : Nat) :
    ∀ (fuel : Nat) (ys : List Node) (q0 : Nat), ys.length ≤ fuel →
      (∀ k ∈ ys, ∃ c, k = cellNode (g.cardW W H n) (g.cardH W H n) c) →
      (List.zipWith (fun q row => arrange m clip (g.rowRect x y W H n q)
          (measure m aw (g.rowNode W H n row)))
        (List.range' q0 (chunksAux (g.columns W) fuel ys).length)
        (chunksAux (g.columns W) fuel ys)).flatMap (fun l => l.children.map Laid.rect) =
      (List.range' (q0 * g.columns W) ys.length).map (g.cell x y W H n)
  | 0, [], _, _, _ => rfl
  | 0, _ :: _, _, h, _ => by simp at h
  | _ + 1, [], _, _, _ => rfl
  | f + 1, y0 :: ys, q0, h, hys => by
    have hc := columns_pos g W
    have hb : (y0 :: ys).length = ys.length + 1 := rfl
    have h' : ys.length ≤ f := by omega
    simp only [chunksAux, List.length_cons, List.range'_succ, List.zipWith_cons_cons,
      List.flatMap_cons]
    rw [row_rects g m aw clip x y W H n q0 _ (fun k hk => hys k (List.mem_of_mem_take hk))
      (by simp only [List.length_take]; omega)]
    have ih := rows_rects m aw clip x y W H n f ((y0 :: ys).drop (g.columns W)) (q0 + 1)
      (by rw [List.length_drop]; omega)
      (fun k hk => hys k (List.mem_of_mem_drop hk))
    rw [ih]
    simp only [List.length_take, List.length_drop, List.length_cons, ← List.map_append]
    congr 1
    by_cases hl : g.columns W ≤ ys.length + 1
    · rw [Nat.min_eq_left hl, Nat.add_mul, Nat.one_mul, List.range'_append_1]
      rw [show g.columns W + (ys.length + 1 - g.columns W) = ys.length + 1 by omega, List.range'_succ]
    · rw [Nat.min_eq_right (by omega), show ys.length + 1 - g.columns W = 0 by omega,
        List.range'_zero, List.append_nil, List.range'_succ]

theorem chunks_mem {α : Type} (c : Nat) (hc : 1 ≤ c) (xs : List α) (row : List α)
    (h : row ∈ chunks c xs) : row.length ≤ c ∧ ∀ k ∈ row, k ∈ xs :=
  chunksAux_length_le c hc _ xs row h

/-- The grid laid out in `r`: its children are its rows, each laid out at its row's rect. -/
theorem node_children {α : Type} (m : TextMetrics) (aw : Int) (clip r : Rect) (W H : Nat)
    (card : Nat → Nat → α → Node) (xs : List α) :
    (arrange m clip r (measure m aw (g.node W H card xs))).children =
      List.zipWith (fun q row => arrange m clip (g.rowRect r.x r.y W H xs.length q)
          (measure m (innerAvail (g.style W H xs.length) aw) (g.rowNode W H xs.length row)))
        (List.range' 0 (chunks (g.columns W) (xs.map fun x => cellNode (g.cardW W H xs.length)
          (g.cardH W H xs.length) (card (g.cardW W H xs.length) (g.cardH W H xs.length) x))).length)
        (chunks (g.columns W) (xs.map fun x => cellNode (g.cardW W H xs.length)
          (g.cardH W H xs.length) (card (g.cardW W H xs.length) (g.cardH W H xs.length) x))) := by
  simp only [node, style, Layout.measure, arrange_children_box]
  rw [measureList_eq_map, arrangeList_zipWith]
  · simp only [childRects, placeRects, scrolled, innerClip, Style.clips, Bool.false_eq_true,
      Bool.or_false, Option.isSome_none, ↓reduceIte]
    rw [lineRects_uniform false _ _ _ (cellItem (g.usedW W H xs.length) (g.cardH W H xs.length))
      (g.cardH W H xs.length) (g.usedW W H xs.length) rfl rfl rfl rfl (by
        intro it hit
        simp only [List.map_map, List.mem_map] at hit
        obtain ⟨k, _, rfl⟩ := hit
        exact rowNode_item g m _ W H xs.length k)]
    simp only [List.length_map, List.map_map, List.range_eq_range']
    simp only [List.zipWith_map_left, List.zipWith_map_right]
    refine congrArg (fun F => List.zipWith F _ _) ?_
    funext q row
    simp only [Function.comp]
    congr 1
    simp only [mkRect, Bool.false_eq_true, ↓reduceIte, Rect.inset, rowRect,
      Rect.mk.injEq]
    refine ⟨trivial, ?_, trivial, trivial⟩; omega
  · simp only [childRects, placeRects, scrolled, lineRects, Line.go_length, List.length_map]

/-- **The cells land on `Grid.rects`.** Laid out by the ordinary layout pass, wherever its
parent puts it, the grid's cells are exactly `rects` at the grid's origin, in order. -/
theorem cells_rects {α : Type} (m : TextMetrics) (aw : Int) (clip r : Rect) (W H : Nat)
    (card : Nat → Nat → α → Node) (xs : List α) :
    (cells (arrange m clip r (measure m aw (g.node W H card xs)))).map Laid.rect =
      g.rects r.x r.y W H xs.length := by
  have h := node_children g m aw clip r W H card xs
  simp only [cells, List.map_flatMap]
  rw [h]
  have hc := columns_pos g W
  have := rows_rects g m (innerAvail (g.style W H xs.length) aw) clip r.x r.y W H xs.length _
    (xs.map fun x => cellNode (g.cardW W H xs.length) (g.cardH W H xs.length)
      (card (g.cardW W H xs.length) (g.cardH W H xs.length) x)) 0 (Nat.le_refl _)
    (fun k hk => by
      obtain ⟨x, _, rfl⟩ := List.mem_map.1 hk
      exact ⟨_, rfl⟩)
  simp only [Nat.zero_mul] at this
  rw [rects, List.range_eq_range']
  exact this.trans (by rw [List.length_map])

/-! ## Controls: the cards', in item order -/

theorem flatMap_flatten' {α β : Type} (f : α → List β) :
    ∀ L : List (List α), L.flatten.flatMap f = L.flatMap fun l => l.flatMap f
  | [] => rfl
  | l :: L => by simp only [List.flatten_cons, List.flatMap_append, List.flatMap_cons,
      flatMap_flatten' f L]

theorem flatMap_congr' {α β : Type} {f g : α → List β} :
    ∀ {l : List α}, (∀ x ∈ l, f x = g x) → l.flatMap f = l.flatMap g
  | [], _ => rfl
  | x :: l, h => by
    simp only [List.flatMap_cons, h x (.head _),
      flatMap_congr' (l := l) (fun y hy => h y (.tail _ hy))]

theorem controlsList_eq : ∀ ks : List Node, Node.controlsList ks = ks.flatMap Node.controls
  | [] => rfl
  | k :: ks => by simp only [Node.controlsList, List.flatMap_cons, controlsList_eq ks]

/-- **Stable order**: the grid's controls are its cards' controls, in the order of the items,
whatever the box's size; resizing moves cards but never reorders them. -/
theorem node_controls {α : Type} (W H : Nat) (card : Nat → Nat → α → Node) (xs : List α) :
    (g.node W H card xs).controls =
      xs.flatMap fun x => (card (g.cardW W H xs.length) (g.cardH W H xs.length) x).controls := by
  simp only [node, Node.controls, Option.toList, List.nil_append, controlsList_eq,
    List.flatMap_map, rowNode]
  rw [← flatMap_flatten', chunks_flatten _ (columns_pos g W), List.flatMap_map]
  simp only [cellNode, Node.controls, Option.toList, Node.controlsList, List.nil_append,
    List.append_nil]

/-! ## Hit testing -/

theorem mem_zipWith' {α β γ : Type} {f : α → β → γ} {c : γ} :
    ∀ {as : List α} {bs : List β}, c ∈ List.zipWith f as bs → ∃ a ∈ as, ∃ b ∈ bs, c = f a b
  | [], _, h => by simp at h
  | _ :: _, [], h => by simp at h
  | a :: as, b :: bs, h => by
    simp only [List.zipWith_cons_cons, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨a, .head _, b, .head _, rfl⟩
    · obtain ⟨a', ha, b', hb, rfl⟩ := mem_zipWith' h
      exact ⟨a', .tail _ ha, b', .tail _ hb, rfl⟩

theorem mem_arrangeList' (m : TextMetrics) (c : Rect) :
    ∀ {rs : List Rect} {ss : List Sized} {x : Laid}, x ∈ arrangeList m c rs ss →
      ∃ r, ∃ s ∈ ss, x = arrange m c r s
  | _, [], _, h => by simp [arrangeList] at h
  | [], s :: ss, x, h => by
    simp only [arrangeList, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨_, s, .head _, rfl⟩
    · obtain ⟨r, s', hs, rfl⟩ := mem_arrangeList' m c h
      exact ⟨r, s', .tail _ hs, rfl⟩
  | r :: rs, s :: ss, x, h => by
    simp only [arrangeList, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨_, s, .head _, rfl⟩
    · obtain ⟨r, s', hs, rfl⟩ := mem_arrangeList' m c h
      exact ⟨r, s', .tail _ hs, rfl⟩

theorem hitsList_eq (o : Option Target) : ∀ ls : List Laid, hitsList o ls = ls.flatMap (hitsOf o)
  | [] => rfl
  | l :: ls => by simp only [hitsList, List.flatMap_cons, hitsList_eq o ls]

/-- Every clip in a laid-out subtree lies within the clip it was laid out in. -/
theorem arrange_clipWithin (m : TextMetrics) (C : Rect) (s : Sized) (r : Rect) :
    (arrange m C r s).Everywhere fun l => ∀ p, l.clip.contains p = true → C.contains p = true :=
  arrange_everywhere m _ (fun c _ => ∀ p, c.contains p = true → C.contains p = true)
    (fun c r s hq => ⟨by simpa only [arrange_clip] using hq, fun k hk p hp => by
      rw [arrange_childClips m c r s k hk] at hp
      apply hq
      cases s with
      | box st ctl sz kids =>
        simp only [arrange, Laid.innerClip, innerClip] at hp
        split at hp
        · exact Rect.inter_contains_left hp
        · exact hp
      | text => simpa only [arrange, Laid.innerClip, Laid.clip] using hp
      | field => simpa only [arrange, field, Laid.innerClip, Laid.clip] using hp⟩)
    s C r (fun _ h => h)

/-- A hit entry of such a subtree contains only points of that clip. -/
theorem hits_within {C : Rect} {l : Laid}
    (hE : l.Everywhere fun l => ∀ p, l.clip.contains p = true → C.contains p = true) :
    ∀ (o : Option Target) (e : Hit) (p : Point), e ∈ hitsOf o l → e.visible.contains p = true →
      C.contains p = true := by
  induction hE with
  | @intro l hP hK ih =>
    intro o e p he hc
    cases l with
    | box r c st ctl kids =>
      simp only [hitsOf, List.mem_append] at he
      rcases he with he | he
      · split at he
        · simp only [List.mem_singleton] at he
          subst he
          exact hP p (Rect.inter_contains_right hc)
        · simp only [List.not_mem_nil] at he
      · obtain ⟨k, hk, he⟩ := mem_hitsList he
        exact ih k (by simp only [Laid.children, hk]) _ e p he hc
    | text =>
      simp only [hitsOf, List.mem_singleton] at he
      subst he; exact hP p (Rect.inter_contains_right hc)
    | field =>
      simp only [hitsOf, List.mem_singleton] at he
      subst he; exact hP p (Rect.inter_contains_right hc)

/-- A cell's hit entries contain only points of its rect: it clips its card. -/
theorem cellNode_hits (m : TextMetrics) (aw : Int) (clip q : Rect) (w h : Nat) (k : Node) :
    ∀ (e : Hit) (p : Point), e ∈ hitsOf none (arrange m clip q (measure m aw (cellNode w h k))) →
      e.visible.contains p = true → q.contains p = true := by
  intro e p he hc
  simp only [cellNode, Layout.measure, measureList, arrange, hitsOf, paints, Option.isSome_none,
    Bool.or_self, Bool.false_eq_true, ↓reduceIte, List.nil_append, innerClip] at he
  obtain ⟨x, hx, he⟩ := mem_hitsList he
  obtain ⟨r', s', hs, rfl⟩ := mem_arrangeList' m _ hx
  have := hits_within (arrange_clipWithin m _ s' r') none e p he hc
  exact Rect.inter_contains_right this

/-- The grid's hit entries are its cells', in order: the grid and its rows paint nothing. -/
theorem node_hits {α : Type} (m : TextMetrics) (aw : Int) (clip r : Rect) (W H : Nat)
    (card : Nat → Nat → α → Node) (xs : List α) :
    let l := arrange m clip r (measure m aw (g.node W H card xs))
    hitsOf none l = (cells l).flatMap (hitsOf none) ∧
      ∀ k ∈ cells l, ∀ (e : Hit) (p : Point), e ∈ hitsOf none k → e.visible.contains p = true →
        k.rect.contains p = true := by
  intro l
  have hch := node_children g m aw clip r W H card xs
  have hrows : ∀ row ∈ l.children, hitsOf none row = row.children.flatMap (hitsOf none) ∧
      ∀ k ∈ row.children, ∀ (e : Hit) (p : Point), e ∈ hitsOf none k →
        e.visible.contains p = true → k.rect.contains p = true := by
    intro row hrow
    rw [hch] at hrow
    obtain ⟨q, _, cs, hcs, rfl⟩ := mem_zipWith' hrow
    refine ⟨?_, ?_⟩
    · simp only [rowNode, rowStyle, Layout.measure, arrange, hitsOf, paints, Option.isSome_none,
        Bool.or_self, Bool.false_eq_true, ↓reduceIte, List.nil_append, hitsList_eq, Laid.children]
    · intro k hk e p he hc
      simp only [rowNode, Layout.measure, arrange, Laid.children] at hk
      obtain ⟨r', s', hs, rfl⟩ := mem_arrangeList' m _ hk
      rw [measureList_eq_map] at hs
      obtain ⟨c, hc', rfl⟩ := List.mem_map.1 hs
      have hcm := (chunks_mem _ (columns_pos g W) _ cs hcs).2 c hc'
      obtain ⟨x, _, rfl⟩ := List.mem_map.1 hcm
      rw [arrange_rect]
      exact cellNode_hits m _ _ r' _ _ _ e p he hc
  refine ⟨?_, ?_⟩
  · have hl : l = .box r clip (g.style W H xs.length) none l.children := by
      simp only [l, node, Layout.measure, arrange, Laid.children]
    rw [hl]
    simp only [hitsOf, paints, style, Option.isSome_none, Bool.or_self, Bool.false_eq_true,
      ↓reduceIte, List.nil_append, hitsList_eq, cells, Laid.children]
    rw [List.flatMap_assoc]
    exact flatMap_congr' fun row hrow => (hrows row hrow).1
  · intro k hk
    simp only [cells, List.mem_flatMap] at hk
    obtain ⟨row, hrow, hk⟩ := hk
    exact (hrows row hrow).2 k hk

/-- If only the `i`-th list's entries can satisfy `q`, the topmost of the concatenation that
does is the `i`-th's. -/
theorem find?_flatMap_only {β : Type} (Ls : List β) (f : β → List Hit) (q : Hit → Bool) (i : Nat)
    (hi : i < Ls.length)
    (h : ∀ j (hj : j < Ls.length), j ≠ i → ∀ e ∈ f Ls[j], q e = false) :
    (Ls.flatMap f).reverse.find? q = (f Ls[i]).reverse.find? q := by
  have hsplit : Ls = Ls.take i ++ Ls[i] :: Ls.drop (i + 1) := by
    simp only [List.take_append_drop, List.getElem_cons_drop]
  have hpre : ∀ e ∈ (Ls.take i).flatMap f, q e = false := by
    intro e he
    obtain ⟨b, hb, he⟩ := List.mem_flatMap.1 he
    obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem hb
    simp only [List.length_take] at hj
    rw [List.getElem_take] at he
    exact h j (by omega) (by omega) e he
  have hpost : ∀ e ∈ (Ls.drop (i + 1)).flatMap f, q e = false := by
    intro e he
    obtain ⟨b, hb, he⟩ := List.mem_flatMap.1 he
    obtain ⟨j, hj, rfl⟩ := List.getElem_of_mem hb
    simp only [List.length_drop] at hj
    rw [List.getElem_drop] at he
    exact h (i + 1 + j) (by omega) (by omega) e he
  conv => lhs; rw [hsplit]
  rw [List.flatMap_append, List.flatMap_cons, List.reverse_append, List.reverse_append,
    List.find?_append, List.find?_append,
    List.find?_eq_none.2 (fun e he => by rw [hpost e (List.mem_reverse.1 he)]; decide)]
  simp only [Option.none_or]
  cases hfi : (f Ls[i]).reverse.find? q with
  | some e => rfl
  | none =>
    simp only [Option.none_or]
    exact List.find?_eq_none.2 (fun e he => by rw [hpre e (List.mem_reverse.1 he)]; decide)

theorem cells_length {α : Type} (m : TextMetrics) (aw : Int) (clip r : Rect) (W H : Nat)
    (card : Nat → Nat → α → Node) (xs : List α) :
    (cells (arrange m clip r (measure m aw (g.node W H card xs)))).length = xs.length := by
  have := congrArg List.length (cells_rects g m aw clip r W H card xs)
  rwa [List.length_map, rects_length] at this

-- region: grid-hit
/-- **Hit testing finds the cell's controls.** A point in card `i`'s rect hits exactly what
card `i`'s cell alone would hit: no other card can take it, and it answers with a control of
that cell or nothing. -/
theorem hitTarget_cell {α : Type} (m : TextMetrics) (aw : Int) (clip r : Rect) (W H : Nat)
    (card : Nat → Nat → α → Node) (xs : List α) (i : Nat) (hi : i < xs.length) (p : Point)
    (hp : (g.cell r.x r.y W H xs.length i).contains p = true) :
    ∃ k, (cells (arrange m clip r (measure m aw (g.node W H card xs))))[i]? = some k ∧
      k.rect = g.cell r.x r.y W H xs.length i ∧
      hitTarget (arrange m clip r (measure m aw (g.node W H card xs))) p = hitTarget k p := by
  generalize hl : arrange m clip r (measure m aw (g.node W H card xs)) = l
  have hlen := cells_length g m aw clip r W H card xs
  have hrects := cells_rects g m aw clip r W H card xs
  have hnh := node_hits g m aw clip r W H card xs
  rw [hl] at hlen hrects hnh
  have hrect : ∀ j (hj : j < (cells l).length), (cells l)[j].rect = g.cell r.x r.y W H xs.length j := by
    intro j hj
    have := congrArg (·[j]?) hrects
    simp only [List.getElem?_map, List.getElem?_eq_getElem hj, rects, List.getElem?_range
      (show j < xs.length by omega), Option.map_some, Option.some.injEq] at this
    exact this
  obtain ⟨hhits, hin⟩ := hnh
  refine ⟨(cells l)[i]'(by omega), List.getElem?_eq_getElem _, hrect i (by omega), ?_⟩
  simp only [hitTarget, hits]
  rw [hhits, find?_flatMap_only (cells l) (hitsOf none) _ i (by omega)]
  intro j hj hji e he
  cases hc : e.visible.contains p
  · rfl
  · exfalso
    have hjp := hin _ (List.getElem_mem hj) e p he hc
    rw [hrect j hj] at hjp
    exact Rect.disjoint_contains (cell_disjoint g r.x r.y W H xs.length j i hji) hjp hp
-- endregion: grid-hit

end Cairn.Grid

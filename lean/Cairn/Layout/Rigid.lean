import Cairn.Layout.Check

/-! # Rigid views: pressable at every size they fit, for every state

`Layout/Check.lean` proves a view pressable by evaluating its layout, which works for one
concrete state, window and set of metrics. An app with a list of any length needs the same
fact for all of them. This file gives a structural condition, `FitsIn n w h`, under which a
view laid out in a `w × h` rect satisfies every per-node condition of `Pressable` and every
control has a nonempty rect, **for all text metrics**.

The idea: in a *rigid* view every box and field is `fixed` or `fill` on both axes, never
`hug`, so no rect depends on how wide a string is. Text appears only inside boxes that clip
and hold nothing but text (`Fits` exempts those: the text may overflow, the clip contains it).
Then each child's size is known from its parent's alone:

- on the cross axis, `fixed n` gets `n` and `fill` gets the content box's length;
- on the main axis, `fixed n` gets `n`, and `fill` gets a share of the leftover space, at least
  `⌊leftover / fills⌋` (`fillShare_ge`).

`FitsIn` asks, node by node, that the fixed children and gaps fit, that each child fits at the
size it will get, and that controls have positive size. `fitsIn_arrange` proves the rest;
`hitTest_center_of_fitsIn` turns it into "hit testing at the centre of every control returns
that control". Positions never appear, so a list of `k` identical rows is handled by one
argument about one row. -/

namespace Cairn.Layout
open Cairn.Runtime

/-! ## The condition -/

/-- A node's sizing on each axis (text hugs). -/
def nodeSizings : Node → Sizing × Sizing
  | .box st .. | .field st .. => (st.width, st.height)
  | .text .. => (.hug, .hug)
  | .para _ wr _ => (wr.width, wr.height)

def _root_.Cairn.Node.isText : Node → Bool
  | .text .. => true
  | _ => false

def _root_.Cairn.Sizing.isHug : Sizing → Bool
  | .hug => true
  | _ => false

/-- The length a non-hug sizing gets when its parent offers `offer`. -/
def lenIn (s : Sizing) (offer : Int) : Int :=
  match s with
  | .fixed n => n
  | _ => offer

/-- What a sizing asks for before leftover space is shared (`fill` asks for nothing). -/
def fixedOf (s : Sizing) : Int :=
  match s with
  | .fixed n => n
  | _ => 0

def mainSz (horiz : Bool) (k : Node) : Sizing := if horiz then (nodeSizings k).1 else (nodeSizings k).2
def crossSz (horiz : Bool) (k : Node) : Sizing := if horiz then (nodeSizings k).2 else (nodeSizings k).1

/-- The fixed main-axis lengths of a line's children, plus its gaps. -/
def lineBase (horiz : Bool) (gap : Nat) (kids : List Node) : Int :=
  (kids.map fun k => fixedOf (mainSz horiz k)).sum + gaps gap kids.length

/-- How many of a line's children fill the main axis. -/
def lineFills (horiz : Bool) (kids : List Node) : Nat :=
  (kids.filter fun k => (mainSz horiz k).isFill).length

def PadOk (p : Insets) : Prop := 0 ≤ p.top ∧ 0 ≤ p.right ∧ 0 ≤ p.bottom ∧ 0 ≤ p.left

def contentW (st : Style) (w : Int) : Int := w - st.padding.left - st.padding.right
def contentH (st : Style) (h : Int) : Int := h - st.padding.top - st.padding.bottom
def mainIn (horiz : Bool) (st : Style) (w h : Int) : Int :=
  if horiz then contentW st w else contentH st h
def crossIn (horiz : Bool) (st : Style) (w h : Int) : Int :=
  if horiz then contentH st h else contentW st w

/-- Width and height from main- and cross-axis lengths. -/
def wOf (horiz : Bool) (main cross : Int) : Int := if horiz then main else cross
def hOf (horiz : Bool) (main cross : Int) : Int := if horiz then cross else main

/-- `FitsIn n w h`: laid out in a `w × h` rect, `n` and everything below it fit, and its
controls have positive size. Three shapes:

- wrapped text (a clipping column of lines, with no controls);
- a field of positive size;
- a box that clips and holds only text (a label: the text may overflow; the clip holds it);
- a row or column whose children are all `fixed` or `fill` on both axes, whose fixed
  main-axis lengths and gaps fit its content box, whose fixed cross-axis lengths fit too, and
  whose every child fits at the size it will get. A `fill` child on the main axis must fit at
  every length from `⌊leftover / fills⌋` up. A box with a control has no controls below it. -/
inductive FitsIn : Node → Int → Int → Prop
  /-- Wrapped text always fits: it is a clipping column of text with no controls. -/
  | para {ts : TextStyle} {wr : Wrap} {s : String} {w h : Int} : FitsIn (.para ts wr s) w h
  | field {st : Style} {ts : TextStyle} {c : Control} {v : FieldView} {w h : Int} :
      0 < w → 0 < h → FitsIn (.field st ts c v) w h
  | clipped {st : Style} {ctl : Option Control} {kids : List Node} {w h : Int} :
      st.clip = true → (∀ k ∈ kids, k.isText = true) →
      (ctl.isSome = true → 0 < w ∧ 0 < h) → FitsIn (.box st ctl kids) w h
  | line {st : Style} {ctl : Option Control} {kids : List Node} {w h : Int} :
      st.axis ≠ .stack → PadOk st.padding → 0 ≤ contentW st w → 0 ≤ contentH st h →
      (ctl.isSome = true → 0 < w ∧ 0 < h ∧ Node.controlsList kids = []) →
      (st.scroll = none → lineBase (Axis.horiz st.axis) st.gap kids ≤ mainIn (Axis.horiz st.axis) st w h) →
      (∀ k ∈ kids, (nodeSizings k).1.isHug = false ∧ (nodeSizings k).2.isHug = false ∧
        fixedOf (crossSz (Axis.horiz st.axis) k) ≤ crossIn (Axis.horiz st.axis) st w h) →
      (∀ k ∈ kids, ∀ len : Int,
          (mainSz (Axis.horiz st.axis) k = .fill →
            (mainIn (Axis.horiz st.axis) st w h - lineBase (Axis.horiz st.axis) st.gap kids) /
              ((lineFills (Axis.horiz st.axis) kids : Nat) : Int) ≤ len) →
          (∀ n : Nat, mainSz (Axis.horiz st.axis) k = .fixed n → len = n) →
          FitsIn k
            (wOf (Axis.horiz st.axis) len
              (lenIn (crossSz (Axis.horiz st.axis) k) (crossIn (Axis.horiz st.axis) st w h)))
            (hOf (Axis.horiz st.axis) len
              (lenIn (crossSz (Axis.horiz st.axis) k) (crossIn (Axis.horiz st.axis) st w h)))) →
      FitsIn (.box st ctl kids) w h

/-! ## Arithmetic -/

/-- Each fill share is at least the even split, rounded down. -/
theorem fillShare_ge {L : Int} {f : Nat} (hf : 0 < f) (j : Nat) :
    L / (f : Int) ≤ fillShare L f j := by
  unfold fillShare cumShare
  have hf' : (f : Int) ≠ 0 := by omega
  have hd := Int.mul_ediv_add_emod L (f : Int)
  have hr := Int.emod_nonneg L hf'
  generalize L / (f : Int) = q at hd ⊢
  generalize L % (f : Int) = r at hd hr
  subst hd
  have e1 : ((f : Int) * q + r) * ((j + 1 : Nat) : Int) =
      r * ((j + 1 : Nat) : Int) + (f : Int) * (q * ((j + 1 : Nat) : Int)) := by
    simp only [Int.add_mul, Int.mul_assoc]; omega
  have e2 : ((f : Int) * q + r) * ((j : Nat) : Int) =
      r * ((j : Nat) : Int) + (f : Int) * (q * ((j : Nat) : Int)) := by
    simp only [Int.add_mul, Int.mul_assoc]; omega
  rw [e1, e2, Int.add_mul_ediv_left _ _ hf', Int.add_mul_ediv_left _ _ hf']
  have hm : r * ((j : Nat) : Int) / (f : Int) ≤ r * ((j + 1 : Nat) : Int) / (f : Int) :=
    Int.ediv_le_ediv (by omega) (Int.mul_le_mul_of_nonneg_left (by omega) hr)
  have : q * ((j + 1 : Nat) : Int) = q * (j : Int) + q := by
    push_cast; rw [Int.mul_add, Int.mul_one]
  omega

theorem le_sum_of_mem {l : List Int} (h : ∀ x ∈ l, 0 ≤ x) {x : Int} (hx : x ∈ l) : x ≤ l.sum := by
  induction l with
  | nil => simp only [List.not_mem_nil] at hx
  | cons y ys ih =>
    simp only [List.sum_cons]
    rcases List.mem_cons.1 hx with rfl | hx
    · have := sum_nonneg ys (fun z hz => h z (.tail _ hz)); omega
    · have := ih (fun z hz => h z (.tail _ hz)) hx; have := h y (.head _); omega

/-! ## Measure and arrange, for rigid children -/

theorem measure_sizings (m : TextMetrics) (aw : Int) (n : Node) :
    (measure m aw n).sizings = nodeSizings n := by
  cases n <;> rfl

theorem measureList_eq_map (m : TextMetrics) (aw : Int) :
    ∀ ks : List Node, measureList m aw ks = ks.map (measure m aw)
  | [] => rfl
  | k :: ks => by simp only [measureList, List.map_cons, measureList_eq_map m aw ks]

/-- With one rect per child, each laid-out child is its node arranged in its rect. -/
theorem mem_arrangeList (m : TextMetrics) (aw : Int) (c : Rect) :
    ∀ (rs : List Rect) (ks : List Node), rs.length = ks.length →
      ∀ k' ∈ arrangeList m c rs (ks.map (measure m aw)),
        ∃ p ∈ List.zip ks rs, k' = arrange m c p.2 (measure m aw p.1)
  | [], [], _, k', hk => by simp only [List.map_nil, arrangeList, List.not_mem_nil] at hk
  | r :: rs, k :: ks, hl, k', hk => by
    simp only [List.map_cons, arrangeList, List.mem_cons] at hk
    rcases hk with rfl | hk
    · exact ⟨(k, r), by simp only [List.zip_cons_cons, List.mem_cons, true_or], rfl⟩
    · obtain ⟨p, hp, e⟩ := mem_arrangeList m aw c rs ks (by simpa using hl) k' hk
      exact ⟨p, by simp only [List.zip_cons_cons, List.mem_cons, hp, or_true], e⟩
  | [], _ :: _, hl, _, _ => by simp at hl
  | _ :: _, [], hl, _, _ => by simp at hl

/-- The main- and cross-axis lengths `Line.go` gives each item. -/
theorem Line.go_lens (ln : Line) :
    ∀ (its : List Item) (i j : Nat) (pos : Int), ∀ p ∈ List.zip its (ln.go i j pos its),
      (∃ j', mainOf ln.horiz p.2 = mainSize ln.horiz ln.L ln.f j' p.1) ∧
      crossOf ln.horiz p.2 = (crossPlace ln.align ln.c0 ln.cc (p.1.crossSizing ln.horiz)
        (p.1.crossPref ln.horiz) p.1.stretch).2
  | [], _, _, _, p, hp => by simp only [Line.go, List.zip_nil_left, List.not_mem_nil] at hp
  | it :: its, i, j, pos, p, hp => by
    simp only [Line.go, List.zip_cons_cons, List.mem_cons] at hp
    rcases hp with rfl | hp
    · exact ⟨⟨j, by simp only [mkRect_mainOf]⟩, by simp only [mkRect_crossOf]⟩
    · exact Line.go_lens ln its _ _ _ p hp

/-- A rigid child's item: its sizings are its node's. -/
theorem item_sizing (m : TextMetrics) (aw : Int) (h : Bool) (k : Node) :
    ((measure m aw k).item.mainSizing h = mainSz h k) ∧
      ((measure m aw k).item.crossSizing h = crossSz h k) := by
  refine ⟨?_, ?_⟩ <;>
    simp only [Item.mainSizing, Item.crossSizing, Sized.item, measure_sizings, mainSz, crossSz]

theorem mainSize_fill {h : Bool} {L : Int} {f j : Nat} {it : Item}
    (hs : it.mainSizing h = .fill) : mainSize h L f j it = fillShare L f j := by
  unfold mainSize; rw [hs]

theorem mainSize_fixed {h : Bool} {L : Int} {f j n : Nat} {it : Item}
    (hs : it.mainSizing h = .fixed n) : mainSize h L f j it = n := by
  unfold mainSize; rw [hs]; rfl

theorem crossPlace_len (al : Align) (c0 cc : Int) (s : Sizing) (p : Int) (b : Bool)
    (hh : s.isHug = false) : (crossPlace al c0 cc s p b).2 = lenIn s cc := by
  cases s <;> simp_all [crossPlace, lenIn, Sizing.isHug]

theorem baseSum_rigid (h : Bool) (m : TextMetrics) (aw : Int) :
    ∀ (ks : List Node), (∀ k ∈ ks, (mainSz h k).isHug = false) →
      baseSum h (ks.map fun k => (measure m aw k).item) = (ks.map fun k => fixedOf (mainSz h k)).sum
  | [], _ => rfl
  | k :: ks, hk => by
    have ih := baseSum_rigid h m aw ks (fun x hx => hk x (.tail _ hx))
    simp only [baseSum, List.map_cons, List.sum_cons] at ih ⊢
    rw [ih, (item_sizing m aw h k).1]
    have := hk k (.head _)
    cases hs : mainSz h k <;> simp_all [Sizing.isHug, mainBase, fixedOf]

theorem fillCount_eq (h : Bool) (m : TextMetrics) (aw : Int) (ks : List Node) :
    fillCount h (ks.map fun k => (measure m aw k).item) = lineFills h ks := by
  simp only [fillCount, lineFills, List.filter_map, List.length_map]
  congr 1
  apply List.filter_congr
  intro k _
  simp only [Function.comp, (item_sizing m aw h k).1]

theorem mainSz_hug (h : Bool) (k : Node) (h1 : (nodeSizings k).1.isHug = false)
    (h2 : (nodeSizings k).2.isHug = false) :
    (mainSz h k).isHug = false ∧ (crossSz h k).isHug = false := by
  cases h <;> simp only [mainSz, crossSz, Bool.false_eq_true, ↓reduceIte, h1, h2, and_self]

theorem childRects_line (st : Style) (r : Rect) (items : List Item) (hax : st.axis ≠ .stack) :
    childRects st r items =
      scrolled st (lineRects (Axis.horiz st.axis) st (r.inset st.padding) items) := by
  rw [childRects, placeRects_line st r items hax]

theorem rect_wh (h : Bool) (q : Rect) :
    q.w = wOf h (mainOf h q) (crossOf h q) ∧ q.h = hOf h (mainOf h q) (crossOf h q) := by
  cases h <;> simp [wOf, hOf, mainOf, crossOf]

theorem mainOf_content (h : Bool) (st : Style) (r : Rect) :
    mainOf h (r.inset st.padding) = mainIn h st r.w r.h ∧
      crossOf h (r.inset st.padding) = crossIn h st r.w r.h := by
  cases h <;> simp [mainOf, crossOf, mainIn, crossIn, Rect.inset, contentW, contentH] <;> omega

/-! ## The theorem -/

/-- What `Pressable` asks at each node. -/
def NodeOk (l : Laid) : Prop := Fits l ∧ StackTop l ∧ ControlLeaf l

theorem text_ok (m : TextMetrics) (aw : Int) (c r : Rect) {k : Node} (hk : k.isText = true) :
    (arrange m c r (measure m aw k)).Everywhere NodeOk ∧
      (arrange m c r (measure m aw k)).isText = true ∧
      (arrange m c r (measure m aw k)).controls = [] := by
  cases k with
  | text ts s =>
    refine ⟨.intro ⟨trivial, trivial, trivial⟩ ?_, rfl, rfl⟩
    simp only [measure, arrange, Laid.children, List.not_mem_nil, false_implies, implies_true]
  | box => simp only [Node.isText, Bool.false_eq_true] at hk
  | para => simp only [Node.isText, Bool.false_eq_true] at hk
  | field => simp only [Node.isText, Bool.false_eq_true] at hk

theorem controlsList_nil_of {ls : List Laid} (h : ∀ l ∈ ls, l.controls = []) :
    Laid.controlsList ls = [] := by
  induction ls with
  | nil => rfl
  | cons l ls ih =>
    simp only [Laid.controlsList, h l (.head _), ih (fun x hx => h x (.tail _ hx)), List.append_nil]

theorem mem_targetsList {t : Target} :
    ∀ {ls : List Laid}, t ∈ targetsList ls → ∃ l ∈ ls, t ∈ targetsOf l
  | [], ht => by simp only [targetsList, List.not_mem_nil] at ht
  | l :: ls, ht => by
    simp only [targetsList, List.mem_append] at ht
    rcases ht with ht | ht
    · exact ⟨l, .head _, ht⟩
    · obtain ⟨k, hk, ht⟩ := mem_targetsList ht
      exact ⟨k, .tail _ hk, ht⟩

/-- Arranged lines of text are text with nothing below them. -/
theorem arrangeList_texts (m : TextMetrics) (c : Rect) :
    ∀ (rs : List Rect) (ss : List Sized), (∀ s ∈ ss, ∃ ts str sz, s = .text ts str sz) →
      ∀ k ∈ arrangeList m c rs ss, k.Everywhere NodeOk ∧ k.isText = true ∧ k.controls = []
  | _, [], _, k, hk => by simp only [arrangeList, List.not_mem_nil] at hk
  | rs, s :: ss, h, k, hk => by
    have hs : ∀ r, (arrange m c r s).Everywhere NodeOk ∧ (arrange m c r s).isText = true ∧
        (arrange m c r s).controls = [] := by
      intro r
      obtain ⟨ts, str, sz, rfl⟩ := h s (.head _)
      refine ⟨.intro ⟨trivial, trivial, trivial⟩ ?_, rfl, rfl⟩
      simp only [arrange, Laid.children, List.not_mem_nil, false_implies, implies_true]
    have h' := fun s hs => h s (.tail _ hs)
    cases rs with
    | nil =>
      simp only [arrangeList, List.mem_cons] at hk
      rcases hk with rfl | hk
      · exact hs _
      · exact arrangeList_texts m c [] ss h' k hk
    | cons r rs =>
      simp only [arrangeList, List.mem_cons] at hk
      rcases hk with rfl | hk
      · exact hs _
      · exact arrangeList_texts m c rs ss h' k hk

/-- Wrapped text lays out as a clipping column of text: it meets `Pressable`'s conditions and
has no controls. -/
theorem para_ok (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (s : String) (aw : Int)
    (c r : Rect) :
    (arrange m c r (measure m aw (.para ts wr s))).Everywhere NodeOk ∧
      ∀ t ∈ targetsOf (arrange m c r (measure m aw (.para ts wr s))), t.node.rect.nonempty := by
  simp only [measure, arrange]
  have hkid := arrangeList_texts m (innerClip (paraStyle wr) c r)
    (childRects (paraStyle wr) r ((paraLines m ts wr aw s).map Sized.item)) (paraLines m ts wr aw s)
    (fun s hs => by
      simp only [paraLines, Text.Wrap.mapSlices, List.mem_map] at hs
      obtain ⟨p, -, rfl⟩ := hs
      exact ⟨_, _, _, rfl⟩)
  have hnil := controlsList_nil_of fun l hl => (hkid l hl).2.2
  refine ⟨.intro ⟨.inl ⟨rfl, fun k hk => (hkid k hk).2.1⟩, fun h => ?_, trivial⟩ ?_, ?_⟩
  · simp only [paraStyle] at h; exact absurd h (by decide)
  · intro k hk; exact (hkid k hk).1
  · intro t ht
    rcases mem_targetsOf_box ht with ⟨k, h, _⟩ | ht
    · exact absurd h (by simp only [reduceCtorEq, not_false_eq_true])
    · obtain ⟨l, hl, ht⟩ := mem_targetsList ht
      rw [targetsOf_eq_nil (hkid l hl).2.2] at ht
      simp only [List.not_mem_nil] at ht

/-- **Rigid views lay out pressably.** If `n` fits in `w × h`, then laid out in any rect of that
size, with any clip and any text metrics, every node meets `Pressable`'s per-node conditions
and every control's rect is nonempty. -/
theorem fitsIn_arrange (m : TextMetrics) {n : Node} {w h : Int} (hf : FitsIn n w h) :
    ∀ (aw : Int) (c r : Rect), r.w = w → r.h = h →
      (arrange m c r (measure m aw n)).Everywhere NodeOk ∧
      ∀ t ∈ targetsOf (arrange m c r (measure m aw n)), t.node.rect.nonempty := by
  induction hf with
  | @para ts wr s w h =>
    intro aw c r _ _
    exact para_ok m ts wr s aw c r
  | @field st ts ctl v w h hw hh =>
    intro aw c r hrw hrh
    refine ⟨.intro ⟨trivial, trivial, trivial⟩ ?_, ?_⟩
    · simp only [measure, arrange, field, Laid.children, List.not_mem_nil, false_implies,
        implies_true]
    · simp only [measure, arrange, field, targetsOf, List.mem_singleton]
      rintro t rfl
      exact ⟨by simp only [Laid.rect]; omega, by simp only [Laid.rect]; omega⟩
  | @clipped st ctl kids w h hclip htext hctl =>
    intro aw c r hrw hrh
    simp only [measure, arrange, measureList_eq_map]
    generalize innerAvail st aw = a'
    have hlen : (childRects st r ((kids.map (measure m a')).map Sized.item)).length = kids.length := by
      simp only [childRects_length, List.length_map]
    have hkid : ∀ k' ∈ arrangeList m (innerClip st c r) (childRects st r ((kids.map (measure m a')).map
        Sized.item)) (kids.map (measure m a')),
        k'.Everywhere NodeOk ∧ k'.isText = true ∧ k'.controls = [] := by
      intro k' hk'
      obtain ⟨p, hp, rfl⟩ := mem_arrangeList m a' _ _ kids hlen k' hk'
      exact text_ok m a' _ _ (htext p.1 (List.of_mem_zip hp).1)
    have hnil := controlsList_nil_of fun l hl => (hkid l hl).2.2
    refine ⟨.intro ⟨.inl ⟨hclip, fun k hk => (hkid k hk).2.1⟩, ?_, ?_⟩ ?_, ?_⟩
    · intro _ k hk; exact (hkid k (List.dropLast_subset _ hk)).2.2
    · cases ctl <;> simp only [ControlLeaf, hnil]
    · intro k hk; exact (hkid k hk).1
    · intro t ht
      rcases mem_targetsOf_box ht with ⟨k, rfl, rfl⟩ | ht
      · have := hctl rfl
        exact ⟨by simp only [Laid.rect]; omega, by simp only [Laid.rect]; omega⟩
      · obtain ⟨l, hl, ht⟩ := mem_targetsList ht
        rw [targetsOf_eq_nil (hkid l hl).2.2] at ht
        simp only [List.not_mem_nil] at ht
  | @line st ctl kids w h hax hpad hcw hch hctl hbase hkids hsub ih =>
    intro aw c r hrw hrh
    simp only [measure, arrange, measureList_eq_map]
    generalize innerAvail st aw = a'
    -- The line, its items and its rects: `rs` where the line places them, `rs'` once a scroll
    -- box's offset has moved them (the same lengths).
    have hitems : (kids.map (measure m a')).map Sized.item = kids.map fun k => (measure m a' k).item := by
      simp only [List.map_map, Function.comp_def]
    rw [hitems, childRects_line st r _ hax]
    generalize hH : Axis.horiz st.axis = H at hbase hkids ih
    generalize hrs : lineRects H st (r.inset st.padding) (kids.map fun k => (measure m a' k).item) = rs
    have hlen : rs.length = kids.length := by
      rw [← hrs, lineRects_length, List.length_map]
    generalize hrs' : scrolled st rs = rs'
    have hlen' : rs'.length = kids.length := by rw [← hrs', scrolled_length, hlen]
    obtain ⟨hcm, hcc⟩ := mainOf_content H st r
    rw [hrw, hrh] at hcm hcc
    have hrigid : ∀ k ∈ kids, (mainSz H k).isHug = false ∧ (crossSz H k).isHug = false :=
      fun k hk => mainSz_hug H k (hkids k hk).1 (hkids k hk).2.1
    have hbs : baseSum H (kids.map fun k => (measure m a' k).item) =
        (kids.map fun k => fixedOf (mainSz H k)).sum :=
      baseSum_rigid H m a' kids fun k hk => (hrigid k hk).1
    have hfc := fillCount_eq H m a' kids
    -- Leftover space: the content length minus the fixed lengths and gaps, floored at zero.
    have hL : leftover H st (r.inset st.padding) (kids.map fun k => (measure m a' k).item) =
        max 0 (mainIn H st w h - lineBase H st.gap kids) := by
      unfold leftover; rw [hbs, hcm, List.length_map]; unfold lineBase; omega
    -- Each child's rect.
    have hdims : ∀ p ∈ List.zip kids rs,
        (∃ len : Int, mainOf H p.2 = len ∧
          (mainSz H p.1 = .fill →
            (mainIn H st w h - lineBase H st.gap kids) / ((lineFills H kids : Nat) : Int) ≤ len) ∧
          (∀ n : Nat, mainSz H p.1 = .fixed n → len = n)) ∧
        crossOf H p.2 = lenIn (crossSz H p.1) (crossIn H st w h) := by
      intro p hp
      have hk := (List.of_mem_zip hp).1
      have hp' : ((measure m a' p.1).item, p.2) ∈
          List.zip (kids.map fun k => (measure m a' k).item) rs := by
        rw [List.zip_map_left]; exact List.mem_map_of_mem hp
      rw [← hrs] at hp'
      obtain ⟨⟨j', hmain⟩, hcross⟩ := Line.go_lens _ _ _ _ _ _ hp'
      simp only [lineOf] at hmain hcross
      obtain ⟨hms, hcs⟩ := item_sizing m a' H p.1
      refine ⟨⟨_, rfl, ?_, ?_⟩, ?_⟩
      · intro hfill
        rw [hmain, mainSize_fill (hms.trans hfill), hL, hfc]
        have hpos : 0 < lineFills H kids := by
          unfold lineFills
          exact List.length_pos_of_mem (List.mem_filter.2 ⟨hk, by simp only [hfill, Sizing.isFill]⟩)
        exact Int.le_trans (Int.ediv_le_ediv (by omega) (Int.le_max_right 0 _)) (fillShare_ge hpos j')
      · intro n hn
        rw [hmain, mainSize_fixed (hms.trans hn)]
      · rw [hcross, hcs, crossPlace_len _ _ _ _ _ _ (hrigid _ hk).2]
        have hci : 0 ≤ crossIn H st w h := by
          cases H <;> simp only [crossIn, Bool.false_eq_true, ↓reduceIte, hcw, hch]
        rw [← hcc] at hci ⊢
        simp only [crossOf] at hci ⊢
        congr 1; omega
    -- Scrolling moves the rects but keeps their lengths.
    have hdims' : ∀ p ∈ List.zip kids rs',
        (∃ len : Int, mainOf H p.2 = len ∧
          (mainSz H p.1 = .fill →
            (mainIn H st w h - lineBase H st.gap kids) / ((lineFills H kids : Nat) : Int) ≤ len) ∧
          (∀ n : Nat, mainSz H p.1 = .fixed n → len = n)) ∧
        crossOf H p.2 = lenIn (crossSz H p.1) (crossIn H st w h) := by
      intro p hp
      rw [← hrs'] at hp
      unfold scrolled at hp
      split at hp
      · exact hdims p hp
      · rw [List.zip_map_right, List.mem_map] at hp
        obtain ⟨q, hq, rfl⟩ := hp
        obtain ⟨⟨len, h1, h2, h3⟩, h4⟩ := hdims q hq
        refine ⟨⟨len, ?_, h2, h3⟩, ?_⟩
        · simp only [Prod.map_snd, mainOf_scrollBy, h1]
        · simp only [Prod.map_snd, crossOf_scrollBy, h4, Prod.map_fst, id_eq]
    -- The children, each where `mem_arrangeList` puts it.
    have hkid : ∀ k' ∈ arrangeList m (innerClip st c r) rs' (kids.map (measure m a')),
        k'.Everywhere NodeOk ∧ (∀ t ∈ targetsOf k', t.node.rect.nonempty) ∧
        ∃ p ∈ List.zip kids rs', k' = arrange m (innerClip st c r) p.2 (measure m a' p.1) := by
      intro k' hk'
      obtain ⟨p, hp, rfl⟩ := mem_arrangeList m a' _ rs' kids hlen' k' hk'
      obtain ⟨⟨len, hlen', hfill, hfix⟩, hcross⟩ := hdims' p hp
      have hk := (List.of_mem_zip hp).1
      obtain ⟨hw', hh'⟩ := rect_wh H p.2
      have := ih p.1 hk len hfill hfix a' (innerClip st c r) p.2
        (by rw [hw', hlen', hcross]) (by rw [hh', hlen', hcross])
      exact ⟨this.1, this.2, p, hp, rfl⟩
    -- Lengths: every main length is non-negative, and they add up to what the line uses.
    have hrsnn : ∀ q ∈ rs', 0 ≤ mainOf H q := by
      intro q hq
      rw [← hrs'] at hq
      obtain ⟨q', hq', hw, hh⟩ := mem_scrolled hq
      rw [← hrs] at hq'
      have := lineRects_nonneg H st _ _ q' hq'
      cases H <;> simp only [mainOf, Bool.false_eq_true, ↓reduceIte] <;> omega
    have hrects : (arrangeList m (innerClip st c r) rs' (kids.map (measure m a'))).map Laid.rect = rs' :=
      arrangeList_rects m _ rs' _ (by simp only [List.length_map, hlen'])
    have hkidrect : ∀ k' ∈ arrangeList m (innerClip st c r) rs' (kids.map (measure m a')),
        k'.rect ∈ rs' := fun k' hk' => by rw [← hrects]; exact List.mem_map_of_mem hk'
    -- Across the axis every child fits the content box.
    have hcle : ∀ k' ∈ arrangeList m (innerClip st c r) rs' (kids.map (measure m a')),
        crossOf H k'.rect ≤ crossOf H (r.inset st.padding) := by
      intro k' hk'
      obtain ⟨p, hp, rfl⟩ := (hkid k' hk').2.2
      obtain ⟨-, hcross⟩ := hdims' p hp
      rw [arrange_rect, hcross, hcc]
      have := (hkids p.1 (List.of_mem_zip hp).1).2.2
      have := (hrigid p.1 (List.of_mem_zip hp).1).2
      cases hs : crossSz H p.1 <;> simp_all [lenIn, fixedOf, Sizing.isHug]
    refine ⟨.intro ⟨?_, ?_, ?_⟩ ?_, ?_⟩
    · -- `Fits`: a scroll box's children fit across it; any other line's fit both ways.
      cases hsc : st.scroll with
      | some o =>
        refine .inr (.inr ⟨by rw [hsc]; rfl, hpad, fun k' hk' => ?_⟩)
        rw [hH]; exact hcle k' hk'
      | none =>
      have hsum : (rs'.map (mainOf H)).sum + gaps st.gap kids.length ≤ mainIn H st w h := by
        rw [← hrs', map_mainOf_scrolled, ← hrs, lineRects_sum, hbs, hfc, hL]
        have hb := hbase hsc
        unfold lineBase at hb ⊢
        split <;> omega
      refine .inr (.inl ⟨hpad, fun k' hk' => ?_, fun _ => ?_⟩)
      · obtain ⟨p, hp, rfl⟩ := (hkid k' hk').2.2
        have hq := (List.of_mem_zip hp).2
        have hmle : mainOf H p.2 ≤ mainIn H st w h := by
          have := le_sum_of_mem (l := rs'.map (mainOf H))
            (fun x hx => by obtain ⟨q, hq, rfl⟩ := List.mem_map.1 hx; exact hrsnn q hq)
            (List.mem_map_of_mem hq)
          have : 0 ≤ gaps st.gap kids.length := by unfold gaps; omega
          omega
        have hc := hcle _ hk'
        rw [arrange_rect] at hc
        obtain ⟨hcm', -⟩ := mainOf_content H st r
        rw [hrw, hrh] at hcm'
        simp only [arrange_rect]
        rw [← hcm'] at hmle
        cases H <;> simp_all [mainOf, crossOf]
      · rw [hH]
        have : ((arrangeList m (innerClip st c r) rs' (kids.map (measure m a'))).map
            fun k => mainOf H k.rect) = rs'.map (mainOf H) := by
          have e := congrArg (List.map (mainOf H)) hrects
          rw [List.map_map] at e; exact e
        rw [this, (mainOf_content _ st r).1, hrw, hrh, arrangeList_length, List.length_map]
        exact hsum
    · -- `StackTop`: a row or column is not a stack.
      intro hs; exact absurd hs hax
    · -- `ControlLeaf`.
      cases ctl with
      | none => trivial
      | some k =>
        have := (hctl rfl).2.2
        simp only [ControlLeaf, arrangeList_controls, ← measureList_eq_map,
          measureList_controls, this]
    · intro k' hk'; exact (hkid k' hk').1
    · intro t ht
      rcases mem_targetsOf_box ht with ⟨k, rfl, rfl⟩ | ht
      · have := hctl rfl
        exact ⟨by simp only [Laid.rect]; omega, by simp only [Laid.rect]; omega⟩
      · obtain ⟨l, hl, ht⟩ := mem_targetsList ht
        exact (hkid l hl).2.1 t ht

/-- A rigid root that fills the window and fits in it lays out pressable. -/
theorem pressable_of_fitsIn {m : TextMetrics} {w : Size} {st : Style}
    {ctl : Option Control} {kids : List Node}
    (hw : st.width = .fill) (hh : st.height = .fill)
    (hf : FitsIn (.box st ctl kids) (max 0 w.w) (max 0 w.h)) :
    Pressable w (layout m w (.box st ctl kids)) := by
  have hl : layout m w (.box st ctl kids) =
      arrange m (windowRect w) (windowRect w) (measure m (windowRect w).w (.box st ctl kids)) := by
    simp only [layout, rootRect, measure, Sized.sizings, hw, hh, Sizing.isFill, ↓reduceIte,
      windowRect]
  obtain ⟨hE, -⟩ := fitsIn_arrange m hf _ (windowRect w) (windowRect w) rfl rfl
  rw [← hl] at hE
  exact ⟨by rw [hl, arrange_rect]; exact Rect.inside_refl _,
     hE.imp fun _ h => h.1, hE.imp fun _ h => h.2.1, hE.imp fun _ h => h.2.2⟩

/-- **Pressable, for a rigid root.** If the root fills the window and fits in it, every control
of the laid-out view with a visible part is pressable at that part's centre, for every text
metrics. (Outside a scroll box the visible part is the whole rect: `visible_eq_rect`.) -/
theorem hitTest_center_of_fitsIn {m : TextMetrics} {w : Size} {st : Style}
    {ctl : Option Control} {kids : List Node}
    (hw : st.width = .fill) (hh : st.height = .fill)
    (hf : FitsIn (.box st ctl kids) (max 0 w.w) (max 0 w.h)) :
    ∀ t ∈ targets (layout m w (.box st ctl kids)), t.visible.nonempty →
      hitTest (layout m w (.box st ctl kids)) t.visible.center = some t.control := by
  intro t ht hv
  exact hitTest_center_of_pressable (pressable_of_fitsIn hw hh hf) ht hv

/-- **Pressable, for a rigid root without scroll boxes**: then every control is visible whole,
so every control of the laid-out view is pressable at its centre, for every text metrics. -/
theorem hitTest_center_of_fitsIn_flat {m : TextMetrics} {w : Size} {st : Style}
    {ctl : Option Control} {kids : List Node}
    (hw : st.width = .fill) (hh : st.height = .fill)
    (hf : FitsIn (.box st ctl kids) (max 0 w.w) (max 0 w.h))
    (hs : (Node.box st ctl kids).scrolls = false) :
    ∀ t ∈ targets (layout m w (.box st ctl kids)),
      hitTest (layout m w (.box st ctl kids)) t.visible.center = some t.control := by
  intro t ht
  have hp := pressable_of_fitsIn (m := m) hw hh hf
  refine hitTest_center_of_pressable hp ht ?_
  rw [visible_eq_rect hp (layout_noScroll m w hs) ht]
  have hl : layout m w (.box st ctl kids) =
      arrange m (windowRect w) (windowRect w) (measure m (windowRect w).w (.box st ctl kids)) := by
    simp only [layout, rootRect, measure, Sized.sizings, hw, hh, Sizing.isFill, ↓reduceIte,
      windowRect]
  obtain ⟨-, hne⟩ := fitsIn_arrange m hf _ (windowRect w) (windowRect w) rfl rfl
  rw [← hl] at hne
  exact hne t ht

/-! ## Example: a list of any length

A column of `k` buttons, each a clipped 44-point row holding a label. Every button is pressable
at its centre, for every text metrics, whenever the window is wider than zero and at least
`44 * k` tall. The proof never looks at a particular `k` or a particular label. -/

def exampleRow (i : Nat) (label : String) : Node :=
  .box { width := .fill, height := .fixed 44, clip := true }
    (some { ref := ⟨1, i⟩, label }) [.text {} label]

def exampleList (labels : List String) : Node :=
  .box { width := .fill, height := .fill } none
    (labels.mapIdx fun i l => exampleRow i l)

theorem exampleList_fitsIn (labels : List String) {w h : Int} (hw : 0 < w)
    (hh : 44 * (labels.length : Int) ≤ h) : FitsIn (exampleList labels) w h := by
  have hmem : ∀ k ∈ labels.mapIdx (fun i l => exampleRow i l), ∃ i l, k = exampleRow i l := by
    intro k hk
    obtain ⟨i, hi, rfl⟩ := List.mem_iff_getElem.1 hk
    simp only [List.getElem_mapIdx]
    exact ⟨_, _, rfl⟩
  have hsum : ∀ ls : List Node, (∀ k ∈ ls, ∃ i l, k = exampleRow i l) →
      (ls.map fun k => fixedOf (mainSz false k)).sum = 44 * (ls.length : Int) := by
    intro ls hls
    induction ls with
    | nil => simp only [List.map_nil, List.sum_nil, List.length_nil, Int.natCast_zero, Int.mul_zero]
    | cons k ks ih =>
      obtain ⟨i, l, rfl⟩ := hls k (.head _)
      simp only [List.map_cons, List.sum_cons, List.length_cons,
        ih (fun x hx => hls x (.tail _ hx))]
      simp only [exampleRow, mainSz, nodeSizings, Bool.false_eq_true, ↓reduceIte, fixedOf]
      omega
  refine .line (by decide) ⟨by decide, by decide, by decide, by decide⟩ ?_ ?_ (by simp) ?_ ?_ ?_
  · simp only [contentW]; omega
  · simp only [contentH]
    have := Int.natCast_nonneg labels.length; omega
  · intro _
    simp only [lineBase, Axis.horiz, hsum _ hmem, List.length_mapIdx, gaps, Nat.zero_mul,
      Int.natCast_zero, Int.add_zero, mainIn, contentH, Bool.false_eq_true, ↓reduceIte]
    omega
  · intro k hk
    obtain ⟨i, l, rfl⟩ := hmem k hk
    simp only [exampleRow, nodeSizings, Sizing.isHug, Axis.horiz, crossSz, Bool.false_eq_true,
      ↓reduceIte, fixedOf, crossIn, contentW, true_and]
    omega
  · intro k hk len _ hfix
    obtain ⟨i, l, rfl⟩ := hmem k hk
    have hl : len = 44 := hfix 44 rfl
    refine .clipped rfl (by simp [Node.isText]) fun _ => ?_
    simp only [Axis.horiz, wOf, hOf, crossSz, nodeSizings, exampleRow, lenIn, crossIn, contentW,
      Bool.false_eq_true, ↓reduceIte]
    omega

/-- Every button in a list of any length is pressable at its centre, with any metrics. -/
theorem exampleList_pressable (m : TextMetrics) (labels : List String) (w : Size) (hw : 0 < w.w)
    (hh : 44 * (labels.length : Int) ≤ w.h) :
    ∀ t ∈ targets (layout m w (exampleList labels)),
      hitTest (layout m w (exampleList labels)) t.visible.center = some t.control :=
  hitTest_center_of_fitsIn_flat rfl rfl (exampleList_fitsIn labels (by omega) (by omega)) (by
    simp only [Node.scrolls, Option.isSome_none, Bool.false_or]
    refine Node.scrollsList_of_forall fun k hk => ?_
    obtain ⟨i, hi, rfl⟩ := List.mem_iff_getElem.1 hk
    simp only [List.getElem_mapIdx, exampleRow, Node.scrolls, Node.scrollsList,
      Option.isSome_none, Bool.or_self])

end Cairn.Layout

module

public import Cairn.App

/-! # Virtual lists: lay out only the rows on screen

A `VList` is a scroll box over a list the view names in full (every row's key) but builds only
in part: the rows that meet the viewport, plus `overscan` points above and below, with a spacer
for the rest above and one for the rest below (docs/layout.md, "Virtual lists").

* **Heights are never measured off screen.** A row's height is known once it has been laid; until
  then it is the list's estimate (given, or the mean of the first heights laid at its width, kept until the width changes). The runtime records
  the real heights from every layout (`record`, called by `Runtime.fixUI`), keyed by row key and
  forgotten when the list's width changes, and `settle` runs the view again when they change.
* **The anchor.** The runtime also records the first row showing and where its top was. When the
  heights above it change, or rows are inserted above it, the offset moves by as much as its top
  did, so it stays where it was on screen. When the clamp keeps the offset from moving that far,
  the row is held, and put back once the clamp allows, until the batch's frame is shown
  (`anchorAt`).

The heights a view lays out by are a `Model`: the known rows, sorted by index, and the estimate
for the rest. `Model.top` and `Model.height` are the specification (sums over the rows); the view
computes them with `topF` and `heightF` (a binary search and a prefix sum, so a frame costs the
same whatever the list's length), and `topF_eq` and `heightF_eq` prove them equal.

Theorems, for every model:

* `window_iff`: the rows laid are exactly those whose extent `[top, top + height)` meets
  `[lo, hi)` (the viewport, widened by the overscan);
* `window_count`: there are at most `(hi − lo) / m + 2` of them, for any `m` no larger than any
  row's height (`minHeight_le`), whatever the list's length;
* `top_succ`: each row starts where the one before it ends (the layout's side,
  `Cairn.Layout.VList`, shows the laid rows do too);
* `record_keeps`: a correction keeps the anchor's on-screen position, unless the clamp moves it;
  `top_eq_of_below`: a change wholly below a row doesn't move its top, so it moves no offset;
* `record_holds`, `record_returns`: when the clamp moves it, the row is held at its place, and
  the next record the clamp allows puts it back there. -/

@[expose] public section

namespace Cairn

namespace VList

/-! ## Searching -/

/-- The least `i` in `[lo, hi)` where `p` holds, or `hi`: binary search, for a `p` that stays
true once it is (`search_spec`). -/
def search (p : Nat → Bool) (lo hi : Nat) : Nat :=
  if h : lo < hi then
    if p ((lo + hi) / 2) then search p lo ((lo + hi) / 2) else search p ((lo + hi) / 2 + 1) hi
  else lo
termination_by hi - lo

/-- `p` stays true once it is. -/
def Mono (p : Nat → Bool) : Prop := ∀ i j, i ≤ j → p i = true → p j = true

theorem search_spec (p : Nat → Bool) (hp : Mono p) (lo hi : Nat) (hle : lo ≤ hi) :
    lo ≤ search p lo hi ∧ search p lo hi ≤ hi ∧
      (∀ i, lo ≤ i → i < search p lo hi → p i = false) ∧
      (search p lo hi < hi → p (search p lo hi) = true) := by
  induction lo, hi using search.induct p with
  | case1 lo hi h hm ih =>
    rw [search]; simp only [h, ↓reduceDIte, hm, ↓reduceIte]
    obtain ⟨h1, h2, h3, h4⟩ := ih (by omega)
    refine ⟨h1, by omega, h3, fun _ => ?_⟩
    by_cases hlt : search p lo ((lo + hi) / 2) < (lo + hi) / 2
    · exact h4 hlt
    · have : search p lo ((lo + hi) / 2) = (lo + hi) / 2 := by omega
      rw [this]; exact hm
  | case2 lo hi h hm ih =>
    rw [search]; simp only [h, ↓reduceDIte, hm, Bool.false_eq_true, ↓reduceIte]
    obtain ⟨h1, h2, h3, h4⟩ := ih (by omega)
    refine ⟨by omega, h2, fun i hi1 hi2 => ?_, h4⟩
    by_cases hi3 : (lo + hi) / 2 + 1 ≤ i
    · exact h3 i hi3 hi2
    · cases hpi : p i
      · rfl
      · exact absurd (hp i _ (by omega) hpi) hm
  | case3 lo hi h =>
    rw [search]; simp only [h, ↓reduceDIte]
    exact ⟨Nat.le_refl _, hle, fun i h1 h2 => absurd h2 (by omega), fun h' => h'.elim⟩

/-! ## Heights: the specification -/

/-- The corrections `height − est` of the rows with index below `i`. -/
def corrBelow (est : Nat) : List Row → Nat → Int
  | [], _ => 0
  | r :: rs, i => (if r.index < i then (r.height : Int) - est else 0) + corrBelow est rs i

/-- The corrections of the rows with index `i` (one at most, in a sorted list). -/
def corrAt (est : Nat) : List Row → Nat → Int
  | [], _ => 0
  | r :: rs, i => (if r.index = i then (r.height : Int) - est else 0) + corrAt est rs i

/-- The corrections of every row. -/
def corrAll (est : Nat) : List Row → Int
  | [] => 0
  | r :: rs => ((r.height : Int) - est) + corrAll est rs

/-- Rows sorted by index, each index once. -/
def Sorted (l : List Row) : Prop := l.Pairwise fun a b => a.index < b.index

/-- The heights a list is laid out by: `count` rows, the known ones (`rows`, sorted by index:
`model_sorted`) at their height, the others at `est`. -/
structure Model where
  rows : Array Row
  est : Nat
  count : Nat
deriving Repr, Inhabited

namespace Model

/-- **Row `i`'s top** in the list's content: the heights of the rows above it. -/
def top (M : Model) (i : Nat) : Int := (i : Int) * M.est + corrBelow M.est M.rows.toList i

/-- **Row `i`'s height**: its known height, or the estimate. -/
def height (M : Model) (i : Nat) : Int := M.est + corrAt M.est M.rows.toList i

end Model

theorem corrBelow_succ (est : Nat) (l : List Row) (i : Nat) :
    corrBelow est l (i + 1) = corrBelow est l i + corrAt est l i := by
  induction l with
  | nil => rfl
  | cons r rs ih =>
    simp only [corrBelow, corrAt, ih]
    by_cases h1 : r.index < i
    · have h2 : r.index < i + 1 := by omega
      have h3 : ¬ r.index = i := by omega
      simp only [h1, h2, h3, ↓reduceIte]; omega
    · by_cases h3 : r.index = i
      · have h2 : r.index < i + 1 := by omega
        simp only [h3, ↓reduceIte, Nat.lt_irrefl]; omega
      · have h2 : ¬ r.index < i + 1 := by omega
        simp only [h1, h2, h3, ↓reduceIte]; omega

theorem Model.top_zero (M : Model) : M.top 0 = 0 := by
  have : ∀ l : List Row, corrBelow M.est l 0 = 0 := by
    intro l; induction l with
    | nil => rfl
    | cons r rs ih => simp only [corrBelow, ih, Nat.not_lt_zero, ↓reduceIte]; omega
  simp only [top, this]; omega

/-- **Adjacent.** Each row starts where the one before it ends: no gaps, no overlaps. -/
theorem Model.top_succ (M : Model) (i : Nat) : M.top (i + 1) = M.top i + M.height i := by
  simp only [top, height, corrBelow_succ]
  push_cast
  rw [Int.add_mul, Int.one_mul]
  omega

theorem corrAt_none (est : Nat) (l : List Row) (i : Nat) (h : ∀ r ∈ l, r.index ≠ i) :
    corrAt est l i = 0 := by
  induction l with
  | nil => rfl
  | cons r rs ih =>
    simp only [corrAt, h r (List.mem_cons_self ..), ↓reduceIte,
      ih fun x hx => h x (List.mem_cons_of_mem _ hx)]; omega

theorem corrAt_mem (est : Nat) (l : List Row) (hs : Sorted l) {r : Row} (hr : r ∈ l) :
    corrAt est l r.index = (r.height : Int) - est := by
  induction l with
  | nil => cases hr
  | cons x xs ih =>
    simp only [Sorted, List.pairwise_cons] at hs
    rcases List.mem_cons.mp hr with rfl | hr
    · rw [corrAt, ite_eq_left_of_eq_true _ _ (eq_self _), corrAt_none]
      · omega
      · intro y hy; have := hs.1 y hy; omega
    · have hne : x.index ≠ r.index := by have := hs.1 r hr; omega
      rw [corrAt, ite_eq_right_of_eq_false _ _ (eq_false hne), ih hs.2 hr]; omega

/-- A row's height in a sorted model: its known height if it is known, else the estimate. -/
theorem Model.height_eq (M : Model) (hs : Sorted M.rows.toList) (i : Nat) :
    (∀ r ∈ M.rows.toList, r.index = i → M.height i = r.height) ∧
    ((∀ r ∈ M.rows.toList, r.index ≠ i) → M.height i = M.est) := by
  refine ⟨fun r hr hi => ?_, fun h => ?_⟩
  · subst hi; simp only [height, corrAt_mem _ _ hs hr]; omega
  · simp only [height, corrAt_none _ _ _ h]; omega

/-- **Heights are at least `m`** when the estimate and every known height are. -/
theorem Model.height_ge (M : Model) (hs : Sorted M.rows.toList) {m : Nat} (he : m ≤ M.est)
    (hr : ∀ r ∈ M.rows.toList, m ≤ r.height) (i : Nat) : (m : Int) ≤ M.height i := by
  by_cases h : ∃ r ∈ M.rows.toList, r.index = i
  · obtain ⟨r, hr', hi⟩ := h
    rw [(M.height_eq hs i).1 r hr' hi]; have := hr r hr'; omega
  · rw [(M.height_eq hs i).2 fun r hr' hi => h ⟨r, hr', hi⟩]; omega

/-- The least height in a model: the estimate's and every known row's. -/
def Model.minHeight (M : Model) : Nat := M.rows.foldl (fun a r => min a r.height) M.est

theorem foldl_min_le (l : List Row) (a : Nat) :
    l.foldl (fun a r => min a r.height) a ≤ a ∧
      ∀ r ∈ l, l.foldl (fun a r => min a r.height) a ≤ r.height := by
  induction l generalizing a with
  | nil => exact ⟨Nat.le_refl _, fun _ h => by cases h⟩
  | cons x xs ih =>
    obtain ⟨h1, h2⟩ := ih (min a x.height)
    simp only [List.foldl_cons]
    refine ⟨by omega, fun r hr => ?_⟩
    rcases List.mem_cons.mp hr with rfl | hr
    · omega
    · exact h2 r hr

theorem foldl_min_ge (l : List Row) (a m : Nat) (ha : m ≤ a) (hl : ∀ r ∈ l, m ≤ r.height) :
    m ≤ l.foldl (fun a r => min a r.height) a := by
  induction l generalizing a with
  | nil => exact ha
  | cons x xs ih =>
    exact ih _ (Nat.le_min.mpr ⟨ha, hl x (List.mem_cons_self ..)⟩)
      (fun r hr => hl r (List.mem_cons_of_mem _ hr))

/-- **`minHeight` is no larger than any row's height.** -/
theorem Model.minHeight_le (M : Model) (hs : Sorted M.rows.toList) (i : Nat) :
    (M.minHeight : Int) ≤ M.height i := by
  have h := foldl_min_le M.rows.toList M.est
  unfold minHeight; rw [← Array.foldl_toList]
  exact M.height_ge hs h.1 h.2 i

theorem Model.top_mono (M : Model) (hh : ∀ i, 0 ≤ M.height i) {i j : Nat} (hij : i ≤ j) :
    M.top i ≤ M.top j := by
  obtain ⟨k, rfl⟩ := Nat.exists_eq_add_of_le hij
  induction k with
  | zero => exact Int.le_refl _
  | succ k ih => rw [← Nat.add_assoc, M.top_succ]; have := hh (i + k); have := ih (by omega); omega

/-- `j − i` rows of at least `m` points each take at least `(j − i)·m` points. -/
theorem Model.top_sub_ge (M : Model) {m : Int} (hh : ∀ i, m ≤ M.height i) {i j : Nat}
    (hij : i ≤ j) : ((j - i : Nat) : Int) * m ≤ M.top j - M.top i := by
  obtain ⟨k, rfl⟩ := Nat.exists_eq_add_of_le hij
  rw [show i + k - i = k by omega]
  induction k with
  | zero => simp
  | succ k ih =>
    rw [← Nat.add_assoc, M.top_succ]
    push_cast
    rw [Int.add_mul, Int.one_mul]
    have := hh (i + k); have := ih (by omega); omega

/-- **A change wholly below a row doesn't move its top.** Two models that agree on the heights
of every row above row `i` put it at the same place (so a correction there moves no offset). -/
theorem top_eq_of_below (M M' : Model) (i : Nat) (h : ∀ j < i, M.height j = M'.height j) :
    M.top i = M'.top i := by
  induction i with
  | zero => rw [M.top_zero, M'.top_zero]
  | succ i ih =>
    rw [M.top_succ, M'.top_succ, ih fun j hj => h j (by omega), h i (by omega)]

/-! ## Heights: the fast path

The view needs a row's top for a handful of rows per frame. `topF` finds how many known rows lie
above it by binary search and adds their corrections from a prefix sum (`Model.pre`, built once
per frame), so it costs `O(log known)` whatever the list's length. -/

/-- `acc` then the running sums of the rows' corrections: entry `m` is `acc` plus the first
`m` rows' corrections. -/
def prefixes (est : Nat) : List Row → Int → List Int
  | [], acc => [acc]
  | r :: rs, acc => acc :: prefixes est rs (acc + ((r.height : Int) - est))

theorem prefixes_get (est : Nat) (l : List Row) (acc : Int) (m : Nat) (hm : m ≤ l.length) :
    (prefixes est l acc)[m]? = some (acc + corrAll est (l.take m)) := by
  induction l generalizing acc m with
  | nil =>
    have : m = 0 := by simp at hm; omega
    subst this; simp [prefixes, corrAll]
  | cons r rs ih =>
    cases m with
    | zero => simp [prefixes, corrAll]
    | succ m =>
      simp only [prefixes, List.getElem?_cons_succ, List.take_succ_cons, corrAll]
      rw [ih _ m (by simp at hm; omega)]; congr 1; omega

namespace Model

/-- The prefix sums of the known rows' corrections (`prefixes`). -/
def pre (M : Model) : Array Int := (prefixes M.est M.rows.toList 0).toArray

/-- Known row `m` lies at or below row `i` (or there is none). -/
def atOrBelow (M : Model) (i m : Nat) : Bool :=
  match M.rows[m]? with
  | some r => decide (i ≤ r.index)
  | none => true

/-- How many known rows lie above row `i`. -/
def below (M : Model) (i : Nat) : Nat := search (M.atOrBelow i) 0 M.rows.size

/-- Row `i`'s top, fast (`topF_eq`). `pre` is `M.pre`, computed once. -/
def topF (M : Model) (pre : Array Int) (i : Nat) : Int :=
  (i : Int) * M.est + (pre[M.below i]?.getD 0)

/-- Row `i`'s height, fast (`heightF_eq`). -/
def heightF (M : Model) (i : Nat) : Int :=
  match M.rows[M.below i]? with
  | some r => if r.index = i then r.height else M.est
  | none => M.est

theorem atOrBelow_mono (M : Model) (hs : Sorted M.rows.toList) (i : Nat) : Mono (M.atOrBelow i) := by
  intro a b hab ha
  unfold atOrBelow at ha ⊢
  by_cases hb : b < M.rows.size
  · have hA : a < M.rows.size := by omega
    rw [Array.getElem?_eq_getElem hb]
    rw [Array.getElem?_eq_getElem hA] at ha
    simp only [decide_eq_true_eq] at ha ⊢
    rcases Nat.lt_or_eq_of_le hab with hlt | rfl
    · have := List.pairwise_iff_getElem.mp hs a b (by simpa using hA) (by simpa using hb) hlt
      simp only [Array.getElem_toList] at this; omega
    · exact ha
  · rw [Array.getElem?_eq_none (by omega)]

theorem below_spec (M : Model) (hs : Sorted M.rows.toList) (i : Nat) :
    M.below i ≤ M.rows.size ∧
      (∀ m (h : m < M.rows.size), m < M.below i → M.rows[m].index < i) ∧
      (∀ m (h : m < M.rows.size), M.below i ≤ m → i ≤ M.rows[m].index) := by
  obtain ⟨-, h2, h3, h4⟩ := search_spec _ (M.atOrBelow_mono hs i) 0 M.rows.size (Nat.zero_le _)
  unfold below
  refine ⟨h2, fun m hm hb => ?_, fun m hm hb => ?_⟩
  · have := h3 m (Nat.zero_le _) hb
    simp only [atOrBelow, Array.getElem?_eq_getElem hm, decide_eq_false_iff_not] at this; omega
  · have hp := M.atOrBelow_mono hs i _ m hb (h4 (by omega))
    simp only [atOrBelow, Array.getElem?_eq_getElem hm, decide_eq_true_eq] at hp; exact hp

theorem corrBelow_append (est : Nat) (a b : List Row) (i : Nat) :
    corrBelow est (a ++ b) i = corrBelow est a i + corrBelow est b i := by
  induction a with
  | nil => simp [corrBelow]
  | cons r rs ih => simp only [List.cons_append, corrBelow, ih]; omega

theorem corrBelow_all_lt (est : Nat) (l : List Row) (i : Nat) (h : ∀ r ∈ l, r.index < i) :
    corrBelow est l i = corrAll est l := by
  induction l with
  | nil => rfl
  | cons r rs ih =>
    simp only [corrBelow, corrAll, h r (List.mem_cons_self ..), ↓reduceIte,
      ih fun x hx => h x (List.mem_cons_of_mem _ hx)]

theorem corrBelow_all_ge (est : Nat) (l : List Row) (i : Nat) (h : ∀ r ∈ l, i ≤ r.index) :
    corrBelow est l i = 0 := by
  induction l with
  | nil => rfl
  | cons r rs ih =>
    have := h r (List.mem_cons_self ..)
    simp only [corrBelow, show ¬ r.index < i by omega, ↓reduceIte,
      ih fun x hx => h x (List.mem_cons_of_mem _ hx)]; omega

/-- **The fast top is the top.** -/
theorem topF_eq (M : Model) (hs : Sorted M.rows.toList) (i : Nat) :
    M.topF M.pre i = M.top i := by
  obtain ⟨hb, hlt, hge⟩ := M.below_spec hs i
  have hl : M.rows.toList.length = M.rows.size := Array.length_toList
  have hsplit := List.take_append_drop (M.below i) M.rows.toList
  have hpre : M.pre[M.below i]? = some (0 + corrAll M.est (M.rows.toList.take (M.below i))) := by
    simp only [pre, List.getElem?_toArray]
    exact prefixes_get _ _ _ _ (by omega)
  simp only [topF, top, hpre, Option.getD_some]
  conv => rhs; rw [← hsplit]
  rw [corrBelow_append, corrBelow_all_lt, corrBelow_all_ge]
  · omega
  · intro r hr
    obtain ⟨m, hm, rfl⟩ := List.getElem_of_mem hr
    simp only [List.getElem_drop, Array.getElem_toList]
    simp only [List.length_drop] at hm
    exact hge _ (by omega) (by omega)
  · intro r hr
    obtain ⟨m, hm, rfl⟩ := List.getElem_of_mem hr
    simp only [List.getElem_take, Array.getElem_toList]
    simp only [List.length_take] at hm
    exact hlt _ (by omega) (by omega)

/-- **The fast height is the height.** -/
theorem heightF_eq (M : Model) (hs : Sorted M.rows.toList) (i : Nat) :
    M.heightF i = M.height i := by
  obtain ⟨hb, hlt, hge⟩ := M.below_spec hs i
  have none_at : (∀ m (h : m < M.rows.size), M.rows[m].index ≠ i) →
      ∀ r ∈ M.rows.toList, r.index ≠ i := by
    intro h r hr
    obtain ⟨m, hm, rfl⟩ := List.getElem_of_mem hr
    simp only [Array.getElem_toList]
    exact h m (by simpa using hm)
  unfold heightF
  by_cases hin : M.below i < M.rows.size
  · rw [Array.getElem?_eq_getElem hin]
    dsimp only
    split
    · rename_i heq
      rw [(M.height_eq hs i).1 _ (Array.getElem_mem_toList hin) heq]
    · rename_i hne
      rw [(M.height_eq hs i).2 (none_at fun m hm => ?_)]
      by_cases hmb : m < M.below i
      · have := hlt m hm hmb; omega
      · rcases Nat.lt_or_eq_of_le (Nat.le_of_not_lt hmb) with hgt | heq
        · have := List.pairwise_iff_getElem.mp hs (M.below i) m (by simpa using hin)
            (by simpa using hm) hgt
          simp only [Array.getElem_toList] at this
          have := hge _ hin (Nat.le_refl _); omega
        · subst heq; exact hne
  · rw [Array.getElem?_eq_none (by omega)]
    dsimp only
    rw [(M.height_eq hs i).2 (none_at fun m hm => by have := hlt m hm (by omega); omega)]

/-! ## The window -/

/-- The first row laid: the least row whose bottom is below `lo`. -/
def firstF (M : Model) (pre : Array Int) (lo : Int) : Nat :=
  search (fun i => decide (lo < M.topF pre (i + 1))) 0 M.count

/-- One past the last row laid: from `first`, the least row whose top is at or below `hi`. -/
def lastF (M : Model) (pre : Array Int) (first : Nat) (hi : Int) : Nat :=
  search (fun i => decide (hi ≤ M.topF pre i)) first M.count

/-- **The rows laid** for the content span `[lo, hi)`: indices `[first, last)`. -/
def window (M : Model) (lo hi : Int) : Nat × Nat :=
  let pre := M.pre
  let f := M.firstF pre lo
  (f, M.lastF pre f hi)

/-- The model is sorted, and its heights are positive. -/
structure Good (M : Model) : Prop where
  sorted : Sorted M.rows.toList
  pos : ∀ i, 0 ≤ M.height i

theorem window_spec (M : Model) (hM : M.Good) (lo hi : Int) :
    (M.window lo hi).1 ≤ (M.window lo hi).2 ∧ (M.window lo hi).2 ≤ M.count ∧
    (∀ i, i < (M.window lo hi).1 → M.top (i + 1) ≤ lo) ∧
    ((M.window lo hi).1 < M.count → lo < M.top ((M.window lo hi).1 + 1)) ∧
    (∀ i, (M.window lo hi).1 ≤ i → i < (M.window lo hi).2 → M.top i < hi) ∧
    ((M.window lo hi).2 < M.count → hi ≤ M.top (M.window lo hi).2) := by
  have hF : M.topF M.pre = M.top := funext (M.topF_eq hM.sorted)
  have m1 : Mono fun i => decide (lo < M.topF M.pre (i + 1)) := by
    intro a b hab ha; simp only [hF, decide_eq_true_eq] at ha ⊢
    have := M.top_mono hM.pos (i := a + 1) (j := b + 1) (by omega); omega
  have m2 : Mono fun i => decide (hi ≤ M.topF M.pre i) := by
    intro a b hab ha; simp only [hF, decide_eq_true_eq] at ha ⊢
    have := M.top_mono hM.pos hab; omega
  obtain ⟨-, a2, a3, a4⟩ := search_spec _ m1 0 M.count (Nat.zero_le _)
  obtain ⟨b1, b2, b3, b4⟩ := search_spec _ m2 (M.firstF M.pre lo) M.count a2
  simp only [hF, decide_eq_true_eq, decide_eq_false_iff_not] at a3 a4 b3 b4
  simp only [window, lastF, firstF, hF]
  simp only [firstF, hF] at b1 b2 b3 b4
  refine ⟨b1, b2, fun i hi => ?_, a4, fun i h1 h2 => ?_, b4⟩
  · have := a3 i (Nat.zero_le _) hi; omega
  · have := b3 i h1 h2; omega

/-- **Exactly the rows that meet the span.** A row is laid if and only if its extent
`[top, top + height)` meets `[lo, hi)`. -/
theorem window_iff (M : Model) (hM : M.Good) (lo hi : Int) {i : Nat} (hi' : i < M.count) :
    ((M.window lo hi).1 ≤ i ∧ i < (M.window lo hi).2) ↔
      (lo < M.top i + M.height i ∧ M.top i < hi) := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := M.window_spec hM lo hi
  rw [← M.top_succ]
  constructor
  · rintro ⟨ha, hb⟩
    refine ⟨?_, h5 i ha hb⟩
    have := h4 (by omega)
    have := M.top_mono hM.pos (i := (M.window lo hi).1 + 1) (j := i + 1) (by omega); omega
  · rintro ⟨ha, hb⟩
    refine ⟨Nat.le_of_not_lt fun h => by have := h3 i h; omega, Nat.lt_of_not_le fun h => ?_⟩
    have := h6 (by omega)
    have := M.top_mono hM.pos h; omega

/-- **Bounded by the viewport, not the list.** With every row at least `m > 0` points tall, at
most `(hi − lo) / m + 2` rows are laid: the ones wholly inside the span, and one at each end. -/
theorem window_count (M : Model) (hM : M.Good) {m : Int} (hm : 0 < m)
    (hh : ∀ i, m ≤ M.height i) (lo hi : Int) (hlh : lo ≤ hi) :
    (((M.window lo hi).2 - (M.window lo hi).1 : Nat) : Int) ≤ (hi - lo) / m + 2 := by
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := M.window_spec hM lo hi
  generalize (M.window lo hi).1 = f at *
  generalize (M.window lo hi).2 = l at *
  have hq : 0 ≤ (hi - lo) / m := Int.ediv_nonneg (by omega) (by omega)
  by_cases hk : l ≤ f + 2
  · omega
  · have ha := h4 (by omega)
    have hb := h5 (l - 1) (by omega) (by omega)
    have hs := M.top_sub_ge hh (i := f + 1) (j := l - 1) (by omega)
    have hlt : ((l - 1 - (f + 1) : Nat) : Int) * m < hi - lo := by omega
    have : ((l - 1 - (f + 1) : Nat) : Int) ≤ (hi - lo) / m := by
      rw [Int.le_ediv_iff_mul_le hm]; omega
    omega

end Model

/-! ## The model a view lays out by -/

/-- The rows of `l` that can be trusted for `keys`: in increasing index order from `next`, each at
an index whose key it is, each at least a point tall. Others are dropped. -/
def keep (keys : Array Nat) : List Row → Nat → List Row
  | [], _ => []
  | r :: rs, next =>
    if next ≤ r.index ∧ keys[r.index]? = some r.key ∧ 1 ≤ r.height then
      r :: keep keys rs (r.index + 1)
    else keep keys rs next

theorem keep_spec (keys : Array Nat) (l : List Row) (next : Nat) :
    Sorted (keep keys l next) ∧ ∀ r ∈ keep keys l next,
      next ≤ r.index ∧ keys[r.index]? = some r.key ∧ 1 ≤ r.height := by
  induction l generalizing next with
  | nil => exact ⟨List.Pairwise.nil, fun _ h => by cases h⟩
  | cons r rs ih =>
    unfold keep
    split
    · rename_i h
      obtain ⟨ih1, ih2⟩ := ih (r.index + 1)
      refine ⟨List.Pairwise.cons (fun x hx => by have := (ih2 x hx).1; omega) ih1, ?_⟩
      intro x hx
      rcases List.mem_cons.mp hx with rfl | hx
      · exact h
      · have := ih2 x hx; exact ⟨by omega, this.2⟩
    · exact ih next

/-- Rows sorted by key, for looking keys up (`indexOf`). -/
def byKey (rows : List Row) : Array Row := (rows.mergeSort fun a b => a.key ≤ b.key).toArray

/-- The known row with key `k` in `sorted` (sorted by key), by binary search. -/
def lookup (sorted : Array Row) (k : Nat) : Option Row :=
  let m := search (fun m => match sorted[m]? with | some r => decide (k ≤ r.key) | none => true)
    0 sorted.size
  match sorted[m]? with
  | some r => if r.key = k then some r else none
  | none => none

/-- `known`'s rows moved to the indices `keys` gives their keys. Usually nothing moves (the same
keys) or every row moves by the same amount (rows inserted at the head); otherwise each key is
looked up. -/
def relocate (keys : Array Nat) (known : Known) : List Row :=
  let fits (d : Nat) : Bool := known.rows.all fun r => keys[r.index + d]? == some r.key
  if fits 0 then known.rows.toList
  else
    let d := keys.size - known.count
    if known.count < keys.size && fits d then
      known.rows.toList.map fun r => { r with index := r.index + d }
    else
      let sorted := byKey known.rows.toList
      (keys.toList.zipIdx.filterMap fun (k, i) =>
        (lookup sorted k).map fun r => { r with index := i })

/-- The known rows for these keys, sorted by index (`model_sorted`): what the runtime knew,
moved to where their keys are now. -/
def align (keys : Array Nat) (known : Known) : Array Row :=
  (keep keys (relocate keys known) 0).toArray

/-- A row's height when nothing is known and no estimate is given. -/
def defaultEstimate : Nat := 40

/-- The mean of the rows' heights; 0 when there are none. -/
def mean (rows : Array Row) : Nat :=
  if rows.size = 0 then 0 else (rows.foldl (fun a r => a + r.height) 0) / rows.size

/-- The estimate: the given one, else the one the runtime keeps (`Known.est`), else the mean of
the known heights; at least a point. -/
def estOf (guess : Option Nat) (stored : Nat) (rows : Array Row) : Nat :=
  max 1 <| guess.getD <|
    if 0 < stored then stored
    else if rows.size = 0 then defaultEstimate
    else mean rows

/-- The model a view lays `keys` out by, from what the runtime knows. -/
def model (keys : Array Nat) (known : Known) (guess : Option Nat) : Model :=
  let rows := align keys known
  { rows, est := estOf guess known.est rows, count := keys.size }

theorem align_spec (keys : Array Nat) (known : Known) :
    Sorted (align keys known).toList ∧ ∀ r ∈ (align keys known).toList,
      keys[r.index]? = some r.key ∧ 1 ≤ r.height := by
  obtain ⟨h1, h2⟩ := keep_spec keys (relocate keys known) 0
  simp only [align, List.toList_toArray]
  exact ⟨h1, fun r hr => (h2 r hr).2⟩

/-- **A view's model is sorted, and every height in it is at least a point** (so `window_iff`
and `window_count` apply, with `m = 1`, or `minHeight`). -/
theorem model_good (keys : Array Nat) (known : Known) (guess : Option Nat) :
    (model keys known guess).Good ∧ ∀ i, 1 ≤ (model keys known guess).height i := by
  obtain ⟨hs, hr⟩ := align_spec keys known
  have hh : ∀ i, (1 : Int) ≤ (model keys known guess).height i := fun i =>
    (model keys known guess).height_ge (m := 1) hs (by simp only [model, estOf]; omega)
      (fun r h => (hr r h).2) i
  exact ⟨⟨hs, fun i => by have := hh i; omega⟩, hh⟩

/-- Known rows lie in the list: each index is below the row count. -/
theorem model_rows_lt (keys : Array Nat) (known : Known) (guess : Option Nat) :
    ∀ r ∈ (model keys known guess).rows.toList, r.index < (model keys known guess).count := by
  intro r hr
  have := ((align_spec keys known).2 r hr).1
  simp only [model]
  exact (Array.getElem?_eq_some_iff.mp this).1

end VList

/-! ## The view's helper -/

/-- A virtual list (docs/layout.md, "Virtual lists"): a scroll box whose offset the runtime owns
(`ref`, usually a place claim's ref, as with `UI.scrolling`), holding only the rows that meet its
viewport and `overscan` points above and below it. -/
structure VList where
  ref : ControlRef
  /-- A row's height until it is laid; none: the mean of the heights known so far. -/
  estimate : Option Nat := none
  /-- Points laid above and below the viewport, so a small scroll shows rows already laid. -/
  overscan : Nat := 200
  /-- The box's own style: its size, padding, background. Its axis, gap, justify and scroll are
  the list's. -/
  style : Style := {}
deriving Inhabited

namespace VList

/-- An empty box of height `h`: what stands for the rows not laid. -/
def spacer (h : Int) : Node := .box { width := .fixed 0, height := .fixed h.toNat } none []

/-- The viewport the window is computed for: the box's length when it was last laid, else the
window's height (more than enough). -/
def viewportOf (ui : UI) (k : Known) : Int := max 0 (if 0 < k.viewport then k.viewport else ui.size.h)

/-- The rows `[first, last)`, each built from its key. -/
def rowNodes (keys : Array Nat) (row : Nat → Node) (first last : Nat) : List Node :=
  (List.range' first (last - first)).map fun i => row (keys[i]?.getD 0)

/-- The model a laid list was laid out by. -/
def Info.modelOf (info : Info) : Model := { rows := info.model, est := info.est, count := info.keys.size }

/-- What `node` lays a list out by: the model, and the rows `[first, last)` it builds. -/
def infoOf (v : VList) (ui : UI) (keys : Array Nat) : Info :=
  let known := ui.listOf v.ref
  let M := model keys known v.estimate
  let pre := M.pre
  let o := ui.scrollOf v.ref
  let vp := viewportOf ui known
  let f := M.firstF pre (o - v.overscan)
  let l := M.lastF pre f (o + vp + v.overscan)
  { known := known, model := M.rows, keys := keys, estimate := v.estimate, est := M.est,
    overscan := v.overscan, viewport := vp, first := f, last := l }

/-- **A virtual list's box.** `keys` names every row, in order (keep the array in the app's state,
so the view doesn't rebuild it every frame); `row` builds the row with a given key. Only the rows
that meet the viewport, widened by the overscan, are built, between a spacer for the rows above
and one for the rows below, at the heights the runtime knows (`model`). -/
def node (v : VList) (ui : UI) (keys : Array Nat) (row : Nat → Node) : Node :=
  let info := infoOf v ui keys
  let M := info.modelOf
  let pre := M.pre
  .box { v.style with axis := .column, gap := 0, justify := .start, scroll := some (ui.scrollOf v.ref),
                      scrollRef := some v.ref, rows := some info } none
    (spacer (M.topF pre info.first) :: rowNodes keys row info.first info.last ++
      [spacer (M.topF pre M.count - M.topF pre info.last)])


/-- The span of content `node` laid rows for: the offset less the overscan, to the offset plus the
viewport and the overscan. -/
def Info.span (info : Info) (o : Int) : Int × Int := (o - info.overscan, o + info.viewport + info.overscan)

theorem infoOf_model (v : VList) (ui : UI) (keys : Array Nat) :
    (infoOf v ui keys).modelOf = model keys (ui.listOf v.ref) v.estimate := rfl

theorem infoOf_window (v : VList) (ui : UI) (keys : Array Nat) :
    ((infoOf v ui keys).first, (infoOf v ui keys).last) =
      (infoOf v ui keys).modelOf.window (ui.scrollOf v.ref - v.overscan)
        (ui.scrollOf v.ref + (infoOf v ui keys).viewport + v.overscan) := rfl

theorem infoOf_viewport (v : VList) (ui : UI) (keys : Array Nat) :
    0 ≤ (infoOf v ui keys).viewport := by
  show 0 ≤ viewportOf ui (ui.listOf v.ref); unfold viewportOf; omega

theorem minHeight_pos (keys : Array Nat) (known : Known) (guess : Option Nat) :
    1 ≤ (model keys known guess).minHeight := by
  unfold Model.minHeight; rw [← Array.foldl_toList]
  exact foldl_min_ge _ _ 1 (by simp only [model, estOf]; omega)
    (fun r h => ((align_spec keys known).2 r h).2)

/-- **The box `node` builds:** a column scroll box with no gap, scrolled by the runtime's offset,
holding a spacer as tall as the rows above `first`, the rows `[first, last)` in key order, and a
spacer as tall as the rows from `last` on, all in the heights of the model it lays out by. -/
theorem node_eq (v : VList) (ui : UI) (keys : Array Nat) (row : Nat → Node) :
    ∃ st, st.scroll = some (ui.scrollOf v.ref) ∧ st.axis = .column ∧ st.gap = 0 ∧
      st.justify = .start ∧ st.scrollRef = some v.ref ∧ st.rows = some (infoOf v ui keys) ∧
      node v ui keys row = .box st none
        (spacer ((infoOf v ui keys).modelOf.top (infoOf v ui keys).first) ::
          rowNodes keys row (infoOf v ui keys).first (infoOf v ui keys).last ++
          [spacer ((infoOf v ui keys).modelOf.top (infoOf v ui keys).modelOf.count -
            (infoOf v ui keys).modelOf.top (infoOf v ui keys).last)]) := by
  have hg := (model_good keys (ui.listOf v.ref) v.estimate).1
  rw [← infoOf_model v ui keys] at hg
  refine ⟨{ v.style with
      axis := .column, gap := 0, justify := .start,
      scroll := some (ui.scrollOf v.ref), scrollRef := some v.ref,
      rows := some (infoOf v ui keys) },
    rfl, rfl, rfl, rfl, rfl, rfl, ?_⟩
  have e := Model.topF_eq _ hg.sorted
  simp only [node]
  rw [e, e, e]

/-- **Exactly the rows meeting the viewport, and only so many.** A virtual list builds row `i`
(of its keys) if and only if the row's extent in the heights it lays out by meets the viewport
widened by the overscan; and it builds at most `(viewport + 2·overscan) / minHeight + 2` rows,
whatever the list's length. -/
theorem node_rows (v : VList) (ui : UI) (keys : Array Nat) :
    let info := infoOf v ui keys
    let lo := ui.scrollOf v.ref - v.overscan
    let hi := ui.scrollOf v.ref + info.viewport + v.overscan
    (∀ i, i < keys.size → (info.first ≤ i ∧ i < info.last ↔
        lo < info.modelOf.top i + info.modelOf.height i ∧ info.modelOf.top i < hi)) ∧
      0 ≤ info.viewport ∧
      (((info.last - info.first : Nat) : Int) ≤
        (info.viewport + 2 * v.overscan) / info.modelOf.minHeight + 2) := by
  intro info lo hi
  have hlo : lo = ui.scrollOf v.ref - v.overscan := rfl
  have hhi : hi = ui.scrollOf v.ref + info.viewport + v.overscan := rfl
  have hg := (model_good keys (ui.listOf v.ref) v.estimate).1
  have hm : info.modelOf = model keys (ui.listOf v.ref) v.estimate := infoOf_model v ui keys
  have hw : (info.first, info.last) = info.modelOf.window lo hi := infoOf_window v ui keys
  have hvp : 0 ≤ info.viewport := infoOf_viewport v ui keys
  have hmin := minHeight_pos keys (ui.listOf v.ref) v.estimate
  have hcount : info.modelOf.count = keys.size := rfl
  clear_value info lo hi
  rw [← hm] at hg hmin
  refine ⟨fun i hi' => ?_, hvp, ?_⟩
  · have hc : i < info.modelOf.count := hcount ▸ hi'
    have := info.modelOf.window_iff hg lo hi hc
    rw [← hw] at this; exact this
  · have := info.modelOf.window_count hg (m := info.modelOf.minHeight) (by omega)
      (info.modelOf.minHeight_le hg.sorted) lo hi (by omega)
    rw [← hw] at this
    have e : hi - lo = info.viewport + 2 * v.overscan := by omega
    rw [e] at this; exact this

/-! ## What the runtime records -/

/-- `x` within `[0, lim]` (lim floored at 0), as the runtime clamps offsets. -/
def clampTo (x lim : Int) : Int := max 0 (min x lim)

/-- The rows a laid list laid, with their heights: its children past the top spacer. -/
def laidRows (info : Info) (kids : List Laid) : List Row :=
  go info.first ((kids.drop 1).take (info.last - info.first))
where
  go : Nat → List Laid → List Row
    | _, [] => []
    | i, k :: ks => { index := i, key := info.keys[i]?.getD 0, height := max 1 k.rect.h.toNat } ::
        go (i + 1) ks

/-- How many rows either side of those laid the runtime keeps the heights of. Further rows go
back to the estimate (the anchor keeps the rows on screen still when they do), so what the
runtime keeps, and what a frame costs, stays bounded however long the list and however much of
it has been scrolled through (bench/vlist.md). -/
def keepSpan : Nat := 500

/-- What is known after a layout: the heights known before within `keepSpan` rows of those laid
(none if the width changed), with the rows just laid at the heights they were laid at. -/
def merged (info : Info) (width : Int) (kids : List Laid) : Array Row :=
  let base := if info.known.width = width then info.model else #[]
  (base.filter fun r => info.first - keepSpan ≤ r.index ∧ r.index < info.first) ++
    (laidRows info kids).toArray ++
    (base.filter fun r => info.last ≤ r.index ∧ r.index < info.last + keepSpan)

/-- The estimate kept after a layout: the one kept before, unless the width changed; else the
mean of the heights now known. -/
def keptEst (info : Info) (width : Int) (rows : Array Row) : Nat :=
  if info.known.width = width ∧ 0 < info.known.est then info.known.est else mean rows

/-- The model after a layout. -/
def after (info : Info) (width : Int) (kids : List Laid) : Model :=
  let rows := merged info width kids
  { rows, est := estOf info.estimate (keptEst info width rows) rows, count := info.keys.size }

/-- The row to keep still, as its index in the new model and its top before: the anchor, if the
offset is where it was recorded (nothing scrolled since) and its key is still known; otherwise
the first row showing at the laid offset `o`, in the heights it was laid by. -/
def keepRow (info : Info) (rows : Array Row) (o : Int) : Option (Nat × Int) :=
  let reanchor : Option (Nat × Int) :=
    let M := info.modelOf
    let pre := M.pre
    let i := M.firstF pre o
    if info.first ≤ i ∧ i < info.last then some (i, M.topF pre i) else none
  match info.known.anchor with
  | some a =>
    if a.offset = o then
      match rows.find? (·.key == a.key) with
      | some r => some (r.index, a.top + a.hold)
      | none => reanchor
    else reanchor
  | none => reanchor

/-- The corrected offset: `o` moved by as much as the kept row's top moved, clamped. -/
def corrected (M' : Model) (keepAt : Option (Nat × Int)) (o lim : Int) : Int :=
  match keepAt with
  | some (i, t) => clampTo (o + (M'.topF M'.pre i - t)) lim
  | none => clampTo o lim

/-- The anchor recorded after a correction to `o'`: the first row showing at `o'`, if it was
laid, else the kept row. But when the clamp moved the offset (the kept row isn't where it was on
screen), the kept row, held: `top + hold` is where its top would be had the offset moved freely
(`o' + (t − o)`), so a later layout in the same batch that can (a longer list, a larger limit)
moves the offset to put it back (`record_holds`, `record_returns`). The hold lasts until the
batch's frame is shown (`Runtime.steps`, `Known.letGo`): then the row is kept where it shows. -/
def anchorAt (info : Info) (M' : Model) (keepAt : Option (Nat × Int)) (o o' : Int) :
    Option Anchor :=
  let pre' := M'.pre
  let i1 := M'.firstF pre' o'
  let first : Option Anchor :=
    if info.first ≤ i1 ∧ i1 < info.last then
      some { key := info.keys[i1]?.getD 0, top := M'.topF pre' i1, offset := o' }
    else keepAt.map fun (i, _) => { key := info.keys[i]?.getD 0, top := M'.topF pre' i, offset := o' }
  match keepAt with
  | some (i, t) =>
    if o' = o + (M'.topF pre' i - t) then first
    else some { key := info.keys[i]?.getD 0, top := M'.topF pre' i, offset := o',
                hold := o' + (t - o) - M'.topF pre' i }
  | none => first

/-- **The runtime's record of a laid list** (`Runtime.fixUI`): the box at `r` with padding `pad`,
laid at offset `o` with children `kids`, whose offset may go up to `lim`. Returns what is now
known (the heights laid, the box's length, the anchor) and the corrected offset. -/
def record (info : Info) (r : Rect) (pad : Insets) (o lim : Int) (kids : List Laid) :
    Known × Int :=
  let width := r.w - pad.left - pad.right
  let M' := after info width kids
  let keepAt := keepRow info M'.rows o
  let o' := corrected M' keepAt o lim
  ({ width, count := info.keys.size, rows := M'.rows, viewport := r.h,
     anchor := anchorAt info M' keepAt o o', est := keptEst info width M'.rows }, o')

/-- **The anchor stays still.** When the runtime keeps a row still (the anchor, or the row
showing at the laid offset), the corrected offset moves by exactly as much as that row's top
moved, so the row is where it was on screen (its top less the offset is unchanged), unless the
clamp moved it. This holds whatever changed: rows inserted or removed above it, heights
corrected above it or the estimate changing; a change wholly below it moves nothing
(`top_eq_of_below`). -/
theorem record_keeps (info : Info) (r : Rect) (pad : Insets) (o lim : Int) (kids : List Laid)
    {i : Nat} {t : Int}
    (hk : keepRow info (after info (r.w - pad.left - pad.right) kids).rows o = some (i, t))
    (hc : 0 ≤ o + ((after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre i - t) ∧
      o + ((after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre i - t) ≤ lim) :
    (after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre i -
      (record info r pad o lim kids).2 = t - o := by
  simp only [record, corrected, hk, clampTo]
  omega

/-- When the anchor is kept, it is the anchor recorded at this offset: the row the reader was
at, wherever its key has moved. -/
theorem keepRow_anchor (info : Info) (rows : Array Row) (o : Int) {a : Anchor}
    (ha : info.known.anchor = some a) (ho : a.offset = o) {r : Row}
    (hr : rows.find? (·.key == a.key) = some r) :
    keepRow info rows o = some (r.index, a.top + a.hold) := by
  simp only [keepRow, ha, ho, ↓reduceIte, hr]

/-- **A clamped row is held, not dropped.** When the clamp keeps the offset from moving as far
as the kept row's top moved (rows inserted above it at the end of a short list, say), the anchor
recorded is that row, held at its top had the offset moved freely: its place on screen before,
`t − o`, from the corrected offset. -/
theorem record_holds (info : Info) (r : Rect) (pad : Insets) (o lim : Int) (kids : List Laid)
    {i : Nat} {t : Int}
    (hk : keepRow info (after info (r.w - pad.left - pad.right) kids).rows o = some (i, t))
    (hc : (record info r pad o lim kids).2 ≠ o + ((after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre i - t)) :
    ∃ a, (record info r pad o lim kids).1.anchor = some a ∧ a.key = info.keys[i]?.getD 0 ∧
      a.offset = (record info r pad o lim kids).2 ∧
      a.top + a.hold = (record info r pad o lim kids).2 + (t - o) := by
  simp only [record, anchorAt, hk] at hc ⊢
  simp only [hc, ↓reduceIte, Option.some.injEq, exists_eq_left']
  exact ⟨trivial, trivial, by omega⟩

/-- **And put back once the clamp allows.** The next record of the list, laid at the offset a
held anchor was recorded at, with the row's key still known, keeps the row where it was before
the clamp held it, `t − o` into the box, unless the clamp moves the offset again. With
`record_holds`: a row inserted or grown above the first row showing moves nothing on screen once
the list is long enough to let it, within the batch. -/
theorem record_returns (info : Info) (r : Rect) (pad : Insets) (o' lim : Int) (kids : List Laid)
    {a : Anchor} {o t : Int} (ha : info.known.anchor = some a) (hao : a.offset = o')
    (hat : a.top + a.hold = o' + (t - o)) {row : Row}
    (hr : (after info (r.w - pad.left - pad.right) kids).rows.find? (·.key == a.key) = some row)
    (hc : 0 ≤ o' + ((after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre row.index - (a.top + a.hold)) ∧
      o' + ((after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre row.index - (a.top + a.hold)) ≤ lim) :
    (after info (r.w - pad.left - pad.right) kids).topF
        (after info (r.w - pad.left - pad.right) kids).pre row.index -
      (record info r pad o' lim kids).2 = t - o := by
  have hk := keepRow_anchor info _ o' ha hao hr
  have := record_keeps info r pad o' lim kids hk hc
  omega

end VList

end Cairn

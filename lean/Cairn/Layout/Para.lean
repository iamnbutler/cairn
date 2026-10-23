import Cairn.Layout.Rigid
import Cairn.Text.WrapProofs

/-! # Wrapped text in layout

`measure` turns `Node.para ts wr s` into a clipping column (`paraStyle wr`) of one `Sized.text`
per line (`paraLines`). The lines come from `Cairn.Text.Wrap.lines` on the offsets of one
measurement of `s`, at `wrapWidth wr aw`. Because a para *is* a box of text once measured,
`arrange`, `Laid`, the frame and hit testing are unchanged, and every layout theorem
(`Cairn.Layout.facts`, `Pressable`, `fitsIn_arrange`) covers views with wrapped text in them.

What is proved here, for every metrics `m` and offered width `aw`:

- `para_lines_fit`: every line's measured width is at most the wrap width (when that is
  non-negative), or the line is a single scalar;
- `para_lines_tile`: the lines, with break spaces only put back between and around them, are
  the text (without `maxLines`); `para_lines_tail` / `para_lines_head`: with `maxLines`, they
  are exactly the last / first lines of that;
- `para_count`: at most `maxLines` lines;
- `para_height`: a `hug` para is lines × line height tall, each line one line height;
  `layout_para_height`: so is a root para's rect. -/

namespace Cairn.Layout
open Cairn.Text.Wrap

/-- The offsets a para breaks with. -/
def paraOffsets (m : TextMetrics) (ts : TextStyle) (s : String) : Nat → Int :=
  offAt (m.offsets ts.font s)

theorem measure_para (m : TextMetrics) (aw : Int) (ts : TextStyle) (wr : Wrap) (s : String) :
    measure m aw (.para ts wr s) =
      .box (paraStyle wr) none
        ⟨resolve wr.width (contentSize .column 0 ((paraLines m ts wr aw s).map Sized.size)).w,
         resolve wr.height (contentSize .column 0 ((paraLines m ts wr aw s).map Sized.size)).h⟩
        (paraLines m ts wr aw s) := rfl

theorem paraLines_eq (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String) :
    paraLines m ts wr aw s = (lines (paraOffsets m ts s) (wrapWidth wr aw) wr s.toList).map
      fun p => .text ts (String.ofList (slice s.toList p))
        ⟨max 0 (width (paraOffsets m ts s) p), max 0 (m.lineHeight ts.font)⟩ := rfl

theorem slice_length_le (cs : List Char) (p : Nat × Nat) : (slice cs p).length ≤ p.2 - p.1 := by
  simp only [slice, List.length_take]; omega

/-- **Lines fit.** Every line of a para is at most the wrap width wide, or is one scalar. -/
theorem para_lines_fit (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String)
    (hW : 0 ≤ wrapWidth wr aw) :
    ∀ k ∈ paraLines m ts wr aw s, ∃ str sz, k = .text ts str sz ∧
      (sz.w ≤ wrapWidth wr aw ∨ str.length ≤ 1) := by
  intro k hk
  rw [paraLines_eq, List.mem_map] at hk
  obtain ⟨p, hp, rfl⟩ := hk
  refine ⟨_, _, rfl, ?_⟩
  rcases lines_fit _ _ wr s.toList p hp with h | h
  · left; simp only [width]; omega
  · right; have := slice_length_le s.toList p
    simp only [String.length_ofList]; omega

/-- The lines' strings, as scalars. -/
def paraStrings (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String) :
    List (List Char) :=
  (paraLines m ts wr aw s).map fun
    | .text _ str _ => str.toList
    | _ => []

theorem paraStrings_eq (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String) :
    paraStrings m ts wr aw s =
      (lines (paraOffsets m ts s) (wrapWidth wr aw) wr s.toList).map (slice s.toList) := by
  simp only [paraStrings, paraLines_eq, List.map_map]
  apply List.map_congr_left
  intro p _
  simp only [Function.comp, String.toList_ofList]

/-- **Lines tile the text.** Without `maxLines`, the text is its lines with break spaces only
between and around them. -/
theorem para_lines_tile (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String)
    (hm : wr.maxLines = none) : Tiles s.toList (paraStrings m ts wr aw s) := by
  rw [paraStrings_eq, lines_none _ _ _ _ hm]
  exact allLines_tiles _ _ _

/-- **Keep tail.** With `maxLines = some n` and `keep = .tail`, the lines shown are exactly the
last `min n k` of the `k` lines the text breaks into. -/
theorem para_lines_tail (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String)
    (n : Nat) (hm : wr.maxLines = some n) (hk : wr.keep = .tail) :
    let all := (allLines (paraOffsets m ts s) (wrapWidth wr aw) s.toList).map (slice s.toList)
    ∃ pre, pre ++ paraStrings m ts wr aw s = all ∧
      (paraStrings m ts wr aw s).length = min n all.length := by
  obtain ⟨pre, h1, h2⟩ := lines_tail (paraOffsets m ts s) (wrapWidth wr aw) wr s.toList n hm hk
  refine ⟨pre.map (slice s.toList), ?_, ?_⟩
  · rw [paraStrings_eq, ← List.map_append, h1]
  · rw [paraStrings_eq, List.length_map, List.length_map, h2]

/-- **Keep head.** With `keep = .head`, the first `min n k` lines. -/
theorem para_lines_head (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String)
    (n : Nat) (hm : wr.maxLines = some n) (hk : wr.keep = .head) :
    let all := (allLines (paraOffsets m ts s) (wrapWidth wr aw) s.toList).map (slice s.toList)
    ∃ post, paraStrings m ts wr aw s ++ post = all ∧
      (paraStrings m ts wr aw s).length = min n all.length := by
  obtain ⟨post, h1, h2⟩ := lines_head (paraOffsets m ts s) (wrapWidth wr aw) wr s.toList n hm hk
  refine ⟨post.map (slice s.toList), ?_, ?_⟩
  · rw [paraStrings_eq, ← List.map_append, h1]
  · rw [paraStrings_eq, List.length_map, List.length_map, h2]

/-- **Line count.** -/
theorem para_count (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String)
    (n : Nat) (hm : wr.maxLines = some n) : (paraLines m ts wr aw s).length ≤ n := by
  rw [paraLines_eq, List.length_map]; exact lines_length_le _ _ wr _ n hm

theorem sum_replicate_heights (lh : Int) :
    ∀ ks : List Sized, (∀ k ∈ ks, k.size.h = lh) → (ks.map fun k => k.size.h).sum = ks.length * lh
  | [], _ => by simp only [List.map_nil, List.sum_nil, List.length_nil, Int.natCast_zero, Int.zero_mul]
  | k :: ks, h => by
    simp only [List.map_cons, List.sum_cons, List.length_cons,
      sum_replicate_heights lh ks (fun x hx => h x (.tail _ hx)), h k (.head _)]
    push_cast; rw [Int.add_mul, Int.one_mul, Int.add_comm]

/-- Every line is one line height tall. -/
theorem para_line_height (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String) :
    ∀ k ∈ paraLines m ts wr aw s, k.size.h = max 0 (m.lineHeight ts.font) := by
  intro k hk
  rw [paraLines_eq, List.mem_map] at hk
  obtain ⟨p, -, rfl⟩ := hk
  rfl

/-- **Height.** A `hug` para is exactly lines × line height tall. -/
theorem para_height (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String)
    (hh : wr.height = .hug) :
    (measure m aw (.para ts wr s)).size.h =
      (paraLines m ts wr aw s).length * max 0 (m.lineHeight ts.font) := by
  rw [measure_para]
  simp only [Sized.size, contentSize, hh, resolve, gaps, Nat.zero_mul, Int.natCast_zero,
    Int.add_zero, List.map_map]
  have := sum_replicate_heights _ _ (para_line_height m ts wr aw s)
  simp only [Function.comp_def] at this ⊢
  rw [this]
  have : (0 : Int) ≤ (paraLines m ts wr aw s).length * max 0 (m.lineHeight ts.font) :=
    Int.mul_nonneg (Int.natCast_nonneg _) (Int.le_max_left _ _)
  omega

/-- A para at the root of a view is lines × line height tall, and wraps at the window's width
unless its width is fixed. -/
theorem layout_para_height (m : TextMetrics) (w : Size) (ts : TextStyle) (wr : Wrap) (s : String)
    (hh : wr.height = .hug) :
    (layout m w (.para ts wr s)).rect.h =
      (paraLines m ts wr (windowRect w).w s).length * max 0 (m.lineHeight ts.font) := by
  simp only [layout, arrange_rect, rootRect, measure_sizings, nodeSizings, hh, Sizing.isFill,
    Bool.false_eq_true, ↓reduceIte]
  exact para_height m ts wr _ s hh

end Cairn.Layout

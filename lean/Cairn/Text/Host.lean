import Cairn.Text.Metrics

/-! Core Text metrics from the host, as a `TextMetrics`.

The host shapes each (font, string) once with Core Text and reports, in whole logical points,
the font's ascent and descent and the caret offset at every Unicode scalar boundary; the
renderer draws glyphs from the very same shaped line (docs/render.md). Lean receives the numbers
as bytes through `cairn_lean_text_metrics` (lean/c/text_host.c), decodes them, and normalises
them so `TextMetrics.host` satisfies `TextMetrics.Valid` *by proof*, whatever the host sends:
`host_valid` below. What stays trusted is only that the numbers match what is painted (an
`assume`, docs/trusted.md).

Linking: the extern symbols live in `text_host.o`, which Lake links into every executable and
puts in `libcairn_Cairn.a`. The C function it calls, `cairn_text_metrics`, is defined weakly
there (returning "no host"), so `bench`, `audit` and Lean tests link without the Swift host and
get `TextMetrics.mono` numbers; the Swift host's strong definition wins when it is linked.
`hostLinked ()` says which one is in use. Never evaluate these at elaboration time (`#eval`,
`#guard`): the interpreter has no native implementation to call. -/

namespace Cairn.Text.Host

/-- `[ascent, descent, offset_0, …, offset_n]` as little-endian int32s (`4 * (n + 3)` bytes,
`n = s.length`), or empty when no host is linked. -/
@[extern "cairn_lean_text_metrics"]
opaque raw (family size weight : UInt32) (italic : UInt8) (s : @& String) : ByteArray

/-- Whether the Swift host's metrics are linked (otherwise `raw` is always empty). -/
@[extern "cairn_lean_text_host_linked"]
opaque hostLinked : Unit → Bool

/-- Font fields cross as `UInt32`, saturating: a size of 2^40 means "huge", not 2^40 mod 2^32.
The host clamps sizes to 1–1024 and weights to 100–900 itself. -/
def sat (n : Nat) : UInt32 := if n < UInt32.size then n.toUInt32 else UInt32.ofNat (UInt32.size - 1)

def rawFor (f : Font) (s : String) : ByteArray :=
  raw (sat f.family) (sat f.size) (sat f.weight) (if f.italic then 1 else 0) s

/-- The `i`th little-endian int32 of `b`; bytes past the end read as 0. -/
def word (b : ByteArray) (i : Nat) : Int :=
  let byte (k : Nat) : Nat := (b.data.getD (4 * i + k) 0).toNat
  let u := byte 0 + byte 1 * 0x100 + byte 2 * 0x10000 + byte 3 * 0x1000000
  if u < 0x80000000 then u else (u : Int) - 0x100000000

/-- Running maximum from `lo`: each entry is at least `lo` and at least the one before it. -/
def climb (lo : Int) : List Int → List Int
  | [] => []
  | x :: xs => max lo x :: climb (max lo x) xs

/-- Offsets from the host's words (or from `fallback` when the reply has the wrong size):
entry 0 forced to 0, the rest made nondecreasing and nonnegative. For a well-behaved host this
is the identity, and the Swift tests check that it is. -/
def normalise (n : Nat) (b : ByteArray) (fallback : Nat → Int) : Array Int :=
  let ok := b.size == 4 * (n + 3)
  let xs := (List.range n).map fun i => if ok then word b (i + 3) else fallback (i + 1)
  (0 :: climb 0 xs).toArray

end Cairn.Text.Host

namespace Cairn.TextMetrics
open Cairn.Text.Host

/-- Core Text's metrics, from the host. Falls back to `mono` when no host is linked. -/
def host : TextMetrics where
  offsets f s :=
    normalise s.length (rawFor f s) fun i => (mono.offsets f s).getD i 0
  ascent f :=
    let b := rawFor f ""
    max 0 (if b.size == 12 then word b 0 else mono.ascent f)
  descent f :=
    let b := rawFor f ""
    max 0 (if b.size == 12 then word b 1 else mono.descent f)

end Cairn.TextMetrics

namespace Cairn.Text.Host

theorem length_climb (lo : Int) (xs : List Int) : (climb lo xs).length = xs.length := by
  induction xs generalizing lo with
  | nil => rfl
  | cons x xs ih => simp [climb, ih]

theorem le_of_mem_climb (lo : Int) (xs : List Int) : ∀ y ∈ climb lo xs, lo ≤ y := by
  induction xs generalizing lo with
  | nil => simp [climb]
  | cons x xs ih =>
    intro y hy
    simp only [climb, List.mem_cons] at hy
    rcases hy with h | h
    · subst h; exact Int.le_max_left _ _
    · exact Int.le_trans (Int.le_max_left lo x) (ih _ y h)

theorem pairwise_climb (lo : Int) (xs : List Int) : (climb lo xs).Pairwise (· ≤ ·) := by
  induction xs generalizing lo with
  | nil => exact List.Pairwise.nil
  | cons x xs ih =>
    exact List.Pairwise.cons (fun y hy => le_of_mem_climb _ _ y hy) (ih _)

theorem pairwise_normalised (xs : List Int) : (0 :: climb 0 xs).Pairwise (· ≤ ·) :=
  List.Pairwise.cons (fun y hy => le_of_mem_climb 0 xs y hy) (pairwise_climb 0 xs)

theorem size_normalise (n : Nat) (b : ByteArray) (fb : Nat → Int) :
    (normalise n b fb).size = n + 1 := by
  simp [normalise, length_climb]

theorem normalise_zero (n : Nat) (b : ByteArray) (fb : Nat → Int) :
    (normalise n b fb)[0]? = some 0 := by
  simp [normalise]

theorem normalise_mono (n : Nat) (b : ByteArray) (fb : Nat → Int) (i j : Nat)
    (hi : i < (normalise n b fb).size) (hj : j < (normalise n b fb).size) (hij : i ≤ j) :
    (normalise n b fb)[i] ≤ (normalise n b fb)[j] := by
  unfold normalise at hi hj ⊢
  simp only [List.getElem_toArray] at hi hj ⊢
  rcases Nat.lt_or_eq_of_le hij with h | h
  · exact List.pairwise_iff_getElem.mp (pairwise_normalised _) i j
      (by simpa using hi) (by simpa using hj) h
  · subst h; exact Int.le_refl _

end Cairn.Text.Host

namespace Cairn.TextMetrics
open Cairn.Text.Host

/-- The host's metrics satisfy everything layout assumes, whatever the host returns. -/
theorem host_valid : host.Valid where
  size _ _ := size_normalise _ _ _
  zero _ _ := normalise_zero _ _ _
  mono _ _ i j hi hj hij := normalise_mono _ _ _ i j hi hj hij
  ascent _ := Int.le_max_left _ _
  descent _ := Int.le_max_left _ _

end Cairn.TextMetrics

namespace Cairn.Text.Host

/-- Little-endian int32 bytes of `v` (two's complement, truncated to 32 bits). -/
def putI32 (b : ByteArray) (v : Int) : ByteArray :=
  let u := (v % 0x100000000).toNat
  b |>.push (u % 0x100).toUInt8 |>.push (u / 0x100 % 0x100).toUInt8
    |>.push (u / 0x10000 % 0x100).toUInt8 |>.push (u / 0x1000000 % 0x100).toUInt8

/-- For the host's end-to-end test (host/Tests/CairnRenderLeanTests): what layout would see for
this font and string through `TextMetrics.host`, as int32s
`[linked, ascent, descent, offset_0, …, offset_n]`. -/
@[export cairn_text_host_check]
def hostCheck (family size weight : UInt32) (italic : UInt8) (s : String) : ByteArray :=
  let f : Font := { family := family.toNat, size := size.toNat, weight := weight.toNat, italic := italic != 0 }
  let m := TextMetrics.host
  let head := [if hostLinked () then 1 else 0, m.ascent f, m.descent f]
  (head ++ (m.offsets f s).toList).foldl putI32 ByteArray.empty

end Cairn.Text.Host

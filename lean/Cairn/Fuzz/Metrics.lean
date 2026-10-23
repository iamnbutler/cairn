import Cairn.Fuzz.Rng
import Cairn.Text.Metrics
import Cairn.Layout.Proofs

/-! # Random text metrics, valid by construction

Layout and text theorems quantify over every `TextMetrics` that is `Valid`, so the fuzzer
shouldn't test with the mono stand-in only. `random seed` gives each font its own widths:
each scalar's width is a hash of the seed, the font and the scalar, between 30% and 90% of the
font size (wider for CJK and emoji), and 0 for combining marks and zero-width joiners;
offsets are their prefix sums. Ascent and descent are random fractions of the size.
`random_valid` proves every such metrics `Valid`. -/

namespace Cairn.Fuzz
open Cairn

/-- Prefix sums from `acc`: one more entry than widths, starting at `acc`, never decreasing. -/
def sums (acc : Int) : List Nat → List Int
  | [] => [acc]
  | w :: ws => acc :: sums (acc + w) ws

theorem sums_length (acc : Int) : ∀ ws, (sums acc ws).length = ws.length + 1
  | [] => rfl
  | _ :: ws => by simp only [sums, List.length_cons, sums_length _ ws]

theorem sums_ge : ∀ (ws : List Nat) (acc : Int) (i : Nat) (h : i < (sums acc ws).length),
    acc ≤ (sums acc ws)[i]
  | [], acc, 0, _ => by simp [sums]
  | [], _, _ + 1, h => by simp [sums] at h
  | _ :: _, acc, 0, _ => by simp [sums]
  | w :: ws, acc, i + 1, h => by
    have := sums_ge ws (acc + w) i (by simpa [sums] using h)
    simp only [sums, List.getElem_cons_succ]
    omega

theorem sums_mono : ∀ (ws : List Nat) (acc : Int) (i j : Nat) (hi : i < (sums acc ws).length)
    (hj : j < (sums acc ws).length), i ≤ j → (sums acc ws)[i] ≤ (sums acc ws)[j]
  | ws, acc, 0, j, _, hj, _ => by
    have := sums_ge ws acc j hj
    cases ws <;> simp_all [sums]
  | [], _, _ + 1, _, hi, _, _ => by simp [sums] at hi
  | _ :: _, _, _ + 1, 0, _, _, h => by omega
  | w :: ws, acc, i + 1, j + 1, hi, hj, h => by
    simp only [sums, List.getElem_cons_succ]
    exact sums_mono ws (acc + w) i j (by simpa [sums] using hi) (by simpa [sums] using hj) (by omega)

/-- Scalars that take no width: combining marks, variation selectors, joiners. -/
def zeroWidth (c : Char) : Bool :=
  let n := c.toNat
  (0x300 ≤ n && n < 0x370) || (0xFE00 ≤ n && n < 0xFE10) || n == 0x200D || n == 0x200C ||
    (0x1F3FB ≤ n && n < 0x1F400)

/-- Wide scalars: CJK and emoji. -/
def wide (c : Char) : Bool := c.toNat ≥ 0x2E80

def fontKey (f : Font) : UInt64 :=
  (f.family * 1000003 + f.size * 1009 + f.weight * 7 + (if f.italic then 1 else 0)).toUInt64

def charWidth (seed : UInt64) (f : Font) (c : Char) : Nat :=
  if zeroWidth c then 0 else
  let h := (Rng.mix (seed ^^^ Rng.mix (fontKey f ^^^ (c.toNat.toUInt64 <<< 20)))).toNat
  let lo := f.size * (if wide c then 8 else 3) / 10
  let hi := f.size * (if wide c then 14 else 9) / 10
  lo + h % (hi + 1 - lo)

def fraction (seed : UInt64) (f : Font) (salt : UInt64) (lo hi : Nat) : Nat :=
  let h := (Rng.mix (seed ^^^ salt ^^^ fontKey f)).toNat
  f.size * (lo + h % (hi + 1 - lo)) / 100

/-- Random metrics from a seed. -/
def randomMetrics (seed : UInt64) : TextMetrics where
  offsets f s := (sums 0 (s.toList.map (charWidth seed f))).toArray
  ascent f := (fraction seed f 0xa5 70 100 : Nat)
  descent f := (fraction seed f 0xd5 10 35 : Nat)

theorem random_valid (seed : UInt64) : (randomMetrics seed).Valid where
  size f s := by simp [randomMetrics, sums_length, String.length_toList]
  zero f s := by
    simp only [randomMetrics]
    cases s.toList.map (charWidth seed f) <;> simp [sums]
  mono f s i j hi hj h := by
    simp only [randomMetrics, List.getElem_toArray]
    exact sums_mono _ 0 i j _ _ h
  ascent _ := by simp [randomMetrics]
  descent _ := by simp [randomMetrics]

/-- The metrics a sequence runs with: random from a seed, or the mono stand-in. -/
inductive MetricsChoice where
  | mono
  | random (seed : UInt64)
deriving Repr, Inhabited

def MetricsChoice.metrics : MetricsChoice → TextMetrics
  | .mono => TextMetrics.mono
  | .random s => randomMetrics s

theorem MetricsChoice.valid : ∀ c : MetricsChoice, c.metrics.Valid
  | .mono => TextMetrics.mono_valid
  | .random s => random_valid s

/-- One sequence in eight uses mono. -/
def MetricsChoice.gen : Gen MetricsChoice := do
  if ← Gen.chance 1 8 then return .mono
  return .random (← Gen.u64)

#guard ((randomMetrics 7).offsets {} "abc").size == 4
#guard ((randomMetrics 7).offsets {} "é")[2]! == ((randomMetrics 7).offsets {} "e")[1]!

end Cairn.Fuzz

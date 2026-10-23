import Cairn.Geometry

/-! Text metrics: the one place layout depends on the host.

Layout is parameterised by a `TextMetrics`. Theorems quantify over every metrics that is
`Valid`; at run time the host supplies Core Text's (an `assume` claim, checked by logging and
replay). Text indices are Unicode scalar positions (`String.length`), not bytes and not UTF-16.
Grapheme clusters are not modelled in M1. Text is single-line in M1: no wrapping. -/

namespace Cairn

structure Font where
  /-- 0 is the system UI font, 1 the system monospaced font. -/
  family : Nat := 0
  /-- Points. -/
  size : Nat := 13
  /-- 100–900, CSS-style. -/
  weight : Nat := 400
  italic : Bool := false
deriving Repr, BEq, DecidableEq, Inhabited, Hashable

structure TextMetrics where
  /-- Caret offsets: entry `i` is the x offset of the boundary before scalar `i`, so the array
  has `s.length + 1` entries, starts at 0 and never decreases. The last entry is the width. -/
  offsets : Font → String → Array Int
  ascent : Font → Int
  descent : Font → Int

namespace TextMetrics

def width (m : TextMetrics) (f : Font) (s : String) : Int := (m.offsets f s).back?.getD 0

def lineHeight (m : TextMetrics) (f : Font) : Int := m.ascent f + m.descent f

/-- What every metrics must satisfy. Layout and text theorems assume this and nothing more. -/
structure Valid (m : TextMetrics) : Prop where
  size : ∀ f s, (m.offsets f s).size = s.length + 1
  zero : ∀ f s, (m.offsets f s)[0]? = some 0
  mono : ∀ f s i j (hi : i < (m.offsets f s).size) (hj : j < (m.offsets f s).size),
    i ≤ j → (m.offsets f s)[i] ≤ (m.offsets f s)[j]
  ascent : ∀ f, 0 ≤ m.ascent f
  descent : ∀ f, 0 ≤ m.descent f

/-- A deterministic stand-in for tests and examples: every scalar is `size * 6 / 10` wide. -/
def mono : TextMetrics where
  offsets f s := Array.map (fun (i : Nat) => (i : Int) * ((f.size * 6 / 10 : Nat) : Int)) (Array.range (s.length + 1))
  ascent f := (f.size * 8 / 10 : Nat)
  descent f := (f.size * 2 / 10 : Nat)

end TextMetrics
end Cairn

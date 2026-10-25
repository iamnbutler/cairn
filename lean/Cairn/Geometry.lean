module

/-! Geometry in integer logical points, origin top-left, y down. No floats anywhere a theorem
looks. The host multiplies by the backing scale when it paints. -/

@[expose] public section


namespace Cairn

structure Point where
  x : Int
  y : Int
deriving Repr, BEq, DecidableEq, Inhabited

structure Size where
  w : Int
  h : Int
deriving Repr, BEq, DecidableEq, Inhabited

structure Rect where
  x : Int
  y : Int
  w : Int
  h : Int
deriving Repr, BEq, DecidableEq, Inhabited

structure Insets where
  top : Int := 0
  right : Int := 0
  bottom : Int := 0
  left : Int := 0
deriving Repr, BEq, DecidableEq, Inhabited

namespace Rect

def contains (r : Rect) (p : Point) : Bool :=
  decide (r.x ≤ p.x ∧ p.x < r.x + r.w ∧ r.y ≤ p.y ∧ p.y < r.y + r.h)

/-- The point a click on this rect is aimed at. Inside the rect whenever `w > 0 ∧ h > 0`. -/
def center (r : Rect) : Point := ⟨r.x + r.w / 2, r.y + r.h / 2⟩

/-- `r` lies entirely within `o`. -/
def inside (r o : Rect) : Prop :=
  o.x ≤ r.x ∧ r.x + r.w ≤ o.x + o.w ∧ o.y ≤ r.y ∧ r.y + r.h ≤ o.y + o.h

instance (r o : Rect) : Decidable (r.inside o) := by unfold inside; infer_instance

def disjoint (a b : Rect) : Prop :=
  a.x + a.w ≤ b.x ∨ b.x + b.w ≤ a.x ∨ a.y + a.h ≤ b.y ∨ b.y + b.h ≤ a.y

def nonempty (r : Rect) : Prop := 0 < r.w ∧ 0 < r.h

instance (r : Rect) : Decidable r.nonempty := by unfold nonempty; infer_instance

def inset (r : Rect) (i : Insets) : Rect :=
  ⟨r.x + i.left, r.y + i.top, r.w - i.left - i.right, r.h - i.top - i.bottom⟩

/-- Intersection, used for clipping. Width and height floor at zero. When the rects don't
overlap, the empty result is placed inside `a` (its origin is clamped to `a`'s far edge), so
`a.inter b` is inside `a` whenever `a` has non-negative size. -/
def inter (a b : Rect) : Rect :=
  let x := min (max a.x b.x) (a.x + a.w)
  let y := min (max a.y b.y) (a.y + a.h)
  ⟨x, y, max 0 (min (a.x + a.w) (b.x + b.w) - x), max 0 (min (a.y + a.h) (b.y + b.h) - y)⟩

end Rect

end Cairn

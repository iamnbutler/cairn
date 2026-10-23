import Cairn.Layout.Core

/-! # What layout guarantees

The vocabulary for the layout theorems: controls of a tree, a predicate holding at every node
(`Laid.Everywhere`), the local facts layout establishes at each node, and `Facts`, the package
the runtime's pressability proof consumes. The theorems are in `Cairn.Layout.Proofs`. -/

namespace Cairn

mutual
/-- The controls of a view, in paint order (a node before its children, children in order). -/
def Node.controls : Node → List Control
  | .box _ c kids => c.toList ++ Node.controlsList kids
  | .text .. => []
  | .field _ _ c _ => [c]
def Node.controlsList : List Node → List Control
  | [] => []
  | n :: ns => n.controls ++ Node.controlsList ns
end

mutual
/-- The controls of a laid-out tree, in paint order. -/
def Laid.controls : Laid → List Control
  | .box _ _ _ c kids => c.toList ++ Laid.controlsList kids
  | .text .. => []
  | .field _ _ _ _ c .. => [c]
def Laid.controlsList : List Laid → List Control
  | [] => []
  | l :: ls => l.controls ++ Laid.controlsList ls
end

namespace Laid

def children : Laid → List Laid
  | .box _ _ _ _ k => k
  | _ => []

/-- Sizing on each axis (text always hugs). -/
def sizings : Laid → Sizing × Sizing
  | .box _ _ st .. | .field _ _ st .. => (st.width, st.height)
  | .text .. => (.hug, .hug)

/-- `P` holds at `l` and at every node below it. -/
inductive Everywhere (P : Laid → Prop) : Laid → Prop
  | intro {l : Laid} : P l → (∀ k ∈ l.children, Everywhere P k) → Everywhere P l

theorem Everywhere.here {P : Laid → Prop} {l : Laid} : l.Everywhere P → P l
  | .intro h _ => h

theorem Everywhere.child {P : Laid → Prop} {l k : Laid} : l.Everywhere P → k ∈ l.children →
    k.Everywhere P
  | .intro _ h, hk => h k hk

/-- The clip a node hands its children: its own, cut down to its rect if it clips. -/
def innerClip : Laid → Rect
  | .box r c st _ _ => Layout.innerClip st c r
  | l => l.clip

end Laid

namespace Layout

/-! ## Local facts, one per node -/

/-- Each child's clip is exactly the clip its parent hands down: the parent's clip, intersected
with the parent's rect when the parent clips. -/
def ChildClips (l : Laid) : Prop := ∀ k ∈ l.children, k.clip = l.innerClip

/-- The node's clip has non-negative size and contains each child's clip. -/
def ClipInside (l : Laid) : Prop :=
  0 ≤ l.clip.w ∧ 0 ≤ l.clip.h ∧ ∀ k ∈ l.children, k.clip.inside l.clip

/-- The node's rect has non-negative size. -/
def RectNonneg (l : Laid) : Prop := 0 ≤ l.rect.w ∧ 0 ≤ l.rect.h

/-- In a row or column, earlier children end before later ones begin on the main axis, so
distinct children's rects are disjoint. -/
def SiblingsDisjoint : Laid → Prop
  | .box _ _ st _ kids => st.axis ≠ .stack → kids.Pairwise fun a b => a.rect.disjoint b.rect
  | _ => True

/-- Whether an axis runs horizontally (rows) or vertically (columns). -/
def Axis.horiz : Axis → Bool
  | .row => true
  | _ => false

/-- Padding along the main axis. -/
def padMain (horiz : Bool) (p : Insets) : Int := if horiz then p.left + p.right else p.top + p.bottom

/-- Fill exactness: in a row or column, if some child fills the main axis and the other
children, gaps and padding fit, then children, gaps and padding span the parent exactly. Each
child is described by its main-axis sizing and length. -/
def FillExact : Laid → Prop
  | .box r _ st _ kids => st.axis ≠ .stack →
    let h := Axis.horiz st.axis
    let ps := kids.map fun k => ((if h then k.sizings.1 else k.sizings.2), mainOf h k.rect)
    ps.any (·.1.isFill) →
    padMain h st.padding + ((ps.filter (!·.1.isFill)).map (·.2)).sum + gaps st.gap ps.length
      ≤ mainOf h r →
    padMain h st.padding + (ps.map (·.2)).sum + gaps st.gap ps.length = mainOf h r
  | _ => True

/-- Children that fit stay inside: if every child's rect is no larger than the content box and,
in a row or column, the children plus gaps fit along the main axis, then every child's rect is
inside the content box. Together with `SiblingsDisjoint`, this means nothing in one child's
subtree can cover another child, as long as the view fits. -/
def ChildrenInside : Laid → Prop
  | .box r _ st _ kids =>
    let content := r.inset st.padding
    (∀ k ∈ kids, k.rect.w ≤ content.w ∧ k.rect.h ≤ content.h) →
    (st.axis ≠ .stack →
      (kids.map fun k => mainOf (Axis.horiz st.axis) k.rect).sum + gaps st.gap kids.length
        ≤ mainOf (Axis.horiz st.axis) content) →
    ∀ k ∈ kids, k.rect.inside content
  | _ => True

/-- Field geometry: the caret sits at the text origin plus the caret's offset, within the
text's extent, is one point wide and a line high, and is inside the content box horizontally
whenever the content box is at least one point wide (the text scrolls to keep it there). The
selection is empty when collapsed and otherwise runs between the offsets of its ends. -/
def CaretPlaced (m : TextMetrics) : Laid → Prop
  | .field r _ st ts _ v o caret sel =>
    let content := r.inset st.padding
    let offs := m.offsets ts.font v.text
    (∀ h : v.caret < offs.size, caret.x = o.x + offs[v.caret]) ∧
    o.x ≤ caret.x ∧ caret.x ≤ o.x + m.width ts.font v.text ∧
    caret.w = 1 ∧ caret.h = m.lineHeight ts.font ∧
    (1 ≤ content.w → content.x ≤ caret.x ∧ caret.x + caret.w ≤ content.x + content.w) ∧
    (v.anchor = v.caret → sel = []) ∧
    (v.anchor ≠ v.caret → ∃ s, sel = [s] ∧ s.y = caret.y ∧ s.h = caret.h ∧
      s.x = o.x + offAt offs (min v.anchor v.caret) ∧
      s.x + s.w = o.x + offAt offs (max v.anchor v.caret))
  | _ => True

/-- Everything `layout m window n` guarantees about its result `l`. The runtime's pressability
theorem takes these as hypotheses; `Cairn.Layout.facts` proves them for every view, window and
valid metrics. -/
structure Facts (m : TextMetrics) (window : Size) (n : Node) (l : Laid) : Prop where
  /-- No control is lost, invented or reordered. -/
  controls : l.controls = n.controls
  /-- The root paints within the window. -/
  rootClip : l.clip = windowRect window
  /-- The root sits at the origin. -/
  rootOrigin : l.rect.x = 0 ∧ l.rect.y = 0
  childClips : l.Everywhere ChildClips
  clipInside : l.Everywhere ClipInside
  rectNonneg : l.Everywhere RectNonneg
  siblingsDisjoint : l.Everywhere SiblingsDisjoint
  fillExact : l.Everywhere FillExact
  childrenInside : l.Everywhere ChildrenInside
  caretPlaced : l.Everywhere (CaretPlaced m)

end Layout
end Cairn

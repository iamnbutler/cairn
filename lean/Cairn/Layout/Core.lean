module

public import Cairn.UI.Node
public import Cairn.Text.Wrap

/-! # Layout

`layout m window node` turns a `Node` into a `Laid`: every rect, clip, baseline, caret and
selection resolved in integer logical points. It is total and pure, and works in two passes:

1. **Measure** (`measure`, bottom-up): each node's preferred ("hug") size, stored in a `Sized`
   tree so that no subtree is measured twice. It is passed the width the parent offers, which
   only wrapped text (`Node.para`) uses: a para measures into a clipping column of its lines,
   one `text` each (`paraLines`), so `arrange` never sees a para.
2. **Arrange** (`arrange`, top-down): each node is given a rect by its parent and places its
   children inside its content box.

The semantics are specified in `docs/layout.md`; the theorems are in `Cairn.Layout.Proofs`.
Every definition here is plain structural recursion over lists so that the proofs can follow
the code. -/

@[expose] public section

namespace Cairn.Layout

/-! ## Measure -/

/-- A node with its preferred size resolved. This is the measure pass's output and the arrange
pass's input. `size` is the size the node asks for: `fixed n` gives `n`, `hug` and `fill` give
the intrinsic size of the content plus padding, floored at zero. -/
inductive Sized where
  | box (style : Style) (control : Option Control) (size : Size) (children : List Sized)
  | text (style : TextStyle) (content : String) (size : Size)
  | field (style : Style) (text : TextStyle) (control : Control) (view : FieldView) (size : Size)
deriving Inhabited

/-- What a parent needs to know about a child to place it. -/
structure Item where
  width : Sizing
  height : Sizing
  size : Size
  /-- Whether `align := .stretch` may stretch the child. Text is never stretched: its rect is
  always its measured box. -/
  stretch : Bool

namespace Sized

def size : Sized → Size
  | .box _ _ s _ | .text _ _ s | .field _ _ _ _ s => s

/-- Sizing on each axis (text always hugs). -/
def sizings : Sized → Sizing × Sizing
  | .box st .. | .field st .. => (st.width, st.height)
  | .text .. => (.hug, .hug)

def item (s : Sized) : Item :=
  { width := s.sizings.1, height := s.sizings.2, size := s.size,
    stretch := match s with | .text .. => false | _ => true }

end Sized

/-- Resolve a preferred length: `fixed n` is `n`; `hug` and `fill` are the intrinsic length,
floored at zero. -/
def resolve (s : Sizing) (intrinsic : Int) : Int :=
  match s with
  | .fixed n => n
  | _ => max 0 intrinsic

/-- Total length of the gaps between `k` children. -/
def gaps (gap : Nat) (k : Nat) : Int := ((gap * (k - 1) : Nat) : Int)

/-- Largest element, or 0. -/
def maxAll : List Int → Int
  | [] => 0
  | x :: xs => max x (maxAll xs)

/-- Intrinsic content size of a container from its children's preferred sizes. -/
def contentSize (axis : Axis) (gap : Nat) (kids : List Size) : Size :=
  match axis with
  | .row => ⟨(kids.map Size.w).sum + gaps gap kids.length, maxAll (kids.map Size.h)⟩
  | .column => ⟨maxAll (kids.map Size.w), (kids.map Size.h).sum + gaps gap kids.length⟩
  | .stack => ⟨maxAll (kids.map Size.w), maxAll (kids.map Size.h)⟩

/-- The string a field sizes itself to: its text, or its placeholder when empty. -/
def FieldView.shown (v : FieldView) : String := if v.text.isEmpty then v.placeholder else v.text

/-- Caret offset at scalar index `i`, clamped to the end of the text. -/
def offAt (offs : Array Int) (i : Nat) : Int := offs[i]?.getD (offs.back?.getD 0)

/-- The width a box offers its children to wrap in: its own (`fixed`) width or the width it was
offered, less its horizontal padding. -/
def innerAvail (st : Style) (aw : Int) : Int :=
  (match st.width with | .fixed n => (n : Int) | _ => aw) - st.padding.left - st.padding.right

/-- The width a wrapped text breaks at: its `fixed` width, or the width it was offered. -/
def wrapWidth (wr : Wrap) (aw : Int) : Int :=
  match wr.width with
  | .fixed n => n
  | _ => aw

/-- A wrapped text is laid out as a column of its lines that clips to its rect. -/
def paraStyle (wr : Wrap) : Style :=
  { axis := .column, width := wr.width, height := wr.height, align := wr.align, clip := true,
    gap := wr.lineSpacing }

/-- The lines of a wrapped text, each a `text` sized to its width by the line height. The
offsets come from one measurement of the whole string. -/
def paraLines (m : TextMetrics) (ts : TextStyle) (wr : Wrap) (aw : Int) (s : String) : List Sized :=
  let cs := s.toList
  let o := offAt (m.offsets ts.font s)
  let lh := max 0 (m.lineHeight ts.font)
  Text.Wrap.mapSlices (fun p t => .text ts (String.ofList t) ⟨max 0 (Text.Wrap.width o p), lh⟩)
    cs (Text.Wrap.lines o (wrapWidth wr aw) wr cs)

mutual
/-- The measure pass. `aw` is the width the parent offers, which only wrapped text uses. -/
def measure (m : TextMetrics) (aw : Int) : Node → Sized
  | .para ts wr s =>
    let ks := paraLines m ts wr aw s
    let c := contentSize .column wr.lineSpacing (ks.map Sized.size)
    .box (paraStyle wr) none ⟨resolve wr.width c.w, resolve wr.height c.h⟩ ks
  | .box st ctl kids =>
    let ks := measureList m (innerAvail st aw) kids
    let c := contentSize st.axis st.gap (ks.map Sized.size)
    .box st ctl
      ⟨resolve st.width (c.w + st.padding.left + st.padding.right),
       resolve st.height (c.h + st.padding.top + st.padding.bottom)⟩ ks
  | .text ts s => .text ts s ⟨max 0 (m.width ts.font s), max 0 (m.lineHeight ts.font)⟩
  | .field st ts ctl v =>
    -- One extra point so a caret at the end of the text fits.
    .field st ts ctl v
      ⟨resolve st.width (max 0 (m.width ts.font (FieldView.shown v)) + 1 + st.padding.left + st.padding.right),
       resolve st.height (max 0 (m.lineHeight ts.font) + st.padding.top + st.padding.bottom)⟩
def measureList (m : TextMetrics) (aw : Int) : List Node → List Sized
  | [] => []
  | n :: ns => measure m aw n :: measureList m aw ns
end

/-! ## Arrange: rows and columns -/

def _root_.Cairn.Sizing.isFill : Sizing → Bool
  | .fill => true
  | _ => false

/-- Main-axis length a child asks for before leftover space is shared: `fill` asks for 0. -/
def mainBase (s : Sizing) (pref : Int) : Int :=
  match s with
  | .fixed n => n
  | .hug => max 0 pref
  | .fill => 0

/-- The first `n` of `f` equal shares of `L`, together: `⌊L·n/f⌋`. -/
def cumShare (L : Int) (f n : Nat) : Int := L * (n : Int) / (f : Int)

/-- The `j`-th of `f` equal shares of `L`. The shares telescope, so they sum to exactly `L`,
and they differ by at most one (the larger ones come later). -/
def fillShare (L : Int) (f j : Nat) : Int := cumShare L f (j + 1) - cumShare L f j

/-- Cross-axis placement within `[c0, c0 + cc)`: returns position and length. -/
def crossPlace (al : Align) (c0 cc : Int) (s : Sizing) (pref : Int) (stretch : Bool) : Int × Int :=
  let len : Int :=
    match s with
    | .fixed n => n
    | .fill => cc
    | .hug => if al == .stretch && stretch then cc else max 0 pref
  let pos : Int :=
    match al with
    | .start | .stretch => c0
    | .center => c0 + (cc - len) / 2
    | .finish => c0 + cc - len
  (pos, len)

def Item.mainSizing (horiz : Bool) (it : Item) : Sizing := if horiz then it.width else it.height
def Item.crossSizing (horiz : Bool) (it : Item) : Sizing := if horiz then it.height else it.width
def Item.mainPref (horiz : Bool) (it : Item) : Int := if horiz then it.size.w else it.size.h
def Item.crossPref (horiz : Bool) (it : Item) : Int := if horiz then it.size.h else it.size.w

/-- The main-axis length of an item, given the shared leftover `L` among `f` fill children, `j`
of which come before it. -/
def mainSize (horiz : Bool) (L : Int) (f j : Nat) (it : Item) : Int :=
  match it.mainSizing horiz with
  | .fill => fillShare L f j
  | s => mainBase s (it.mainPref horiz)

def mkRect (horiz : Bool) (mainPos mainLen crossPos crossLen : Int) : Rect :=
  if horiz then ⟨mainPos, crossPos, mainLen, crossLen⟩ else ⟨crossPos, mainPos, crossLen, mainLen⟩

/-- Everything a line of children shares. -/
structure Line where
  horiz : Bool
  align : Align
  /-- Cross-axis start and length of the content box. -/
  c0 : Int
  cc : Int
  /-- Leftover space for fill children, and how many there are. -/
  L : Int
  f : Nat
  /-- Space after the `i`-th child. -/
  spacing : Nat → Int

/-- Place a line of children: `i` is the child's index, `j` the number of fill children before
it, `pos` where it starts on the main axis. -/
def Line.go (ln : Line) : Nat → Nat → Int → List Item → List Rect
  | _, _, _, [] => []
  | i, j, pos, it :: its =>
    let s := mainSize ln.horiz ln.L ln.f j it
    let c := crossPlace ln.align ln.c0 ln.cc (it.crossSizing ln.horiz) (it.crossPref ln.horiz) it.stretch
    let j' := if (it.mainSizing ln.horiz).isFill then j + 1 else j
    mkRect ln.horiz pos s c.1 c.2 :: ln.go (i + 1) j' (pos + s + ln.spacing i) its

/-- Space after child `i` for `justify`: `gap`, plus for `stretch` (space-between) an equal
share of the free space when there is some and more than one child. -/
def spacing (justify : Align) (gap : Nat) (free : Int) (k : Nat) (i : Nat) : Int :=
  match justify with
  | .stretch => if 0 < free ∧ 1 < k then (gap : Int) + fillShare free (k - 1) i else gap
  | _ => gap

/-- Where the first child starts, relative to the content box, for `justify`. -/
def startOffset (justify : Align) (free : Int) : Int :=
  match justify with
  | .start | .stretch => 0
  | .center => free / 2
  | .finish => free

/-- The main-axis length of a row (`horiz`) or column's content box. -/
def mainOf (horiz : Bool) (r : Rect) : Int := if horiz then r.w else r.h

/-- Sum of the children's base lengths (fill children count 0). -/
def baseSum (horiz : Bool) (items : List Item) : Int :=
  (items.map fun it => mainBase (it.mainSizing horiz) (it.mainPref horiz)).sum

/-- Number of fill children on the main axis. -/
def fillCount (horiz : Bool) (items : List Item) : Nat :=
  (items.filter fun it => (it.mainSizing horiz).isFill).length

/-- Leftover main-axis space shared by fill children, floored at zero. -/
def leftover (horiz : Bool) (st : Style) (content : Rect) (items : List Item) : Int :=
  max 0 (mainOf horiz content - baseSum horiz items - gaps st.gap items.length)

/-- Main-axis space left after every child and gap; this is what `justify` distributes.
With fill children the line is full unless it overflows. -/
def free (horiz : Bool) (st : Style) (content : Rect) (items : List Item) : Int :=
  let used := if fillCount horiz items = 0 then baseSum horiz items
    else baseSum horiz items + leftover horiz st content items
  mainOf horiz content - (used + gaps st.gap items.length)

def lineOf (horiz : Bool) (st : Style) (content : Rect) (items : List Item) : Line :=
  { horiz, align := st.align,
    c0 := if horiz then content.y else content.x,
    cc := max 0 (if horiz then content.h else content.w),
    L := leftover horiz st content items, f := fillCount horiz items,
    spacing := spacing st.justify st.gap (free horiz st content items) items.length }

/-- Rects for the children of a row (`horiz`) or column with content box `content`. -/
def lineRects (horiz : Bool) (st : Style) (content : Rect) (items : List Item) : List Rect :=
  (lineOf horiz st content items).go 0 0
    ((if horiz then content.x else content.y) + startOffset st.justify (free horiz st content items))
    items

/-- Rects for the children of a stack: each child is placed in the whole content box,
horizontally by `justify` and vertically by `align`. -/
def stackRects (st : Style) (content : Rect) (items : List Item) : List Rect :=
  items.map fun it =>
    let x := crossPlace st.justify content.x (max 0 content.w) it.width it.size.w it.stretch
    let y := crossPlace st.align content.y (max 0 content.h) it.height it.size.h it.stretch
    ⟨x.1, y.1, x.2, y.2⟩

/-- Rects for a container's children, given the container's rect. -/
def childRects (st : Style) (r : Rect) (items : List Item) : List Rect :=
  match st.axis with
  | .row => lineRects true st (r.inset st.padding) items
  | .column => lineRects false st (r.inset st.padding) items
  | .stack => stackRects st (r.inset st.padding) items

/-! ## Arrange: fields -/

/-- How far a field's text is scrolled left so that a caret at offset `co` is visible in a
content box `cw` wide: zero unless the caret would fall off the right edge, and then just
enough to put it at the right edge. -/
def scrollFor (co cw : Int) : Int := max 0 (co + 1 - cw)

/-- Lay out a field in `r`: text vertically centred in the content box, scrolled horizontally
so the caret is visible. -/
def field (m : TextMetrics) (clip r : Rect) (st : Style) (ts : TextStyle) (ctl : Control)
    (v : FieldView) : Laid :=
  let content := r.inset st.padding
  let offs := m.offsets ts.font v.text
  let lh := m.lineHeight ts.font
  let top := content.y + (content.h - lh) / 2
  let co := offAt offs v.caret
  let tx := content.x - scrollFor co content.w
  let lo := min v.anchor v.caret
  let hi := max v.anchor v.caret
  .field r clip st ts ctl v ⟨tx, top + m.ascent ts.font⟩ ⟨tx + co, top, 1, lh⟩
    (if lo = hi then [] else [⟨tx + offAt offs lo, top, offAt offs hi - offAt offs lo, lh⟩])

/-! ## Arrange -/

/-- Region a container's children may paint in: its own clip, intersected with its rect when
it clips. -/
def innerClip (st : Style) (clip r : Rect) : Rect := if st.clip then clip.inter r else clip

mutual
/-- The arrange pass: lay out `s` in `r`, painting within `clip`. -/
def arrange (m : TextMetrics) (clip r : Rect) : Sized → Laid
  | .box st ctl _ kids =>
    .box r clip st ctl
      (arrangeList m (innerClip st clip r) (childRects st r (kids.map Sized.item)) kids)
  | .text ts s _ => .text r clip (r.y + m.ascent ts.font) ts s
  | .field st ts ctl v _ => field m clip r st ts ctl v
/-- Arrange children against their rects (the lists always have the same length; a missing
rect would be empty). -/
def arrangeList (m : TextMetrics) (clip : Rect) : List Rect → List Sized → List Laid
  | _, [] => []
  | [], s :: ss => arrange m clip ⟨0, 0, 0, 0⟩ s :: arrangeList m clip [] ss
  | r :: rs, s :: ss => arrange m clip r s :: arrangeList m clip rs ss
end

/-- The window as a rect at the origin, sizes floored at zero. -/
def windowRect (w : Size) : Rect := ⟨0, 0, max 0 w.w, max 0 w.h⟩

/-- The root's rect: at the origin, `fill` takes the window's length, otherwise the preferred
length. -/
def rootRect (window : Size) (s : Sized) : Rect :=
  let wr := windowRect window
  let pick (sz : Sizing) (win pref : Int) : Int := if sz.isFill then win else pref
  ⟨0, 0, pick s.sizings.1 wr.w s.size.w, pick s.sizings.2 wr.h s.size.h⟩

/-- Lay out a view in a window. -/
def layout (m : TextMetrics) (window : Size) (n : Node) : Laid :=
  let s := measure m (windowRect window).w n
  arrange m (windowRect window) (rootRect window s) s

end Cairn.Layout

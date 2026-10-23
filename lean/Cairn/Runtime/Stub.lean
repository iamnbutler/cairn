import Cairn.Frame
import Cairn.Spike.Frame

/-! **Stand-ins until other workstreams land. Nothing here is proved or meant to last.**

- `Stub.layout`: a naive layout for runtime tests (B owns real layout, `Cairn.Layout`).
- `Stub.frame`: `Laid` → `Frame`, rects, text and accessibility only (E owns `Frame.ofLaid`).
- `Stub.encode` / `Stub.decode`: the spike's v0 byte formats (E owns the v1 encoding), so the
  spike host can already drive a runtime app: quads, accessibility nodes, and pointer down, up
  and resize events.

The runtime's theorems never mention these; they quantify over the layout function. -/

namespace Cairn.Runtime.Stub

open Cairn

def fieldHeight (m : TextMetrics) (ts : TextStyle) : Int := m.lineHeight ts.font + 8

def mainOf (a : Axis) (s : Size) : Int := if a == .row then s.w else s.h
def crossOf (a : Axis) (s : Size) : Int := if a == .row then s.h else s.w
def mk (a : Axis) (main cross : Int) : Size := if a == .row then ⟨main, cross⟩ else ⟨cross, main⟩

def sized (sz : Sizing) (natural : Int) : Int :=
  match sz with
  | .fixed n => n
  | _ => natural

mutual
/-- Natural size: fixed sizes as given, everything else hugs its content. -/
def measure (m : TextMetrics) : Node → Size
  | .box st _ cs =>
    let kids := measureList m cs
    let gaps : Int := if kids.isEmpty then 0 else st.gap * (kids.length - 1 : Nat)
    let main := if st.axis == .stack then kids.foldl (fun a k => max a (mainOf .column k)) 0
      else kids.foldl (fun a k => a + mainOf st.axis k) 0 + gaps
    let cross := kids.foldl (fun a k => max a (crossOf (if st.axis == .stack then .column else st.axis) k)) 0
    let inner := mk (if st.axis == .stack then .column else st.axis) main cross
    ⟨sized st.width (inner.w + st.padding.left + st.padding.right),
     sized st.height (inner.h + st.padding.top + st.padding.bottom)⟩
  | .text ts s => ⟨m.width ts.font s, m.lineHeight ts.font⟩
  | .field st ts _ _ => ⟨sized st.width 200, sized st.height (fieldHeight m ts)⟩
def measureList (m : TextMetrics) : List Node → List Size
  | [] => []
  | n :: ns => measure m n :: measureList m ns
end

def styleOf : Node → Option Style
  | .box st .. | .field st .. => some st
  | .text .. => none

mutual
def place (m : TextMetrics) (r clip : Rect) : Node → Laid
  | .box st c cs =>
    let inner := r.inset st.padding
    let clip' := if st.clip then clip.inter r else clip
    .box r clip st c (placeList m st inner clip' ⟨inner.x, inner.y⟩ cs)
  | .text ts s => .text r clip (r.y + m.ascent ts.font) ts s
  | .field st ts c v =>
    let o : Point := ⟨r.x + 4, r.y + 4 + m.ascent ts.font⟩
    let offs := m.offsets ts.font v.text
    let cx := o.x + offs.getD v.caret 0
    .field r clip st ts c v o ⟨cx, r.y + 4, 1, m.lineHeight ts.font⟩ []
def placeList (m : TextMetrics) (st : Style) (inner clip : Rect) (at_ : Point) :
    List Node → List Laid
  | [] => []
  | n :: ns =>
    let sz := measure m n
    let ax := if st.axis == .stack then Axis.column else st.axis
    let fillsCross : Bool := match styleOf n with
      | some s => (if ax == .row then s.height else s.width) == .fill
      | none => false
    let cross := if fillsCross then crossOf ax ⟨inner.w, inner.h⟩ else crossOf ax sz
    let sz := mk ax (mainOf ax sz) cross
    let r : Rect := ⟨at_.x, at_.y, sz.w, sz.h⟩
    let next : Point := if st.axis == .stack then at_
      else if st.axis == .row then ⟨at_.x + sz.w + st.gap, at_.y⟩
      else ⟨at_.x, at_.y + sz.h + st.gap⟩
    place m r clip n :: placeList m st inner clip next ns
end

/-- The root fills the window. -/
def layout (m : TextMetrics) (size : Size) (n : Node) : Laid :=
  let win : Rect := ⟨0, 0, size.w, size.h⟩
  place m win win n

mutual
def drawsOf : Laid → List Draw
  | .box r _ st _ cs =>
    (if st.background.isSome || st.border.isSome then [.rect r st.background st.radius st.border]
     else []) ++ drawsList cs
  | .text r _ base ts s => [.text ⟨r.x, base⟩ ts.font ts.color s]
  | .field r _ st ts _ v o _ _ =>
    [.rect r st.background st.radius st.border, .text o ts.font ts.color v.text]
def drawsList : List Laid → List Draw
  | [] => []
  | l :: ls => drawsOf l ++ drawsList ls
end

mutual
def axOf : Laid → List AxNode
  | .box r _ _ (some c) cs => ⟨some c.ref, c.role, r, c.label, c.value, none, false, c.selected, c.checked⟩ :: axList cs
  | .box _ _ _ none cs => axList cs
  | .text r _ _ _ s => [⟨none, .text, r, s, "", none, false, false, none⟩]
  | .field r _ _ _ c v .. => [⟨some c.ref, .textField, r, c.label, v.text, none, v.focused, false, none⟩]
def axList : List Laid → List AxNode
  | [] => []
  | l :: ls => axOf l ++ axList ls
end

def frame (laid : Laid) (size : Size) : Frame :=
  { size, draws := (drawsOf laid).toArray, ax := (axOf laid).toArray }

open Cairn.Spike in
/-- The spike's frame v0: rect draws become quads, accessibility nodes keep their claim id. -/
def encode (f : Frame) : ByteArray := Id.run do
  let quads := f.draws.filterMap fun
    | .rect r fill radius _ => some (r, fill.getD ⟨0, 0, 0, 0⟩, radius)
    | _ => none
  let mut b := ByteArray.mk #[0x43, 0x41, 0x46, 0x52]
  b := pushU16 b 0
  b := pushU16 b 0
  b := pushI32 b f.size.w
  b := pushI32 b f.size.h
  b := pushU32 b quads.size.toUInt32
  b := pushU32 b f.ax.size.toUInt32
  for (r, c, radius) in quads do
    b := pushI32 (pushI32 (pushI32 (pushI32 b r.x) r.y) r.w) r.h
    b := pushU32 b ((c.r.toUInt32 <<< 24) ||| (c.g.toUInt32 <<< 16) ||| (c.b.toUInt32 <<< 8) ||| c.a.toUInt32)
    b := pushU16 b radius.toUInt16
    b := pushU16 b 0
  for a in f.ax do
    b := pushU32 b ((a.control.map fun (c : ControlRef) => c.claim).getD 0).toUInt32
    b := pushU8 b (if a.role == .text then 0 else 1)
    b := pushU8 (pushU8 (pushU8 b 0) 0) 0
    b := pushI32 (pushI32 (pushI32 (pushI32 b a.rect.x) a.rect.y) a.rect.w) a.rect.h
    b := pushStr b a.label
  return b

open Cairn.Spike in
/-- The spike's events v0: `1 x y` pointer down, `2 x y` pointer up, `3 w h` resize. -/
def decode (b : ByteArray) : List Event :=
  (Cairn.Spike.decodeEvents b).map fun
    | .down p => .pointerDown ⟨p.x, p.y⟩ .primary 1 {}
    | .up p => .pointerUp ⟨p.x, p.y⟩ .primary {}
    | .resize w h => .resize ⟨w, h⟩

end Cairn.Runtime.Stub

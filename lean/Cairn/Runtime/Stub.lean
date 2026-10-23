import Cairn.Frame
import Cairn.Spike.Frame

/-! **Stand-ins until other workstreams land. Nothing here is proved or meant to last.**

- `Stub.frame`: `Laid` → `Frame`, rects, text and accessibility only (E owns `Frame.ofLaid`).
- `Stub.encode` / `Stub.decode`: the spike's v0 byte formats (E owns the v1 encoding), so the
  spike host can already drive a runtime app: quads, accessibility nodes, and pointer down, up
  and resize events.

The runtime's theorems never mention these. (The stub layout is gone: `Config.layout` defaults
to `Cairn.Layout.layout`.) -/

namespace Cairn.Runtime.Stub

open Cairn

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

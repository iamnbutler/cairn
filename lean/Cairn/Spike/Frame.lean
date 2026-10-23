module

public import Cairn.Spike.Bytes

/-! The spike's UI core: leaf boxes in a column, a frame of quads and accessibility nodes,
hit testing and encoding. The real UI core replaces this. -/

@[expose] public section


namespace Cairn.Spike

structure Point where
  x : Int
  y : Int
deriving Repr, BEq

structure Rect where
  x : Int
  y : Int
  w : Int
  h : Int
deriving Repr, BEq

def Rect.contains (r : Rect) (p : Point) : Bool :=
  r.x ≤ p.x && p.x < r.x + r.w && r.y ≤ p.y && p.y < r.y + r.h

inductive Role where
  | text | button
deriving Repr, BEq

def Role.code : Role → UInt8
  | .text => 0
  | .button => 1

/-- A leaf in the spike's tree. `claim` is the id of the move this box performs, if any. -/
structure Box where
  w : Int
  h : Int
  color : UInt32
  claim : Option Nat := none
  role : Role := .text
  label : String := ""

/-- Lay boxes out top to bottom from `o`, `gap` apart. -/
def column (o : Point) (gap : Int) : List Box → List (Rect × Box)
  | [] => []
  | b :: bs => (⟨o.x, o.y, b.w, b.h⟩, b) :: column ⟨o.x, o.y + b.h + gap⟩ gap bs

theorem column_boxes (o : Point) (gap : Int) (bs : List Box) :
    (column o gap bs).map (·.2) = bs := by
  induction bs generalizing o with
  | nil => rfl
  | cons b bs ih => simp [column, ih]

/-- The claim ids present in a laid-out frame. -/
def claims (laid : List (Rect × Box)) : List Nat := laid.filterMap (·.2.claim)

theorem claims_column (o : Point) (gap : Int) (bs : List Box) :
    claims (column o gap bs) = bs.filterMap (·.claim) := by
  unfold claims
  rw [← column_boxes o gap bs]
  simp [List.filterMap_map, Function.comp_def]
  rw [column_boxes]

/-- The topmost box with a claim under `p`. Later boxes are drawn on top. -/
def hitTest (laid : List (Rect × Box)) (p : Point) : Option Nat :=
  laid.foldl (fun acc (r, b) => if r.contains p then (b.claim <|> acc) else acc) none

def magic : List UInt8 := [0x43, 0x41, 0x46, 0x52] -- "CAFR", Cairn frame

/-- Frame v0: header, quads, accessibility nodes. See docs/frame.md. -/
def encode (width height : Int) (laid : List (Rect × Box)) : ByteArray := Id.run do
  let mut b := ByteArray.mk magic.toArray
  b := pushU16 b 0
  b := pushU16 b 0
  b := pushI32 b width
  b := pushI32 b height
  b := pushU32 b laid.length.toUInt32
  b := pushU32 b laid.length.toUInt32
  for (r, x) in laid do
    b := pushI32 (pushI32 (pushI32 (pushI32 b r.x) r.y) r.w) r.h
    b := pushU32 b x.color
    b := pushU16 b (if x.role == .button then 8 else 4)
    b := pushU16 b 0
  for (r, x) in laid do
    b := pushU32 b (x.claim.getD 0).toUInt32
    b := pushU8 b x.role.code
    b := pushU8 (pushU8 (pushU8 b 0) 0) 0
    b := pushI32 (pushI32 (pushI32 (pushI32 b r.x) r.y) r.w) r.h
    b := pushStr b x.label
  return b

/-- Events v0: `1 x y` pointer down, `2 x y` pointer up, `3 w h` resize, all i32. -/
inductive Event where
  | down (p : Point)
  | up (p : Point)
  | resize (w h : Int)

def decodeEvents (b : ByteArray) : List Event := go b.size 0
where
  go : Nat → Nat → List Event
    | 0, _ => []
    | fuel + 1, i =>
      if i + 9 > b.size then [] else
      let a := getI32 b (i + 1)
      let c := getI32 b (i + 5)
      let rest := go fuel (i + 9)
      match b.get! i with
      | 1 => .down ⟨a, c⟩ :: rest
      | 2 => .up ⟨a, c⟩ :: rest
      | 3 => .resize a c :: rest
      | _ => rest

end Cairn.Spike

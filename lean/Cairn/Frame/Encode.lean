module

public import Cairn.Frame
public import Cairn.Frame.Bytes

/-! Frame byte format v1 (docs/frame.md): specification encoder `Wire.Enc.frame`, decoder
`Wire.Dec.frame`, the executable encoder `encodeFrame` (proved equal to the specification and
installed with `@[csimp]`), and the round trip `decodeFrame_encodeFrame`.

Layout, all little-endian:

```
header     "CAFR" u16 version=1 u16 flags=0 i32 w i32 h                       16 bytes
draws      u32 count u32 byteLength, then count records
ax         u32 count u32 byteLength, then count records
textInput  4 bytes [present, hasMarked, 0, 0], then the rest of the record when present
cursor     4 bytes [cursor, 0, 0, 0]
effects    u32 count u32 byteLength, then count records
```

Records start with a 4-byte head whose first byte is the tag, followed by fixed-size fields and
at most two strings, each `u32` byte length + UTF-8. -/

@[expose] public section

namespace Cairn.Wire

/-! ## Codes -/

def Role.code : Role → UInt8
  | .group => 0 | .button => 1 | .checkbox => 2 | .text => 3 | .textField => 4
  | .link => 5 | .list => 6 | .listItem => 7 | .heading => 8 | .tab => 9

def Role.ofCode : UInt8 → Option Role
  | 0 => some .group | 1 => some .button | 2 => some .checkbox | 3 => some .text
  | 4 => some .textField | 5 => some .link | 6 => some .list | 7 => some .listItem
  | 8 => some .heading | 9 => some .tab | _ => none

@[simp] theorem Role.ofCode_code (r : Role) : Role.ofCode (Role.code r) = some r := by
  cases r <;> rfl

def Cursor.code : Cursor → UInt8
  | .arrow => 0 | .pointer => 1 | .text => 2

def Cursor.ofCode : UInt8 → Option Cursor
  | 0 => some .arrow | 1 => some .pointer | 2 => some .text | _ => none

@[simp] theorem Cursor.ofCode_code (c : Cursor) : Cursor.ofCode (Cursor.code c) = some c := by
  cases c <;> rfl

def checkedCode : Option Bool → UInt8
  | none => 0 | some false => 1 | some true => 2

def checkedOfCode : UInt8 → Option (Option Bool)
  | 0 => some none | 1 => some (some false) | 2 => some (some true) | _ => none

@[simp] theorem checkedOfCode_code (c : Option Bool) : checkedOfCode (checkedCode c) = some c := by
  rcases c with _ | _ | _ <;> rfl

/-! ## What fits

The round trip holds for frames whose integers fit the wire's 32-bit fields and whose strings
are shorter than 4 GiB. These are checks, not conventions: `fitsFrame` is executable. -/

def fu (n : Nat) : Bool := decide (FitsU32 n)
def fi (v : Int) : Bool := decide (FitsI32 v)
def fs (s : String) : Bool := decide (FitsStr s)

@[simp] theorem fu_iff (n : Nat) : fu n = true ↔ FitsU32 n := by simp only [fu, decide_eq_true_eq]
@[simp] theorem fi_iff (v : Int) : fi v = true ↔ FitsI32 v := by simp only [fi, decide_eq_true_eq]
@[simp] theorem fs_iff (s : String) : fs s = true ↔ FitsStr s := by simp only [fs,
    decide_eq_true_eq]

def fitsRect (r : Rect) : Bool := fi r.x && fi r.y && fi r.w && fi r.h
def fitsRef (c : ControlRef) : Bool := fu c.claim && fu c.key
def fitsRange (p : Nat × Nat) : Bool := fu p.1 && fu p.2

@[simp] theorem fitsRef_zero : fitsRef ⟨0, 0⟩ = true := by simp only [fitsRef, Bool.and_self,
    fu_iff, fitsU32_zero]
@[simp] theorem fitsRange_zero : fitsRange (0, 0) = true := by simp only [fitsRange, Bool.and_self,
    fu_iff, fitsU32_zero]

/-- Font fields are clamped, not wrapped, so out-of-range fonts still name the font layout
measured with (`Cairn.Text.Host.sat`); the round trip is exact when they fit. -/
def fitsDraw : Draw → Bool
  | .rect r _ radius border => fitsRect r && fu radius && (border.all fun b => fu b.width)
  | .text o font _ s =>
    fi o.x && fi o.y && fu font.family && fu font.size && fu font.weight && fs s
  | .pushClip r => fitsRect r
  | .popClip => true

def fitsAx (n : AxNode) : Bool :=
  n.control.all fitsRef && n.parent.all fu && fitsRect n.rect && fs n.label && fs n.value

def fitsTextInput (t : TextInput) : Bool :=
  fitsRef t.control && fitsRect t.rect && fitsRect t.caret && fitsRange t.selection &&
    t.marked.all fitsRange && fi t.textOrigin.x && fi t.textOrigin.y && fs t.text

def fitsEffect : Effect → Bool
  | .setClipboard s => fs s
  | .beep => true
  | .focus c => fitsRef c

/-- Every value fits its field. The other condition of the round trip is that the encoding is
under 4 GiB (each section's byte length is a `u32`). -/
def fitsFrame (f : Frame) : Bool :=
  fi f.size.w && fi f.size.h &&
    fu f.draws.size && f.draws.all fitsDraw &&
    fu f.ax.size && f.ax.all fitsAx &&
    f.textInput.all fitsTextInput &&
    fu f.effects.size && f.effects.all fitsEffect

/-! ## Encoding (specification) -/

namespace Enc

def rect (r : Rect) : List UInt8 := i32 r.x ++ i32 r.y ++ i32 r.w ++ i32 r.h
def point (p : Point) : List UInt8 := i32 p.x ++ i32 p.y
def size (s : Size) : List UInt8 := i32 s.w ++ i32 s.h
def color (c : Color) : List UInt8 := [c.r, c.g, c.b, c.a]
def ref (c : ControlRef) : List UInt8 := u32 c.claim ++ u32 c.key
def range (p : Nat × Nat) : List UInt8 := u32 p.1 ++ u32 p.2

def noColor : Color := ⟨0, 0, 0, 0⟩

/-- A list: `u32` count, then the records as a sized section. -/
def list {α : Type} (e : α → List UInt8) (xs : List α) : List UInt8 :=
  u32 xs.length ++ sect (xs.flatMap e)

def draw : Draw → List UInt8
  | .rect r fill radius border =>
    [0] ++ bool fill.isSome ++ bool border.isSome ++ pad 1 ++ rect r ++
      color (fill.getD noColor) ++ u32 radius ++
      u32 (border.elim 0 (·.width)) ++ color (border.elim noColor (·.color))
  | .text o font c s =>
    [1] ++ bool font.italic ++ pad 2 ++ point o ++
      u32 (satU32 font.family) ++ u32 (satU32 font.size) ++ u32 (satU32 font.weight) ++
      color c ++ str s
  | .pushClip r => [2] ++ pad 3 ++ rect r
  | .popClip => [3] ++ pad 3

def ax (n : AxNode) : List UInt8 :=
  [Role.code n.role] ++ bool n.focused ++ bool n.selected ++ [checkedCode n.checked] ++
    bool n.control.isSome ++ bool n.parent.isSome ++ pad 2 ++
    ref (n.control.getD ⟨0, 0⟩) ++ u32 (n.parent.getD 0) ++ rect n.rect ++
    str n.label ++ str n.value

def textInput : Option TextInput → List UInt8
  | none => [0] ++ pad 3
  | some t =>
    [1] ++ bool t.marked.isSome ++ pad 2 ++ ref t.control ++ rect t.rect ++ rect t.caret ++
      range t.selection ++ range (t.marked.getD (0, 0)) ++ point t.textOrigin ++ str t.text

def cursor (c : Cursor) : List UInt8 := [Cursor.code c] ++ pad 3

def effect : Effect → List UInt8
  | .setClipboard s => [0] ++ pad 3 ++ str s
  | .beep => [1] ++ pad 3
  | .focus c => [2] ++ pad 3 ++ ref c

def magic : List UInt8 := [0x43, 0x41, 0x46, 0x52] -- "CAFR"

/-- Magic, version 1, flags 0. -/
def header : List UInt8 := magic ++ [1, 0, 0, 0]

def frame (f : Frame) : List UInt8 :=
  header ++ size f.size ++ list draw f.draws.toList ++ list ax f.ax.toList ++
    textInput f.textInput ++ cursor f.cursor ++ list effect f.effects.toList

end Enc

/-! ## Decoding -/

namespace Dec

def expect (bs : List UInt8) : Dec Unit := fun l =>
  if l.take bs.length = bs then some ((), l.drop bs.length) else none

def rect : Dec Rect := do return ⟨← i32, ← i32, ← i32, ← i32⟩
def point : Dec Point := do return ⟨← i32, ← i32⟩
def size : Dec Size := do return ⟨← i32, ← i32⟩
def color : Dec Color := do return ⟨← byte, ← byte, ← byte, ← byte⟩
def ref : Dec ControlRef := do return ⟨← u32, ← u32⟩
def range : Dec (Nat × Nat) := do return (← u32, ← u32)

def list {α : Type} (d : Dec α) : Dec (List α) := do
  let n ← u32
  sect (count d n)

def draw : Dec Draw := do
  match (← byte) with
  | 0 =>
    let hasFill ← bool
    let hasBorder ← bool
    skip 1
    let r ← rect
    let fill ← color
    let radius ← u32
    let bw ← u32
    let bc ← color
    return .rect r (if hasFill then some fill else none) radius
      (if hasBorder then some ⟨bw, bc⟩ else none)
  | 1 =>
    let italic ← bool
    skip 2
    let o ← point
    let family ← u32
    let sz ← u32
    let weight ← u32
    let c ← color
    let s ← str
    return .text o ⟨family, sz, weight, italic⟩ c s
  | 2 =>
    skip 3
    return .pushClip (← rect)
  | 3 =>
    skip 3
    return .popClip
  | _ => fail

def ax : Dec AxNode := do
  let some role := Role.ofCode (← byte) | fail
  let focused ← bool
  let selected ← bool
  let some checked := checkedOfCode (← byte) | fail
  let hasControl ← bool
  let hasParent ← bool
  skip 2
  let c ← ref
  let parent ← u32
  let r ← rect
  let label ← str
  let value ← str
  return { control := if hasControl then some c else none, role, rect := r, label, value,
           parent := if hasParent then some parent else none, focused, selected, checked }

def textInput : Dec (Option TextInput) := do
  match (← byte) with
  | 0 =>
    skip 3
    return none
  | 1 =>
    let hasMarked ← bool
    skip 2
    let control ← ref
    let r ← rect
    let caret ← rect
    let selection ← range
    let marked ← range
    let textOrigin ← point
    let text ← str
    return some { control, rect := r, caret, text, selection, textOrigin,
                  marked := if hasMarked then some marked else none }
  | _ => fail

def cursor : Dec Cursor := do
  let some c := Cursor.ofCode (← byte) | fail
  skip 3
  return c

def effect : Dec Effect := do
  match (← byte) with
  | 0 =>
    skip 3
    return .setClipboard (← str)
  | 1 =>
    skip 3
    return .beep
  | 2 =>
    skip 3
    return .focus (← ref)
  | _ => fail

def frame : Dec Frame := do
  expect Enc.header
  let sz ← size
  let draws ← list draw
  let ax ← list ax
  let textInput ← textInput
  let cursor ← cursor
  let effects ← list effect
  return { size := sz, draws := draws.toArray, ax := ax.toArray, textInput, cursor,
           effects := effects.toArray }

/-! ### Round trips -/

theorem expect_enc (bs r : List UInt8) : expect bs (bs ++ r) = some ((), r) := by
  simp only [expect, List.take_left', ↓reduceIte, List.drop_left']

theorem rect_enc {x : Rect} (h : fitsRect x = true) (r : List UInt8) :
    rect (Enc.rect x ++ r) = some (x, r) := by
  simp only [fitsRect, Bool.and_eq_true, fi_iff] at h
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
  simp only [rect, Enc.rect, List.append_assoc, bind_apply, i32_enc, pure_apply, h1, h2, h3, h4]

theorem point_enc {p : Point} (h1 : FitsI32 p.x) (h2 : FitsI32 p.y) (r : List UInt8) :
    point (Enc.point p ++ r) = some (p, r) := by
  simp only [point, Enc.point, List.append_assoc, bind_apply, i32_enc, pure_apply, h1, h2]

theorem size_enc {s : Size} (h1 : FitsI32 s.w) (h2 : FitsI32 s.h) (r : List UInt8) :
    size (Enc.size s ++ r) = some (s, r) := by
  simp only [size, Enc.size, List.append_assoc, bind_apply, i32_enc, pure_apply, h1, h2]

theorem color_enc (c : Color) (r : List UInt8) : color (Enc.color c ++ r) = some (c, r) := by
  simp only [color, Enc.color, List.cons_append, List.nil_append, bind_apply, byte_cons, pure_apply]

theorem ref_enc {c : ControlRef} (h : fitsRef c = true) (r : List UInt8) :
    ref (Enc.ref c ++ r) = some (c, r) := by
  simp only [fitsRef, Bool.and_eq_true, fu_iff] at h
  simp only [ref, Enc.ref, List.append_assoc, bind_apply, u32_enc, pure_apply, h]

theorem range_enc {p : Nat × Nat} (h : fitsRange p = true) (r : List UInt8) :
    range (Enc.range p ++ r) = some (p, r) := by
  simp only [fitsRange, Bool.and_eq_true, fu_iff] at h
  simp only [range, Enc.range, List.append_assoc, bind_apply, u32_enc, pure_apply, h]

theorem list_enc {α : Type} {d : Dec α} {e : α → List UInt8} (xs : List α)
    (h : ∀ x ∈ xs, ∀ r, d (e x ++ r) = some (x, r))
    (hn : FitsU32 xs.length) (hb : FitsU32 (xs.flatMap e).length) (r : List UInt8) :
    list d (Enc.list e xs ++ r) = some (xs, r) := by
  simp only [list, Enc.list, List.append_assoc, bind_apply, u32_enc hn]
  exact sect_enc (by simpa using count_enc xs h []) hb r

theorem draw_enc {x : Draw} (h : fitsDraw x = true) (r : List UInt8) :
    draw (Enc.draw x ++ r) = some (x, r) := by
  cases x with
  | rect rc fill radius border =>
    simp only [fitsDraw, Bool.and_eq_true, fu_iff] at h
    obtain ⟨⟨hr, hrad⟩, hb⟩ := h
    cases fill <;> cases border <;>
      simp_all only [Option.all_none, draw, Enc.draw, Option.isSome_none, List.cons_append,
          List.nil_append, List.append_assoc, Option.getD_none, Option.elim_none, bind_apply,
          byte_cons, bool_enc, Bool.false_eq_true, ↓reduceIte, skip_pad, rect_enc, color_enc,
          u32_enc, fitsU32_zero, pure_apply, Option.all_some, fu_iff, Option.isSome_some,
          Option.elim_some, Option.getD_some]
  | text o font c s =>
    simp only [fitsDraw, Bool.and_eq_true, fu_iff, fi_iff, fs_iff] at h
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, List.append_assoc, h,
        satU32_of_fits, bind_apply, byte_cons, bool_enc, skip_pad, point_enc, u32_enc, color_enc,
        str_enc, pure_apply]
  | pushClip rc =>
    simp only [fitsDraw] at h
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, h, rect_enc, pure_apply]
  | popClip =>
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, bind_apply, byte_cons, skip_pad,
        pure_apply]

theorem ax_enc {x : AxNode} (h : fitsAx x = true) (r : List UInt8) :
    ax (Enc.ax x ++ r) = some (x, r) := by
  obtain ⟨control, role, rc, label, value, parent, focused, selected, checked⟩ := x
  simp only [fitsAx, Bool.and_eq_true, fs_iff] at h
  obtain ⟨⟨⟨⟨hc, hp⟩, hr⟩, hl⟩, hv⟩ := h
  cases control <;> cases parent <;>
    simp_all only [Option.all_none, ax, Enc.ax, List.cons_append, List.nil_append,
        List.append_assoc, Option.isSome_none, Option.getD_none, bind_apply, byte_cons,
        Role.ofCode_code, bool_enc, checkedOfCode_code, Bool.false_eq_true, ↓reduceIte, skip_pad,
        fitsRef_zero, ref_enc, fitsU32_zero, u32_enc, rect_enc, str_enc, pure_apply,
        Option.all_some, fu_iff, Option.isSome_some, Option.getD_some]

theorem textInput_enc {x : Option TextInput} (h : x.all fitsTextInput = true) (r : List UInt8) :
    textInput (Enc.textInput x ++ r) = some (x, r) := by
  cases x with
  | none => simp only [textInput, Enc.textInput, List.cons_append, List.nil_append, bind_apply,
      byte_cons, skip_pad, pure_apply]
  | some t =>
    obtain ⟨control, rc, caret, text, selection, marked, origin⟩ := t
    simp only [Option.all_some, fitsTextInput, Bool.and_eq_true, fs_iff, fi_iff] at h
    obtain ⟨⟨⟨⟨⟨⟨⟨hc, hr⟩, hk⟩, hs⟩, hm⟩, hx⟩, hy⟩, ht⟩ := h
    cases marked <;>
      simp_all only [Option.all_none, textInput, Enc.textInput, Option.isSome_none,
          List.cons_append, List.nil_append, List.append_assoc, Option.getD_none, bind_apply,
          byte_cons, bool_enc, Bool.false_eq_true, ↓reduceIte, skip_pad, ref_enc, rect_enc,
          range_enc, fitsRange_zero, point_enc, str_enc, pure_apply, Option.all_some,
          Option.isSome_some, Option.getD_some]

theorem cursor_enc (c : Cursor) (r : List UInt8) : cursor (Enc.cursor c ++ r) = some (c, r) := by
  simp only [cursor, Enc.cursor, List.cons_append, List.nil_append, bind_apply, byte_cons,
      Cursor.ofCode_code, skip_pad, pure_apply]

theorem effect_enc {x : Effect} (h : fitsEffect x = true) (r : List UInt8) :
    effect (Enc.effect x ++ r) = some (x, r) := by
  cases x with
  | setClipboard s =>
    simp only [fitsEffect, fs_iff] at h
    simp only [effect, Enc.effect, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, h, str_enc, pure_apply]
  | beep => simp only [effect, Enc.effect, List.cons_append, List.nil_append, bind_apply, byte_cons,
      skip_pad, pure_apply]
  | focus c =>
    simp only [fitsEffect] at h
    simp only [effect, Enc.effect, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, ref_enc h, pure_apply]

/-- Sections of a frame whose encoding is under 4 GiB have `u32` byte lengths. -/
def SizeOk (f : Frame) : Prop := (Enc.frame f).length < 4294967296

theorem frame_enc {f : Frame} (h : fitsFrame f = true) (hs : SizeOk f) (r : List UInt8) :
    frame (Enc.frame f ++ r) = some (f, r) := by
  obtain ⟨sz, draws, axs, ti, cur, effs⟩ := f
  simp only [fitsFrame, Bool.and_eq_true, fi_iff, fu_iff, Array.all_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨⟨hw, hh⟩, hdn⟩, hd⟩, han⟩, ha⟩, ht⟩, hen⟩, he⟩ := h
  simp only [SizeOk, Enc.frame, Enc.list, Enc.sect, List.length_append, Enc.length_u32] at hs
  simp only [frame, Enc.frame, List.append_assoc, bind_apply, expect_enc]
  rw [size_enc hw hh]; dsimp only
  rw [list_enc (e := Enc.draw) _ (fun x hx => draw_enc (hd x (by simpa using hx))) (by simpa using hdn)
    (by unfold FitsU32; omega)]; dsimp only
  rw [list_enc (e := Enc.ax) _ (fun x hx => ax_enc (ha x (by simpa using hx))) (by simpa using han)
    (by unfold FitsU32; omega)]; dsimp only
  rw [textInput_enc ht]; dsimp only
  rw [cursor_enc]; dsimp only
  rw [list_enc (e := Enc.effect) _ (fun x hx => effect_enc (he x (by simpa using hx))) (by simpa using hen)
    (by unfold FitsU32; omega)]
  simp only [Array.toArray_toList, pure_apply]

end Dec

/-! ## Executable encoder

`Put.*` writes the same bytes as `Enc.*` straight into a `ByteArray`. Section byte lengths are
computed up front by `Len.*` (proved equal to the encoded lengths), so nothing is copied or
patched afterwards. -/

namespace Len

def str (s : String) : Nat := 4 + s.toUTF8.size

def draw : Draw → Nat
  | .rect .. => 36
  | .text _ _ _ s => 28 + str s
  | .pushClip _ => 20
  | .popClip => 4

def ax (n : AxNode) : Nat := 36 + str n.label + str n.value

def effect : Effect → Nat
  | .setClipboard s => 4 + str s
  | .beep => 4
  | .focus _ => 12

def textInput : Option TextInput → Nat
  | none => 4
  | some t => 68 + str t.text

def list {α : Type} (len : α → Nat) (xs : Array α) : Nat := xs.foldl (fun n x => n + len x) 0

theorem str_eq (s : String) : str s = (Enc.str s).length := by
  simp only [str, String.toUTF8_eq_toByteArray, String.size_toByteArray, Enc.str,
      List.length_append, Enc.length_u32, Array.length_toList, ByteArray.size_data]; all_goals omega

theorem draw_eq (d : Draw) : draw d = (Enc.draw d).length := by
  cases d <;> simp only [draw, Enc.draw, Enc.bool, List.cons_append, List.nil_append, Enc.pad,
      List.replicate_one, Enc.rect, List.append_assoc, Enc.color, List.length_cons,
      List.length_append, Enc.length_i32, Enc.length_u32, List.length_nil, Nat.zero_add,
      Nat.reduceAdd, str_eq, Enc.str, String.toUTF8_eq_toByteArray, String.size_toByteArray,
      Array.length_toList, ByteArray.size_data, List.reduceReplicate, Enc.point] <;> all_goals omega

theorem ax_eq (n : AxNode) : ax n = (Enc.ax n).length := by
  simp only [ax, str_eq, Enc.str, String.toUTF8_eq_toByteArray, String.size_toByteArray,
      List.length_append, Enc.length_u32, Array.length_toList, ByteArray.size_data, Enc.ax,
      Enc.bool, List.cons_append, List.nil_append, Enc.pad, List.reduceReplicate, Enc.ref,
      List.append_assoc, Enc.rect, List.length_cons, Enc.length_i32]; all_goals omega

theorem effect_eq (e : Effect) : effect e = (Enc.effect e).length := by
  cases e <;> simp only [effect, str_eq, Enc.str, String.toUTF8_eq_toByteArray,
      String.size_toByteArray, List.length_append, Enc.length_u32, Array.length_toList,
      ByteArray.size_data, Enc.effect, Enc.pad, List.reduceReplicate, List.cons_append,
      List.nil_append, List.length_cons, List.length_nil, Nat.zero_add,
      Nat.reduceAdd, Enc.ref] <;> all_goals omega

theorem textInput_eq (t : Option TextInput) : textInput t = (Enc.textInput t).length := by
  cases t <;> simp only [textInput, Enc.textInput, Enc.pad, List.reduceReplicate, List.cons_append,
      List.nil_append, List.length_cons, List.length_nil, Nat.zero_add, Nat.reduceAdd, str_eq,
      Enc.str, String.toUTF8_eq_toByteArray, String.size_toByteArray, List.length_append,
      Enc.length_u32, Array.length_toList, ByteArray.size_data, Enc.bool, Enc.ref, Enc.rect,
      List.append_assoc, Enc.range, Enc.point, Enc.length_i32] <;> all_goals omega

theorem foldl_add {α : Type} (len : α → Nat) (xs : List α) (n : Nat) :
    xs.foldl (fun n x => n + len x) n = n + (xs.map len).sum := by
  induction xs generalizing n with
  | nil => simp only [List.foldl_nil, List.map_nil, List.sum_nil, Nat.add_zero]
  | cons x xs ih => simp only [List.foldl_cons, ih, List.map_cons, List.sum_cons]; omega

theorem list_eq {α : Type} (len : α → Nat) (e : α → List UInt8) (h : ∀ x, len x = (e x).length)
    (xs : Array α) : list len xs = (xs.toList.flatMap e).length := by
  rw [list, ← Array.foldl_toList, foldl_add]
  induction xs.toList with
  | nil => simp only [List.map_nil, List.sum_nil, Nat.add_zero, List.flatMap_nil, List.length_nil]
  | cons x xs ih => simp_all only [Nat.zero_add, List.length_flatMap, List.map_cons, List.sum_cons,
      List.flatMap_cons, List.length_append]

end Len

namespace Put

def rect (b : ByteArray) (r : Rect) : ByteArray := i32 (i32 (i32 (i32 b r.x) r.y) r.w) r.h
def point (b : ByteArray) (p : Point) : ByteArray := i32 (i32 b p.x) p.y
def color (b : ByteArray) (c : Color) : ByteArray := (((b.push c.r).push c.g).push c.b).push c.a
def ref (b : ByteArray) (c : ControlRef) : ByteArray := u32 (u32 b c.claim) c.key
def range (b : ByteArray) (p : Nat × Nat) : ByteArray := u32 (u32 b p.1) p.2

def draw (b : ByteArray) : Draw → ByteArray
  | .rect r fill radius border =>
    let b := pad (bool (bool (b.push 0) fill.isSome) border.isSome) 1
    color (u32 (u32 (color (rect b r) (fill.getD Enc.noColor)) radius)
      (border.elim 0 (·.width))) (border.elim Enc.noColor (·.color))
  | .text o font c s =>
    let b := point (pad (bool (b.push 1) font.italic) 2) o
    str (color (u32 (u32 (u32 b (satU32 font.family)) (satU32 font.size))
      (satU32 font.weight)) c) s
  | .pushClip r => rect (pad (b.push 2) 3) r
  | .popClip => pad (b.push 3) 3

def ax (b : ByteArray) (n : AxNode) : ByteArray :=
  let b := bool (bool (b.push (Role.code n.role)) n.focused) n.selected
  let b := pad (bool (bool (b.push (checkedCode n.checked)) n.control.isSome) n.parent.isSome) 2
  let b := rect (u32 (ref b (n.control.getD ⟨0, 0⟩)) (n.parent.getD 0)) n.rect
  str (str b n.label) n.value

def textInput (b : ByteArray) : Option TextInput → ByteArray
  | none => pad (b.push 0) 3
  | some t =>
    let b := ref (pad (bool (b.push 1) t.marked.isSome) 2) t.control
    let b := range (range (rect (rect b t.rect) t.caret) t.selection) (t.marked.getD (0, 0))
    str (point b t.textOrigin) t.text

def cursor (b : ByteArray) (c : Cursor) : ByteArray := pad (b.push (Cursor.code c)) 3

def effect (b : ByteArray) : Effect → ByteArray
  | .setClipboard s => str (pad (b.push 0) 3) s
  | .beep => pad (b.push 1) 3
  | .focus c => ref (pad (b.push 2) 3) c

def list {α : Type} (put : ByteArray → α → ByteArray) (len : α → Nat) (b : ByteArray)
    (xs : Array α) : ByteArray :=
  xs.foldl put (u32 (u32 b xs.size) (Len.list len xs))

def frame (f : Frame) : ByteArray :=
  let cap := 40 + Len.list Len.draw f.draws + Len.list Len.ax f.ax +
    Len.textInput f.textInput + Len.list Len.effect f.effects
  let b := (ByteArray.emptyWithCapacity cap).append ⟨Enc.header.toArray⟩
  let b := list draw Len.draw (i32 (i32 b f.size.w) f.size.h) f.draws
  let b := list ax Len.ax b f.ax
  let b := cursor (textInput b f.textInput) f.cursor
  list effect Len.effect b f.effects

@[simp] theorem rect_data (b : ByteArray) (r : Rect) :
    (rect b r).data.toList = b.data.toList ++ Enc.rect r := by simp only [rect, i32_data,
        List.append_assoc, Enc.rect]
@[simp] theorem point_data (b : ByteArray) (p : Point) :
    (point b p).data.toList = b.data.toList ++ Enc.point p := by simp only [point, i32_data,
        List.append_assoc, Enc.point]
@[simp] theorem color_data (b : ByteArray) (c : Color) :
    (color b c).data.toList = b.data.toList ++ Enc.color c := by simp only [color,
        ByteArray.data_push, Array.toList_push, List.append_assoc, List.cons_append,
        List.nil_append, Enc.color]
@[simp] theorem ref_data (b : ByteArray) (c : ControlRef) :
    (ref b c).data.toList = b.data.toList ++ Enc.ref c := by simp only [ref, u32_data,
        List.append_assoc, Enc.ref]
@[simp] theorem range_data (b : ByteArray) (p : Nat × Nat) :
    (range b p).data.toList = b.data.toList ++ Enc.range p := by simp only [range, u32_data,
        List.append_assoc, Enc.range]

@[simp] theorem draw_data (b : ByteArray) (d : Draw) :
    (draw b d).data.toList = b.data.toList ++ Enc.draw d := by
  cases d <;> simp only [draw, color_data, u32_data, rect_data, pad_data, bool_data,
      ByteArray.data_push, Array.toList_push, List.append_assoc, List.cons_append, List.nil_append,
      Enc.draw, str_data, point_data]

@[simp] theorem ax_data (b : ByteArray) (n : AxNode) :
    (ax b n).data.toList = b.data.toList ++ Enc.ax n := by
  simp only [ax, str_data, rect_data, u32_data, ref_data, pad_data, bool_data, ByteArray.data_push,
      Array.toList_push, List.append_assoc, List.cons_append, List.nil_append, Enc.ax]

@[simp] theorem textInput_data (b : ByteArray) (t : Option TextInput) :
    (textInput b t).data.toList = b.data.toList ++ Enc.textInput t := by
  cases t <;> simp only [textInput, pad_data, ByteArray.data_push, Array.toList_push,
      List.append_assoc, List.cons_append, List.nil_append, Enc.textInput, str_data, point_data,
      range_data, rect_data, ref_data, bool_data]

@[simp] theorem cursor_data (b : ByteArray) (c : Cursor) :
    (cursor b c).data.toList = b.data.toList ++ Enc.cursor c := by
  simp only [cursor, pad_data, ByteArray.data_push, Array.toList_push, List.append_assoc,
      List.cons_append, List.nil_append, Enc.cursor]

@[simp] theorem effect_data (b : ByteArray) (e : Effect) :
    (effect b e).data.toList = b.data.toList ++ Enc.effect e := by
  cases e <;> simp only [effect, str_data, pad_data, ByteArray.data_push, Array.toList_push,
      List.append_assoc, List.cons_append, List.nil_append, Enc.effect, ref_data]

theorem foldl_data {α : Type} (put : ByteArray → α → ByteArray) (e : α → List UInt8)
    (h : ∀ b x, (put b x).data.toList = b.data.toList ++ e x) (xs : List α) (b : ByteArray) :
    (xs.foldl put b).data.toList = b.data.toList ++ xs.flatMap e := by
  induction xs generalizing b with
  | nil => simp only [List.foldl_nil, List.flatMap_nil, List.append_nil]
  | cons x xs ih => simp only [List.foldl_cons, ih, h, List.append_assoc, List.flatMap_cons]

theorem list_data {α : Type} (put : ByteArray → α → ByteArray) (len : α → Nat)
    (e : α → List UInt8) (h : ∀ b x, (put b x).data.toList = b.data.toList ++ e x)
    (hl : ∀ x, len x = (e x).length) (b : ByteArray) (xs : Array α) :
    (list put len b xs).data.toList = b.data.toList ++ Enc.list e xs.toList := by
  rw [list, ← Array.foldl_toList, foldl_data put e h]
  simp only [Len.list_eq len e hl, List.length_flatMap, u32_data, List.append_assoc, Enc.list,
      Array.length_toList, Enc.sect]

theorem frame_data (f : Frame) : (frame f).data.toList = Enc.frame f := by
  have hempty : (ByteArray.emptyWithCapacity 0).data.toList = [] := rfl
  simp only [frame, Enc.frame]
  rw [list_data _ _ _ effect_data Len.effect_eq, cursor_data, textInput_data,
    list_data _ _ _ ax_data Len.ax_eq, list_data _ _ _ draw_data Len.draw_eq]
  simp only [ByteArray.append_eq, i32_data, ByteArray.data_append, Array.toList_append,
      List.append_assoc, Enc.size, List.append_left_eq_self, Array.toList_eq_nil_iff]
  rfl

end Put

end Cairn.Wire

namespace Cairn

open Wire

/-- The frame's bytes (docs/frame.md). Defined by the specification; compiled as `Put.frame`. -/
def encodeFrame (f : Frame) : ByteArray := ⟨(Enc.frame f).toArray⟩

def decodeFrame (b : ByteArray) : Option Frame := Dec.run Dec.frame b.data.toList

@[csimp] theorem encodeFrame_eq_put : @encodeFrame = @Put.frame := by
  funext f
  apply ByteArray.ext
  simp only [encodeFrame, ← Put.frame_data f, Array.toArray_toList]

/-- **Round trip.** Every frame whose values fit the wire's fields (`fitsFrame`, executable)
and whose encoding is under 4 GiB decodes to itself. -/
theorem decodeFrame_encodeFrame (f : Frame) (h : fitsFrame f = true)
    (hs : (encodeFrame f).size < 4294967296) : decodeFrame (encodeFrame f) = some f := by
  have hs' : Dec.SizeOk f := by simpa [encodeFrame, ByteArray.size, Dec.SizeOk] using hs
  simp only [decodeFrame, encodeFrame]
  exact Dec.run_enc (Dec.frame_enc h hs' [])

end Cairn

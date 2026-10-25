module

public import Cairn.Frame
public import Cairn.Frame.Bytes

/-! Frame byte format (docs/frame.md; version 5): specification encoder `Wire.Enc.frame`, decoder
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

def FontWidth.wire : FontWidth → UInt8
  | .standard => 0 | .condensed => 1 | .expanded => 2 | .compressed => 3

def FontWidth.ofWire : UInt8 → Option FontWidth
  | 0 => some .standard | 1 => some .condensed | 2 => some .expanded | 3 => some .compressed
  | _ => none

@[simp] theorem FontWidth.ofWire_wire (w : FontWidth) : FontWidth.ofWire (FontWidth.wire w) = some w := by
  cases w <;> rfl

def Corner.code : Corner → UInt8
  | .circular => 0 | .continuous => 1

def Corner.ofCode : UInt8 → Option Corner
  | 0 => some .circular | 1 => some .continuous | _ => none

@[simp] theorem Corner.ofCode_code (c : Corner) : Corner.ofCode (Corner.code c) = some c := by
  cases c <;> rfl

def checkedCode : Option Bool → UInt8
  | none => 0 | some false => 1 | some true => 2

def checkedOfCode : UInt8 → Option (Option Bool)
  | 0 => some none | 1 => some (some false) | 2 => some (some true) | _ => none

@[simp] theorem checkedOfCode_code (c : Option Bool) : checkedOfCode (checkedCode c) = some c := by
  rcases c with _ | _ | _ <;> rfl

def Request.Kind.code : Request.Kind → UInt8
  | .readFile => 0 | .writeFile => 1 | .playSound => 2 | .http => 3
  | .appendFile => 4 | .listDir => 5 | .deleteFile => 6 | .frontmostApp => 7 | .permission => 8
  | .typeText => 9 | .upload => 10 | .forgetClip => 11
  | .openItem => 12 | .appRunning => 13 | .readDefault => 14 | .makeDir => 15
  | .loadImage => 16

def Request.Kind.ofCode : UInt8 → Option Request.Kind
  | 0 => some .readFile | 1 => some .writeFile | 2 => some .playSound | 3 => some .http
  | 4 => some .appendFile | 5 => some .listDir | 6 => some .deleteFile | 7 => some .frontmostApp
  | 8 => some .permission | 9 => some .typeText | 10 => some .upload | 11 => some .forgetClip
  | 12 => some .openItem | 13 => some .appRunning | 14 => some .readDefault | 15 => some .makeDir
  | 16 => some .loadImage
  | _ => none

@[simp] theorem Request.Kind.ofCode_code (k : Request.Kind) :
    Request.Kind.ofCode (Request.Kind.code k) = some k := by
  cases k <;> rfl

def Permission.code : Permission → UInt8
  | .accessibility => 0 | .microphone => 1

def Permission.ofCode : UInt8 → Option Permission
  | 0 => some .accessibility | 1 => some .microphone | _ => none

@[simp] theorem Permission.ofCode_code (p : Permission) :
    Permission.ofCode (Permission.code p) = some p := by
  cases p <;> rfl

/-- `every` 0, `watchFile` 1, `record` 2, `globalKey` 3. -/
def Sub.code : Sub → UInt8
  | .every _ => 0 | .watchFile _ => 1 | .record _ => 2 | .globalKey .. => 3

/-- `char` is 13 and carries its scalar in the record's `u32` field. -/
def Key.code : Key → UInt8
  | .enter => 0 | .escape => 1 | .tab => 2 | .backspace => 3 | .delete => 4
  | .left => 5 | .right => 6 | .up => 7 | .down => 8 | .home => 9 | .finish => 10
  | .pageUp => 11 | .pageDown => 12 | .char _ => 13

def Key.scalar : Key → Nat
  | .char c => c.toNat
  | _ => 0

def Key.ofCode (code : UInt8) (scalar : Nat) : Option Key :=
  match code with
  | 0 => some .enter | 1 => some .escape | 2 => some .tab | 3 => some .backspace
  | 4 => some .delete | 5 => some .left | 6 => some .right | 7 => some .up | 8 => some .down
  | 9 => some .home | 10 => some .finish | 11 => some .pageUp | 12 => some .pageDown
  | 13 => if scalar.isValidChar then some (.char (Char.ofNat scalar)) else none
  | _ => none

@[simp] theorem Key.ofCode_code (k : Key) : Key.ofCode (Key.code k) (Key.scalar k) = some k := by
  cases k with
  | char c =>
    have : c.toNat.isValidChar := c.valid
    simp only [ofCode, code, scalar, this, ↓reduceIte, Char.ofNat_toNat]
  | _ => rfl

theorem Key.scalar_fits (k : Key) : FitsU32 (Key.scalar k) := by
  cases k with
  | char c =>
    have h : c.toNat.isValidChar := c.valid
    simp only [scalar, FitsU32]; unfold Nat.isValidChar at h; omega
  | _ => decide

/-- Bit 0 shift, 1 command, 2 option, 3 control. -/
def Mods.code (m : Mods) : UInt8 :=
  UInt8.ofNat ((if m.shift then 1 else 0) + (if m.command then 2 else 0) +
    (if m.option then 4 else 0) + (if m.control then 8 else 0))

def Mods.ofCode (b : UInt8) : Option Mods :=
  let n := b.toNat
  if n < 16 then
    some ⟨n % 2 == 1, n / 2 % 2 == 1, n / 4 % 2 == 1, n / 8 % 2 == 1⟩
  else none

@[simp] theorem Mods.ofCode_code (m : Mods) : Mods.ofCode (Mods.code m) = some m := by
  obtain ⟨s, c, o, t⟩ := m
  cases s <;> cases c <;> cases o <;> cases t <;> rfl

def SurfaceKind.code : SurfaceKind → UInt8
  | .window => 0 | .panel => 1 | .statusItem => 2

def SurfaceKind.ofCode : UInt8 → Option SurfaceKind
  | 0 => some .window | 1 => some .panel | 2 => some .statusItem | _ => none

@[simp] theorem SurfaceKind.ofCode_code (k : SurfaceKind) :
    SurfaceKind.ofCode (SurfaceKind.code k) = some k := by
  cases k <;> rfl

def MenuKind.code : MenuKind → UInt8
  | .item => 0 | .info => 1 | .submenu => 2 | .separator => 3

def MenuKind.ofCode : UInt8 → Option MenuKind
  | 0 => some .item | 1 => some .info | 2 => some .submenu | 3 => some .separator | _ => none

@[simp] theorem MenuKind.ofCode_code (k : MenuKind) : MenuKind.ofCode (MenuKind.code k) = some k := by
  cases k <;> rfl

def ScreenChoice.code : ScreenChoice → UInt8
  | .pointer => 0 | .main => 1

def ScreenChoice.ofCode : UInt8 → Option ScreenChoice
  | 0 => some .pointer | 1 => some .main | _ => none

@[simp] theorem ScreenChoice.ofCode_code (c : ScreenChoice) :
    ScreenChoice.ofCode (ScreenChoice.code c) = some c := by
  cases c <;> rfl

/-- `bottomCenter` is 0; its offset goes in the record's `u32` field. -/
def Anchor.code : Anchor → UInt8
  | .bottomCenter _ => 0

def Anchor.ofCode (code : UInt8) (offset : Nat) : Option Anchor :=
  match code with
  | 0 => some (.bottomCenter offset)
  | _ => none

@[simp] theorem Anchor.ofCode_code (a : Anchor) : Anchor.ofCode (Anchor.code a) (Anchor.offset a) = some a := by
  cases a; rfl

/-- The shortcut fields of a menu record without one. -/
def noShortcut : Shortcut := ⟨.enter, {}⟩

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
def fitsInts (xs : List Int) : Bool := fu xs.length && xs.all fi

def fitsPaint (p : Paint) : Bool :=
  fs p.shader && decide (FitsU64 p.origin) && fitsInts p.scalars && fu p.arrays.length &&
    p.arrays.all fitsInts

def fitsShadow (s : Shadow) : Bool := fu s.radius && fi s.x && fi s.y

def fitsDraw : Draw → Bool
  | .rect r _ radius border => fitsRect r && fu radius && (border.all fun b => fu b.width)
  | .text o font _ s =>
    fi o.x && fi o.y && fu font.family && fu font.size && fu font.weight && fi font.tracking &&
      fs s
  | .pushClip r => fitsRect r
  | .popClip => true
  | .shape r _ radius border _ shadow =>
    fitsRect r && fu radius && (border.all fun b => fu b.width) && shadow.all fitsShadow
  | .paint r p => fitsRect r && fitsPaint p
  | .image r d src => fitsRect r && fitsRect d && fs src

def fitsAx (n : AxNode) : Bool :=
  n.control.all fitsRef && n.parent.all fu && fitsRect n.rect && fs n.label && fs n.value

def fitsTextInput (t : TextInput) : Bool :=
  fitsRef t.control && fitsRect t.rect && fitsRect t.caret && fitsRange t.selection &&
    t.marked.all fitsRange && fi t.textOrigin.x && fi t.textOrigin.y && fs t.text

def fu64 (n : Nat) : Bool := decide (FitsU64 n)
def fi64 (v : Int) : Bool := decide (FitsI64 v)
def fb (b : ByteArray) : Bool := decide (FitsBytes b)

@[simp] theorem fu64_iff (n : Nat) : fu64 n = true ↔ FitsU64 n := by
  simp only [fu64, decide_eq_true_eq]
@[simp] theorem fi64_iff (v : Int) : fi64 v = true ↔ FitsI64 v := by
  simp only [fi64, decide_eq_true_eq]
@[simp] theorem fb_iff (b : ByteArray) : fb b = true ↔ FitsBytes b := by
  simp only [fb, decide_eq_true_eq]

def fitsHeaders (hs : List (String × String)) : Bool :=
  fu hs.length && hs.all fun (k, v) => fs k && fs v

def fitsPart : Part → Bool
  | .bytes b => fb b
  | .wav c st sp => fu c && fu st && sp.all fu

def fitsSecret (s : Secret) : Bool := fs s.header && fs s.scheme && fs s.file && fs s.name

def fitsRequest : Request → Bool
  | .readFile p => fs p
  | .writeFile p d => fs p && fb d
  | .playSound n => fs n
  | .http m u hs b t => fs m && fs u && fitsHeaders hs && fb b && fu t
  | .appendFile p d => fs p && fb d
  | .listDir p | .deleteFile p | .makeDir p => fs p
  | .frontmostApp | .permission .. => true
  | .typeText pid t _ => fu pid && fs t
  | .upload m u hs sec body t =>
    fs m && fs u && fitsHeaders hs && sec.all fitsSecret && fu body.length && body.all fitsPart &&
      fu t
  | .forgetClip c => fu c
  | .openItem t | .appRunning t => fs t
  | .readDefault d k => fs d && fs k
  | .loadImage src _ => fs src

def fitsEffect : Effect → Bool
  | .setClipboard s => fs s
  | .beep => true
  | .focus c => fitsRef c
  | .setTimer n ms => fs n && fu ms
  | .cancelTimer n => fs n
  | .request id r => fu id && fitsRequest r
  | .quit => true

def fitsSub : Sub → Bool
  | .every ms => fu ms
  | .watchFile p => fs p
  | .record c => fu c
  | .globalKey code m => fu code && m.all fu

def fitsSubCmd : SubCmd → Bool
  | .start id sub => fu id && fitsSub sub
  | .stop id => fu id

/-- Every value fits its field. The other condition of the round trip is that the encoding is
under 4 GiB (each section's byte length is a `u32`). -/
def fitsCanvas (c : Canvas) : Bool :=
  fi c.size.w && fi c.size.h &&
    fu c.draws.size && c.draws.all fitsDraw &&
    fu c.ax.size && c.ax.all fitsAx &&
    c.textInput.all fitsTextInput

def fitsMenuRecord (m : MenuRecord) : Bool :=
  m.control.all fitsRef && m.parent.all fu && m.place.all fu && fs m.label

def fitsStatus (s : StatusFrame) : Bool :=
  fitsRef s.control && fs s.symbol && fs s.title && fs s.label &&
    fu s.menu.size && s.menu.all fitsMenuRecord

def fitsSurface (s : SurfaceFrame) : Bool :=
  fu s.place && fu s.anchor.offset && fs s.title && fitsCanvas s.canvas && fitsStatus s.status

def fitsFrame (f : Frame) : Bool :=
  fu f.surfaces.size && f.surfaces.all fitsSurface &&
    fu f.effects.size && f.effects.all fitsEffect &&
    fu f.subs.size && f.subs.all fitsSubCmd && f.wake.all fu64

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

/-- A `u32` count, then each as an `i32`. -/
def ints (xs : List Int) : List UInt8 := u32 xs.length ++ xs.flatMap i32

/-- A `u32` count, then each list as `ints`. -/
def intLists (xss : List (List Int)) : List UInt8 := u32 xss.length ++ xss.flatMap ints

def draw : Draw → List UInt8
  | .rect r fill radius border =>
    [0] ++ bool fill.isSome ++ bool border.isSome ++ pad 1 ++ rect r ++
      color (fill.getD noColor) ++ u32 radius ++
      u32 (border.elim 0 (·.width)) ++ color (border.elim noColor (·.color))
  | .text o font c s =>
    [1] ++ bool font.italic ++ [FontWidth.wire font.width] ++ bool font.tabular ++ point o ++
      u32 (satU32 font.family) ++ u32 (satU32 font.size) ++ u32 (satU32 font.weight) ++
      i32 (satI32 font.tracking) ++ color c ++ str s
  | .pushClip r => [2] ++ pad 3 ++ rect r
  | .popClip => [3] ++ pad 3
  | .paint r p => [4] ++ pad 3 ++ rect r ++ u64 p.origin ++ str p.shader ++ ints p.scalars ++
      intLists p.arrays
  | .shape r fill radius border corner shadow =>
    [5] ++ bool fill.isSome ++ bool border.isSome ++ bool shadow.isSome ++
      [Corner.code corner] ++ pad 3 ++ rect r ++ color (fill.getD noColor) ++ u32 radius ++
      u32 (border.elim 0 (·.width)) ++ color (border.elim noColor (·.color)) ++
      color (shadow.elim noColor (·.color)) ++ u32 (shadow.elim 0 (·.radius)) ++
      i32 (shadow.elim 0 (·.x)) ++ i32 (shadow.elim 0 (·.y))
  | .image r d src => [6] ++ pad 3 ++ rect r ++ rect d ++ str src

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

def header1 (kv : String × String) : List UInt8 := str kv.1 ++ str kv.2

/-- A `u32` count, then each name and value. -/
def headers (hs : List (String × String)) : List UInt8 := u32 hs.length ++ hs.flatMap header1

/-- `[0, 0, 0, 0]` and bytes, or `[1, hasStop, 0, 0]`, clip, start and stop. -/
def part : Part → List UInt8
  | .bytes b => [0] ++ pad 3 ++ bytes b
  | .wav c st sp => [1] ++ bool sp.isSome ++ pad 2 ++ u32 c ++ u32 st ++ u32 (sp.getD 0)

def secret (s : Secret) : List UInt8 := str s.header ++ str s.scheme ++ str s.file ++ str s.name

def optSecret : Option Secret → List UInt8
  | none => [0] ++ pad 3
  | some s => [1] ++ pad 3 ++ secret s

/-- A `u32` count, then each part. -/
def parts (ps : List Part) : List UInt8 := u32 ps.length ++ ps.flatMap part

/-- A request's fields after its record head and id. -/
def requestBody : Request → List UInt8
  | .readFile p => str p
  | .writeFile p d => str p ++ bytes d
  | .playSound n => str n
  | .http m u hs b t => u32 t ++ str m ++ str u ++ headers hs ++ bytes b
  | .appendFile p d => str p ++ bytes d
  | .listDir p => str p
  | .deleteFile p => str p
  | .frontmostApp => []
  | .permission p prompt => [Permission.code p] ++ bool prompt ++ pad 2
  | .typeText pid t r => u32 pid ++ bool r ++ pad 3 ++ str t
  | .upload m u hs sec body t =>
    u32 t ++ str m ++ str u ++ headers hs ++ optSecret sec ++ parts body
  | .forgetClip c => u32 c
  | .openItem t => str t
  | .appRunning b => str b
  | .readDefault d k => str d ++ str k
  | .makeDir p => str p
  | .loadImage src reload => bool reload ++ pad 3 ++ str src

def effect : Effect → List UInt8
  | .setClipboard s => [0] ++ pad 3 ++ str s
  | .beep => [1] ++ pad 3
  | .focus c => [2] ++ pad 3 ++ ref c
  | .setTimer n ms => [3] ++ pad 3 ++ u32 ms ++ str n
  | .cancelTimer n => [4] ++ pad 3 ++ str n
  | .request id r => [5, Request.Kind.code r.kind] ++ pad 2 ++ u32 id ++ requestBody r
  | .quit => [6] ++ pad 3

/-- A subscription's fields after its record head and id. -/
def subBody : Sub → List UInt8
  | .every ms => u32 ms
  | .watchFile p => str p
  | .record c => u32 c
  | .globalKey code m => u32 code ++ bool m.isSome ++ pad 3 ++ u32 (m.getD 0)

def subCmd : SubCmd → List UInt8
  | .start id s => [0, Sub.code s] ++ pad 2 ++ u32 id ++ subBody s
  | .stop id => [1] ++ pad 3 ++ u32 id

/-- `[hasWake, 0, 0, 0]`, then the deadline as a `u64` (0 when there is none). -/
def wake (w : Option Nat) : List UInt8 := bool w.isSome ++ pad 3 ++ u64 (w.getD 0)

def magic : List UInt8 := [0x43, 0x41, 0x46, 0x52] -- "CAFR"

/-- A Metal surface's content: size, draws, accessibility nodes, text input, cursor. -/
def canvas (c : Canvas) : List UInt8 :=
  size c.size ++ list draw c.draws.toList ++ list ax c.ax.toList ++ textInput c.textInput ++
    cursor c.cursor

/-- 32 bytes, then the label. A field the record doesn't have is written as zero. -/
def menuRecord (m : MenuRecord) : List UInt8 :=
  let sc := m.shortcut.getD noShortcut
  [MenuKind.code m.kind] ++ bool m.enabled ++ [checkedCode m.checked] ++ bool m.shortcut.isSome ++
    bool m.control.isSome ++ bool m.parent.isSome ++ bool m.place.isSome ++ [Key.code sc.key] ++
    ref (m.control.getD ⟨0, 0⟩) ++ u32 (m.parent.getD 0) ++ u32 (m.place.getD 0) ++
    u32 (Key.scalar sc.key) ++ [Mods.code sc.mods] ++ pad 3 ++ str m.label

def status (s : StatusFrame) : List UInt8 :=
  ref s.control ++ str s.symbol ++ str s.title ++ str s.label ++ list menuRecord s.menu.toList

/-- `[kind, shown, anchor, screen]`, place, anchor offset, title, canvas, status. -/
def surface (s : SurfaceFrame) : List UInt8 :=
  [SurfaceKind.code s.kind] ++ bool s.shown ++ [Anchor.code s.anchor, ScreenChoice.code s.screen] ++
    u32 s.place ++ u32 s.anchor.offset ++ str s.title ++ canvas s.canvas ++ status s.status

/-- Magic, version 5, flags 0. -/
def header : List UInt8 := magic ++ [5, 0, 0, 0]

def frame (f : Frame) : List UInt8 :=
  header ++ list surface f.surfaces.toList ++ list effect f.effects.toList ++
    list subCmd f.subs.toList ++ wake f.wake

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

def ints : Dec (List Int) := do
  let n ← u32
  count i32 n

def intLists : Dec (List (List Int)) := do
  let n ← u32
  count ints n

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
    let some width := FontWidth.ofWire (← byte) | fail
    let tabular ← bool
    let o ← point
    let family ← u32
    let sz ← u32
    let weight ← u32
    let tracking ← i32
    let c ← color
    let s ← str
    return .text o { family, size := sz, weight, italic, width, tracking, tabular } c s
  | 2 =>
    skip 3
    return .pushClip (← rect)
  | 3 =>
    skip 3
    return .popClip
  | 4 =>
    skip 3
    let r ← rect
    let origin ← u64
    let shader ← str
    let scalars ← ints
    let arrays ← intLists
    return .paint r { shader, origin, scalars, arrays }
  | 5 =>
    let hasFill ← bool
    let hasBorder ← bool
    let hasShadow ← bool
    let some corner := Corner.ofCode (← byte) | fail
    skip 3
    let r ← rect
    let fill ← color
    let radius ← u32
    let bw ← u32
    let bc ← color
    let sc ← color
    let sr ← u32
    let sx ← i32
    let sy ← i32
    return .shape r (if hasFill then some fill else none) radius
      (if hasBorder then some ⟨bw, bc⟩ else none) corner
      (if hasShadow then some ⟨sc, sr, sx, sy⟩ else none)
  | 6 =>
    skip 3
    let r ← rect
    let d ← rect
    return .image r d (← str)
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

def header1 : Dec (String × String) := do return (← str, ← str)

def headers : Dec (List (String × String)) := do
  let n ← u32
  count header1 n

def part : Dec Part := do
  match (← byte) with
  | 0 =>
    skip 3
    return .bytes (← bytes)
  | 1 =>
    let has ← bool
    skip 2
    let c ← u32
    let st ← u32
    let sp ← u32
    return .wav c st (if has then some sp else none)
  | _ => fail

def secret : Dec Secret := do return ⟨← str, ← str, ← str, ← str⟩

def optSecret : Dec (Option Secret) := do
  match (← byte) with
  | 0 =>
    skip 3
    return none
  | 1 =>
    skip 3
    return some (← secret)
  | _ => fail

def parts : Dec (List Part) := do
  let n ← u32
  count part n

def requestBody : Request.Kind → Dec Request
  | .readFile => do return .readFile (← str)
  | .writeFile => do
    let p ← str
    return .writeFile p (← bytes)
  | .playSound => do return .playSound (← str)
  | .http => do
    let t ← u32
    let m ← str
    let u ← str
    let hs ← headers
    let b ← bytes
    return .http m u hs b t
  | .appendFile => do
    let p ← str
    return .appendFile p (← bytes)
  | .listDir => do return .listDir (← str)
  | .deleteFile => do return .deleteFile (← str)
  | .frontmostApp => pure .frontmostApp
  | .permission => do
    let some p := Permission.ofCode (← byte) | fail
    let prompt ← bool
    skip 2
    return .permission p prompt
  | .typeText => do
    let pid ← u32
    let r ← bool
    skip 3
    return .typeText pid (← str) r
  | .upload => do
    let t ← u32
    let m ← str
    let u ← str
    let hs ← headers
    let sec ← optSecret
    let body ← parts
    return .upload m u hs sec body t
  | .forgetClip => do return .forgetClip (← u32)
  | .openItem => do return .openItem (← str)
  | .appRunning => do return .appRunning (← str)
  | .readDefault => do
    let d ← str
    return .readDefault d (← str)
  | .makeDir => do return .makeDir (← str)
  | .loadImage => do
    let reload ← bool
    skip 3
    return .loadImage (← str) reload

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
  | 3 =>
    skip 3
    let ms ← u32
    return .setTimer (← str) ms
  | 4 =>
    skip 3
    return .cancelTimer (← str)
  | 5 =>
    let some k := Request.Kind.ofCode (← byte) | fail
    skip 2
    let id ← u32
    return .request id (← requestBody k)
  | 6 =>
    skip 3
    return .quit
  | _ => fail

def subBody : UInt8 → Dec Sub
  | 0 => do return .every (← u32)
  | 1 => do return .watchFile (← str)
  | 2 => do return .record (← u32)
  | 3 => do
    let code ← u32
    let has ← bool
    skip 3
    let m ← u32
    return .globalKey code (if has then some m else none)
  | _ => fail

def subCmd : Dec SubCmd := do
  match (← byte) with
  | 0 =>
    let code ← byte
    skip 2
    let id ← u32
    return .start id (← subBody code)
  | 1 =>
    skip 3
    return .stop (← u32)
  | _ => fail

def wake : Dec (Option Nat) := do
  let has ← bool
  skip 3
  let w ← u64
  return if has then some w else none

def canvas : Dec Canvas := do
  let sz ← size
  let draws ← list draw
  let ax ← list ax
  let textInput ← textInput
  let cursor ← cursor
  return { size := sz, draws := draws.toArray, ax := ax.toArray, textInput, cursor }

def shortcut (has : Bool) (key : UInt8) (scalar : Nat) (mods : UInt8) : Dec (Option Shortcut) :=
  if has then
    match Key.ofCode key scalar, Mods.ofCode mods with
    | some k, some m => pure (some ⟨k, m⟩)
    | _, _ => fail
  else pure none

def menuRecord : Dec MenuRecord := do
  let some kind := MenuKind.ofCode (← byte) | fail
  let enabled ← bool
  let some checked := checkedOfCode (← byte) | fail
  let hasShortcut ← bool
  let hasControl ← bool
  let hasParent ← bool
  let hasPlace ← bool
  let key ← byte
  let c ← ref
  let parent ← u32
  let place ← u32
  let scalar ← u32
  let mods ← byte
  skip 3
  let label ← str
  let sc ← shortcut hasShortcut key scalar mods
  return { kind, label, control := if hasControl then some c else none,
           place := if hasPlace then some place else none,
           parent := if hasParent then some parent else none, enabled, checked, shortcut := sc }

def status : Dec StatusFrame := do
  let control ← ref
  let symbol ← str
  let title ← str
  let label ← str
  let menu ← list menuRecord
  return { control, symbol, title, label, menu := menu.toArray }

def surface : Dec SurfaceFrame := do
  let some kind := SurfaceKind.ofCode (← byte) | fail
  let shown ← bool
  let anchorCode ← byte
  let some screen := ScreenChoice.ofCode (← byte) | fail
  let place ← u32
  let offset ← u32
  let some anchor := Anchor.ofCode anchorCode offset | fail
  let title ← str
  let canvas ← canvas
  let status ← status
  return { kind, place, shown, title, anchor, screen, canvas, status }

def frame : Dec Frame := do
  expect Enc.header
  let surfaces ← list surface
  let effects ← list effect
  let subs ← list subCmd
  let wake ← wake
  return { surfaces := surfaces.toArray, effects := effects.toArray, subs := subs.toArray, wake }

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

theorem ints_enc {xs : List Int} (h : fitsInts xs = true) (r : List UInt8) :
    ints (Enc.ints xs ++ r) = some (xs, r) := by
  simp only [fitsInts, Bool.and_eq_true, fu_iff, List.all_eq_true, fi_iff] at h
  simp only [ints, Enc.ints, List.append_assoc, bind_apply, u32_enc h.1]
  exact count_enc xs (fun v hv => i32_enc (h.2 v hv)) r

theorem intLists_enc {xss : List (List Int)} (hn : FitsU32 xss.length)
    (h : ∀ xs ∈ xss, fitsInts xs = true) (r : List UInt8) :
    intLists (Enc.intLists xss ++ r) = some (xss, r) := by
  simp only [intLists, Enc.intLists, List.append_assoc, bind_apply, u32_enc hn]
  exact count_enc xss (fun xs hxs => ints_enc (h xs hxs)) r

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
        satU32_of_fits, satI32_of_fits, bind_apply, byte_cons, bool_enc, FontWidth.ofWire_wire,
        point_enc, u32_enc, i32_enc, color_enc, str_enc, pure_apply]
  | pushClip rc =>
    simp only [fitsDraw] at h
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, h, rect_enc, pure_apply]
  | popClip =>
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, bind_apply, byte_cons, skip_pad,
        pure_apply]
  | paint rc p =>
    simp only [fitsDraw, fitsPaint, Bool.and_eq_true, fs_iff, decide_eq_true_eq, fu_iff,
        List.all_eq_true] at h
    obtain ⟨hr, ⟨⟨⟨⟨hs, ho⟩, hsc⟩, hn⟩, ha⟩⟩ := h
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, rect_enc hr, u64_enc ho, str_enc hs, ints_enc hsc,
        intLists_enc hn ha, pure_apply]
  | shape rc fill radius border corner shadow =>
    simp only [fitsDraw, Bool.and_eq_true, fu_iff] at h
    obtain ⟨⟨⟨hr, hrad⟩, hb⟩, hsh⟩ := h
    cases shadow with
    | none =>
      cases fill <;> cases border <;>
        simp_all only [Option.all_none, draw, Enc.draw, Option.isSome_none, List.cons_append,
            List.nil_append, List.append_assoc, Option.getD_none, Option.elim_none, bind_apply,
            byte_cons, bool_enc, Bool.false_eq_true, ↓reduceIte, skip_pad, rect_enc, color_enc,
            u32_enc, i32_enc, fitsU32_zero, pure_apply, Option.all_some, fu_iff,
            Option.isSome_some, Option.elim_some, Option.getD_some, Corner.ofCode_code,
            show FitsI32 0 by decide]
    | some sh =>
      simp only [Option.all_some, fitsShadow, Bool.and_eq_true, fu_iff, fi_iff] at hsh
      obtain ⟨⟨hsr, hsx⟩, hsy⟩ := hsh
      cases fill <;> cases border <;>
        simp_all only [Option.all_none, draw, Enc.draw, Option.isSome_none, List.cons_append,
            List.nil_append, List.append_assoc, Option.getD_none, Option.elim_none, bind_apply,
            byte_cons, bool_enc, Bool.false_eq_true, ↓reduceIte, skip_pad, rect_enc, color_enc,
            u32_enc, i32_enc, fitsU32_zero, pure_apply, Option.all_some, fu_iff,
            Option.isSome_some, Option.elim_some, Option.getD_some, Corner.ofCode_code]
  | image rc d src =>
    simp only [fitsDraw, Bool.and_eq_true, fs_iff] at h
    obtain ⟨⟨hr, hd⟩, hs⟩ := h
    simp only [draw, Enc.draw, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, rect_enc hr, rect_enc hd, str_enc hs, pure_apply]

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

theorem header1_enc {kv : String × String} (h : (fs kv.1 && fs kv.2) = true) (r : List UInt8) :
    header1 (Enc.header1 kv ++ r) = some (kv, r) := by
  simp only [Bool.and_eq_true, fs_iff] at h
  simp only [header1, Enc.header1, List.append_assoc, bind_apply, str_enc h.1, str_enc h.2,
      pure_apply]

theorem headers_enc {hs : List (String × String)} (h : fitsHeaders hs = true) (r : List UInt8) :
    headers (Enc.headers hs ++ r) = some (hs, r) := by
  simp only [fitsHeaders, Bool.and_eq_true, fu_iff, List.all_eq_true] at h
  simp only [headers, Enc.headers, List.append_assoc, bind_apply, u32_enc h.1]
  exact count_enc hs (fun kv hkv => header1_enc (by simpa using h.2 kv hkv)) r

theorem part_enc {x : Part} (h : fitsPart x = true) (r : List UInt8) :
    part (Enc.part x ++ r) = some (x, r) := by
  cases x with
  | bytes b =>
    simp only [fitsPart, fb_iff] at h
    simp only [part, Enc.part, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, bytes_enc h, pure_apply]
  | wav c st sp =>
    simp only [fitsPart, Bool.and_eq_true, fu_iff] at h
    obtain ⟨⟨hc, hs⟩, hp⟩ := h
    cases sp <;>
      simp_all only [Option.all_none, Option.all_some, fu_iff, part, Enc.part, Option.isSome_none,
        Option.isSome_some, Option.getD_none, Option.getD_some, List.cons_append, List.nil_append,
        List.append_assoc, bind_apply, byte_cons, bool_enc, skip_pad, u32_enc, fitsU32_zero,
        pure_apply, Bool.false_eq_true, ↓reduceIte]

theorem secret_enc {s : Secret} (h : fitsSecret s = true) (r : List UInt8) :
    secret (Enc.secret s ++ r) = some (s, r) := by
  simp only [fitsSecret, Bool.and_eq_true, fs_iff] at h
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
  simp only [secret, Enc.secret, List.append_assoc, bind_apply, str_enc h1, str_enc h2,
      str_enc h3, str_enc h4, pure_apply]

theorem optSecret_enc {s : Option Secret} (h : s.all fitsSecret = true) (r : List UInt8) :
    optSecret (Enc.optSecret s ++ r) = some (s, r) := by
  cases s with
  | none => simp only [optSecret, Enc.optSecret, List.cons_append, List.nil_append, bind_apply,
      byte_cons, skip_pad, pure_apply]
  | some s =>
    simp only [Option.all_some] at h
    simp only [optSecret, Enc.optSecret, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, skip_pad, secret_enc h, pure_apply]

theorem parts_enc {ps : List Part} (hn : FitsU32 ps.length) (h : ∀ p ∈ ps, fitsPart p = true)
    (r : List UInt8) : parts (Enc.parts ps ++ r) = some (ps, r) := by
  simp only [parts, Enc.parts, List.append_assoc, bind_apply, u32_enc hn]
  exact count_enc ps (fun p hp => part_enc (h p hp)) r

theorem requestBody_enc {q : Request} (h : fitsRequest q = true) (r : List UInt8) :
    requestBody q.kind (Enc.requestBody q ++ r) = some (q, r) := by
  cases q with
  | readFile p =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | writeFile p d =>
    simp only [fitsRequest, Bool.and_eq_true, fs_iff, fb_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        str_enc h.1, bytes_enc h.2, pure_apply]
  | playSound n =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | http m u hs b t =>
    simp only [fitsRequest, Bool.and_eq_true, fs_iff, fb_iff, fu_iff] at h
    obtain ⟨⟨⟨⟨hm, hu⟩, hh⟩, hb⟩, ht⟩ := h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        u32_enc ht, str_enc hm, str_enc hu, headers_enc hh, bytes_enc hb, pure_apply]
  | appendFile p d =>
    simp only [fitsRequest, Bool.and_eq_true, fs_iff, fb_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        str_enc h.1, bytes_enc h.2, pure_apply]
  | listDir p =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | deleteFile p =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | frontmostApp => rfl
  | permission p prompt =>
    simp only [Request.kind, requestBody, Enc.requestBody, List.cons_append, List.nil_append,
        List.append_assoc, bind_apply, byte_cons, Permission.ofCode_code, bool_enc, skip_pad,
        pure_apply]
  | typeText pid t ret =>
    simp only [fitsRequest, Bool.and_eq_true, fu_iff, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        u32_enc h.1, bool_enc, skip_pad, str_enc h.2, pure_apply]
  | upload m u hs sec body t =>
    simp only [fitsRequest, Bool.and_eq_true, fs_iff, fu_iff, List.all_eq_true] at h
    obtain ⟨⟨⟨⟨⟨⟨hm, hu⟩, hh⟩, hsec⟩, hn⟩, hb⟩, ht⟩ := h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        u32_enc ht, str_enc hm, str_enc hu, headers_enc hh, optSecret_enc hsec,
        parts_enc hn hb, pure_apply]
  | forgetClip c =>
    simp only [fitsRequest, fu_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, u32_enc h, pure_apply]
  | openItem t =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | appRunning b =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | readDefault d k =>
    simp only [fitsRequest, Bool.and_eq_true, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        str_enc h.1, str_enc h.2, pure_apply]
  | makeDir p =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, bind_apply, str_enc h, pure_apply]
  | loadImage src reload =>
    simp only [fitsRequest, fs_iff] at h
    simp only [Request.kind, requestBody, Enc.requestBody, List.append_assoc, bind_apply,
        bool_enc, skip_pad, str_enc h, pure_apply]

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
  | setTimer n ms =>
    simp only [fitsEffect, Bool.and_eq_true, fs_iff, fu_iff] at h
    simp only [effect, Enc.effect, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, u32_enc h.2, str_enc h.1, pure_apply]
  | cancelTimer n =>
    simp only [fitsEffect, fs_iff] at h
    simp only [effect, Enc.effect, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, skip_pad, str_enc h, pure_apply]
  | request id rq =>
    simp only [fitsEffect, Bool.and_eq_true, fu_iff] at h
    simp only [effect, Enc.effect, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
        byte_cons, Request.Kind.ofCode_code, skip_pad, u32_enc h.1]
    rw [requestBody_enc h.2]; rfl
  | quit => simp only [effect, Enc.effect, List.cons_append, List.nil_append, bind_apply, byte_cons,
      skip_pad, pure_apply]

theorem subCmd_enc {x : SubCmd} (h : fitsSubCmd x = true) (r : List UInt8) :
    subCmd (Enc.subCmd x ++ r) = some (x, r) := by
  cases x with
  | start id sub =>
    cases sub with
    | every ms =>
      simp only [fitsSubCmd, fitsSub, Bool.and_eq_true, fu_iff] at h
      simp only [subCmd, Enc.subCmd, Sub.code, Enc.subBody, subBody, List.cons_append,
          List.nil_append, List.append_assoc, bind_apply, byte_cons, skip_pad, u32_enc h.1,
          u32_enc h.2, pure_apply]
    | watchFile p =>
      simp only [fitsSubCmd, fitsSub, Bool.and_eq_true, fu_iff, fs_iff] at h
      simp only [subCmd, Enc.subCmd, Sub.code, Enc.subBody, subBody, List.cons_append,
          List.nil_append, List.append_assoc, bind_apply, byte_cons, skip_pad, u32_enc h.1,
          str_enc h.2, pure_apply]
    | record c =>
      simp only [fitsSubCmd, fitsSub, Bool.and_eq_true, fu_iff] at h
      simp only [subCmd, Enc.subCmd, Sub.code, Enc.subBody, subBody, List.cons_append,
          List.nil_append, List.append_assoc, bind_apply, byte_cons, skip_pad, u32_enc h.1,
          u32_enc h.2, pure_apply]
    | globalKey code m =>
      simp only [fitsSubCmd, fitsSub, Bool.and_eq_true, fu_iff] at h
      obtain ⟨hid, hc, hm⟩ := h
      cases m <;>
        simp_all only [Option.all_none, Option.all_some, fu_iff, subCmd, Enc.subCmd, Sub.code,
          Enc.subBody, subBody, Option.isSome_none, Option.isSome_some, Option.getD_none,
          Option.getD_some, List.cons_append, List.nil_append, List.append_assoc, bind_apply,
          byte_cons, skip_pad, bool_enc, u32_enc, fitsU32_zero, pure_apply, Bool.false_eq_true,
          ↓reduceIte]
  | stop id =>
    simp only [fitsSubCmd, fu_iff] at h
    simp only [subCmd, Enc.subCmd, List.cons_append, List.nil_append, List.append_assoc,
        bind_apply, byte_cons, skip_pad, u32_enc h, pure_apply]

theorem wake_enc {w : Option Nat} (h : w.all fu64 = true) (r : List UInt8) :
    wake (Enc.wake w ++ r) = some (w, r) := by
  cases w with
  | none =>
    simp only [wake, Enc.wake, Option.isSome_none, Option.getD_none, List.append_assoc,
        bind_apply, bool_enc, skip_pad, u64_enc (show FitsU64 0 by decide), pure_apply,
        Bool.false_eq_true, ↓reduceIte]
  | some n =>
    simp only [Option.all_some, fu64_iff] at h
    simp only [wake, Enc.wake, Option.isSome_some, Option.getD_some, List.append_assoc,
        bind_apply, bool_enc, skip_pad, u64_enc h, pure_apply, ↓reduceIte]

theorem length_le_flatMap {α : Type} (e : α → List UInt8) {xs : List α} {x : α} (h : x ∈ xs) :
    (e x).length ≤ (xs.flatMap e).length := by
  induction xs with
  | nil => simp only [List.not_mem_nil] at h
  | cons y ys ih =>
    simp only [List.flatMap_cons, List.length_append]
    rcases List.mem_cons.mp h with rfl | h
    · omega
    · have := ih h; omega

theorem canvas_enc {c : Canvas} (h : fitsCanvas c = true) (hs : (Enc.canvas c).length < 4294967296)
    (r : List UInt8) : canvas (Enc.canvas c ++ r) = some (c, r) := by
  obtain ⟨sz, draws, axs, ti, cur⟩ := c
  simp only [fitsCanvas, Bool.and_eq_true, fi_iff, fu_iff, Array.all_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨⟨hw, hh⟩, hdn⟩, hd⟩, han⟩, ha⟩, ht⟩ := h
  simp only [Enc.canvas, Enc.list, Enc.sect, Enc.size, Enc.textInput, Enc.cursor,
    List.length_append, Enc.length_u32, Enc.length_i32] at hs
  simp only [canvas, Enc.canvas, List.append_assoc, bind_apply]
  rw [size_enc hw hh]; dsimp only
  rw [list_enc (e := Enc.draw) _ (fun x hx => draw_enc (hd x (by simpa using hx))) (by simpa using hdn)
    (by unfold FitsU32; omega)]; dsimp only
  rw [list_enc (e := Enc.ax) _ (fun x hx => ax_enc (ha x (by simpa using hx))) (by simpa using han)
    (by unfold FitsU32; omega)]; dsimp only
  rw [textInput_enc ht]; dsimp only
  rw [cursor_enc]
  simp only [Array.toArray_toList, pure_apply]

theorem menuRecord_enc {m : MenuRecord} (h : fitsMenuRecord m = true) (r : List UInt8) :
    menuRecord (Enc.menuRecord m ++ r) = some (m, r) := by
  obtain ⟨kind, label, control, place, parent, enabled, checked, sc⟩ := m
  simp only [fitsMenuRecord, Bool.and_eq_true, fs_iff] at h
  obtain ⟨⟨⟨hc, hp⟩, hpl⟩, hl⟩ := h
  have hk : ∀ k : Key, FitsU32 (Key.scalar k) := Key.scalar_fits
  cases control <;> cases parent <;> cases place <;> cases sc <;>
    simp_all only [Option.all_none, Option.all_some, fu_iff, menuRecord, Enc.menuRecord,
        List.cons_append, List.nil_append, List.append_assoc, Option.isSome_none,
        Option.isSome_some, Option.getD_none, Option.getD_some, bind_apply, byte_cons,
        MenuKind.ofCode_code, bool_enc, checkedOfCode_code, Bool.false_eq_true, ↓reduceIte,
        skip_pad, fitsRef_zero, ref_enc, fitsU32_zero, u32_enc, str_enc, pure_apply, shortcut,
        Key.ofCode_code, Mods.ofCode_code]

theorem status_enc {s : StatusFrame} (h : fitsStatus s = true)
    (hs : (Enc.status s).length < 4294967296) (r : List UInt8) :
    status (Enc.status s ++ r) = some (s, r) := by
  obtain ⟨c, sym, title, label, menu⟩ := s
  simp only [fitsStatus, Bool.and_eq_true, fs_iff, fu_iff, Array.all_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨hc, hsy⟩, ht⟩, hl⟩, hmn⟩, hm⟩ := h
  simp only [Enc.status, Enc.list, Enc.sect, List.length_append, Enc.length_u32] at hs
  simp only [status, Enc.status, List.append_assoc, bind_apply, ref_enc hc, str_enc hsy,
    str_enc ht, str_enc hl]
  rw [list_enc (e := Enc.menuRecord) _ (fun x hx => menuRecord_enc (hm x (by simpa using hx)))
    (by simpa using hmn) (by unfold FitsU32; omega)]
  simp only [Array.toArray_toList, pure_apply]

theorem surface_enc {s : SurfaceFrame} (h : fitsSurface s = true)
    (hs : (Enc.surface s).length < 4294967296) (r : List UInt8) :
    surface (Enc.surface s ++ r) = some (s, r) := by
  obtain ⟨kind, place, shown, title, anchor, screen, c, st⟩ := s
  simp only [fitsSurface, Bool.and_eq_true, fu_iff, fs_iff] at h
  obtain ⟨⟨⟨⟨hp, ho⟩, ht⟩, hc⟩, hst⟩ := h
  simp only [Enc.surface, List.length_append, List.length_cons, List.length_nil,
    Enc.length_u32, Enc.bool] at hs
  simp only [surface, Enc.surface, List.cons_append, List.nil_append, List.append_assoc,
    bind_apply, byte_cons, SurfaceKind.ofCode_code, bool_enc, ScreenChoice.ofCode_code,
    u32_enc hp, u32_enc ho, Anchor.ofCode_code, str_enc ht]
  rw [canvas_enc hc (by omega)]; dsimp only
  rw [status_enc hst (by omega)]
  simp only [pure_apply]

/-- Sections of a frame whose encoding is under 4 GiB have `u32` byte lengths. -/
def SizeOk (f : Frame) : Prop := (Enc.frame f).length < 4294967296

theorem frame_enc {f : Frame} (h : fitsFrame f = true) (hs : SizeOk f) (r : List UInt8) :
    frame (Enc.frame f ++ r) = some (f, r) := by
  obtain ⟨surfs, effs, subs, wk⟩ := f
  simp only [fitsFrame, Bool.and_eq_true, fu_iff, Array.all_eq_true'] at h
  obtain ⟨⟨⟨⟨⟨⟨hsn, hsf⟩, hen⟩, he⟩, hcn⟩, hsc⟩, hwk⟩ := h
  simp only [SizeOk, Enc.frame, Enc.list, Enc.sect, List.length_append, Enc.length_u32] at hs
  simp only [frame, Enc.frame, List.append_assoc, bind_apply, expect_enc]
  rw [list_enc (e := Enc.surface) _ (fun x hx => surface_enc (hsf x (by simpa using hx))
    (by have := length_le_flatMap Enc.surface hx; omega)) (by simpa using hsn)
    (by unfold FitsU32; omega)]; dsimp only
  rw [list_enc (e := Enc.effect) _ (fun x hx => effect_enc (he x (by simpa using hx))) (by simpa using hen)
    (by unfold FitsU32; omega)]; dsimp only
  rw [list_enc (e := Enc.subCmd) _ (fun x hx => subCmd_enc (hsc x (by simpa using hx)))
    (by simpa using hcn) (by unfold FitsU32; omega)]; dsimp only
  rw [wake_enc hwk]
  simp only [Array.toArray_toList, pure_apply]

end Dec

/-! ## Executable encoder

`Put.*` writes the same bytes as `Enc.*` straight into a `ByteArray`. Section byte lengths are
computed up front by `Len.*` (proved equal to the encoded lengths), so nothing is copied or
patched afterwards. -/

namespace Len

def str (s : String) : Nat := 4 + s.toUTF8.size

def ints (xs : List Int) : Nat := 4 + 4 * xs.length

def intLists (xss : List (List Int)) : Nat := 4 + xss.foldl (fun n xs => n + ints xs) 0

def draw : Draw → Nat
  | .rect .. => 36
  | .text _ _ _ s => 32 + str s
  | .pushClip _ => 20
  | .popClip => 4
  | .paint _ p => 28 + str p.shader + ints p.scalars + intLists p.arrays
  | .shape .. => 56
  | .image _ _ src => 36 + str src

def ax (n : AxNode) : Nat := 36 + str n.label + str n.value

def bytes (b : ByteArray) : Nat := 4 + b.size

def headers (hs : List (String × String)) : Nat :=
  4 + hs.foldl (fun n kv => n + (str kv.1 + str kv.2)) 0

def part : Part → Nat
  | .bytes b => 4 + bytes b
  | .wav .. => 16

def parts (ps : List Part) : Nat := 4 + ps.foldl (fun n p => n + part p) 0

def secret (s : Secret) : Nat := str s.header + str s.scheme + str s.file + str s.name

def optSecret : Option Secret → Nat
  | none => 4
  | some s => 4 + secret s

def requestBody : Request → Nat
  | .readFile p => str p
  | .writeFile p d => str p + bytes d
  | .playSound n => str n
  | .http m u hs b _ => 4 + str m + str u + headers hs + bytes b
  | .appendFile p d => str p + bytes d
  | .listDir p | .deleteFile p | .makeDir p => str p
  | .frontmostApp => 0
  | .permission .. => 4
  | .typeText _ t _ => 8 + str t
  | .upload m u hs sec body _ => 4 + str m + str u + headers hs + optSecret sec + parts body
  | .forgetClip _ => 4
  | .openItem t | .appRunning t => str t
  | .readDefault d k => str d + str k
  | .loadImage src _ => 4 + str src

def effect : Effect → Nat
  | .setClipboard s => 4 + str s
  | .beep => 4
  | .focus _ => 12
  | .setTimer n _ => 8 + str n
  | .cancelTimer n => 4 + str n
  | .request _ r => 8 + requestBody r
  | .quit => 4

def subBody : Sub → Nat
  | .every _ => 4
  | .watchFile p => str p
  | .record _ => 4
  | .globalKey .. => 12

def subCmd : SubCmd → Nat
  | .start _ s => 8 + subBody s
  | .stop _ => 8

def textInput : Option TextInput → Nat
  | none => 4
  | some t => 68 + str t.text

def list {α : Type} (len : α → Nat) (xs : Array α) : Nat := xs.foldl (fun n x => n + len x) 0

def canvas (c : Canvas) : Nat :=
  8 + (8 + list draw c.draws) + (8 + list ax c.ax) + textInput c.textInput + 4

def menuRecord (m : MenuRecord) : Nat := 32 + str m.label

def status (s : StatusFrame) : Nat :=
  8 + str s.symbol + str s.title + str s.label + (8 + list menuRecord s.menu)

def surface (s : SurfaceFrame) : Nat := 12 + str s.title + canvas s.canvas + status s.status

theorem foldl_add {α : Type} (len : α → Nat) (xs : List α) (n : Nat) :
    xs.foldl (fun n x => n + len x) n = n + (xs.map len).sum := by
  induction xs generalizing n with
  | nil => simp only [List.foldl_nil, List.map_nil, List.sum_nil, Nat.add_zero]
  | cons x xs ih => simp only [List.foldl_cons, ih, List.map_cons, List.sum_cons]; omega

theorem str_eq (s : String) : str s = (Enc.str s).length := by
  simp only [str, String.toUTF8_eq_toByteArray, String.size_toByteArray, Enc.str,
      List.length_append, Enc.length_u32, Array.length_toList, ByteArray.size_data]; all_goals omega

theorem length_flatMap_i32 (xs : List Int) : (xs.flatMap Enc.i32).length = 4 * xs.length := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.flatMap_cons, List.length_append, Enc.length_i32, ih, List.length_cons]
    omega

theorem ints_eq (xs : List Int) : ints xs = (Enc.ints xs).length := by
  simp only [ints, Enc.ints, List.length_append, Enc.length_u32, length_flatMap_i32]

theorem intLists_eq (xss : List (List Int)) : intLists xss = (Enc.intLists xss).length := by
  rw [intLists, foldl_add]
  simp only [Enc.intLists, List.length_append, Enc.length_u32, List.length_flatMap, ← ints_eq,
      Nat.zero_add]

theorem draw_eq (d : Draw) : draw d = (Enc.draw d).length := by
  cases d <;> simp only [draw, Enc.draw, ints_eq, intLists_eq, Enc.length_u64, Enc.bool, List.cons_append, List.nil_append, Enc.pad,
      List.replicate_one, Enc.rect, List.append_assoc, Enc.color, List.length_cons,
      List.length_append, Enc.length_i32, Enc.length_u32, List.length_nil, Nat.zero_add,
      Nat.reduceAdd, str_eq, Enc.str, String.toUTF8_eq_toByteArray, String.size_toByteArray,
      Array.length_toList, ByteArray.size_data, List.reduceReplicate, Enc.point] <;> all_goals omega

theorem ax_eq (n : AxNode) : ax n = (Enc.ax n).length := by
  simp only [ax, str_eq, Enc.str, String.toUTF8_eq_toByteArray, String.size_toByteArray,
      List.length_append, Enc.length_u32, Array.length_toList, ByteArray.size_data, Enc.ax,
      Enc.bool, List.cons_append, List.nil_append, Enc.pad, List.reduceReplicate, Enc.ref,
      List.append_assoc, Enc.rect, List.length_cons, Enc.length_i32]; all_goals omega

theorem bytes_eq (b : ByteArray) : bytes b = (Enc.bytes b).length := by
  simp only [bytes, Enc.bytes, List.length_append, Enc.length_u32, Array.length_toList,
      ByteArray.size_data]

theorem headers_eq (hs : List (String × String)) : headers hs = (Enc.headers hs).length := by
  rw [headers, foldl_add]
  simp only [Enc.headers, List.length_append, Enc.length_u32, List.length_flatMap, Enc.header1,
      str_eq, Nat.zero_add]

theorem part_eq (p : Part) : part p = (Enc.part p).length := by
  cases p <;> simp only [part, Enc.part, bytes_eq, List.length_append, List.length_cons,
      List.length_nil, Enc.pad, List.length_replicate, Enc.bool, Enc.length_u32] <;> omega

theorem parts_eq (ps : List Part) : parts ps = (Enc.parts ps).length := by
  rw [parts, foldl_add]
  simp only [Enc.parts, List.length_append, Enc.length_u32, List.length_flatMap, ← part_eq,
      Nat.zero_add]

theorem optSecret_eq (s : Option Secret) : optSecret s = (Enc.optSecret s).length := by
  cases s <;> simp only [optSecret, secret, Enc.optSecret, Enc.secret, str_eq,
      List.length_append, List.length_cons, List.length_nil, Enc.pad, List.length_replicate] <;>
    omega

theorem requestBody_eq (r : Request) : requestBody r = (Enc.requestBody r).length := by
  cases r <;> simp only [requestBody, Enc.requestBody, List.length_append, str_eq, bytes_eq,
      headers_eq, optSecret_eq, parts_eq, Enc.length_u32, List.length_nil, List.length_cons,
      Enc.bool, Enc.pad, List.length_replicate] <;> try omega

theorem effect_eq (e : Effect) : effect e = (Enc.effect e).length := by
  cases e <;> simp only [effect, requestBody_eq, str_eq, Enc.str, String.toUTF8_eq_toByteArray,
      String.size_toByteArray, List.length_append, Enc.length_u32, Array.length_toList,
      ByteArray.size_data, Enc.effect, Enc.pad, List.reduceReplicate, List.cons_append,
      List.nil_append, List.length_cons, List.length_nil, Nat.zero_add,
      Nat.reduceAdd, Enc.ref] <;> all_goals omega

theorem subCmd_eq (c : SubCmd) : subCmd c = (Enc.subCmd c).length := by
  rcases c with ⟨_, ⟨_⟩ | ⟨_⟩ | ⟨_⟩ | ⟨_, _⟩⟩ | _ <;> simp only [subCmd, subBody, Enc.subCmd,
      Enc.subBody, str_eq, List.length_append, List.length_cons, Enc.pad, List.length_replicate,
      Enc.length_u32, List.length_nil, Enc.bool] <;> omega

theorem textInput_eq (t : Option TextInput) : textInput t = (Enc.textInput t).length := by
  cases t <;> simp only [textInput, Enc.textInput, Enc.pad, List.reduceReplicate, List.cons_append,
      List.nil_append, List.length_cons, List.length_nil, Nat.zero_add, Nat.reduceAdd, str_eq,
      Enc.str, String.toUTF8_eq_toByteArray, String.size_toByteArray, List.length_append,
      Enc.length_u32, Array.length_toList, ByteArray.size_data, Enc.bool, Enc.ref, Enc.rect,
      List.append_assoc, Enc.range, Enc.point, Enc.length_i32] <;> all_goals omega

theorem list_eq {α : Type} (len : α → Nat) (e : α → List UInt8) (h : ∀ x, len x = (e x).length)
    (xs : Array α) : list len xs = (xs.toList.flatMap e).length := by
  rw [list, ← Array.foldl_toList, foldl_add]
  induction xs.toList with
  | nil => simp only [List.map_nil, List.sum_nil, Nat.add_zero, List.flatMap_nil, List.length_nil]
  | cons x xs ih => simp_all only [Nat.zero_add, List.length_flatMap, List.map_cons, List.sum_cons,
      List.flatMap_cons, List.length_append]

theorem canvas_eq (c : Canvas) : canvas c = (Enc.canvas c).length := by
  simp only [canvas, Enc.canvas, list_eq draw Enc.draw draw_eq, list_eq ax Enc.ax ax_eq,
    textInput_eq, List.length_append, Enc.size, Enc.length_i32, Enc.list, Enc.sect,
    Enc.length_u32, Enc.cursor, Enc.pad, List.reduceReplicate, List.cons_append, List.nil_append,
    List.length_cons, List.length_nil]
  omega

theorem menuRecord_eq (m : MenuRecord) : menuRecord m = (Enc.menuRecord m).length := by
  simp only [menuRecord, Enc.menuRecord, str_eq, List.length_append, List.length_cons,
    Enc.bool, Enc.ref, Enc.length_u32, Enc.pad, List.length_replicate,
    List.cons_append, List.nil_append, List.append_assoc]
  omega

theorem status_eq (s : StatusFrame) : status s = (Enc.status s).length := by
  simp only [status, Enc.status, str_eq, list_eq menuRecord Enc.menuRecord menuRecord_eq,
    List.length_append, Enc.ref, Enc.length_u32, Enc.list, Enc.sect]
  omega

theorem surface_eq (s : SurfaceFrame) : surface s = (Enc.surface s).length := by
  simp only [surface, Enc.surface, str_eq, canvas_eq, status_eq, List.length_append,
    List.length_cons, Enc.bool, Enc.length_u32, List.cons_append,
    List.nil_append]
  omega

end Len

namespace Put

def rect (b : ByteArray) (r : Rect) : ByteArray := i32 (i32 (i32 (i32 b r.x) r.y) r.w) r.h
def point (b : ByteArray) (p : Point) : ByteArray := i32 (i32 b p.x) p.y
def color (b : ByteArray) (c : Color) : ByteArray := (((b.push c.r).push c.g).push c.b).push c.a
def ref (b : ByteArray) (c : ControlRef) : ByteArray := u32 (u32 b c.claim) c.key
def range (b : ByteArray) (p : Nat × Nat) : ByteArray := u32 (u32 b p.1) p.2

def ints (b : ByteArray) (xs : List Int) : ByteArray := xs.foldl i32 (u32 b xs.length)

def intLists (b : ByteArray) (xss : List (List Int)) : ByteArray :=
  xss.foldl ints (u32 b xss.length)

def draw (b : ByteArray) : Draw → ByteArray
  | .rect r fill radius border =>
    let b := pad (bool (bool (b.push 0) fill.isSome) border.isSome) 1
    color (u32 (u32 (color (rect b r) (fill.getD Enc.noColor)) radius)
      (border.elim 0 (·.width))) (border.elim Enc.noColor (·.color))
  | .text o font c s =>
    let b := point (bool ((bool (b.push 1) font.italic).push (FontWidth.wire font.width))
      font.tabular) o
    str (color (i32 (u32 (u32 (u32 b (satU32 font.family)) (satU32 font.size))
      (satU32 font.weight)) (satI32 font.tracking)) c) s
  | .pushClip r => rect (pad (b.push 2) 3) r
  | .popClip => pad (b.push 3) 3
  | .paint r p =>
    intLists (ints (str (u64 (rect (pad (b.push 4) 3) r) p.origin) p.shader) p.scalars) p.arrays
  | .shape r fill radius border corner shadow =>
    let b := (bool (bool (bool (b.push 5) fill.isSome) border.isSome) shadow.isSome).push
      (Corner.code corner)
    let b := color (u32 (u32 (color (rect (pad b 3) r) (fill.getD Enc.noColor)) radius)
      (border.elim 0 (·.width))) (border.elim Enc.noColor (·.color))
    i32 (i32 (u32 (color b (shadow.elim Enc.noColor (·.color))) (shadow.elim 0 (·.radius)))
      (shadow.elim 0 (·.x))) (shadow.elim 0 (·.y))
  | .image r d src => str (rect (rect (pad (b.push 6) 3) r) d) src

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

def header1 (b : ByteArray) (kv : String × String) : ByteArray := str (str b kv.1) kv.2

def headers (b : ByteArray) (hs : List (String × String)) : ByteArray :=
  hs.foldl header1 (u32 b hs.length)

def part (b : ByteArray) : Part → ByteArray
  | .bytes d => bytes (pad (b.push 0) 3) d
  | .wav c st sp => u32 (u32 (u32 (pad (bool (b.push 1) sp.isSome) 2) c) st) (sp.getD 0)

def parts (b : ByteArray) (ps : List Part) : ByteArray := ps.foldl part (u32 b ps.length)

def secret (b : ByteArray) (s : Secret) : ByteArray := str (str (str (str b s.header) s.scheme) s.file) s.name

def optSecret (b : ByteArray) : Option Secret → ByteArray
  | none => pad (b.push 0) 3
  | some s => secret (pad (b.push 1) 3) s

def requestBody (b : ByteArray) : Request → ByteArray
  | .readFile p => str b p
  | .writeFile p d => bytes (str b p) d
  | .playSound n => str b n
  | .http m u hs body t => bytes (headers (str (str (u32 b t) m) u) hs) body
  | .appendFile p d => bytes (str b p) d
  | .listDir p | .deleteFile p | .makeDir p => str b p
  | .frontmostApp => b
  | .permission p prompt => pad (bool (b.push (Permission.code p)) prompt) 2
  | .typeText pid t r => str (pad (bool (u32 b pid) r) 3) t
  | .upload m u hs sec body t =>
    parts (optSecret (headers (str (str (u32 b t) m) u) hs) sec) body
  | .forgetClip c => u32 b c
  | .openItem t | .appRunning t => str b t
  | .readDefault d k => str (str b d) k
  | .loadImage src reload => str (pad (bool b reload) 3) src

def effect (b : ByteArray) : Effect → ByteArray
  | .setClipboard s => str (pad (b.push 0) 3) s
  | .beep => pad (b.push 1) 3
  | .focus c => ref (pad (b.push 2) 3) c
  | .setTimer n ms => str (u32 (pad (b.push 3) 3) ms) n
  | .cancelTimer n => str (pad (b.push 4) 3) n
  | .request id r => requestBody (u32 (pad ((b.push 5).push (Request.Kind.code r.kind)) 2) id) r
  | .quit => pad (b.push 6) 3

def subBody (b : ByteArray) : Sub → ByteArray
  | .every ms => u32 b ms
  | .watchFile p => str b p
  | .record c => u32 b c
  | .globalKey code m => u32 (pad (bool (u32 b code) m.isSome) 3) (m.getD 0)

def subCmd (b : ByteArray) : SubCmd → ByteArray
  | .start id s => subBody (u32 (pad ((b.push 0).push (Sub.code s)) 2) id) s
  | .stop id => u32 (pad (b.push 1) 3) id

def wake (b : ByteArray) (w : Option Nat) : ByteArray := u64 (pad (bool b w.isSome) 3) (w.getD 0)

def list {α : Type} (put : ByteArray → α → ByteArray) (len : α → Nat) (b : ByteArray)
    (xs : Array α) : ByteArray :=
  xs.foldl put (u32 (u32 b xs.size) (Len.list len xs))

def canvas (b : ByteArray) (c : Canvas) : ByteArray :=
  let b := list draw Len.draw (i32 (i32 b c.size.w) c.size.h) c.draws
  let b := list ax Len.ax b c.ax
  cursor (textInput b c.textInput) c.cursor

def menuRecord (b : ByteArray) (m : MenuRecord) : ByteArray :=
  let sc := m.shortcut.getD noShortcut
  let b := bool (b.push (MenuKind.code m.kind)) m.enabled
  let b := bool (b.push (checkedCode m.checked)) m.shortcut.isSome
  let b := bool (bool (bool b m.control.isSome) m.parent.isSome) m.place.isSome
  let b := ref (b.push (Key.code sc.key)) (m.control.getD ⟨0, 0⟩)
  let b := u32 (u32 (u32 b (m.parent.getD 0)) (m.place.getD 0)) (Key.scalar sc.key)
  str (pad (b.push (Mods.code sc.mods)) 3) m.label

def status (b : ByteArray) (s : StatusFrame) : ByteArray :=
  list menuRecord Len.menuRecord (str (str (str (ref b s.control) s.symbol) s.title) s.label) s.menu

def surface (b : ByteArray) (s : SurfaceFrame) : ByteArray :=
  let b := ((bool (b.push (SurfaceKind.code s.kind)) s.shown).push (Anchor.code s.anchor)).push
    (ScreenChoice.code s.screen)
  let b := str (u32 (u32 b s.place) s.anchor.offset) s.title
  status (canvas b s.canvas) s.status

def frame (f : Frame) : ByteArray :=
  let cap := 8 + (8 + Len.list Len.surface f.surfaces) + (8 + Len.list Len.effect f.effects) +
    (8 + Len.list Len.subCmd f.subs) + 12
  let b := (ByteArray.emptyWithCapacity cap).append ⟨Enc.header.toArray⟩
  let b := list surface Len.surface b f.surfaces
  let b := list effect Len.effect b f.effects
  wake (list subCmd Len.subCmd b f.subs) f.wake

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

theorem foldl_data' {α : Type} (put : ByteArray → α → ByteArray) (e : α → List UInt8)
    (h : ∀ b x, (put b x).data.toList = b.data.toList ++ e x) (xs : List α) (b : ByteArray) :
    (xs.foldl put b).data.toList = b.data.toList ++ xs.flatMap e := by
  induction xs generalizing b with
  | nil => simp only [List.foldl_nil, List.flatMap_nil, List.append_nil]
  | cons x xs ih => simp only [List.foldl_cons, ih, h, List.append_assoc, List.flatMap_cons]

@[simp] theorem ints_data (b : ByteArray) (xs : List Int) :
    (ints b xs).data.toList = b.data.toList ++ Enc.ints xs := by
  simp only [ints, foldl_data' i32 Enc.i32 i32_data, u32_data, List.append_assoc, Enc.ints]

@[simp] theorem intLists_data (b : ByteArray) (xss : List (List Int)) :
    (intLists b xss).data.toList = b.data.toList ++ Enc.intLists xss := by
  simp only [intLists, foldl_data' ints Enc.ints ints_data, u32_data, List.append_assoc,
      Enc.intLists]

@[simp] theorem draw_data (b : ByteArray) (d : Draw) :
    (draw b d).data.toList = b.data.toList ++ Enc.draw d := by
  cases d <;> simp only [draw, ints_data, intLists_data, u64_data, i32_data, color_data, u32_data, rect_data, pad_data, bool_data,
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

@[simp] theorem header1_data (b : ByteArray) (kv : String × String) :
    (header1 b kv).data.toList = b.data.toList ++ Enc.header1 kv := by
  simp only [header1, str_data, List.append_assoc, Enc.header1]

@[simp] theorem headers_data (b : ByteArray) (hs : List (String × String)) :
    (headers b hs).data.toList = b.data.toList ++ Enc.headers hs := by
  simp only [headers, foldl_data' header1 Enc.header1 header1_data, u32_data, List.append_assoc,
      Enc.headers]

@[simp] theorem part_data (b : ByteArray) (p : Part) :
    (part b p).data.toList = b.data.toList ++ Enc.part p := by
  cases p <;> simp only [part, bytes_data, u32_data, pad_data, bool_data, ByteArray.data_push,
      Array.toList_push, List.append_assoc, List.cons_append, List.nil_append, Enc.part]

@[simp] theorem parts_data (b : ByteArray) (ps : List Part) :
    (parts b ps).data.toList = b.data.toList ++ Enc.parts ps := by
  simp only [parts, foldl_data' part Enc.part part_data, u32_data, List.append_assoc, Enc.parts]

@[simp] theorem secret_data (b : ByteArray) (s : Secret) :
    (secret b s).data.toList = b.data.toList ++ Enc.secret s := by
  simp only [secret, str_data, List.append_assoc, Enc.secret]

@[simp] theorem optSecret_data (b : ByteArray) (s : Option Secret) :
    (optSecret b s).data.toList = b.data.toList ++ Enc.optSecret s := by
  cases s <;> simp only [optSecret, secret_data, pad_data, ByteArray.data_push, Array.toList_push,
      List.append_assoc, List.cons_append, List.nil_append, Enc.optSecret]

@[simp] theorem requestBody_data (b : ByteArray) (r : Request) :
    (requestBody b r).data.toList = b.data.toList ++ Enc.requestBody r := by
  cases r <;> simp only [requestBody, str_data, bytes_data, headers_data, u32_data,
      List.append_assoc, Enc.requestBody, List.append_nil, pad_data, bool_data,
      ByteArray.data_push, Array.toList_push, List.cons_append, List.nil_append, parts_data,
      optSecret_data]

@[simp] theorem subCmd_data (b : ByteArray) (c : SubCmd) :
    (subCmd b c).data.toList = b.data.toList ++ Enc.subCmd c := by
  rcases c with ⟨_, ⟨_⟩ | ⟨_⟩ | ⟨_⟩ | ⟨_, _⟩⟩ | _ <;> simp only [subCmd, subBody, u32_data, str_data,
      pad_data, bool_data, ByteArray.data_push, Array.toList_push, List.append_assoc,
      List.cons_append, List.nil_append, Enc.subCmd, Enc.subBody]

@[simp] theorem wake_data (b : ByteArray) (w : Option Nat) :
    (wake b w).data.toList = b.data.toList ++ Enc.wake w := by
  simp only [wake, u64_data, pad_data, bool_data, List.append_assoc, Enc.wake]

@[simp] theorem effect_data (b : ByteArray) (e : Effect) :
    (effect b e).data.toList = b.data.toList ++ Enc.effect e := by
  cases e <;> simp only [effect, str_data, u32_data, requestBody_data, pad_data, ByteArray.data_push, Array.toList_push,
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

@[simp] theorem canvas_data (b : ByteArray) (c : Canvas) :
    (canvas b c).data.toList = b.data.toList ++ Enc.canvas c := by
  simp only [canvas, cursor_data, textInput_data, list_data _ _ _ ax_data Len.ax_eq,
    list_data _ _ _ draw_data Len.draw_eq, i32_data, List.append_assoc, Enc.canvas, Enc.size]

@[simp] theorem menuRecord_data (b : ByteArray) (m : MenuRecord) :
    (menuRecord b m).data.toList = b.data.toList ++ Enc.menuRecord m := by
  simp only [menuRecord, str_data, pad_data, u32_data, ref_data, bool_data, ByteArray.data_push,
    Array.toList_push, List.append_assoc, List.cons_append, List.nil_append, Enc.menuRecord]

@[simp] theorem status_data (b : ByteArray) (s : StatusFrame) :
    (status b s).data.toList = b.data.toList ++ Enc.status s := by
  simp only [status, list_data _ _ _ menuRecord_data Len.menuRecord_eq, str_data, ref_data,
    List.append_assoc, Enc.status]

@[simp] theorem surface_data (b : ByteArray) (s : SurfaceFrame) :
    (surface b s).data.toList = b.data.toList ++ Enc.surface s := by
  simp only [surface, status_data, canvas_data, str_data, u32_data, bool_data,
    ByteArray.data_push, Array.toList_push, List.append_assoc, List.cons_append, List.nil_append,
    Enc.surface]

theorem frame_data (f : Frame) : (frame f).data.toList = Enc.frame f := by
  have hempty : (ByteArray.emptyWithCapacity 0).data.toList = [] := rfl
  simp only [frame, Enc.frame]
  rw [wake_data, list_data _ _ _ subCmd_data Len.subCmd_eq,
    list_data _ _ _ effect_data Len.effect_eq, list_data _ _ _ surface_data Len.surface_eq]
  simp only [ByteArray.append_eq, ByteArray.data_append, Array.toList_append,
      List.append_assoc, List.append_left_eq_self, Array.toList_eq_nil_iff]
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

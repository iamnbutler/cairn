import Cairn.Fuzz.Rng
import Cairn.Frame.Encode
import Cairn.Frame.Events

/-! # Generators for the trusted-base fuzzer

Random frames for differential fuzzing of the Swift frame decoder (docs/fuzz.md, "Trusted
base"). Built on workstream L's SplitMix64 (`Cairn.Fuzz.Gen`), so a seed replays exactly.

Every generated frame fits the wire (`fitsFrame`): integers are drawn inside `i32`/`u32`, with a
bias toward the edges (0, ±1, the extremes), because that is where a hand-written decoder slips.
Strings lean on what breaks text code: astral scalars (surrogate pairs in UTF-16), the last
scalar before and after the surrogate block, U+10FFFF, NUL, combining marks, ZWJ sequences, skin
tones, flags, CJK, right-to-left scripts, line breaks and the BOM. -/

namespace Cairn.Fuzz.Trusted
open Cairn Cairn.Fuzz

/-- Scalars at the edges of UTF-8 and UTF-16 encodings, and ones text code mishandles. -/
def edgeScalars : Array Nat :=
  #[0x0, 0x9, 0xA, 0xD, 0x1F, 0x20, 0x22, 0x5C, 0x7E, 0x7F, 0x80, 0xFF, 0x100, 0x7FF, 0x800,
    0x301, 0x200D, 0x200E, 0x200F, 0x2028, 0x2029, 0xFE0F, 0xFEFF, 0xD7FF, 0xE000, 0xFFFD, 0xFFFE,
    0xFFFF, 0x10000, 0x1F3FB, 0x1F3FF, 0x1F600, 0x1F1EB, 0x1F1F7, 0xE0067, 0x10FFFF, 0x5D0,
    0x627, 0x65E5, 0xD55C, 0x30A2, 0x0E01, 0x0915, 0x094D]

/-- Whole strings that are hard to measure or index: ZWJ families, skin tones, flags, combining
stacks, mixed bidi. -/
def edgeStrings : Array String :=
  #["", "a", "👍🏽", "👨‍👩‍👧", "👩🏽‍💻", "🇫🇷", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "é", "ä́", "Z̤̈", "日本語", "한국어", "אבג", "عربي",
    "abאבc", "क्षि", "\uFEFFbom", "tab\there", "a\nb", "\r\n", "x" ++ String.singleton (Char.ofNat 0x10FFFF) ++ "y", "\x00", "😀😀",
    "Hello, world", "  padded  "]

def scalar : Gen Char := do
  let n ← Gen.weighted
    [ (6, Gen.range 0x20 0x7E),
      (3, do return (← Gen.elem edgeScalars.toList)),
      (1, Gen.range 0x80 0xD7FF),
      (1, Gen.range 0xE000 0xFFFF),
      (1, Gen.range 0x10000 0x10FFFF) ]
  return Char.ofNat n

def str : Gen String := do
  Gen.weighted
    [ (2, pure ""),
      (3, do return (← Gen.elem edgeStrings.toList)),
      (6, do
        let n ← Gen.below 12
        let mut s := ""
        for _ in [0:n] do
          if ← Gen.chance 1 5 then s := s ++ (← Gen.elem edgeStrings.toList)
          else s := s.push (← scalar)
        return s),
      (1, do return String.ofList (List.replicate (← Gen.range 50 400) (← scalar))) ]

def i32 : Gen Int :=
  Gen.weighted
    [ (1, do return (← Gen.elem [-2147483648, 2147483647, 0, -1, 1, -2147483647, 2147483646])),
      (4, Gen.int (-2000) 4000),
      (1, Gen.int (-2147483648) 2147483647) ]

def u32 : Gen Nat :=
  Gen.weighted
    [ (1, do return (← Gen.elem [0, 1, 4294967295, 4294967294, 65535, 65536, 2147483648])),
      (4, Gen.below 2000),
      (1, Gen.below 4294967296) ]

def byte : Gen UInt8 := do return (← Gen.below 256).toUInt8
def opt {α : Type} (g : Gen α) : Gen (Option α) := do
  if ← Gen.bool then return some (← g) else return none

def rect : Gen Rect := do return ⟨← i32, ← i32, ← i32, ← i32⟩
def color : Gen Color := do return ⟨← byte, ← byte, ← byte, ← byte⟩
def ref : Gen ControlRef := do return ⟨← u32, ← u32⟩
def range : Gen (Nat × Nat) := do return (← u32, ← u32)

def font : Gen Font := do
  return ⟨← Gen.elem [0, 1, 2, 4294967295], ← Gen.elem [0, 1, 9, 13, 17, 24, 1024, 4294967295],
    ← Gen.elem [0, 100, 400, 700, 900, 4294967295], ← Gen.bool,
    ← Gen.elem [FontWidth.standard, .condensed, .expanded, .compressed],
    ← Gen.elem [0, 140, -50, 2147483647, -2147483648], ← Gen.bool⟩

def ints : Gen (List Int) := do
  let n ← Gen.below 5
  (List.range n).mapM fun _ => i32

def draw : Gen Draw := do
  match ← Gen.below 7 with
  | 0 => return .rect (← rect) (← opt color) (← u32) (← opt (do return ⟨← u32, ← color⟩))
  | 1 => return .text ⟨← i32, ← i32⟩ (← font) (← color) (← str)
  | 2 => return .pushClip (← rect)
  | 3 =>
    let r ← rect
    let fill ← opt color
    let radius ← u32
    let border ← opt (do return ⟨← u32, ← color⟩)
    let corner ← Gen.elem [Corner.circular, Corner.continuous]
    let shadow ← opt (do return (⟨← color, ← u32, ← i32, ← i32⟩ : Shadow))
    return .shape r fill radius border corner shadow
  | 4 =>
    let k ← Gen.below 3
    let r ← rect
    let shader ← str
    let origin ← Gen.elem [0, 1, 4294967296, 18446744073709551615]
    let scalars ← ints
    let arrays ← (List.range k).mapM fun _ => ints
    return .paint r { shader, origin, scalars, arrays }
  | 5 => return .image (← rect) (← rect) (← str)
  | _ => return .popClip

def role : Gen Role :=
  Gen.elem [.group, .button, .checkbox, .text, .textField, .link, .list, .listItem, .heading, .tab]

def axNode : Gen AxNode := do
  return { control := ← opt ref, role := ← role, rect := ← rect, label := ← str, value := ← str,
           parent := ← opt u32, focused := ← Gen.bool, selected := ← Gen.bool,
           checked := ← opt Gen.bool }

def textInput : Gen TextInput := do
  return { control := ← ref, rect := ← rect, caret := ← rect, text := ← str,
           selection := ← range, marked := ← opt range, textOrigin := ⟨← i32, ← i32⟩ }

def array {α : Type} (n : Nat) (g : Gen α) : Gen (Array α) := do
  let k ← Gen.below (n + 1)
  let mut xs := #[]
  for _ in [0:k] do xs := xs.push (← g)
  return xs

/-- A `u64`, edges first: around 2³² (where the two words split) and the top. -/
def u64 : Gen Nat :=
  Gen.weighted [
    (1, Gen.elem [0, 1, 4294967295, 4294967296, 4294967297, 18446744073709551615,
      9223372036854775807, 9223372036854775808]),
    (3, do return (← Gen.below 4294967296) + 4294967296 * (← Gen.below 4294967296))]

def bytes : Gen ByteArray := do
  let n ← Gen.weighted [(4, Gen.below 8), (1, Gen.below 300)]
  let mut b := ByteArray.empty
  for _ in [0:n] do b := b.push (← byte)
  return b

def headers : Gen (List (String × String)) := do return (← array 3 (do return (← str, ← str))).toList

def part : Gen Part := do
  if ← Gen.chance 1 2 then return .bytes (← bytes)
  else return .wav (← u32) (← u32) (← opt u32)

def secret : Gen Secret := do
  let h ← str
  let sc ← str
  if ← Gen.chance 1 2 then return ⟨h, sc, .env (← str) (← str)⟩
  else return ⟨h, sc, .keychain (← str)⟩

def request : Gen Request := do
  match ← Gen.below 18 with
  | 0 => return .readFile (← str)
  | 1 => return .writeFile (← str) (← bytes)
  | 2 => return .playSound (← str)
  | 3 => return .appendFile (← str) (← bytes)
  | 4 => return .listDir (← str)
  | 5 => return .deleteFile (← str)
  | 6 => return .frontmostApp
  | 7 => return .permission (← Gen.elem [.accessibility, .microphone]) (← Gen.chance 1 2)
  | 8 => return .typeText (← u32) (← str) (← Gen.chance 1 2)
  | 9 => return .upload (← str) (← str) (← headers) (← opt secret) (← array 4 part).toList (← u32)
  | 10 => return .forgetClip (← u32)
  | 11 => return .openItem (← str)
  | 12 => return .appRunning (← str)
  | 13 => return .readDefault (← str) (← str)
  | 14 => return .makeDir (← str)
  | 15 => return .loadImage (← str) (← Gen.chance 1 2)
  | 16 => return .forgetSecret (← str)
  | _ => return .http (← str) (← str) (← headers) (← bytes) (← u32) (← opt secret) (← headers)

def effect : Gen Effect := do
  match ← Gen.below 8 with
  | 0 => return .setClipboard (← str)
  | 1 => return .focus (← ref)
  | 2 => return .beep
  | 3 => return .setTimer (← str) (← u32)
  | 4 => return .cancelTimer (← str)
  | 5 => return .request (← u32) (← request)
  | 6 => return .cancelRequest (← u32)
  | _ => return .quit

def subCmd : Gen SubCmd := do
  match ← Gen.below 6 with
  | 0 => return .start (← u32) (.every (← u32))
  | 1 => return .start (← u32) (.watchFile (← str))
  | 2 => return .start (← u32) (.record (← u32))
  | 3 => return .start (← u32) (.globalKey (← u32) (← opt u32))
  | 4 => return .start (← u32) (.imageCache (← u64))
  | _ => return .stop (← u32)

def canvas (big : Bool) : Gen Canvas := do
  return { size := ⟨← i32, ← i32⟩, draws := ← array (if big then 200 else 12) draw,
           ax := ← array (if big then 150 else 10) axNode,
           textInput := ← opt textInput, cursor := ← Gen.elem [.arrow, .pointer, .text] }

def key : Gen Key := do
  match ← Gen.below 14 with
  | 0 => return .enter | 1 => return .escape | 2 => return .tab | 3 => return .backspace
  | 4 => return .delete | 5 => return .left | 6 => return .right | 7 => return .up
  | 8 => return .down | 9 => return .home | 10 => return .finish | 11 => return .pageUp
  | 12 => return .pageDown
  | _ => return .char (← scalar)

def mods : Gen Mods := do return ⟨← Gen.bool, ← Gen.bool, ← Gen.bool, ← Gen.bool⟩

def menuRecord : Gen MenuRecord := do
  return { kind := ← Gen.elem [.item, .info, .submenu, .separator], label := ← str,
           control := ← opt ref, place := ← opt u32, parent := ← opt u32,
           enabled := ← Gen.bool, checked := ← opt Gen.bool,
           shortcut := ← opt (do return ⟨← key, ← mods⟩) }

def status (big : Bool) : Gen StatusFrame := do
  return { control := ← ref, symbol := ← str, title := ← str, label := ← str,
           menu := ← array (if big then 60 else 8) menuRecord }

def surface (big : Bool) : Gen SurfaceFrame := do
  return { kind := ← Gen.elem [.window, .panel, .statusItem], place := ← u32, shown := ← Gen.bool,
           title := ← str, anchor := .bottomCenter (← u32), minSize := ⟨← i32, ← i32⟩,
           screen := ← Gen.elem [.pointer, .main], canvas := ← canvas big, status := ← status big }

def frame : Gen Frame := do
  let big ← Gen.chance 1 10
  return { surfaces := ← array 3 (surface big),
           effects := ← array 3 effect, subs := ← array 3 subCmd, wake := ← opt u64 }

/-- The frame for a seed. -/
def frameOf (seed : UInt64) : Frame := (frame.run (Rng.ofSeed seed.toNat)).1

end Cairn.Fuzz.Trusted

import Cairn.Frame.Build
import Cairn.Frame.Dump

/-! `lake exe framecorpus` checks the Swift side of the boundary against Lean's encoder and
decoder (docs/frame.md, "Corpus").

* `gen DIR` writes `frames/NNNN.{bin,txt}` and `events/NNNN.{bin,txt}`: deterministic
  pseudo-random frames and event batches plus edge cases, Lean's bytes and Lean's canonical dump.
  The Swift tests decode every frame and compare their dump, and parse every event dump, encode
  it and compare bytes.
* `verify DIR` decodes the `swift-events/NNNN.bin` the Swift tests wrote and compares Lean's dump
  of them with Swift's `NNNN.txt`.
* `bench DIR` times `Frame.ofLaid` and `encodeFrame` at 1,000 and 10,000 nodes and writes the
  frames to `bench/N.bin` for the Swift decode benchmark. -/

open Cairn

/-! ## A deterministic generator (SplitMix64) -/

structure Rng where
  s : UInt64

def Rng.next (g : Rng) : UInt64 × Rng :=
  let s := g.s + 0x9E3779B97F4A7C15
  let z := (s ^^^ (s >>> 30)) * 0xBF58476D1CE4E5B9
  let z := (z ^^^ (z >>> 27)) * 0x94D049BB133111EB
  (z ^^^ (z >>> 31), ⟨s⟩)

abbrev Gen := StateM Rng

def below (n : Nat) : Gen Nat := do
  let (x, g) := (← get).next
  set g
  return if n == 0 then 0 else x.toNat % n

def chance (k : Nat) : Gen Bool := return (← below k) == 0

def pick {α : Type} [Inhabited α] (xs : Array α) : Gen α := return xs[← below xs.size]!

def int : Gen Int := do
  if ← chance 6 then pick #[-2147483648, 2147483647, 0, -1, 1]
  else return (← below 20001 : Nat) - 10000

def nat : Gen Nat := do
  if ← chance 6 then pick #[0, 1, 4294967295, 65536] else below 2000

def byte : Gen UInt8 := return (← below 256).toUInt8

def coin : Gen Bool := chance 2

def charPool : Array Char :=
  #['a', 'b', 'Z', '0', ' ', '"', '\\', '\n', '\t', (Char.ofNat 0), 'é', 'ü', 'ß', 'ש', 'ا',
    '日', '本', '語', '한', 'ア', '🙂', '👍', (Char.ofNat 0x1F3FD), (Char.ofNat 0x301),
    (Char.ofNat 0xFEFF), (Char.ofNat 0x200D), (Char.ofNat 0x10FFFF), (Char.ofNat 0xE000)]

def str : Gen String := do
  if ← chance 5 then return ""
  let n ← below 14
  let mut s := ""
  for _ in [0:n] do s := s.push (← pick charPool)
  return s

def opt {α : Type} (g : Gen α) : Gen (Option α) := do
  if ← coin then return some (← g) else return none

def rect : Gen Rect := return ⟨← int, ← int, ← int, ← int⟩
def color : Gen Color := return ⟨← byte, ← byte, ← byte, ← byte⟩
def ref : Gen ControlRef := return ⟨← nat, ← nat⟩
def range : Gen (Nat × Nat) := return (← nat, ← nat)

def draw : Gen Draw := do
  match ← below 4 with
  | 0 => return .rect (← rect) (← opt color) (← nat) (← opt (return ⟨← nat, ← color⟩))
  | 1 => return .text ⟨← int, ← int⟩ ⟨← nat, ← nat, ← nat, ← coin⟩ (← color) (← str)
  | 2 => return .pushClip (← rect)
  | _ => return .popClip

def role : Gen Role :=
  pick #[.group, .button, .checkbox, .text, .textField, .link, .list, .listItem, .heading, .tab]

def axNode : Gen AxNode := do
  return { control := ← opt ref, role := ← role, rect := ← rect, label := ← str, value := ← str,
           parent := ← opt nat, focused := ← coin, selected := ← coin, checked := ← opt coin }

def textInput : Gen TextInput := do
  return { control := ← ref, rect := ← rect, caret := ← rect, text := ← str,
           selection := ← range, marked := ← opt range, textOrigin := ⟨← int, ← int⟩ }

def effect : Gen Effect := do
  if ← coin then return .setClipboard (← str) else return .beep

def array {α : Type} (n : Nat) (g : Gen α) : Gen (Array α) := do
  let k ← below (n + 1)
  let mut xs := #[]
  for _ in [0:k] do xs := xs.push (← g)
  return xs

def frame : Gen Frame := do
  return { size := ⟨← int, ← int⟩, draws := ← array 40 draw, ax := ← array 30 axNode,
           textInput := ← opt textInput, cursor := ← pick #[.arrow, .pointer, .text],
           effects := ← array 3 effect }

def mods : Gen Mods := return ⟨← coin, ← coin, ← coin, ← coin⟩

def key : Gen Key := do
  if ← chance 3 then return .char (← pick charPool)
  pick #[.enter, .escape, .tab, .backspace, .delete, .left, .right, .up, .down, .home, .finish,
    .pageUp, .pageDown]

def event : Gen Event := do
  match ← below 18 with
  | 0 => return .pointerMove ⟨← int, ← int⟩
  | 1 => return .pointerDown ⟨← int, ← int⟩ (← pick #[.primary, .secondary]) (← nat) (← mods)
  | 2 => return .pointerUp ⟨← int, ← int⟩ (← pick #[.primary, .secondary]) (← mods)
  | 3 => return .pointerExit
  | 4 => return .scroll ⟨← int, ← int⟩ (← int) (← int)
  | 5 => return .key (← key) (← mods)
  | 6 => return .insertText (← str) (← opt range)
  | 7 => return .setMarked (← str) (← nat) (← nat) (← opt range)
  | 8 => return .unmark
  | 9 => return .copy
  | 10 => return .cut
  | 11 => return .selectAll
  | 12 => return .undo
  | 13 => return .redo
  | 14 => return .paste (← str)
  | 15 => return .resize ⟨← int, ← int⟩
  | 16 => return .scale (← nat)
  | _ => return .windowFocus (← coin)

/-! ## Frames from layout -/

/-- A list of `n / 2` rows, each a button with a label: about `n` laid nodes. -/
def benchLaid (n : Nat) (w : Int) : Laid :=
  let win : Rect := ⟨0, 0, w, 600⟩
  let rows := (List.range (n / 2)).map fun (i : Nat) =>
    let r : Rect := ⟨8, 8 + 24 * i, w - 16, 20⟩
    Laid.box r win { background := some ⟨240, 240, 240, 255⟩, radius := 4 }
      (some { ref := ⟨1, i⟩, label := s!"Item {i}", role := .listItem })
      [.text ⟨16, 10 + 24 * i, 80, 16⟩ win (24 + 24 * i) {} s!"Item {i}"]
  .box win win { clip := true } none rows

def laidFrame : Frame :=
  let field : Control := { ref := ⟨2, 0⟩, role := .textField, label := "What needs to be done?" }
  let win : Rect := ⟨0, 0, 400, 300⟩
  Frame.ofLaid { focus := some ⟨2, 0⟩ } <|
    .box win win { clip := true } none [
      .field ⟨10, 10, 300, 24⟩ win { border := some ⟨1, ⟨200, 200, 200, 255⟩⟩ } {} field
        { text := "Buy 🥛 and 日本茶", caret := 4, anchor := 4, marked := some (4, 6) }
        ⟨14, 27⟩ ⟨52, 12, 1, 18⟩ [],
      benchLaid 6 400]

/-! ## Edge cases -/

def maxFrame : Frame where
  size := ⟨2147483647, -2147483648⟩
  draws := #[.rect ⟨-2147483648, 2147483647, 0, -1⟩ (some ⟨255, 255, 255, 255⟩) 4294967295
      (some ⟨4294967295, ⟨0, 0, 0, 0⟩⟩),
    .text ⟨-2147483648, 2147483647⟩ ⟨4294967295, 4294967295, 4294967295, true⟩ ⟨0, 0, 0, 0⟩
      "🙂👍🏽日本語한국어\x00",
    .pushClip ⟨0, 0, 0, 0⟩, .popClip, .popClip]
  ax := #[{ control := some ⟨4294967295, 4294967295⟩, role := .tab, rect := ⟨0, 0, 0, 0⟩,
            label := "", value := "", parent := some 4294967295, checked := some false }]
  textInput := some { control := ⟨0, 0⟩, rect := ⟨-1, -1, -1, -1⟩, caret := ⟨0, 0, 0, 0⟩,
                      text := "", selection := (4294967295, 0), marked := some (0, 4294967295),
                      textOrigin := ⟨-2147483648, 2147483647⟩ }
  cursor := .pointer
  effects := #[.setClipboard "", .beep, .setClipboard "📋"]

def emptyFrame : Frame := { size := ⟨0, 0⟩, draws := #[], ax := #[] }

def edgeEvents : Array Event := #[
  .pointerMove ⟨-2147483648, 2147483647⟩,
  .pointerDown ⟨0, 0⟩ .primary 4294967295 ⟨true, true, true, true⟩,
  .key (.char (Char.ofNat 0x10FFFF)) {}, .key (.char (Char.ofNat 0)) { option := true },
  .insertText "" none, .insertText "é" (some (0, 4294967295)),
  .setMarked "にほん" 4294967295 0 (some (2, 2)), .paste "👍🏽", .scale 0,
  .resize ⟨-1, 2147483647⟩, .windowFocus true]

/-! ## Commands -/

def pad4 (i : Nat) : String :=
  let s := toString i
  "".pushn '0' (4 - s.length) ++ s

def check (ok : Bool) (msg : String) : IO Unit :=
  unless ok do throw (IO.userError msg)

def writeFrame (dir : System.FilePath) (i : Nat) (f : Frame) : IO Unit := do
  check (Wire.fitsFrame f) s!"frame {i} does not fit"
  let b := encodeFrame f
  let some g := decodeFrame b | throw (IO.userError s!"frame {i} does not decode")
  check (Dump.frame g == Dump.frame f) s!"frame {i} does not round-trip"
  IO.FS.writeBinFile (dir / s!"{pad4 i}.bin") b
  IO.FS.writeFile (dir / s!"{pad4 i}.txt") (Dump.frame f)

def writeEvents (dir : System.FilePath) (i : Nat) (es : Array Event) : IO Unit := do
  check (es.all Wire.fitsEvent) s!"events {i} do not fit"
  let b := encodeEvents es
  check (decodeEvents b == some es) s!"events {i} do not round-trip"
  IO.FS.writeBinFile (dir / s!"{pad4 i}.bin") b
  IO.FS.writeFile (dir / s!"{pad4 i}.txt") (Dump.events es)

def gen (root : System.FilePath) (count : Nat) : IO Unit := do
  let fdir := root / "frames"
  let edir := root / "events"
  IO.FS.createDirAll fdir
  IO.FS.createDirAll edir
  let fixed := #[emptyFrame, maxFrame, laidFrame, Frame.ofLaid {} (benchLaid 40 300)]
  for h : i in [0:fixed.size] do writeFrame fdir i fixed[i]
  let mut g : Rng := ⟨0x5EED⟩
  for i in [fixed.size:count] do
    let (f, g') := frame.run g
    g := g'
    writeFrame fdir i f
  writeEvents edir 0 #[]
  writeEvents edir 1 edgeEvents
  for i in [2:count] do
    let (es, g') := (array 30 event).run g
    g := g'
    writeEvents edir i es
  IO.println s!"framecorpus: wrote {count} frames and {count} event batches to {root}"

def verify (root : System.FilePath) : IO Unit := do
  let dir := root / "swift-events"
  let entries ← dir.readDir
  let bins := entries.filter (·.path.extension == some "bin")
  check (bins.size > 0) s!"no Swift-encoded events in {dir}"
  for e in bins do
    let bytes ← IO.FS.readBinFile e.path
    let expected ← IO.FS.readFile (e.path.withExtension "txt")
    let some es := decodeEvents bytes
      | throw (IO.userError s!"{e.path}: Lean cannot decode Swift's events")
    check (Dump.events es == expected) s!"{e.path}: Lean's dump differs from Swift's"
  IO.println s!"framecorpus: Lean decoded {bins.size} Swift-encoded event batches"

def bench (root : System.FilePath) (reps : Nat := 50) : IO Unit := do
  IO.FS.createDirAll (root / "bench")
  for n in [1000, 10000] do
    let mut tBuild := 0
    let mut tEnc := 0
    let mut bytes := 0
    for i in [0:reps + 5] do
      -- The width varies so nothing is hoisted out of the loop.
      let l := benchLaid n (400 + i)
      let t0 ← IO.monoNanosNow
      let f := Frame.ofLaid {} l
      let t1 ← if f.draws.size > 0 then IO.monoNanosNow else pure 0
      let b := encodeFrame f
      let t2 ← if b.size > 0 then IO.monoNanosNow else pure 0
      if i ≥ 5 then
        tBuild := tBuild + (t1 - t0)
        tEnc := tEnc + (t2 - t1)
      bytes := b.size
      if i == 0 then IO.FS.writeBinFile (root / "bench" / s!"{n}.bin") b
    let ms (t : Nat) : Float := t.toFloat / reps.toFloat / 1000000.0
    IO.println s!"{n} nodes: ofLaid {ms tBuild} ms, encodeFrame {ms tEnc} ms, {bytes} bytes"

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["gen", dir] => gen dir 300
    | ["verify", dir] => verify dir
    | ["bench", dir] => bench dir
    | ["bench", dir, reps] => bench dir reps.toNat!
    | _ => throw (IO.userError "usage: framecorpus (gen | verify | bench) DIR")
    return 0
  catch e =>
    IO.eprintln s!"framecorpus: {e}"
    return 1

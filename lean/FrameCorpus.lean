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

def array {α : Type} (n : Nat) (g : Gen α) : Gen (Array α) := do
  let k ← below (n + 1)
  let mut xs := #[]
  for _ in [0:k] do xs := xs.push (← g)
  return xs

def u64 : Gen Nat := do
  if ← chance 4 then pick #[0, 1, 4294967295, 4294967296, 18446744073709551615]
  else return (← below 4294967296) + 4294967296 * (← below 4096)

def i64 : Gen Int := do
  if ← chance 4 then pick #[0, -1, 9223372036854775807, -9223372036854775808, 1700000000000]
  else return (← u64 : Nat) / 2 - 2251799813685248

def bytes : Gen ByteArray := do
  let n ← below 12
  let mut b := ByteArray.empty
  for _ in [0:n] do b := b.push (← byte)
  return b

def headers : Gen (List (String × String)) := do
  return (← array 3 (return (← str, ← str))).toList

def part : Gen Part := do
  if ← coin then return .bytes (← bytes) else return .wav (← nat) (← nat) (← opt nat)

def request : Gen Request := do
  match ← below 15 with
  | 0 => return .readFile (← str)
  | 1 => return .writeFile (← str) (← bytes)
  | 2 => return .playSound (← str)
  | 3 => return .appendFile (← str) (← bytes)
  | 4 => return .listDir (← str)
  | 5 => return .deleteFile (← str)
  | 6 => return .frontmostApp
  | 7 => return .permission (← pick #[.accessibility, .microphone]) (← coin)
  | 8 => return .typeText (← nat) (← str) (← coin)
  | 9 =>
    let sec ← opt (do return (⟨← str, ← str, ← str, ← str⟩ : Secret))
    return .upload (← str) (← str) (← headers) sec (← array 3 part).toList (← nat)
  | 10 => return .forgetClip (← nat)
  | 11 => return .openItem (← str)
  | 12 => return .appRunning (← str)
  | 13 => return .readDefault (← str) (← str)
  | _ => return .http (← str) (← str) (← headers) (← bytes) (← nat)

def effect : Gen Effect := do
  match ← below 7 with
  | 0 => return .setClipboard (← str)
  | 1 => return .focus (← ref)
  | 2 => return .beep
  | 3 => return .setTimer (← str) (← nat)
  | 4 => return .cancelTimer (← str)
  | 5 => return .request (← nat) (← request)
  | _ => return .quit

def subCmd : Gen SubCmd := do
  match ← below 5 with
  | 0 => return .start (← nat) (.every (← nat))
  | 1 => return .start (← nat) (.watchFile (← str))
  | 2 => return .start (← nat) (.record (← nat))
  | 3 => return .start (← nat) (.globalKey (← nat) (← opt nat))
  | _ => return .stop (← nat)

def fault : Gen Fault := pick #[.notFound, .denied, .timeout, .network, .invalid, .other]

def reply : Gen Reply := do
  match ← below 7 with
  | 0 => return .done
  | 1 => return .bytes (← bytes)
  | 2 => return .http (← nat) (← headers) (← bytes)
  | 3 => return .names (← array 4 str).toList
  | 4 => return .app (← nat) (← str)
  | 5 => return .flag (← coin)
  | _ => return .failed (← fault) (← str)

def subEvent : Gen SubEvent := do
  match ← below 7 with
  | 0 => return .tick
  | 1 => return .changed
  | 2 => return .audio (← nat) (← nat) (← array 6 (do return ⟨← u64, ← nat⟩)).toList
  | 3 => return .keyDown (← u64)
  | 4 => return .keyUp (← u64)
  | 5 => return .otherKey (← u64)
  | _ => return .failed (← fault) (← str)

def mods : Gen Mods := return ⟨← coin, ← coin, ← coin, ← coin⟩

def key : Gen Key := do
  if ← chance 3 then return .char (← pick charPool)
  pick #[.enter, .escape, .tab, .backspace, .delete, .left, .right, .up, .down, .home, .finish,
    .pageUp, .pageDown]

def canvas : Gen Canvas := do
  return { size := ⟨← int, ← int⟩, draws := ← array 40 draw, ax := ← array 30 axNode,
           textInput := ← opt textInput, cursor := ← pick #[.arrow, .pointer, .text] }

def menuRecord : Gen MenuRecord := do
  return { kind := ← pick #[.item, .info, .submenu, .separator], label := ← str,
           control := ← opt ref, place := ← opt nat, parent := ← opt nat, enabled := ← coin,
           checked := ← opt coin, shortcut := ← opt (return ⟨← key, ← mods⟩) }

def statusFrame : Gen StatusFrame := do
  return { control := ← ref, symbol := ← str, title := ← str, label := ← str,
           menu := ← array 12 menuRecord }

def surface : Gen SurfaceFrame := do
  let kind ← pick #[.window, .panel, .statusItem]
  return { kind, place := ← nat, shown := ← coin, title := ← str,
           anchor := .bottomCenter (← nat), screen := ← pick #[.pointer, .main],
           canvas := ← canvas, status := ← statusFrame }

def frame : Gen Frame := do
  return { surfaces := ← array 3 surface,
           effects := ← array 3 effect, subs := ← array 3 subCmd, wake := ← opt u64 }

def localEvent : Gen Event := do
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

def event : Gen Event := do
  match ← below 25 with
  | 21 => return .surface (← nat) (← localEvent)
  | 22 => return .menuOpen (← nat)
  | 23 => return .menuClose (← nat)
  | 24 => return .menuSelect (← nat) (← ref)
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
  | 17 => return .windowFocus (← coin)
  | 18 => return .clock ⟨← u64, ← i64, ← int⟩
  | 19 => return .reply (← nat) (← reply)
  | _ => return .subEvent (← nat) (← subEvent)

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
  Frame.single <| Frame.ofLaid { focus := some ⟨2, 0⟩ } <|
    .box win win { clip := true } none [
      .field ⟨10, 10, 300, 24⟩ win { border := some ⟨1, ⟨200, 200, 200, 255⟩⟩ } {} field
        { text := "Buy 🥛 and 日本茶", caret := 4, anchor := 4, marked := some (4, 6) }
        ⟨14, 27⟩ ⟨52, 12, 1, 18⟩ [],
      benchLaid 6 400]

/-! ## Edge cases -/

def maxCanvas : Canvas where
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

def maxMenu : Array MenuRecord := #[
  { kind := .submenu, label := "🙂 Recent", place := some 4294967295, parent := some 4294967295,
    enabled := true },
  { kind := .item, label := "", control := some ⟨4294967295, 4294967295⟩, parent := some 0,
    checked := some true, shortcut := some ⟨.char (Char.ofNat 0x10FFFF), ⟨true, true, true, true⟩⟩ },
  { kind := .item, label := "Off", control := some ⟨0, 0⟩, enabled := false,
    checked := some false, shortcut := some ⟨.pageDown, {}⟩ },
  { kind := .info, label := "日本語", enabled := false }, { kind := .separator, enabled := false }]

def maxFrame : Frame where
  surfaces := #[
    { kind := .window, place := 4294967295, title := "🙂\x00", canvas := maxCanvas },
    { kind := .panel, place := 0, shown := false, anchor := .bottomCenter 4294967295,
      screen := .main },
    { kind := .statusItem, place := 1,
      status := { control := ⟨4294967295, 0⟩, symbol := "waveform.circle.fill", title := "Ŷ",
                  label := "", menu := maxMenu } }]
  effects := #[.setClipboard "", .beep, .setClipboard "📋", .focus ⟨202, 7⟩,
    .setTimer "tick" 4294967295, .cancelTimer "", .quit,
    .request 4294967295 (.writeFile "~/a/🙂.txt" ⟨#[0, 255, 10]⟩),
    .request 0 (.http "GET" "https://example.com/?q=日本" [("Accept", "*/*"), ("", "")]
      ByteArray.empty 0),
    .request 1 (.appendFile "" ByteArray.empty), .request 2 (.listDir "~/日本"),
    .request 3 (.deleteFile "\x00"), .request 4 .frontmostApp,
    .request 5 (.permission .microphone true), .request 6 (.typeText 4294967295 "" true),
    .request 7 (.typeText 0 "héllo 🙂\n" false), .request 8 (.forgetClip 4294967295),
    .request 9 (.upload "POST" "https://api.openai.com/v1/audio/transcriptions" []
      (some ⟨"Authorization", "Bearer ", "~/.config/yap/secrets.env", "OPENAI_API_KEY"⟩)
      [.bytes ⟨#[45, 45]⟩, .wav 4294967295 0 none, .wav 0 4294967295 (some 4294967295),
       .bytes ByteArray.empty] 4294967295),
    .request 10 (.upload "" "" [("", "")] none [] 0),
    .request 11 (.openItem "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
    .request 12 (.appRunning ""), .request 13 (.readDefault "dev.yap.Yap" "日本🙂")]
  subs := #[.start 4294967295 (.every 0), .stop 0, .start 1 (.watchFile "~/a 🙂.json"),
    .start 2 (.record 4294967295), .start 3 (.globalKey 63 none), .start 4 (.globalKey 0 (some 4294967295))]
  wake := some 18446744073709551615

def emptyFrame : Frame := { surfaces := #[] }

def edgeEvents : Array Event := #[
  .pointerMove ⟨-2147483648, 2147483647⟩,
  .pointerDown ⟨0, 0⟩ .primary 4294967295 ⟨true, true, true, true⟩,
  .key (.char (Char.ofNat 0x10FFFF)) {}, .key (.char (Char.ofNat 0)) { option := true },
  .insertText "" none, .insertText "é" (some (0, 4294967295)),
  .setMarked "にほん" 4294967295 0 (some (2, 2)), .paste "👍🏽", .scale 0,
  .resize ⟨-1, 2147483647⟩, .windowFocus true,
  .clock ⟨18446744073709551615, -9223372036854775808, -2147483648⟩, .clock ⟨0, 9223372036854775807, 0⟩,
  .reply 0 .done, .reply 4294967295 (.bytes ⟨#[0, 255]⟩),
  .reply 1 (.http 4294967295 [("Content-Type", "text/plain; charset=utf-8")] ⟨#[104, 105]⟩),
  .reply 2 (.failed .other "é"), .subEvent 4294967295 .tick,
  .reply 3 (.names []), .reply 4 (.names ["", "2026-10-23.jsonl", "🙂"]),
  .reply 5 (.app 4294967295 "Terminal"), .reply 6 (.app 0 ""), .reply 7 (.flag true),
  .reply 8 (.flag false), .subEvent 0 .changed,
  .subEvent 1 (.audio 4294967295 32768 [⟨18446744073709551615, 32767⟩, ⟨0, 0⟩]),
  .subEvent 2 (.audio 0 0 []), .subEvent 3 (.keyDown 18446744073709551615), .subEvent 4 (.keyUp 0),
  .subEvent 5 (.otherKey 1), .subEvent 6 (.failed .denied "Accessibility"),
  .subEvent 7 (.failed .other ""),
  .surface 4294967295 (.key (.char 'q') { command := true }), .surface 0 .pointerExit,
  .menuOpen 4294967295, .menuClose 0, .menuSelect 450 ⟨4294967295, 4294967295⟩]

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
  let fixed := #[emptyFrame, maxFrame, laidFrame, Frame.single (Frame.ofLaid {} (benchLaid 40 300))]
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
      let f := Frame.single (Frame.ofLaid {} l)
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

/-- What one second of recording costs Lean to read: 25 event batches of one `audio` event each,
640 samples (two 20 ms windows) per batch, as the host sends at 50 windows a second. -/
def benchAudio (seconds : Nat := 2000) : IO Unit := do
  let batch (i : Nat) : ByteArray := encodeEvents #[.subEvent 3 (.audio 640 (9000 + i % 7)
    [⟨123456789 + i, 9000 + i % 5⟩, ⟨987654321 + i, 8000 + i % 3⟩])]
  let batches := (List.range 25).toArray.map batch
  let bytes := batches.foldl (fun n b => n + b.size) 0
  let mut windows := 0
  let t0 ← IO.monoNanosNow
  for s in [0:seconds] do
    for b in batches do
      match decodeEvents b with
      | some #[.subEvent _ (.audio _ _ ws)] => windows := windows + ws.length + s % 1
      | _ => throw (IO.userError "audio batch did not decode")
  let t1 ← IO.monoNanosNow
  let perSecond := (t1 - t0).toFloat / seconds.toFloat / 1000.0
  IO.println s!"audio: {bytes} bytes per second of recording in 25 batches; Lean decodes them in {perSecond} µs ({windows} windows checked)"

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["gen", dir] => gen dir 300
    | ["verify", dir] => verify dir
    | ["bench", dir] => bench dir
    | ["bench", dir, reps] => bench dir reps.toNat!
    | ["bench-audio"] => benchAudio
    | _ => throw (IO.userError "usage: framecorpus (gen | verify | bench) DIR")
    return 0
  catch e =>
    IO.eprintln s!"framecorpus: {e}"
    return 1

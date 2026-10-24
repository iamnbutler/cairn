import Cairn.Frame.Events

/-! A canonical text dump of frames and events (docs/frame.md, "Canonical dump"). The Swift
decoder's tests print the same format and compare it line for line with Lean's, and it is a
readable form for the debug socket. Strings print printable ASCII as itself and every other
Unicode scalar, `"` and `\` as `\u{HEX}`. -/

namespace Cairn.Dump

open Wire

def hexDigits (n : Nat) : String :=
  if n < 16 then String.singleton (Nat.digitChar n) else hexDigits (n / 16) ++ String.singleton (Nat.digitChar (n % 16))
termination_by n
decreasing_by omega

def str (s : String) : String :=
  "\"" ++ s.foldl (fun acc c =>
    let n := c.toNat
    if 0x20 ≤ n && n ≤ 0x7e && c != '"' && c != '\\' then acc.push c
    else acc ++ "\\u{" ++ (hexDigits n).toUpper ++ "}") "" ++ "\""

def rect (r : Rect) : String := s!"{r.x} {r.y} {r.w} {r.h}"
def color (c : Color) : String := s!"{c.r},{c.g},{c.b},{c.a}"
def ref (c : ControlRef) : String := s!"{c.claim}#{c.key}"
def opt {α : Type} (f : α → String) : Option α → String
  | some a => f a
  | none => "none"
def range (p : Nat × Nat) : String := s!"{p.1} {p.2}"
def bit (b : Bool) : String := if b then "1" else "0"

def draw : Draw → String
  | .rect r fill radius border =>
    s!"rect {rect r} fill={opt color fill} radius={radius} border=" ++
      opt (fun b => s!"{b.width}:{color b.color}") border
  | .text o f c s =>
    s!"text {o.x} {o.y} font={f.family},{f.size},{f.weight},{bit f.italic} color={color c} {str s}"
  | .pushClip r => s!"push {rect r}"
  | .popClip => "pop"

def ax (n : AxNode) : String :=
  s!"node role={Role.code n.role} control={opt ref n.control} parent={opt toString n.parent} " ++
    s!"rect={rect n.rect} focused={bit n.focused} selected={bit n.selected} " ++
    s!"checked={opt bit n.checked} label={str n.label} value={str n.value}"

def textInput : Option TextInput → String
  | none => "textInput none"
  | some t =>
    s!"textInput control={ref t.control} rect={rect t.rect} caret={rect t.caret} " ++
      s!"selection={range t.selection} marked={opt range t.marked} " ++
      s!"origin={t.textOrigin.x} {t.textOrigin.y} text={str t.text}"

/-- Bytes as `x` and two lowercase hex digits each. -/
def bytes (b : ByteArray) : String :=
  b.foldl (fun acc x => acc ++ (if x < 16 then "0" else "") ++ hexDigits x.toNat) "x"

def headers (hs : List (String × String)) : String :=
  s!"headers={hs.length}" ++ hs.foldl (fun acc (k, v) => acc ++ s!" {str k} {str v}") ""

def part : Part → String
  | .bytes b => s!"bytes {bytes b}"
  | .wav c st sp => s!"wav {c} {st} {opt toString sp}"

def secret (s : Secret) : String := s!"{str s.header} {str s.scheme} {str s.file} {str s.name}"

def request : Request → String
  | .readFile p => s!"readFile {str p}"
  | .writeFile p d => s!"writeFile {str p} {bytes d}"
  | .playSound n => s!"sound {str n}"
  | .http m u hs b t => s!"http {str m} {str u} timeout={t} {headers hs} body={bytes b}"
  | .appendFile p d => s!"appendFile {str p} {bytes d}"
  | .listDir p => s!"listDir {str p}"
  | .deleteFile p => s!"deleteFile {str p}"
  | .frontmostApp => "frontmostApp"
  | .permission p prompt => s!"permission {Permission.code p} {bit prompt}"
  | .typeText pid t r => s!"typeText {pid} {bit r} {str t}"
  | .upload m u hs sec body t =>
    s!"upload {str m} {str u} timeout={t} {headers hs} secret={opt secret sec} parts={body.length}" ++
      body.foldl (fun acc p => acc ++ s!" {part p}") ""
  | .forgetClip c => s!"forgetClip {c}"
  | .openItem t => s!"open {str t}"
  | .appRunning b => s!"appRunning {str b}"
  | .readDefault d k => s!"readDefault {str d} {str k}"
  | .makeDir p => s!"makeDir {str p}"

def effect : Effect → String
  | .setClipboard s => s!"clipboard {str s}"
  | .beep => "beep"
  | .focus c => s!"focus {ref c}"
  | .setTimer n ms => s!"timer {str n} {ms}"
  | .cancelTimer n => s!"cancelTimer {str n}"
  | .request id r => s!"request {id} {request r}"
  | .quit => "quit"

def subCmd : SubCmd → String
  | .start id (.every ms) => s!"start {id} every {ms}"
  | .start id (.watchFile p) => s!"start {id} watchFile {str p}"
  | .start id (.record c) => s!"start {id} record {c}"
  | .start id (.globalKey code m) => s!"start {id} globalKey {code} {opt toString m}"
  | .stop id => s!"stop {id}"

def reply : Reply → String
  | .done => "done"
  | .bytes d => s!"bytes {bytes d}"
  | .http st hs b => s!"http {st} {headers hs} body={bytes b}"
  | .failed f m => s!"failed {Fault.code f} {str m}"
  | .names ns => s!"names {ns.length}" ++ ns.foldl (fun acc n => acc ++ s!" {str n}") ""
  | .app pid n => s!"app {pid} {str n}"
  | .flag b => s!"flag {bit b}"

def canvas (c : Canvas) : String := Id.run do
  let mut out := s!"canvas {c.size.w} {c.size.h}\ndraws {c.draws.size}\n"
  for d in c.draws do out := out ++ draw d ++ "\n"
  out := out ++ s!"ax {c.ax.size}\n"
  for n in c.ax do out := out ++ ax n ++ "\n"
  out := out ++ textInput c.textInput ++ "\n"
  out := out ++ s!"cursor {Cursor.code c.cursor}\n"
  return out

def shortcut (s : Shortcut) : String := s!"{Key.code s.key},{Key.scalar s.key},{Mods.code s.mods}"

def menuRecord (m : MenuRecord) : String :=
  s!"item kind={MenuKind.code m.kind} control={opt ref m.control} parent={opt toString m.parent} " ++
    s!"place={opt toString m.place} enabled={bit m.enabled} checked={opt bit m.checked} " ++
    s!"shortcut={opt shortcut m.shortcut} label={str m.label}"

def status (s : StatusFrame) : String := Id.run do
  let mut out := s!"status control={ref s.control} symbol={str s.symbol} title={str s.title} " ++
    s!"label={str s.label}\nmenu {s.menu.size}\n"
  for m in s.menu do out := out ++ menuRecord m ++ "\n"
  return out

def surface (s : SurfaceFrame) : String :=
  s!"surface kind={SurfaceKind.code s.kind} place={s.place} shown={bit s.shown} " ++
    s!"anchor={Anchor.code s.anchor} offset={s.anchor.offset} screen={ScreenChoice.code s.screen} " ++
    s!"title={str s.title}\n" ++ canvas s.canvas ++ status s.status

/-- One line per item, each ending in a newline. -/
def frame (f : Frame) : String := Id.run do
  let mut out := s!"frame\nsurfaces {f.surfaces.size}\n"
  for x in f.surfaces do out := out ++ surface x
  out := out ++ s!"effects {f.effects.size}\n"
  for e in f.effects do out := out ++ effect e ++ "\n"
  out := out ++ s!"subs {f.subs.size}\n"
  for c in f.subs do out := out ++ subCmd c ++ "\n"
  out := out ++ s!"wake {opt toString f.wake}\n"
  return out

def subEvent : SubEvent → String
  | .tick => "0"
  | .changed => "1"
  | .audio n pk ws =>
    s!"2 {n} {pk} {ws.length}" ++ ws.foldl (fun acc l => acc ++ s!" {l.sumSq}:{l.peak}") ""
  | .keyDown t => s!"3 {t}"
  | .keyUp t => s!"4 {t}"
  | .otherKey t => s!"5 {t}"
  | .failed f m => s!"6 {Fault.code f} {str m}"

def event : Event → String
  | .surface p e => s!"surface {p} " ++ event e
  | .menuOpen p => s!"menuOpen {p}"
  | .menuClose p => s!"menuClose {p}"
  | .menuSelect p r => s!"menuSelect {p} {ref r}"
  | .pointerMove p => s!"move {p.x} {p.y}"
  | .pointerDown p b clicks m => s!"down {p.x} {p.y} {Button.code b} {clicks} {Mods.code m}"
  | .pointerUp p b m => s!"up {p.x} {p.y} {Button.code b} {Mods.code m}"
  | .pointerExit => "exit"
  | .scroll p dx dy => s!"scroll {p.x} {p.y} {dx} {dy}"
  | .key k m => s!"key {Key.code k} {Key.scalar k} {Mods.code m}"
  | .insertText s rep => s!"insert {str s} replace={opt range rep}"
  | .setMarked s a l rep => s!"marked {str s} {a} {l} replace={opt range rep}"
  | .unmark => "unmark"
  | .copy => "copy"
  | .cut => "cut"
  | .selectAll => "selectAll"
  | .undo => "undo"
  | .redo => "redo"
  | .paste s => s!"paste {str s}"
  | .resize sz => s!"resize {sz.w} {sz.h}"
  | .scale p => s!"scale {p}"
  | .windowFocus b => s!"focus {bit b}"
  | .clock t => s!"clock {t.mono} {t.wall} {t.zone}"
  | .reply id r => s!"reply {id} {reply r}"
  | .subEvent id e => s!"sub {id} {subEvent e}"

def events (es : Array Event) : String := Id.run do
  let mut out := s!"events {es.size}\n"
  for e in es do out := out ++ event e ++ "\n"
  return out

#guard str "a\"é🙂\\" == "\"a\\u{22}\\u{E9}\\u{1F642}\\u{5C}\""

end Cairn.Dump

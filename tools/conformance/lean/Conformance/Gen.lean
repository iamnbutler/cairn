module

public import Cairn.Claims.Core
public import Cairn.Runtime.Abi
public import Cairn.Abi

/-! # The conformance generator (docs/conformance.md)

Walks an app's model and writes move sequences for the conformance driver
(`tools/conformance/driver.ts`). Each sequence starts from the app's initial state. At every step
the generator looks at the model's current frame, picks something a person could do (mostly an
enabled move, sometimes a plain UI gesture such as Tab or a hover), and records:

- the **gestures** the driver performs on the running app (pointer moves, presses and releases at
  a point, keys, text-input calls, Edit-menu commands);
- the **events** the host is expected to turn them into (docs/host.md, "Input"), and the
  **actions** the runtime delivers for them (`Runtime.route`);
- the **effects** the step emits, and the **frame** the app must then show: draws, accessibility
  nodes, text input and cursor, from the same `Runtime.step` and `Frame.ofLaid` the app runs;
- **probes**: a point inside each control's box with the colour the frame paints there.

The model is evaluated with the app's own `Runtime.Config`, so its text metrics are Core Text's
when the generator is linked with the host's metrics (`make conformance` does that).

Nothing here is linked into the host, and nothing here imports `Lean`: each app's entry point
(`Conformance/Apps/<App>.lean`) is a module whose runtime initializer stays clear of the claim
commands, like the app library it links (docs/claims.md, "Linking"). -/

@[expose] public section

namespace Conformance
open Cairn Cairn.Claims Cairn.Runtime

/-! ## JSON -/

def hexDigit (n : Nat) : Char := if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

def esc (s : String) : String :=
  s.foldl (fun acc c =>
    match c with
    | '"' => acc ++ "\\\""
    | '\\' => acc ++ "\\\\"
    | '\n' => acc ++ "\\n"
    | '\r' => acc ++ "\\r"
    | '\t' => acc ++ "\\t"
    | c =>
      if c.toNat < 0x20 then
        acc ++ "\\u00" ++ String.singleton (hexDigit (c.toNat / 16)) ++ String.singleton (hexDigit (c.toNat % 16))
      else acc.push c) ""

def jstr (s : String) : String := "\"" ++ esc s ++ "\""
def jarr (xs : List String) : String := "[" ++ ",".intercalate xs ++ "]"
def jobj (kvs : List (String × String)) : String :=
  "{" ++ ",".intercalate (kvs.map fun (k, v) => jstr k ++ ":" ++ v) ++ "}"
def jbool (b : Bool) : String := if b then "true" else "false"
def jopt {α : Type} (f : α → String) : Option α → String
  | some a => f a
  | none => "null"
def jint (i : Int) : String := toString i
def jnat (n : Nat) : String := toString n

def jrect (r : Rect) : String := jarr [jint r.x, jint r.y, jint r.w, jint r.h]
def jpoint (p : Point) : String := jarr [jint p.x, jint p.y]
def jcolor (c : Color) : String := jarr [jnat c.r.toNat, jnat c.g.toNat, jnat c.b.toNat, jnat c.a.toNat]

/-- `^5`, or `^5#12` for a keyed control: the accessibility identifier. -/
def refLabel (c : ControlRef) : String :=
  if c.key = 0 then s!"^{c.claim}" else s!"^{c.claim}#{c.key}"

def roleName : Role → String
  | .group => "group" | .button => "button" | .checkbox => "checkbox" | .text => "text"
  | .textField => "textField" | .link => "link" | .list => "list" | .listItem => "listItem"
  | .heading => "heading" | .tab => "tab"

def cursorName : Cursor → String
  | .arrow => "arrow" | .pointer => "pointer" | .text => "text"

/-! The frame as JSON. The host's debug socket writes the same shape from the frame it decoded
(`host/Sources/CairnHost/DebugJSON.swift`), so the driver compares the two as values. -/

def jdraw : Draw → String
  | .rect r fill radius border =>
    jobj [("rect", jrect r), ("fill", jopt jcolor fill), ("radius", jnat radius),
          ("border", jopt (fun b => jobj [("width", jnat b.width), ("color", jcolor b.color)]) border)]
  | .text o f c s =>
    jobj [("text", jstr s), ("at", jpoint o),
          ("font", jarr [jnat f.family, jnat f.size, jnat f.weight, jbool f.italic,
                         jnat f.width.code, jint f.tracking, jbool f.tabular]), ("color", jcolor c)]
  | .pushClip r => jobj [("push", jrect r)]
  | .popClip => jobj [("pop", "true")]
  | .shape r fill radius border corner shadow =>
    jobj [("shape", jrect r), ("fill", jopt jcolor fill), ("radius", jnat radius),
          ("border", jopt (fun b => jobj [("width", jnat b.width), ("color", jcolor b.color)]) border),
          ("continuous", jbool (corner == .continuous)),
          ("shadow", jopt (fun s => jobj [("color", jcolor s.color), ("radius", jnat s.radius),
                                          ("offset", jarr [jint s.x, jint s.y])]) shadow)]
  | .paint r p =>
    jobj [("paint", jrect r), ("shader", jstr p.shader), ("origin", jnat p.origin),
          ("scalars", jarr (p.scalars.map jint)), ("arrays", jarr (p.arrays.map fun a => jarr (a.map jint)))]
  | .image r d src => jobj [("image", jrect r), ("dest", jrect d), ("source", jstr src)]

def jax (n : AxNode) : String :=
  jobj [("role", jstr (roleName n.role)), ("control", jopt (jstr ∘ refLabel) n.control),
        ("parent", jopt jnat n.parent), ("rect", jrect n.rect), ("label", jstr n.label),
        ("value", jstr n.value), ("focused", jbool n.focused), ("selected", jbool n.selected),
        ("checked", jopt jbool n.checked)]

def jrange (p : Nat × Nat) : String := jarr [jnat p.1, jnat p.2]

def jtextInput (t : TextInput) : String :=
  jobj [("control", jstr (refLabel t.control)), ("rect", jrect t.rect), ("caret", jrect t.caret),
        ("text", jstr t.text), ("selection", jrange t.selection), ("marked", jopt jrange t.marked),
        ("origin", jpoint t.textOrigin)]

/-! A status item's menu, in the shape the debug socket's `menu` command reads it back from
AppKit (`DebugJSON.menu`): the host's own key-equivalent table, and an item inside a disabled
submenu reported disabled, as AppKit reports it (docs/trusted.md, ^940). -/

def kindName : SurfaceKind → String
  | .window => "window" | .panel => "panel" | .statusItem => "statusItem"

/-- `MenuHost.keyEquivalent`: AppKit's key equivalent for a shortcut. -/
def keyEquivalent : Key → String
  | .enter => "\r" | .escape => "\x1b" | .tab => "\t" | .backspace => "\x08"
  | .delete => String.singleton (Char.ofNat 0xF728) | .left => String.singleton (Char.ofNat 0xF702)
  | .right => String.singleton (Char.ofNat 0xF703) | .up => String.singleton (Char.ofNat 0xF700)
  | .down => String.singleton (Char.ofNat 0xF701) | .home => String.singleton (Char.ofNat 0xF729)
  | .finish => String.singleton (Char.ofNat 0xF72B) | .pageUp => String.singleton (Char.ofNat 0xF72C)
  | .pageDown => String.singleton (Char.ofNat 0xF72D) | .char c => String.singleton c.toLower

/-- Modifier names in `DebugJSON.modNames` order. -/
def menuMods (m : Mods) : List String :=
  (if m.command then ["command"] else []) ++ (if m.shift then ["shift"] else []) ++
  (if m.option then ["option"] else []) ++ (if m.control then ["control"] else [])

/-- Whether record `i` and every submenu around it are enabled. -/
def effectiveEnabled (recs : Array MenuRecord) (i : Nat) : Bool := Id.run do
  let mut j := some i
  for _ in [0:recs.size + 1] do
    match j with
    | none => return true
    | some k =>
      let some r := recs[k]? | return true
      unless r.enabled do return false
      j := r.parent
  return true

/-- The items whose parent is `parent`, nested. `fuel` bounds the depth. -/
def jmenuItems (recs : Array MenuRecord) (parent : Option Nat) : Nat → String
  | 0 => "[]"
  | fuel + 1 => jarr <| (List.range recs.size).filterMap fun i => do
    let r ← recs[i]?
    guard (r.parent == parent)
    let en := effectiveEnabled recs i
    let plain (kind : String) (enabled : Bool) (id : String) : List (String × String) :=
      [("kind", jstr kind), ("title", jstr r.label), ("enabled", jbool enabled), ("state", jstr "off"),
       ("id", id), ("key", jstr ""), ("mods", "[]")]
    match r.kind, r.control with
    | .separator, _ => some (jobj [("kind", jstr "separator")])
    | .submenu, _ =>
      some (jobj (plain "submenu" en (jopt (fun p => jstr s!"^{p}") r.place) ++
        [("items", jmenuItems recs (some i) fuel)]))
    | .item, some c =>
      let (key, mods) := match r.shortcut with
        | some sc => (keyEquivalent sc.key, menuMods sc.mods)
        | none => ("", [])
      some (jobj [("kind", jstr "item"), ("title", jstr r.label), ("enabled", jbool en),
        ("state", jstr (if r.checked == some true then "on" else "off")), ("id", jstr (refLabel c)),
        ("key", jstr key), ("mods", jarr (mods.map jstr))])
    | _, _ => some (jobj (plain "info" false "null"))

def jmenus (f : Frame) : String :=
  jarr <| f.surfaces.toList.filterMap fun s =>
    if s.kind == .statusItem then
      some (jobj [("place", jnat s.place), ("items", jmenuItems s.status.menu none (s.status.menu.size + 1))])
    else none

def jsurfaces (f : Frame) : String :=
  jarr <| f.surfaces.toList.map fun s =>
    jobj [("kind", jstr (kindName s.kind)), ("place", jnat s.place), ("shown", jbool s.shown)]

/-- The window's canvas (empty when the app has none), then what the debug socket's `menu` and
`surfaces` commands must answer: `menus` and `surfaces`, which the driver compares on their own. -/
def jframe (f : Frame) : String :=
  jobj [("size", jarr [jint f.size.w, jint f.size.h]),
        ("draws", jarr (f.draws.toList.map jdraw)),
        ("ax", jarr (f.ax.toList.map jax)),
        ("textInput", jopt jtextInput f.textInput),
        ("cursor", jstr (cursorName f.cursor)),
        ("menus", jmenus f), ("surfaces", jsurfaces f)]

/-- A request as the debug socket describes it (`DebugJSON.request` in the host): what it asks
for, never a secret, a body or typed text. -/
def requestKind : Request → String
  | .readFile p => s!"readFile {p}"
  | .writeFile p d => s!"writeFile {p} ({d.size} bytes)"
  | .playSound n => s!"playSound {n}"
  | .http m u _ _ _ sec cap =>
    s!"http {m} {u}{match sec with | some x => s!" secret {x.header}" | none => ""}" ++
      (if cap.isEmpty then "" else s!" capture {cap.length}")
  | .appendFile p d => s!"appendFile {p} ({d.size} bytes)"
  | .listDir p => s!"listDir {p}"
  | .deleteFile p => s!"deleteFile {p}"
  | .frontmostApp => "frontmostApp"
  | .permission p prompt =>
    s!"permission {match p with | .accessibility => "accessibility" | .microphone => "microphone"}{if prompt then " prompt" else ""}"
  | .typeText pid t ret => s!"typeText {pid} ({t.utf8ByteSize} bytes){if ret then " return" else ""}"
  | .upload m u _ sec body _ =>
    s!"upload {m} {u} ({body.length} parts){match sec with | some x => s!" secret {x.header}" | none => ""}"
  | .forgetClip c => s!"forgetClip {c}"
  | .openItem t => s!"open {t}"
  | .appRunning b => s!"appRunning {b}"
  | .readDefault d k => s!"readDefault {d} {k}"
  | .makeDir p => s!"makeDir {p}"
  | .loadImage src r => s!"loadImage {src}{if r then " reload" else ""}"
  | .forgetSecret a => s!"forgetSecret {a}"

def jeffect : Effect → String
  | .setClipboard s => jobj [("clipboard", jstr s)]
  | .beep => jobj [("beep", "true")]
  | .focus c => jobj [("focus", jstr (refLabel c))]
  | .setTimer n ms => jobj [("setTimer", jstr n), ("ms", toString ms)]
  | .cancelTimer n => jobj [("cancelTimer", jstr n)]
  | .request id r => jobj [("request", toString id), ("kind", jstr (requestKind r))]
  | .quit => jobj [("quit", "true")]
  | .cancelRequest id => jobj [("cancelRequest", toString id)]

def opName : TextOp → String
  | .insert s => s!"insert {repr s}" | .deleteBackward => "deleteBackward"
  | .deleteForward => "deleteForward" | .deleteWordBackward => "deleteWordBackward"
  | .deleteWordForward => "deleteWordForward" | .moveLeft e => s!"moveLeft {e}"
  | .moveRight e => s!"moveRight {e}" | .moveWordLeft e => s!"moveWordLeft {e}"
  | .moveWordRight e => s!"moveWordRight {e}" | .moveHome e => s!"moveHome {e}"
  | .moveEnd e => s!"moveEnd {e}" | .setCaret i e => s!"setCaret {i} {e}"
  | .selectAll => "selectAll" | .setMarked s a l => s!"setMarked {repr s} {a} {l}"
  | .unmark => "unmark" | .cut => "cut" | .copy => "copy" | .paste s => s!"paste {repr s}"
  | .undo => "undo" | .redo => "redo"

def actionName : Action → String
  | .press c => s!"press {refLabel c}" | .doublePress c => s!"doublePress {refLabel c}"
  | .edit c op => s!"edit {refLabel c} ({opName op})" | .submit c => s!"submit {refLabel c}"
  | .cancel c => s!"cancel {refLabel c}" | .blur c => s!"blur {refLabel c}"

def keyName : Key → String
  | .enter => "enter" | .escape => "escape" | .tab => "tab" | .backspace => "backspace"
  | .delete => "delete" | .left => "left" | .right => "right" | .up => "up" | .down => "down"
  | .home => "home" | .finish => "end" | .pageUp => "pageUp" | .pageDown => "pageDown"
  | .char _ => "char"

def modNames (m : Mods) : List String :=
  (if m.shift then ["shift"] else []) ++ (if m.command then ["command"] else []) ++
  (if m.option then ["option"] else []) ++ (if m.control then ["control"] else [])

def eventName : Event → String
  | .pointerMove p => s!"move {p.x} {p.y}"
  | .pointerDown p _ n m => s!"down {p.x} {p.y} clicks={n} {modNames m}"
  | .pointerUp p _ m => s!"up {p.x} {p.y} {modNames m}"
  | .pointerExit => "exit"
  | .scroll p dx dy => s!"scroll {p.x} {p.y} {dx} {dy}"
  | .key k m => match k with
    | .char c => s!"key char {repr c} {modNames m}"
    | k => s!"key {keyName k} {modNames m}"
  | .insertText s r => s!"insertText {repr s} {r}"
  | .setMarked s a l r => s!"setMarked {repr s} {a} {l} {r}"
  | .unmark => "unmark" | .copy => "copy" | .cut => "cut" | .selectAll => "selectAll"
  | .undo => "undo" | .redo => "redo" | .paste s => s!"paste {repr s}"
  | .resize s => s!"resize {s.w} {s.h}" | .scale p => s!"scale {p}"
  | .windowFocus b => s!"windowFocus {b}"
  | .clock t => s!"clock {t.mono}"
  | .reply id _ => s!"reply {id}"
  | .subEvent id _ => s!"subEvent {id}"
  | .surface p e => s!"surface {p} " ++ eventName e
  | .menuOpen p => s!"menuOpen {p}" | .menuClose p => s!"menuClose {p}"
  | .menuSelect p r => s!"menuSelect {p} {refLabel r}"

/-! ## Gestures

What the driver does to the running app, through the debug socket. Each becomes the events the
host's input table (docs/host.md) says it does; `paste` carries the model's clipboard. -/

inductive Gesture where
  /-- mouseMoved at a point. -/
  | move (p : Point)
  /-- mouseDown with a click count. -/
  | down (p : Point) (clicks : Nat)
  /-- mouseUp. -/
  | up (p : Point)
  /-- mouseExited. -/
  | exit
  /-- keyDown (with interpretKeyEvents when a field is focused). -/
  | key (k : Key) (mods : Mods)
  /-- `insertText(_:replacementRange:)` with no replacement range. -/
  | text (s : String)
  /-- `setMarkedText(_:selectedRange:replacementRange:)`. -/
  | marked (s : String) (selStart selLen : Nat)
  /-- `unmarkText()`. -/
  | unmark
  /-- An Edit-menu command: copy, cut, paste, selectAll, undo or redo. -/
  | menu (name : String)
  /-- A status item's menu opens (closes): its delegate's `menuWillOpen` (`menuDidClose`). -/
  | menuOpen (place : ClaimId)
  | menuClose (place : ClaimId)
  /-- An item of a status item's menu is chosen: `performActionForItem(at:)` when it is
  enabled, its action sent directly when it isn't (the menu changed while it was open). -/
  | menuSelect (place : ClaimId) (r : ControlRef)
deriving Inhabited

def Gesture.events (clipboard : String) : Gesture → List Event
  | .move p => [.pointerMove p]
  | .down p n => [.pointerMove p, .pointerDown p .primary n {}]
  | .up p => [.pointerUp p .primary {}]
  | .exit => [.pointerExit]
  | .key k m => [.key k m]
  | .text s => [.insertText s none]
  | .marked s a l => [.setMarked s a l none]
  | .unmark => [.unmark]
  | .menu "copy" => [.copy]
  | .menu "cut" => [.cut]
  | .menu "paste" => [.paste clipboard]
  | .menu "selectAll" => [.selectAll]
  | .menu "undo" => [.undo]
  | .menu "redo" => [.redo]
  | .menu _ => []
  | .menuOpen p => [.menuOpen p]
  | .menuClose p => [.menuClose p]
  | .menuSelect p r => [.menuSelect p r]

def Gesture.json : Gesture → String
  | .move p => jobj [("g", jstr "move"), ("at", jpoint p)]
  | .down p n => jobj [("g", jstr "down"), ("at", jpoint p), ("clicks", jnat n)]
  | .up p => jobj [("g", jstr "up"), ("at", jpoint p)]
  | .exit => jobj [("g", jstr "exit")]
  | .key k m =>
    let ch := match k with
      | .char c => [("char", jstr (String.singleton c))]
      | _ => []
    jobj ([("g", jstr "key"), ("key", jstr (keyName k)), ("mods", jarr ((modNames m).map jstr))] ++ ch)
  | .text s => jobj [("g", jstr "text"), ("text", jstr s)]
  | .marked s a l => jobj [("g", jstr "marked"), ("text", jstr s), ("sel", jarr [jnat a, jnat l])]
  | .unmark => jobj [("g", jstr "unmark")]
  | .menu n => jobj [("g", jstr "menu"), ("name", jstr n)]
  | .menuOpen p => jobj [("g", jstr "menuOpen"), ("place", jnat p)]
  | .menuClose p => jobj [("g", jstr "menuClose"), ("place", jnat p)]
  | .menuSelect p r => jobj [("g", jstr "menuSelect"), ("place", jnat p), ("id", jstr (refLabel r)),
                              ("ref", jarr [jnat r.claim, jnat r.key])]

def click (p : Point) : List Gesture := [.move p, .down p 1, .up p]
def doubleClick (p : Point) : List Gesture := [.move p, .down p 1, .up p, .down p 2, .up p]

/-! ## Choosing what to do -/

/-- xorshift64. The seed is mixed first so small seeds differ in their first draws. -/
structure Rng where
  s : UInt64

def Rng.ofSeed (seed : Nat) : Rng :=
  let x := (seed.toUInt64 + 1) * 0x9E3779B97F4A7C15
  ⟨if x = 0 then 1 else x ^^^ (x >>> 31)⟩

def Rng.next (r : Rng) : UInt64 × Rng :=
  let x := r.s
  let x := x ^^^ (x <<< 13)
  let x := x ^^^ (x >>> 7)
  let x := x ^^^ (x <<< 17)
  (x, ⟨x⟩)

def Rng.below (r : Rng) (n : Nat) : Nat × Rng :=
  let (x, r) := r.next
  (if n = 0 then 0 else x.toNat % n, r)

def Rng.pick {α : Type} [Inhabited α] (r : Rng) (xs : Array α) : α × Rng :=
  let (i, r) := r.below xs.size
  (xs[i]!, r)

/-- Text typed into fields: plain words, surrounding and inner spaces, blank text, accents,
CJK, an emoji with a skin tone (two scalars), and a line too long for the field. -/
def vocabulary : Array String :=
  #["milk", " eggs ", "   ", "a", "Bread and butter", "Ünïcödé", "日本語", "👍🏽", "x",
    "  spaced  out  ", "A much longer item that goes on and on past the edge of the field"]

/-- Something to do: a label for reports, the move it means to exercise (its control and
trigger), and the gestures. -/
structure Choice where
  label : String
  move : Option (ControlRef × String) := none
  gestures : List Gesture
deriving Inhabited

def visible (r : Rect) : Bool := decide (0 < r.w) && decide (0 < r.h)

/-- A point in a rect: `fx`, `fy` in thousandths of its width and height. -/
def ptAt (r : Rect) (fx fy : Nat) : Point :=
  ⟨r.x + r.w * fx / 1000, r.y + r.h * fy / 1000⟩

variable {S : Type}

/-- Everything a person could do now, weighted by repetition. -/
def choices (M : Machine S) (s : Runtime.State S) (f : Frame) (r : Rng) : Array Choice × Rng := Id.run do
  let mut out : Array Choice := #[]
  let mut r := r
  let field := f.textInput.map (·.control)
  let focusedButton := f.ax.toList.findSome? fun n =>
    if n.focused && n.role != .textField then n.control else none
  for n in f.ax do
    let some c := n.control | continue
    let some m := find? M.moves c.claim | continue
    unless m.enabled s.app c.key && visible n.rect do continue
    let ts := m.triggers
    if n.role == .textField then
      if field == some c then
        -- The field has focus: edit it.
        if ts.contains .edit then
          for _ in [0:4] do
            let (t, r') := r.pick vocabulary
            r := r'
            out := out.push { label := s!"type {repr t} in {refLabel c}", move := some (c, "edit"),
                              gestures := [.text t] }
          let keys : List (String × Key × Mods) :=
            [("Backspace", .backspace, {}), ("Delete", .delete, {}), ("Left", .left, {}),
             ("Right", .right, {}), ("Shift-Left", .left, { shift := true }),
             ("Shift-Right", .right, { shift := true }), ("Option-Left", .left, { option := true }),
             ("Option-Shift-Right", .right, { option := true, shift := true }),
             ("Option-Backspace", .backspace, { option := true }),
             ("Command-Left", .left, { command := true }),
             ("Command-Shift-Right", .right, { command := true, shift := true }),
             ("Command-Backspace", .backspace, { command := true }), ("Home", .home, {}),
             ("End", .finish, {}), ("Up", .up, {}), ("Down", .down, {})]
          for (name, k, mods) in keys do
            out := out.push { label := s!"{name} in {refLabel c}", move := some (c, "edit"),
                              gestures := [.key k mods] }
          for cmd in ["selectAll", "undo", "redo", "copy", "cut", "paste"] do
            out := out.push { label := s!"{cmd} in {refLabel c}", move := some (c, "edit"),
                              gestures := [.menu cmd] }
          out := out.push { label := s!"compose 日本 in {refLabel c}", move := some (c, "edit"),
                            gestures := [.marked "に" 1 0, .marked "にほん" 3 0, .text "日本"] }
          out := out.push { label := s!"compose and keep in {refLabel c}", move := some (c, "edit"),
                            gestures := [.marked "か" 1 0, .marked "かな" 2 0, .unmark] }
          let (fx, r') := r.below 1000
          r := r'
          out := out.push { label := s!"click inside {refLabel c}", move := some (c, "edit"),
                            gestures := click (ptAt n.rect fx 500) }
          let (gx, r') := r.below 1000
          r := r'
          let a := ptAt n.rect fx 500
          let b := ptAt n.rect gx 500
          out := out.push { label := s!"drag-select in {refLabel c}", move := some (c, "edit"),
                            gestures := [.move a, .down a 1, .move b, .up b] }
        if ts.contains .submit then
          for _ in [0:3] do
            out := out.push { label := s!"Enter in {refLabel c}", move := some (c, "submit"),
                              gestures := [.key .enter {}] }
        if ts.contains .cancel then
          out := out.push { label := s!"Escape in {refLabel c}", move := some (c, "cancel"),
                            gestures := [.key .escape {}] }
      else
        -- Focus it with a click, as a person would.
        for _ in [0:3] do
          out := out.push { label := s!"click {refLabel c}", move := some (c, "edit"),
                            gestures := click n.rect.center }
    else
      if ts.contains .press then
        for _ in [0:3] do
          out := out.push { label := s!"press {refLabel c}", move := some (c, "press"),
                            gestures := click n.rect.center }
      if ts.contains .doublePress then
        out := out.push { label := s!"double-click {refLabel c}", move := some (c, "doublePress"),
                          gestures := doubleClick n.rect.center }
  -- Keyboard presses on a focused button-like control.
  if let some c := focusedButton then
    if let some m := find? M.moves c.claim then
      if m.triggers.contains .press then
        out := out.push { label := s!"Enter on {refLabel c}", move := some (c, "press"),
                          gestures := [.key .enter {}] }
        out := out.push { label := s!"Space on {refLabel c}", move := some (c, "press"),
                          gestures := [.key (.char ' ') {}] }
  -- Status items: open the menu (a press on the item's control), choose an item. A greyed-out
  -- item is chosen too, as when the menu changed while it was open: nothing may happen.
  for sf in f.surfaces do
    unless sf.kind == .statusItem && sf.shown do continue
    let p := sf.place
    let sc := sf.status.control
    if let some m := find? M.moves sc.claim then
      if m.enabled s.app sc.key then
        out := out.push { label := s!"open the menu of ^{p}", move := some (sc, "press"),
                          gestures := [.menuOpen p, .menuClose p] }
    let recs := sf.status.menu
    for i in [0:recs.size] do
      let some rec := recs[i]? | continue
      let some c := rec.control | continue
      unless rec.kind == .item do continue
      let live := effectiveEnabled recs i &&
        (find? M.moves c.claim).any (fun m => m.enabled s.app c.key)
      if live then
        for _ in [0:2] do
          out := out.push { label := s!"choose {refLabel c} in ^{p}", move := some (c, "press"),
                            gestures := [.menuSelect p c] }
      else
        out := out.push { label := s!"choose greyed-out {refLabel c} in ^{p}",
                          gestures := [.menuSelect p c] }
  -- Plain UI: focus traversal, hover, leaving the window, clicking nothing. Only with a window.
  if f.surfaces.any (·.kind == .window) then
    out := out.push { label := "Tab", gestures := [.key .tab {}] }
    out := out.push { label := "Shift-Tab", gestures := [.key .tab { shift := true }] }
    out := out.push { label := "pointer leaves the window", gestures := [.exit] }
    let (x, r') := r.below (Int.toNat f.size.w)
    let (y, r'') := r'.below (Int.toNat f.size.h)
    r := r''
    out := out.push { label := s!"hover at {x},{y}", gestures := [.move ⟨x, y⟩] }
    out := out.push { label := "click empty space", gestures := click ⟨2, f.size.h - 2⟩ }
  (out, r)

/-! ## Running the model -/

/-- Runs events one at a time, as `Runtime.steps` does, and collects the actions `route`
delivers for each (`Runtime.step_delivers`: exactly what `update` sees). -/
def runEvents (app : App S) (cfg : Config) (s : Runtime.State S) (es : List Event) :
    Runtime.State S × List Action × List Effect :=
  es.foldl (fun (s, acts, effs) e =>
    let (_, a) := route cfg.metrics s e
    let (s', ef) := step app cfg s e
    (s', acts ++ a, effs ++ ef)) (s, [], [])

/-- Whether a press or double press of `c` is dropped by design (TodoMVC decision T33,
docs/plan.md): the first pointerDown delivers a `blur`, and after its step `c` is no longer at
the point, because the edit the blur saved moved or removed it. The release then lands elsewhere
and presses nothing (docs/runtime.md), which is where `Runtime.click_presses`'s hypothesis fails. -/
def droppedClick (app : App S) (cfg : Config) (s : Runtime.State S) (c : ControlRef) :
    List Event → Bool
  | [] => false
  | e@(.pointerDown p _ 1 _) :: _ =>
    (route cfg.metrics s e).2.any (· matches .blur _) && hitRef (step app cfg s e).1.laid p != some c
  | e :: es => droppedClick app cfg (step app cfg s e).1 c es

def modelFrame (s : Runtime.State S) (effs : List Effect) : Frame :=
  Runtime.frame Frame.boundary { s with effects := effs.toArray }

/-! ## Pixel probes

For each control, a point inside its box away from text, edges, borders and rounded corners,
and the colour the frame's draws give it there: rect fills and borders in paint order, blended
by alpha in gamma space (as the renderer does, docs/trusted.md), over `clear`, the window's
background. -/

def blend (dst src : Color) : Color :=
  let a := src.a.toNat
  let mix (d s : UInt8) : UInt8 := ((s.toNat * a + d.toNat * (255 - a) + 127) / 255).toUInt8
  ⟨mix dst.r src.r, mix dst.g src.g, mix dst.b src.b, 255⟩

def has (r : Rect) (p : Point) : Bool :=
  decide (r.x ≤ p.x) && decide (p.x < r.x + r.w) && decide (r.y ≤ p.y) && decide (p.y < r.y + r.h)

/-- At least `d` points inside `r` on every side. -/
def deep (r : Rect) (p : Point) (d : Int) : Bool :=
  decide (r.x + d ≤ p.x) && decide (p.x < r.x + r.w - d) && decide (r.y + d ≤ p.y) &&
    decide (p.y < r.y + r.h - d)

/-- Near a rounded corner of `r` (within `radius + 1` of two edges). -/
def inCorner (r : Rect) (rad : Nat) (p : Point) : Bool :=
  let k : Int := rad + 1
  let nearX := decide (p.x < r.x + k) || decide (p.x ≥ r.x + r.w - k)
  let nearY := decide (p.y < r.y + k) || decide (p.y ≥ r.y + r.h - k)
  rad > 0 && nearX && nearY

/-- The colour at `p`, or none when `p` is too close to an edge, a border's inner edge, a
rounded corner or text for the answer to be exact. -/
def colourAt (m : TextMetrics) (draws : List Draw) (clear : Color) (p : Point) :
    Option Color := Id.run do
  let mut c := clear
  let mut clips : List Rect := []
  for d in draws do
    match d with
    | .pushClip r => clips := r :: clips
    | .popClip => clips := clips.drop 1
    | .rect r fill rad border =>
      unless clips.all (has · p) && has r p do continue
      unless deep r p 1 do return none
      if inCorner r rad p then return none
      let bw : Int := (border.map (·.width)).getD 0
      if bw > 0 && !deep r p bw then
        -- In the border band; the band's inner edge must not be adjacent.
        if deep r p (bw - 1) then return none
        if let some b := border then c := blend c b.color
      else
        if bw > 0 && !deep r p (bw + 1) then return none
        if let some f := fill then c := blend c f
    | .text o font _ s =>
      let w := (m.offsets font s).back?.getD 0
      let box : Rect := ⟨o.x - 1, o.y - m.ascent font - 1, w + 2, m.ascent font + m.descent font + 2⟩
      if has box p then return none
    | .shape r _ _ _ _ shadow =>
      -- Continuous corners and soft shadows aren't modelled here: no exact answer near one.
      let spread : Int := match shadow with
        | some s => 3 * s.radius + s.x.natAbs + s.y.natAbs + 1
        | none => 1
      if has ⟨r.x - spread, r.y - spread, r.w + 2 * spread, r.h + 2 * spread⟩ p then return none
    | .paint r _ =>
      if has r p then return none
    | .image r _ _ =>
      -- The host's pixels: no exact answer anywhere in the box.
      if has r p then return none
  return some c

/-- The topmost rect draw covering `p` has exactly the rect `r`: the control's own box. -/
def ownBox (draws : List Draw) (r : Rect) (p : Point) : Bool :=
  let top := draws.foldl (fun acc d => match d with
    | .rect q (some _) _ _ => if has q p then some q else acc
    | .rect q _ _ (some _) => if has q p then some q else acc
    | _ => acc) none
  top == some r

def probeFor (m : TextMetrics) (f : Frame) (clear : Color) (n : AxNode) : Option String := do
  let c ← n.control
  let r := n.rect
  guard (visible r)
  let cands : List Point :=
    [ptAt r 500 500, ⟨r.x + 3, r.y + r.h / 2⟩, ⟨r.x + r.w - 4, r.y + r.h / 2⟩,
     ⟨r.x + r.w / 2, r.y + 3⟩, ⟨r.x + r.w / 2, r.y + r.h - 4⟩, ⟨r.x + 3, r.y + 3⟩,
     ⟨r.x + r.w - 4, r.y + r.h - 4⟩, ptAt r 250 500, ptAt r 750 500]
  let draws := f.draws.toList
  let (p, col) ← cands.findSome? fun p =>
    if has r p then (colourAt m draws clear p).map (p, ·) else none
  return jobj [("ref", jstr (refLabel c)), ("at", jpoint p), ("expect", jcolor col),
               ("own", jbool (ownBox draws r p))]

/-! ## Sequences -/

structure Options where
  seed : Nat := 1
  count : Nat := 1
  length : Nat := 12
  width : Nat := 480
  height : Nat := 600
  scale : Nat := 200
  clear : Color := ⟨247, 247, 245, 255⟩
  /-- Witnesses to replay instead of random walks (`--witness FILE`). -/
  witness : Option String := none
  /-- Raw gesture sequences to replay (`--gestures FILE`). -/
  gestures : Option String := none

/-- The label of a press dropped by design (`droppedClick`). The driver counts these as
known, not as failures: the app did what the model does. -/
def t33Label : String := "T33"

/-- Model checks that need no app: every control on screen belongs to an enabled move
(presence), and a chosen press delivers exactly that press, after any blurs (pressable),
unless the click was dropped by design (`dropped`, T33): then it is in `known`, not here. -/
def findings (M : Machine S) (s : Runtime.State S) (f : Frame) (ch : Choice)
    (acts : List Action) (dropped : Bool := false) : List String := Id.run do
  let mut out := []
  for n in f.ax do
    if let some c := n.control then
      match find? M.moves c.claim with
      | none => out := out ++ [s!"{refLabel c} is on screen but no move owns ^{c.claim}"]
      | some m =>
        unless m.enabled s.app c.key do
          out := out ++ [s!"{refLabel c} is on screen but its move is not enabled"]
  for sf in f.surfaces do
    for rec in sf.status.menu do
      if let some c := rec.control then
        match find? M.moves c.claim with
        | none => out := out ++ [s!"{refLabel c} is in the menu of ^{sf.place} but no move owns ^{c.claim}"]
        | some m =>
          if rec.enabled && !m.enabled s.app c.key then
            out := out ++ [s!"{refLabel c} is enabled in the menu of ^{sf.place} but its move is not"]
  if let some (c, t) := ch.move then
    let main := acts.filter fun a => match a with | .blur _ => false | _ => true
    if dropped && main.isEmpty then return out
    match t with
    | "press" =>
      unless main == [.press c] do
        out := out ++ [s!"{ch.label} delivered {main.map actionName}, not [press {refLabel c}]"]
    | "doublePress" =>
      unless main == [.press c, .doublePress c] do
        out := out ++ [s!"{ch.label} delivered {main.map actionName}"]
    | _ => pure ()
  return out

def jstep (M : Machine S) (s : Runtime.State S) (ch : Choice) (clipboard : String) (es : List Event)
    (acts : List Action) (effs : List Effect) (f : Frame) (probes : List String)
    (finds : List String) (known : List String := []) : String :=
  jobj [("label", jstr ch.label),
        ("move", jopt (fun (r, t) =>
            jobj [("ref", jstr (refLabel r)), ("claim", jnat r.claim), ("key", jnat r.key),
                  ("trigger", jstr t)]) ch.move),
        ("gestures", jarr (ch.gestures.map Gesture.json)),
        ("events", jarr (es.map (jstr ∘ eventName))),
        ("actions", jarr (acts.map fun a => jobj [("action", jstr (actionName a)),
            ("claim", jnat a.control.claim), ("ref", jstr (refLabel a.control)),
            ("accepted", jbool (accepts M.moves s.app a))])),
        ("effects", jarr (effs.map jeffect)),
        ("clipboard", jstr clipboard),
        ("frame", jframe f), ("probes", jarr probes), ("findings", jarr (finds.map jstr)),
        ("known", jarr (known.map jstr))]

/-- One step: perform `ch` on the model; returns the new state and clipboard and the step's JSON.
The actions are accepted against the state before the step's first event, which is exact for a
single action and a good summary otherwise. -/
def stepModel (M : Machine S) (app : App S) (cfg : Config) (o : Options)
    (s : Runtime.State S) (clipboard : String) (ch : Choice) : Runtime.State S × String × String :=
  let es := ch.gestures.flatMap (·.events clipboard)
  let (s', acts, effs) := runEvents app cfg s es
  let clip := effs.foldl (fun c e => match e with | .setClipboard t => t | _ => c) clipboard
  let f := modelFrame s' effs
  let probes := f.ax.toList.filterMap (probeFor cfg.metrics f o.clear)
  let dropped := match ch.move with
    | some (c, "press") | some (c, "doublePress") => droppedClick app cfg s c es
    | _ => false
  let main := acts.filter fun a => match a with | .blur _ => false | _ => true
  let known := if dropped && main.isEmpty then
      [s!"{t33Label}: {ch.label} dropped: the blur saved the edit, which moved or removed the control before the release"]
    else []
  let finds := findings M s (modelFrame s []) ch acts dropped
  (s', clip, jstep M s ch clipboard es acts effs f probes finds known)

def start (app : App S) (cfg : Config) (o : Options) : Runtime.State S :=
  initState app cfg o.width.toUInt32 o.height.toUInt32 o.scale.toUInt32

/-- The group a choice belongs to: its control and trigger, or plain UI. -/
def Choice.group (ch : Choice) : String :=
  match ch.move with
  | some (c, t) => s!"{refLabel c} {t}"
  | none => "ui"

/-- Picks a group (a control and trigger, or plain UI) uniformly, with editing the focused field
weighted three times, then a choice within it. Picking among choices directly would let the
field's many gestures crowd out the other moves. -/
def pickGrouped (cs : Array Choice) (r : Rng) : Choice × Rng := Id.run do
  let mut groups : Array String := #[]
  for ch in cs do
    unless groups.contains ch.group do groups := groups.push ch.group
  let weighted := groups.flatMap fun g =>
    if (cs.find? (·.group == g)).any (fun ch => ch.move.any (·.2 == "edit") && ch.gestures.length == 1)
    then #[g, g, g] else #[g]
  let (g, r) := r.pick weighted
  r.pick (cs.filter (·.group == g))

/-- A random walk of `o.length` steps from the initial state. -/
def walk (M : Machine S) (app : App S) (cfg : Config) (o : Options) (i : Nat) : String := Id.run do
  let mut r := Rng.ofSeed (o.seed * 1000003 + i)
  let mut s := start app cfg o
  let mut clip := ""
  let mut steps : Array String := #[]
  let initFrame := modelFrame s []
  for _ in [0:o.length] do
    let f := modelFrame s []
    let (cs, r') := choices M s f r
    let (ch, r'') := pickGrouped cs r'
    r := r''
    let (s', clip', js) := stepModel M app cfg o s clip ch
    s := s'
    clip := clip'
    steps := steps.push js
  return jobj [("name", jstr s!"walk-{o.seed}-{i}"), ("seed", jnat o.seed), ("index", jnat i),
               ("init", jframe initFrame),
               ("initProbes", jarr (initFrame.ax.toList.filterMap (probeFor cfg.metrics initFrame o.clear))),
               ("steps", jarr steps.toList)]

/-! ## Witnesses

`--witness FILE` replays flows instead of walking: one flow per line, `name` then its steps
separated by tabs, each step `trigger claim key [op text]` with spaces (the driver writes it
from `lake exe claims`). Each step becomes the gestures a person would use, from the current
frame: a press is a click at the control's centre, an edit focuses the field with a click if
it isn't focused, then types; a submit is Enter, a cancel Escape, a blur Tab. -/

def parseNat (s : String) : Nat := s.toNat?.getD 0

def witnessChoice (f : Frame) (step : String) : Option Choice := do
  let parts := step.splitOn " "
  let trigger ← parts[0]?
  let c : ControlRef := ⟨parseNat (parts[1]?.getD "0"), parseNat (parts[2]?.getD "0")⟩
  let label := s!"{trigger} {refLabel c}"
  -- A press on a status item's control opens its menu; on one of its items, chooses it.
  let statuses := f.surfaces.toList.filter (·.kind == .statusItem)
  let inMenu := statuses.find? fun sf => sf.status.menu.any (·.control == some c)
  match trigger, statuses.find? (·.status.control == c), inMenu with
  | "press", some sf, _ =>
    return { label, move := some (c, "press"), gestures := [.menuOpen sf.place, .menuClose sf.place] }
  | "press", none, some sf =>
    return { label, move := some (c, "press"), gestures := [.menuSelect sf.place c] }
  | _, _, _ => pure ()
  let node ← f.ax.toList.find? (·.control == some c)
  let focused := f.textInput.map (·.control) == some c
  let focus := if focused then [] else click node.rect.center
  let rest := " ".intercalate (parts.drop 4)
  match trigger, parts[3]? with
  | "press", _ => some { label, move := some (c, "press"), gestures := click node.rect.center }
  | "doublePress", _ => some { label, move := some (c, "doublePress"), gestures := doubleClick node.rect.center }
  | "submit", _ => some { label, move := some (c, "submit"), gestures := focus ++ [.key .enter {}] }
  | "cancel", _ => some { label, move := some (c, "cancel"), gestures := focus ++ [.key .escape {}] }
  | "blur", _ => some { label, move := some (c, "blur"), gestures := focus ++ [.key .tab {}] }
  | "edit", some "insert" => some { label := s!"{label} insert {repr rest}", move := some (c, "edit"),
                                     gestures := focus ++ [.text rest] }
  | "edit", some "paste" => some { label := s!"{label} paste", move := some (c, "edit"),
                                    gestures := focus ++ [.menu "paste"] }
  | "edit", some "deleteBackward" => some { label, move := some (c, "edit"), gestures := focus ++ [.key .backspace {}] }
  | "edit", some "deleteForward" => some { label, move := some (c, "edit"), gestures := focus ++ [.key .delete {}] }
  | "edit", some op =>
    if op ∈ ["selectAll", "undo", "redo", "copy", "cut"] then
      some { label := s!"{label} {op}", move := some (c, "edit"), gestures := focus ++ [.menu op] }
    else none
  | _, _ => none

def replay (M : Machine S) (app : App S) (cfg : Config) (o : Options) (line : String) : String := Id.run do
  let parts := line.splitOn "\t"
  let name := parts.headD "flow"
  let mut s := start app cfg o
  let mut clip := ""
  let mut steps : Array String := #[]
  let initFrame := modelFrame s []
  let mut stopped : Option String := none
  for st in parts.drop 1 do
    let f := modelFrame s []
    match witnessChoice f st with
    | none =>
      stopped := some s!"cannot perform {repr st} from the model's frame"
      break
    | some ch =>
      let (s', clip', js) := stepModel M app cfg o s clip ch
      s := s'
      clip := clip'
      steps := steps.push js
  return jobj [("name", jstr name), ("witness", "true"), ("init", jframe initFrame),
               ("initProbes", jarr (initFrame.ax.toList.filterMap (probeFor cfg.metrics initFrame o.clear))),
               ("stopped", jopt jstr stopped), ("steps", jarr steps.toList)]

/-! ## Gesture replay

`--gestures FILE` replays raw gesture lists, which the driver uses to shrink a failing sequence:
one sequence per line, gestures separated by tabs, each one of `move X Y`, `down X Y CLICKS`,
`up X Y`, `exit`, `key NAME MODS [CHAR]` (MODS comma-separated, or `-`), `text TEXT`,
`marked START LEN TEXT`, `unmark`, `menu NAME`, `menuOpen PLACE`, `menuClose PLACE` or
`menuSelect PLACE CLAIM KEY`. Text runs to the end of the gesture. -/

def parseInt (s : String) : Int := s.toInt?.getD 0

def parseKey (name : String) (ch : String) : Option Key :=
  match name with
  | "enter" => some .enter | "escape" => some .escape | "tab" => some .tab
  | "backspace" => some .backspace | "delete" => some .delete | "left" => some .left
  | "right" => some .right | "up" => some .up | "down" => some .down | "home" => some .home
  | "end" => some .finish | "pageUp" => some .pageUp | "pageDown" => some .pageDown
  | "char" => ch.toList.head?.map Key.char
  | _ => none

def parseMods (s : String) : Mods :=
  let ms := s.splitOn ","
  { shift := ms.contains "shift", command := ms.contains "command",
    option := ms.contains "option", control := ms.contains "control" }

def parseGesture (g : String) : Option Gesture :=
  let ps := g.splitOn " "
  let pt (i : Nat) : Point := ⟨parseInt (ps[i]?.getD "0"), parseInt (ps[i+1]?.getD "0")⟩
  let rest (n : Nat) := " ".intercalate (ps.drop n)
  match ps.headD "" with
  | "move" => some (.move (pt 1))
  | "down" => some (.down (pt 1) (parseNat (ps[3]?.getD "1")))
  | "up" => some (.up (pt 1))
  | "exit" => some .exit
  | "key" => (parseKey (ps[1]?.getD "") (rest 3)).map (Gesture.key · (parseMods (ps[2]?.getD "-")))
  | "text" => some (.text (rest 1))
  | "marked" => some (.marked (rest 3) (parseNat (ps[1]?.getD "0")) (parseNat (ps[2]?.getD "0")))
  | "unmark" => some .unmark
  | "menu" => some (.menu (ps[1]?.getD ""))
  | "menuOpen" => some (.menuOpen (parseNat (ps[1]?.getD "0")))
  | "menuClose" => some (.menuClose (parseNat (ps[1]?.getD "0")))
  | "menuSelect" => some (.menuSelect (parseNat (ps[1]?.getD "0"))
      ⟨parseNat (ps[2]?.getD "0"), parseNat (ps[3]?.getD "0")⟩)
  | _ => none

/-- One sequence of steps, each step its gestures separated by `\x1f` (unit separator). -/
def replayGestures (M : Machine S) (app : App S) (cfg : Config) (o : Options) (line : String) :
    String := Id.run do
  let mut s := start app cfg o
  let mut clip := ""
  let mut steps : Array String := #[]
  let initFrame := modelFrame s []
  let mut stopped : Option String := none
  for (st, i) in (line.splitOn "\t").zipIdx do
    let gs := (st.splitOn "\x1f").filterMap parseGesture
    if gs.isEmpty then
      stopped := some s!"cannot parse step {i}: {repr st}"
      break
    let ch : Choice := { label := s!"replay {i}", move := none, gestures := gs }
    let (s', clip', js) := stepModel M app cfg o s clip ch
    s := s'
    clip := clip'
    steps := steps.push js
  return jobj [("name", jstr "replay"), ("init", jframe initFrame),
               ("initProbes", jarr (initFrame.ax.toList.filterMap (probeFor cfg.metrics initFrame o.clear))),
               ("stopped", jopt jstr stopped), ("steps", jarr steps.toList)]

/-! ## Entry point -/

def parseColor (s : String) : Color :=
  match (s.splitOn ",").map parseNat with
  | [r, g, b] => ⟨r.toUInt8, g.toUInt8, b.toUInt8, 255⟩
  | [r, g, b, a] => ⟨r.toUInt8, g.toUInt8, b.toUInt8, a.toUInt8⟩
  | _ => ⟨247, 247, 245, 255⟩

def parseArgs : List String → Options → Options
  | "--seed" :: v :: rest, o => parseArgs rest { o with seed := parseNat v }
  | "--count" :: v :: rest, o => parseArgs rest { o with count := parseNat v }
  | "--length" :: v :: rest, o => parseArgs rest { o with length := parseNat v }
  | "--size" :: w :: h :: rest, o => parseArgs rest { o with width := parseNat w, height := parseNat h }
  | "--scale" :: v :: rest, o => parseArgs rest { o with scale := parseNat v }
  | "--clear" :: v :: rest, o => parseArgs rest { o with clear := parseColor v }
  | "--witness" :: v :: rest, o => parseArgs rest { o with witness := some v }
  | "--gestures" :: v :: rest, o => parseArgs rest { o with gestures := some v }
  | _ :: rest, o => parseArgs rest o
  | [], o => o

/-- `gen [--seed N] [--count N] [--length N] [--size W H] [--scale P] [--clear R,G,B]
[--witness FILE] [--gestures FILE]`: one JSON sequence per line on stdout. -/
def run (M : Machine S) (app : App S) (cfg : Config) (args : List String) : IO UInt32 := do
  let o := parseArgs args {}
  let out ← IO.getStdout
  if let some file := o.gestures then
    for line in (← IO.FS.lines file) do
      unless line.isEmpty do
        out.putStrLn (replayGestures M app cfg o line)
    out.flush
    return 0
  match o.witness with
  | some file =>
    for line in (← IO.FS.lines file) do
      unless line.isEmpty do
        out.putStrLn (replay M app cfg o line)
  | none =>
    for i in [0:o.count] do
      out.putStrLn (walk M app cfg o i)
  out.flush
  return 0

end Conformance

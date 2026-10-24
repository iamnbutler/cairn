module

public import Examples.Yap.App
public import Cairn.Layout.Core

/-! # Yap on Cairn: the menu and the overlay

What the app shows (docs/yap.md), as functions of `AppState`:

* **The status item** (^301): the icon follows the machine's phase (`waveform`, `mic.fill`,
  `text.bubble`), as in Yap's `YapApp`. Its menu is Yap's, in Yap's order: the status line;
  status lines for the original Yap running, Accessibility and the microphone; Copy Last
  Transcript; Recent Transcripts (with ⚠︎ on those never typed) and Open Transcripts Folder;
  Dictate with the key, Press Return After Dictating, Keep Transcripts; Edit Dictionary…, Edit
  Settings…; Quit.
* **The overlay** (^399): the original's panel at the bottom of the screen, 520 points wide: a
  glowing dot, the phase's label and the clock; the tape (the original's shader, as a `paint`
  draw); the live preview in 14-point text, its last 280 characters.

Every actionable menu item is a control naming a move in `Examples.Yap`. -/

@[expose] public section

namespace Examples.Yap
open Cairn

/-! ## The menu -/

def copyLastRef : ControlRef := ⟨302, 0⟩
def recentRef (k : Nat) : ControlRef := ⟨303, k⟩
def keepRef : ControlRef := ⟨304, 0⟩
def submitsRef : ControlRef := ⟨305, 0⟩
def enabledRef : ControlRef := ⟨306, 0⟩
def transcriptsRef : ControlRef := ⟨307, 0⟩
def dictionaryRef : ControlRef := ⟨308, 0⟩
def settingsRef : ControlRef := ⟨309, 0⟩
def grantAccessRef : ControlRef := ⟨310, 0⟩
def quitRef : ControlRef := ⟨342, 0⟩
def grantMicRef : ControlRef := ⟨343, 0⟩
def openMenuRef : ControlRef := ⟨344, 0⟩

/-- A recent transcript's line, as Yap's `YapMenu.label`: the time, ⚠︎ when it never reached
its app, and the text on one line, cut at 60 characters. -/
def recentLabel (zone : Int) (t : Transcript) : String :=
  let words := (t.text.split (fun c => isNewline c)).toList.map (·.toString) |>.filter (· ≠ "")
  let line := " ".intercalate words
  let preview := if Graphemes.count line > 60 then Graphemes.take 60 line ++ "…" else line
  s!"{Dates.shortTime t.date zone}  {if t.typed then "" else "⚠︎ "}{preview}"

/-- Items `k`, `k + 1`, … for these transcripts. -/
def recentItems (zone : Int) (k : Nat) : List Transcript → List MenuItem
  | [] => []
  | t :: ts => .button (recentRef k) (recentLabel zone t) :: recentItems zone (k + 1) ts

def statusLines (s : AppState) : List MenuItem :=
  [.info (if s.core.detail.isEmpty then ready s.core else s.core.detail)] ++
  (if s.io.original == some true then
     [.info s!"Yap is running. Quit it to dictate with {s.core.hotkey.name} here."]
   else []) ++
  (if s.core.trusted then [] else [.button grantAccessRef "Accessibility Is Off: Grant It…"]) ++
  (if s.io.micGranted == some false then [.button grantMicRef "Microphone Is Off: Grant It…"]
   else []) ++
  (if s.io.note.isEmpty then [] else [.info s.io.note])

def menuItems (s : AppState) : List MenuItem :=
  statusLines s ++
  [ .separator,
    .button copyLastRef "Copy Last Transcript" (enabled := !s.core.recent.isEmpty),
    .submenu "Recent Transcripts" none
      ((if s.core.recent.isEmpty then [MenuItem.info "None yet"]
        else recentItems s.io.zone 0 s.core.recent) ++
       [.separator, .button transcriptsRef "Open Transcripts Folder"]),
    .separator,
    .check enabledRef s!"Dictate with {s.core.hotkey.name}" s.core.enabled,
    .check submitsRef "Press Return After Dictating" s.core.submits (enabled := s.core.enabled),
    .check keepRef s!"Keep Transcripts ({s.core.settings.retentionDays} Days)"
      s.core.settings.keepTranscripts,
    .separator,
    .button dictionaryRef "Edit Dictionary…",
    .button settingsRef "Edit Settings…",
    .separator,
    .button quitRef "Quit Yap (Cairn)" (shortcut := some { key := .char 'q' }) ]

def statusItem (s : AppState) : StatusItem :=
  { symbol := match phase s.core with
      | .idle => "waveform" | .recording => "mic.fill" | .transcribing => "text.bubble",
    label := "Yap", control := openMenuRef, menu := menuItems s }

/-! ## The overlay

The original's `OverlayView`, one to one (docs/yap.md, "Overlay parity"): a black rounded
rectangle (continuous corners, radius 14) 520 points wide with a 1-point edge and a soft
shadow, 18 points of room for the shadow around it; inside, 12 points above, 14 below and 16 at
the sides, rows 10 apart: the header (a glowing dot, the phase's label, the clock), the tape
(the original's `Overlay.metal`, drawn by the host's `yap.tape` painter from the levels, cuts and
times here) and, once there is text, a rule and the transcript's tail. -/

/-- The original's `Palette`, in 8-bit sRGB. -/
def cream : Color := ⟨237, 232, 219, 255⟩
def blue : Color := ⟨97, 153, 255, 255⟩
def orange : Color := ⟨255, 158, 51, 255⟩
def red : Color := ⟨255, 77, 46, 255⟩
def edge : Color := ⟨43, 43, 43, 255⟩

def withAlpha (c : Color) (a : UInt8) : Color := ⟨c.r, c.g, c.b, a⟩

/-- The palette for the tape's shader, in ten-thousandths (`Palette` exactly). -/
def Look.tint : Look → List Int
  | .listening | .failed => [10000, 3000, 1800]
  | .handsFree => [10000, 6200, 2000]
  | .transcribing => [3800, 6000, 10000]
  | .typed => [9300, 9100, 8600]

def Look.color : Look → Color
  | .listening | .failed => red
  | .handsFree => orange
  | .transcribing => blue
  | .typed => cream

def Look.label : Look → String
  | .listening => "REC"
  | .handsFree => "REC · HANDS FREE · TAP AGAIN TO SEND"
  | .transcribing => "TRANSCRIBING"
  | .typed => "TYPED"
  | .failed => "NOT TYPED · IN RECENT TRANSCRIPTS"

/-- `%d:%02d` of whole seconds in `ms`. -/
def clockText (ms : Nat) : String :=
  let s := ms / 1000
  s!"{s / 60}:{if s % 60 < 10 then "0" else ""}{s % 60}"

/-- How much of the transcript the overlay shows: about four lines. -/
def shownChars : Nat := 280

/-- The text as the original shows it: all of it, or "…" and its last 280 characters. -/
def tailText (t : String) : String :=
  if t.length ≤ shownChars then t else "…" ++ String.ofList (t.toList.drop (t.length - shownChars))

/-- A time relative to the tape's clock, in ms, within the shader's 32-bit numbers. -/
def tapeMs (o : Overlay) (t : Nat) : Int := max (-2147483648) (min 2147483647 ((t : Int) - o.epoch))

/-- What the `yap.tape` painter is given (host/Sources/CairnYapPaint/YapTape.swift): the tint,
whether it is recording, its start and stop, then the levels' times and values and the cuts,
all in ms on the tape's clock (`epoch`). -/
def tapePaint (o : Overlay) : Paint :=
  { shader := "yap.tape", origin := o.epoch,
    scalars := o.look.tint ++
      [if o.isLive then 1 else 0, tapeMs o o.since, (o.stop.map (tapeMs o)).getD (-1)],
    arrays := [o.levels.map (tapeMs o ·.1), o.levels.map (fun l => (l.2 : Int)),
               (o.marks.reverse.map fun n => tapeMs o (o.since + n / 16))] }

def header (o : Overlay) (now : Nat) : Node :=
  .box { axis := .row, width := .fill, height := .fixed 26, gap := 7, align := .center } none
    [ .box { width := .fixed 7, height := .fixed 7, radius := 4, background := some o.look.color,
             shadow := some { color := withAlpha o.look.color 204, radius := 3 } } none [],
      .text { font := { size := 10, weight := 600, width := .expanded, tracking := 140 },
              color := o.look.color } o.look.label,
      .box { width := .fill, height := .fixed 1 } none [],
      .text { font := { size := 22, weight := 200, width := .expanded, tabular := true },
              color := cream } (clockText (o.stop.getD now - o.since)) ]

/-- The panel's shadow. SwiftUI's `shadow` on the original's whole stack shadows every view in it,
so the tape (an opaque Metal view) and the rule cast it too, below the panel's edge. -/
def panelShadow : Shadow := { color := ⟨0, 0, 0, 89⟩, radius := 14, y := 4 }

/-- `c` with its alpha scaled by `p` millionths. -/
def fade (c : Color) (p : Nat) : Color := withAlpha c (c.a.toNat * min p 1000000 / 1000000).toUInt8

def black : Color := ⟨0, 0, 0, 255⟩

/-- The rule above the transcript, at opacity `p` (millionths). -/
def rule (p : Nat) : Node :=
  .box { width := .fill, height := .fixed 1, background := some (fade edge p),
         shadow := some { panelShadow with color := fade panelShadow.color p } } none []

/-- The transcript's tail, at opacity `p` (millionths): full in TYPED, 60% before. -/
def transcript (o : Overlay) (t : String) (p : Nat) : Node :=
  .para { font := { size := 14 },
          color := fade (withAlpha cream (if o.look == .typed then 255 else 153)) p }
    { lineSpacing := 3 } (tailText t)

def tapeBox (o : Overlay) : Node :=
  .box { width := .fill, height := .fixed 58, background := some black,
         shadow := some panelShadow, paint := some (tapePaint o) } none []

/-- The panel's own box: black, continuous corners, the edge and the shadow. -/
def panelStyle : Style :=
  { width := .fill, padding := ⟨12, 16, 14, 16⟩, gap := 10, radius := 14,
    corner := .continuous, background := some black, border := some ⟨1, edge⟩,
    shadow := some panelShadow }

/-- The panel at rest showing `t`: the header, the tape and, once there is text, the rule and
the text. -/
def restingView (o : Overlay) (now : Nat) (t : String) : Node :=
  .box { width := .fill, padding := ⟨18, 18, 18, 18⟩ } none
    [ .box panelStyle none
        ([header o now, tapeBox o] ++
         (if t.isEmpty then [] else [rule 1000000, transcript o t 1000000])) ]

/-- `easeOut`'s curve, SwiftUI's `.easeOut` (the cubic Bézier through (0.58, 1)): the progress
at time fraction `u`, both in millionths, found by bisecting the curve's parameter. -/
def easeOut (u : Nat) : Nat :=
  let x (t : Nat) : Nat := (174 * (1000000 - t) * t * t / 100 + t * t * t) / 1000000000000
  let y (t : Nat) : Nat := (3 * (1000000 - t) * t * t + t * t * t) / 1000000000000
  if u ≥ 1000000 then 1000000 else y (go x 24 0 1000000)
where
  go (x : Nat → Nat) : Nat → Nat → Nat → Nat
    | 0, lo, _ => lo
    | k + 1, lo, hi => let mid := (lo + hi) / 2
                       if x mid < u then go x k mid hi else go x k lo mid

/-- How far the panel has eased to its text's height at `now`, in millionths. -/
def Overlay.progress (o : Overlay) (now : Nat) : Nat :=
  let t := now - (o.changed + textEaseDelayMs)
  if now < o.changed + textEaseDelayMs then 0
  else easeOut (min 1000000 (t * 1000000 / textEaseMs))

/-- `a + (b − a)·p`, `p` in millionths, to the nearest point. -/
def lerp (a b : Int) (p : Nat) : Int := a + ((b - a) * p + 500000) / 1000000

/-- Put `n` `y` points down from the top of a stack, 34 in from its sides (the panel's 18 and
its 16 of padding). -/
def placed (y : Int) (n : Node) : Node := .box { width := .fill, padding := ⟨y, 34, 0, 34⟩ } none [n]

/-- The panel easing from `o.prev` to `o.text` (SwiftUI's animation of the original's stack):
the window takes the new height at once and the panel's box eases from the old height to the
new, centred in it; the header, the tape and anything that stays (the rule, the old text)
move with its top; what is new (the rule and the new text) fades in where it ends up, and the
old text fades out as it moves. `m` measures both heights. -/
def easingView (m : TextMetrics) (o : Overlay) (now : Nat) (p : Nat) : Node :=
  let height (t : String) : Int := (Layout.measure m 556 (restingView o now t)).size.h - 36
  let h0 := height o.prev
  let h1 := height o.text
  let h := lerp h0 h1 p
  let top := 18 + (h1 - h + 1) / 2
  -- Under the header (26), the tape (58) and two gaps of 10, from the panel's top padding.
  let ruleY := 12 + 26 + 10 + 58 + 10
  let textY := ruleY + 1 + 10
  .box { axis := .stack, width := .fill, height := .fixed (h1 + 36).toNat } none
    ([ .box { width := .fill, padding := ⟨top, 18, 0, 18⟩ } none
         [ .box { panelStyle with height := .fixed h.toNat, padding := {} } none [] ],
       .box { width := .fill, padding := ⟨top + 12, 34, 0, 34⟩, gap := 10 } none
         [header o now, tapeBox o] ] ++
     (if o.prev.isEmpty then []
      else [placed (top + ruleY) (rule (if o.text.isEmpty then 1000000 - p else 1000000)),
            placed (top + textY) (transcript o o.prev (1000000 - p))]) ++
     (if o.text.isEmpty then []
      else (if o.prev.isEmpty then [placed (18 + ruleY) (rule p)] else []) ++
           [placed (18 + textY) (transcript o o.text p)]))

def overlayView (m : TextMetrics) (s : AppState) : Node :=
  let o := s.io.overlay
  if o.easing s.io.mono then easingView m o s.io.mono (o.progress s.io.mono)
  else restingView o s.io.mono o.text

/-- The panel: 520 points and 18 of room for the shadow on each side. -/
def panel (m : TextMetrics) (s : AppState) : Option PanelView :=
  if s.io.overlay.shown then some { width := 556, content := overlayView m s } else none

end Examples.Yap

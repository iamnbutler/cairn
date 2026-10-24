module

public import Examples.Yap.App

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

def overlayView (s : AppState) : Node :=
  let o := s.io.overlay
  .box { width := .fill, padding := ⟨18, 18, 18, 18⟩ } none
    [ .box { width := .fill, padding := ⟨12, 16, 14, 16⟩, gap := 10, radius := 14,
             corner := .continuous, background := some ⟨0, 0, 0, 255⟩, border := some ⟨1, edge⟩,
             shadow := some panelShadow } none
        ([ header o s.io.mono,
           .box { width := .fill, height := .fixed 58, background := some ⟨0, 0, 0, 255⟩,
                  shadow := some panelShadow, paint := some (tapePaint o) } none [] ] ++
         (if o.text.isEmpty then []
          else [ .box { width := .fill, height := .fixed 1, background := some edge,
                        shadow := some panelShadow } none [],
                 .para { font := { size := 14 },
                         color := withAlpha cream (if o.look == .typed then 255 else 153) }
                   { lineSpacing := 3 } (tailText o.text) ])) ]

/-- The panel: 520 points and 18 of room for the shadow on each side. -/
def panel (s : AppState) : Option PanelView :=
  if s.io.overlay.shown then some { width := 556, content := overlayView s } else none

end Examples.Yap

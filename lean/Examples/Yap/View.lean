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
* **The overlay** (^345): Yap's black panel at the bottom of the screen, 520 points wide: a
  coloured dot, the phase's label and the elapsed time; a waveform of bars drawn from the
  recording's levels (one bar per 20 ms window); the live preview in 14-point text, its last
  four lines (`Node.para`, keep tail).

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

/-! ## The overlay -/

def panelBg : Color := ⟨0, 0, 0, 235⟩
def edge : Color := ⟨255, 255, 255, 43⟩
def red : Color := ⟨255, 77, 46, 255⟩
def orange : Color := ⟨255, 158, 51, 255⟩
def blue : Color := ⟨97, 153, 255, 255⟩
def cream : Color := ⟨237, 232, 219, 255⟩
def dim : Color := ⟨237, 232, 219, 140⟩

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

/-- `m:ss` of milliseconds. -/
def clockText (ms : Nat) : String :=
  let s := ms / 1000
  s!"{s / 60}:{if s % 60 < 10 then "0" else ""}{s % 60}"

def bar (c : Color) (h : Nat) : Node :=
  .box { width := .fixed 2, height := .fixed h, radius := 1, background := some c } none []

/-- The last 280 characters, as Yap's overlay keeps them. -/
def tailText (t : String) : String := String.ofList (t.toList.drop (t.length - 280))

def overlayView (s : AppState) : Node :=
  let o := s.io.overlay
  let live := o.look == .listening || o.look == .handsFree
  .box { width := .fill, padding := ⟨14, 20, 16, 20⟩, gap := 10, radius := 14,
         background := some panelBg, border := some ⟨1, edge⟩ } none
    ([ .box { axis := .row, width := .fill, height := .fixed 16, gap := 8, align := .center } none
        [ .box { width := .fixed 8, height := .fixed 8, radius := 4, background := some o.look.color }
            none [],
          .text { font := { size := 11, weight := 600 }, color := o.look.color } o.look.label,
          .box { width := .fill, height := .fixed 1 } none [],
          .text { font := { size := 11, weight := 500, family := 1 }, color := dim }
            (if live then clockText (s.io.mono - o.since) else "") ],
       .box { axis := .row, width := .fill, height := .fixed 58, gap := 2, align := .center,
              justify := .finish, clip := true } none
         (o.levels.map (bar (if live then o.look.color else dim))) ] ++
     (if o.text.isEmpty then []
      else [ .box { width := .fill, height := .fixed 1, background := some edge } none [],
             .para { font := { size := 14, weight := 400 }, color := cream }
               { maxLines := some 4, keep := .tail } (tailText o.text) ]))

def panel (s : AppState) : Option PanelView :=
  if s.io.overlay.shown then some { width := 520, content := overlayView s } else none

end Examples.Yap

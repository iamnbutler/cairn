module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.App
public import Cairn.Layout.Core

/-! # Tray: a menu bar item and an overlay panel

The example for surfaces (docs/surfaces.md). An accessory app (no window, no Dock icon) with a
menu bar status item and a non-activating, click-through overlay panel.

* **The menu** is built from `menu`: a status line, Show/Hide Overlay (⌘O), the Keep Recent
  Items checkbox, Add Item (disabled while Keep Recent Items is off), the Recent Items submenu
  (the items, or "None yet", then Clear Recent Items, disabled when there are none) and Quit
  Tray (⌘Q). Opening the menu is a press on ^453 and is counted on the status line.
* **The overlay** shows 24 bars moving at 50 Hz (an `every 20` subscription while it is shown)
  and a growing caption wrapped to its last two lines (`Node.para`, keep tail). The bars are plain rects: the waveform path of decision 5 in
  docs/surfaces.md, measured in bench/surfaces.md.

| Id | Kind | What |
|---|---|---|
| ^450 | place | the status item's menu |
| ^451 | place | the Recent Items submenu, in ^450 |
| ^452 | place | the overlay panel |
| ^453 | move | open the menu (the status item's button) |
| ^454 | move | Show / Hide Overlay |
| ^455 | move | Keep Recent Items (checkbox) |
| ^456 | move | Add Item: enabled while Keep Recent Items is on |
| ^457 | move, keyed | a recent item |
| ^458 | move | Clear Recent Items: enabled when there are some |
| ^459 | move | Quit Tray |
| ^460 | invariant | at most five recent items |
| ^461, ^462 | flow | show the overlay; add an item and pick it |

Menu presence, enablement and checkmarks are proved in `Examples.Tray.Proofs`; the exports are
in `Examples.Tray.Abi`; the host is `host/Sources/CairnTray`. -/

@[expose] public section

namespace Examples.Tray
open Cairn Cairn.Claims

/-- How many recent items are kept. -/
def maxRecent : Nat := 5

structure State where
  overlay : Bool := false
  keep : Bool := true
  /-- Newest first, at most `maxRecent`. -/
  recent : List String := []
  /-- Items added so far: the next is "Item (added + 1)". -/
  added : Nat := 0
  /-- How many times the menu was opened. -/
  opens : Nat := 0
  picked : Option String := none
  /-- The waveform's phase: one step per tick while the overlay is shown. -/
  phase : Nat := 0
deriving Repr, DecidableEq, Inhabited

def openRef : ControlRef := ⟨453, 0⟩
def overlayRef : ControlRef := ⟨454, 0⟩
def keepRef : ControlRef := ⟨455, 0⟩
def addRef : ControlRef := ⟨456, 0⟩
def recentRef (k : Nat) : ControlRef := ⟨457, k⟩
def clearRef : ControlRef := ⟨458, 0⟩
def quitRef : ControlRef := ⟨459, 0⟩

/-- Add the next item at the front, keeping `maxRecent`. -/
def addItem (s : State) : State :=
  { s with recent := (s!"Item {s.added + 1}" :: s.recent).take maxRecent, added := s.added + 1 }

/-- Flip Keep Recent Items; turning it off forgets the items. -/
def flipKeep (s : State) : State :=
  if s.keep then { s with keep := false, recent := [] } else { s with keep := true }

theorem flipKeep_post (s : State) :
    (flipKeep s).keep = !s.keep ∧ (s.keep = true → (flipKeep s).recent = []) := by
  unfold flipKeep
  cases s.keep
  · exact ⟨rfl, fun h => nomatch h⟩
  · exact ⟨rfl, fun _ => rfl⟩

place ^450 trayMenu "Tray menu" where
  does "The menu of Tray's menu bar item: the status line, Show or Hide Overlay, Keep Recent Items, Add Item, the Recent Items submenu and Quit Tray."

place ^451 recentMenu "Recent Items submenu" in ^450 where
  does "The Recent Items submenu: the recent items, newest first (or None yet), then Clear Recent Items."

place ^452 overlayPanel "Overlay panel" where
  does "A panel at the bottom of the screen, over every app, that never takes focus or clicks: a row of moving bars and a line of text. Shown and hidden from the menu."

move ^453 openMenu (s : State) "Open the menu" in ^450 where
  does "Click Tray's menu bar item."
  sees "The menu opens; its status line counts one more opening. Nothing else changes."
  on press
    apply := { s with opens := s.opens + 1 }
    post s' := s'.opens = s.opens + 1 ∧ s'.recent = s.recent ∧ s'.overlay = s.overlay
    sound := by intro s; exact ⟨rfl, rfl, rfl⟩

move ^454 toggleOverlay (s : State) "Show Overlay" in ^450 where
  does "Choose Show Overlay (Hide Overlay while it is shown), or press ⌘O with the menu open."
  sees "The overlay appears at the bottom of the screen, or goes away. Nothing else changes."
  on press
    apply := { s with overlay := !s.overlay }
    post s' := s'.overlay = !s.overlay ∧ s'.recent = s.recent ∧ s'.keep = s.keep
    sound := by intro s; exact ⟨rfl, rfl, rfl⟩

move ^455 toggleKeep (s : State) "Keep Recent Items" in ^450 where
  does "Choose Keep Recent Items."
  sees "The checkmark flips. Turning it off forgets the recent items and disables Add Item."
  on press
    apply := flipKeep s
    post s' := s'.keep = !s.keep ∧ (s.keep = true → s'.recent = [])
    sound := by intro s; exact flipKeep_post s

move ^456 addMove (s : State) "Add Item" in ^450 where
  does "Choose Add Item while Keep Recent Items is on."
  sees "A new item is first under Recent Items; the oldest goes when there are more than five."
  enabled := s.keep
  on press
    apply := addItem s
    post s' := s'.recent.head? = some s!"Item {s.added + 1}" ∧ s'.recent.length ≤ maxRecent
    sound := by
      intro s _
      exact ⟨rfl, List.length_take_le _ _⟩

move ^457 pickRecent (s : State) (k : Nat) "Recent item" in ^451 where
  does "Choose an item under Recent Items."
  sees "The status line names the item. The list doesn't change."
  enabled := decide (k < s.recent.length)
  on press
    apply := { s with picked := s.recent[k]? }
    post s' := s'.picked = s.recent[k]? ∧ s'.recent = s.recent
    sound := by intro s k _; exact ⟨rfl, rfl⟩

move ^458 clearRecent (s : State) "Clear Recent Items" in ^451 where
  does "Choose Clear Recent Items under Recent Items, while there are some."
  sees "Recent Items says None yet."
  enabled := !s.recent.isEmpty
  on press
    apply := { s with recent := [], picked := none }
    post s' := s'.recent = [] ∧ s'.keep = s.keep
    sound := by intro s _; exact ⟨rfl, rfl⟩

move ^459 quitMove (s : State) "Quit Tray" in ^450 where
  does "Choose Quit Tray, or press ⌘Q with the menu open."
  sees "Tray's menu bar item and overlay go away; the app has quit."
  on press
    emit := (s, [.quit])
    post s' := s' = s
    sound := by intro s; rfl

/-- Ticks move the waveform; nothing else from the world matters. -/
def receive (s : State) : Msg → State × List Effect
  | .sub _ .tick => ({ s with phase := s.phase + 1 }, [])
  | _ => (s, [])

def machine : Machine State := { init := {}, moves := moves%, receive }

invariant ^460 fewRecent "At most five recent items" for machine where
  does "Recent Items never lists more than five items, however many are added."
  holds s := s.recent.length ≤ maxRecent
  init := Nat.zero_le _
  step := machine.preserves <|
    Move.all_cons (openMenu.preserves _ fun _ h => h)
      (Move.all_cons (toggleOverlay.preserves _ fun _ h => h)
      (Move.all_cons (toggleKeep.preserves _ fun s h => by
          unfold toggleKeep.press.apply flipKeep; split
          · exact Nat.zero_le _
          · exact h)
      (Move.all_cons (addMove.preserves _ fun _ _ _ => List.length_take_le _ _)
      (Move.all_cons (pickRecent.preserves _ fun _ _ _ h => h)
      (Move.all_cons (clearRecent.preserves _ fun _ _ _ => Nat.zero_le _)
      (Move.all_cons (quitMove.preserves _ fun _ h => h)
        Move.all_nil))))))
  receive := by
    intro s m h
    cases m with
    | sub _ e => cases e <;> exact h
    | _ => exact h

flow ^461 showOverlay "Show the overlay" for machine where
  does "Open the menu and choose Show Overlay."
  sees "The overlay is shown."
  goal s := s.overlay = true
  witness press ^453, press ^454

flow ^462 addAndPick "Add an item and pick it" for machine where
  does "Choose Add Item, then the new item under Recent Items."
  sees "The status line names the new item."
  goal s := s.picked.isSome = true ∧ s.recent.length = 1
  witness press ^456, press ^457 #0

def claimInfos : List ClaimInfo := claims%

/-! ## The menu -/

/-- The menu's first line. -/
def statusLine (s : State) : String :=
  let picked := match s.picked with
    | some t => s!", picked {t}"
    | none => ""
  s!"{s.recent.length} recent, menu opened {s.opens} times{picked}"

/-- Items `k`, `k + 1`, … for the titles `ts`. -/
def itemsFrom (k : Nat) : List String → List MenuItem
  | [] => []
  | t :: ts => .button (recentRef k) t :: itemsFrom (k + 1) ts

/-- The recent items, newest first, keyed by position; "None yet" when there are none. -/
def recentItems (s : State) : List MenuItem :=
  if s.recent.isEmpty then [MenuItem.info "None yet"] else itemsFrom 0 s.recent

def menu (s : State) : List MenuItem :=
  [ .info (statusLine s),
    .separator,
    .button overlayRef (if s.overlay then "Hide Overlay" else "Show Overlay")
      (shortcut := some { key := .char 'o' }),
    .check keepRef "Keep Recent Items" s.keep,
    .button addRef "Add Item" (enabled := s.keep),
    .submenu "Recent Items" (some 451)
      (recentItems s ++ [.separator,
        .button clearRef "Clear Recent Items" (enabled := !s.recent.isEmpty)]),
    .separator,
    .button quitRef "Quit Tray" (shortcut := some { key := .char 'q' }) ]

def statusItem (s : State) : StatusItem :=
  { symbol := if s.recent.isEmpty then "tray" else "tray.full", label := "Tray",
    control := openRef, menu := menu s }

/-! ## The overlay -/

def panelBg : Color := ⟨22, 22, 26, 225⟩
def barColor : Color := ⟨255, 149, 0, 255⟩
def textColor : Color := ⟨240, 240, 244, 255⟩

def bars : Nat := 24

/-- Bar `i`'s height at `phase`: a triangle wave, 4 to 40 points. -/
def barHeight (phase i : Nat) : Nat :=
  let t := (i * 3 + phase) % 24
  4 + 3 * (if t < 12 then t else 24 - t)

def bar (phase i : Nat) : Node :=
  .box { width := .fixed 8, height := .fixed (barHeight phase i), radius := 2,
         background := some barColor } none []

/-- Words the caption grows by, one every ten ticks, like a live transcript. -/
def words : List String :=
  ["the", "overlay", "keeps", "its", "last", "two", "lines", "as", "the", "text", "grows"]

/-- The overlay's text: a growing run of words, then the tick. Shown as a paragraph that keeps
its last two lines (`Node.para`, keep tail), so the newest words and the tick stay in view. -/
def caption (s : State) : String :=
  let n := s.phase / 10
  let ws := (List.range n).map fun i => words.getD (i % words.length) ""
  " ".intercalate (s!"Tray overlay, {s.recent.length} recent:" :: ws) ++ s!" · tick {s.phase}"

def overlayView (s : State) : Node :=
  .box { width := .fill, padding := ⟨14, 16, 14, 16⟩, gap := 10, radius := 12,
         background := some panelBg } none
    [ .box { axis := .row, width := .fill, height := .fixed 40, gap := 4, align := .finish }
        none ((List.range bars).map (bar s.phase)),
      .para { font := { size := 13, weight := 500 }, color := textColor }
        { maxLines := some 2, keep := .tail } (caption s) ]

def panel (s : State) : Option PanelView :=
  if s.overlay then some { width := 320, content := overlayView s } else none

def app : App State :=
  { machine.toApp [.statusItem 450 (some ∘ statusItem), .panel 452 panel] claimInfos with
    subscriptions := fun s => if s.overlay then [.every 20] else [] }

example : claimInfos.map (·.id) =
    [450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462] := by decide

/-- The surfaces' places are distinct (docs/surfaces.md, "What was built"). -/
example : (app.surfaces.map Surface.place).Nodup := by decide

end Examples.Tray

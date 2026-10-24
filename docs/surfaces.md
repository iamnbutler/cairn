# Surfaces: the menu bar menu and the overlay panel

Design for GOAL.md M2, "Done means" item 3: a menu bar item whose menu is built from Lean's view,
every item a move with an id, and a panel that never takes focus or clicks, both mirrored to
accessibility. Sections 1–7 are the design; [What was built](#what-was-built) says where the
implementation differs from it, and [Decisions](#decisions) records how the open questions were
settled. Sources are in [research/surfaces/](../research/surfaces/README.md).

M1 has one surface: a window whose whole content is `view : S → UI → Node`, laid out, hit tested
and painted by Metal. Yap (`~/code/yap`) has no window at all. It has:

| Surface | Yap today | What it shows |
|---|---|---|
| Status item and its menu | SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.menu)` (`App/YapApp.swift`); the icon is an SF Symbol per state (`waveform`, `mic.fill`, `text.bubble`) | a status line (`detail`); "Accessibility Is Off: Grant It…" when it is; Copy Last Transcript (disabled when there are none); a **Recent Transcripts** submenu of up to five items, "None yet", Open Transcripts Folder; three checkboxes (Dictate with *key*, Press Return After Dictating, which is disabled while dictation is off, Keep Transcripts (*N* Days)); Edit Dictionary…, Edit Settings…; Quit Yap (⌘Q) |
| Overlay | a borderless `NSPanel` with `.nonactivatingPanel`, level `.statusBar`, `ignoresMouseEvents`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, shown with `orderFrontRegardless` (`App/Overlay.swift`) | 520 pt wide, height from its content; a tinted dot, a phase label (REC, HANDS FREE, TRANSCRIBING, TYPED, NOT TYPED), a clock; a 58 pt Metal waveform (reel, scope over a tape ruler with orange cut marks, level meter; `App/Overlay.metal`); below a rule, the live transcript wrapped over about four lines, the last 280 characters |

Yap's own comment on the menu is the first constraint: "A native menu, not a panel: only a native
menu has submenus, and Recent Transcripts is one." Its comment on the overlay is the second: "Typing
goes to the app that was in front when the key went down, and a panel that became key would be that
app."

## Summary

1. **The menu is native.** Lean's view emits a semantic description of the status item and its
   menu (items, labels, checkmarks, enabled state, submenus, shortcuts, each actionable item a
   `Control` naming a move). The host reconciles a real `NSStatusItem` and `NSMenu` with it. A
   selected item comes back as an event naming the item's `ControlRef`; the runtime delivers
   `press ref` only if that ref is an enabled item of the menu Lean is showing. Presence,
   enablement and checkmarks are proved on the description, with no layout in between; that
   AppKit shows the description and reports the item that was chosen is an `assume` claim checked
   through the debug socket and the accessibility tree.
2. **The overlay is a Metal panel.** A second Metal surface, drawn from Lean frames exactly like
   the window, in a host-owned `NSPanel` whose window behaviour (non-activating, never key,
   click-through, every Space, over full-screen apps) is fixed by its kind, not configurable from
   Lean. Lean decides whether it is shown, its content, its width (its height comes from layout)
   and where it is anchored; the host resolves the anchor against a screen.
3. **An app is a static list of surfaces.** `App.view : S → UI → Node` becomes
   `App.surfaces : List (Surface S)`, declared once, each with a `place` claim id as its durable
   identity and its own view function. Which surfaces exist never changes at run time; whether
   each is shown, and what it shows, does. M1 apps become one `window` surface through an
   adapter, and their theorems carry over.
4. **The app is an accessory** when it declares no window: `LSUIElement` in the bundle and
   `.accessory` activation policy, no Dock icon and no main menu.
5. **The frame becomes a list of surfaces** and surface-local events say which surface they are
   for. That is a new frame and event version, to land after (or together with) workstream Q's
   effects changes, not alongside them.

## 1. The menu

### Native NSMenu or a Metal popover

| | Native: Lean emits a menu description, the host builds `NSMenu` | Custom: Lean draws a popover with Metal |
|---|---|---|
| Look and feel | The system menu: vibrancy, dark mode, the menu font, checkmarks, the ⌘Q glyph, highlight, submenu arrows, Liquid Glass or whatever comes next | A lookalike that drifts from the system with every macOS release |
| Submenus | Free, with AppKit's submenu-aiming heuristics | A second popover window, hover intent, edge flipping, all written and proved by us |
| Keyboard | Arrows, type-select, Return, Escape, ⌘Q while open: free | Needs a key window. A popover that becomes key activates the app, which is what Yap must never do while it is about to type into the frontmost app (the menu is not open then, but the activation policy and focus rules get harder) |
| Dismissal | AppKit tracks the menu modally and dismisses it on an outside click, Escape, or app switch | Global event monitors for outside clicks and Space switches, trusted and fiddly |
| VoiceOver | Menu items are real AX menu items, announced as such (role, checked, disabled, submenu); `^N` as the item's identifier | Our AX mirror would have to imitate `AXMenu`/`AXMenuItem` roles and menu-tracking notifications, which no custom-rendered toolkit we read does well |
| Presence, enablement, checked | Proved on the description (simpler than M1: no layout) | Proved on the view, through layout and the frame (as M1) |
| Pressable | The runtime half is proved (a selection of an enabled item delivers exactly `press ref`); AppKit's half (the item the person chose is the item reported) is an `assume` with conformance evidence | Proved end to end through hit testing, as M1's `click_center_presses` |
| Conformance | The socket reads the `NSMenu` AppKit holds and compares it with the frame's menu; it selects items through `NSMenu.performActionForItem(at:)` | As M1, plus window management |
| Work | A frame section, a reconciler, two events, a few theorems | A popover window kind, submenus, keyboard navigation, dismissal, AX roles, and the theorems for all of it |

**Recommendation: native.** The claims GOAL.md asks of the menu are presence and enablement
("menu presence and enablement, as in M1"); the native design proves both more directly than M1
does, because the menu description *is* the view, with no layout between the move and the item.
What it gives up is the pressable proof through hit testing, and what replaces it is one assumption
about AppKit that is narrow (the item chosen is the item reported) and testable. A Metal popover
would buy a proof about geometry that exists only because we chose to replace AppKit, and pay for
it with a worse menu: no real submenus, a key window, home-made dismissal and imitation
accessibility. Every framework we looked at that models menus as data (GPUI, Tauri/muda,
Electron, Flutter's `PlatformMenuBar`, SwiftUI's `MenuBarExtra` in `.menu` style) renders them
natively for these reasons; the ones that draw their own (iced_aw, VS Code's custom title bar)
do it to look the same across platforms, which Cairn doesn't need.

One development cuts the other way: macOS 27 adds `NSStatusItem.expandedInterfaceDelegate`, an
official hook for a status item that shows its own window instead of a menu, so that it
"participate[s] in keyboard navigation and menu tracking behaviors" (NSStatusItem.h, SDK 27.0).
That makes a Metal popover less home-made than it was (opening, closing and keyboard handoff
become AppKit's), but it still has no submenus or menu semantics for VoiceOver, so it doesn't
change the recommendation. It is the path to take if a later app wants a rich popover.

This is also the rule for the line between Lean and the host that the rest of Cairn already
follows: Lean owns meaning (which items, in which state, doing which move), the host owns the
pixels. The menu just moves the pixels to AppKit instead of Metal.

### The description

```lean
/-- A keyboard shortcut shown on a menu item (⌘Q). Shown and honoured only while the menu is
open: an accessory app has no main menu. -/
structure Shortcut where
  key : Key        -- `.char 'q'`
  mods : Mods      -- command

inductive MenuItem where
  /-- An item that performs a move. `control.checked = some b` makes it a checkbox item
  (state on/off); `enabled = false` greys it out. -/
  | item (control : Control) (enabled : Bool := true) (shortcut : Option Shortcut := none)
  /-- A line of text that does nothing: a status line, "None yet". Shown disabled. -/
  | info (label : String)
  /-- A submenu. `place` is the place claim it is, if it has one ("Recent Transcripts"). -/
  | submenu (label : String) (place : Option ClaimId) (items : List MenuItem)
  | separator

structure StatusItem where
  /-- An SF Symbol name, drawn as a template image so it follows the menu bar's appearance. -/
  symbol : String
  /-- Optional text beside the symbol. -/
  title : String := ""
  /-- What VoiceOver says for the button ("Yap, recording"). -/
  label : String
  /-- Opening the menu is a press on this control. -/
  control : Control
  menu : List MenuItem
```

`MenuItem` is a nested inductive, so every function over it follows the AGENTS.md rule: a
structural pair (`f` with `where go : List MenuItem → _`) and hand-written `DecidableEq`.

Yap's menu as data, roughly (ids are placeholders; the Yap lane issues the real ones):

```lean
def menu (s : State) : List MenuItem :=
  [ .info s.detail ] ++
  (if s.trusted then [] else [ .item (btn grantRef "Accessibility Is Off: Grant It…") ]) ++
  [ .separator,
    .item (btn copyLastRef "Copy Last Transcript") (enabled := !s.recent.isEmpty),
    .submenu "Recent Transcripts" (some recentPlace)
      ((if s.recent.isEmpty then [.info "None yet"] else []) ++
       s.recent.enum.map (fun (i, t) => .item (btn ⟨copyRecent, i + 1⟩ (label t))) ++
       [ .separator, .item (btn openFolderRef "Open Transcripts Folder") ]),
    .separator,
    .item (check enabledRef s!"Dictate with {s.keyName}" s.enabled),
    .item (check submitsRef "Press Return After Dictating" s.submits) (enabled := s.enabled),
    .item (check keepRef s!"Keep Transcripts ({s.config.retentionDays} Days)" s.keep),
    .separator,
    .item (btn editDictRef "Edit Dictionary…"), .item (btn editConfigRef "Edit Settings…"),
    .separator,
    .item (btn quitRef "Quit Yap") (shortcut := some ⟨.char 'q', { command := true }⟩) ]
```

Keyed moves work as they do in M1: the five recent transcripts are one move, `copyRecent`, with
keys 1–5 (`^N#1` … `^N#5`).

Disabled items keep their control. "Copy Last Transcript" is on screen and disabled when there
are no transcripts, so the presence theorem for it is "always present" and the enablement theorem
is "enabled iff `s.recent ≠ []`". This is new: in M1 a control on screen was always pressable, and
a disabled move had no control. `MenuItem.item`'s `enabled` flag is what the runtime checks, and
`dispatch_disabled` already makes a press of a disabled move a no-op, so there are two independent
reasons a greyed-out item does nothing.

### Selecting an item

| Host → Lean | When | Runtime → app |
|---|---|---|
| `menuOpen place` | `NSMenuDelegate.menuWillOpen` on the status item's menu | `press c`, where `c` is the status item's `control`, if the status item is shown |
| `menuSelect ref` | the item's action fires | `press ref`, if `ref` is an `item` of the status item's current menu (in any submenu) with `enabled = true`; otherwise nothing |
| `menuClose place` | `menuDidClose` | nothing in M2 (recorded in `UI` for views that want it) |

So opening the menu is a move, which is how Yap's "re-measure Accessibility when the menu opens"
(`refreshTrust`) becomes a move whose handler emits a permission check request (workstream Q's
requests). Every action still names a control, and every control a claim.

The check against the current menu matters because the menu can be open while Lean's state
changes (a transcript lands, a recording starts). The host reports the ref the person chose; Lean
accepts it only if that item is still present and enabled in the menu it is showing now. This is
the menu's version of "slide-off cancels". A press can therefore be dropped if the menu changed in
the frames between what the person saw and what Lean holds; it can never press something that is
not there.

**Theorems** (in `Cairn.Runtime`, for every app):

- `menu_route_names`: every action produced by `menuSelect` names an enabled item control of the
  status item's menu in the runtime state; `menuOpen` produces only the status item's control.
- `menu_select_presses`: if `ref` is an enabled item of the current menu, `menuSelect ref`
  delivers exactly `[press ref]`. This is the menu's `click_presses`, without layout.
- `step_delivers` and `deliver_effect` carry over unchanged, so "every effect comes from a move"
  holds for menu items too.

**Per app** (Yap's proofs, in the style of `reset_present_iff`):

- presence: `copyLastRef ∈ refs (menu s)` for every `s`; `grantRef ∈ refs (menu s) ↔ ¬ s.trusted`;
  `⟨copyRecent, k⟩ ∈ refs (menu s) ↔ 1 ≤ k ∧ k ≤ s.recent.length`;
- enablement: `enabledOf (menu s) copyLastRef = some (!s.recent.isEmpty)`;
  `enabledOf (menu s) submitsRef = some s.enabled`;
- checked: `checkedOf (menu s) keepRef = some (some s.keep)`, and so on;
- `move.enabled` agrees with the item's `enabled` (so the greyed state and the move's own
  `enabled` can't drift): stated per item, proved by `decide`/`simp` on the definitions.

No layout, metrics or hit testing appears in any of these.

### The host

- **Status item.** `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`,
  its `button.image` the SF Symbol as a template, `button.title`, the button's accessibility label
  and identifier (`^N` of the status item's control). `statusItem.menu` is the `NSMenu`.
- **Reconciling.** On each frame whose status item changed, the host updates the `NSMenu` in
  place: items keyed like the AX mirror's elements (by `ControlRef`, else by parent key, kind and
  position), titles, `state`, `isEnabled`, `keyEquivalent` and submenus updated on the existing
  `NSMenuItem`s, and items inserted or removed only where the shape changed. Rebuilding the menu
  wholesale while it is open would drop the highlighted item. `autoenablesItems = false` on every
  menu: with it on, AppKit ignores `isEnabled` and validates items itself (NSMenu.h). Each
  `NSMenuItem` gets its ref in `representedObject`, `setAccessibilityIdentifier("^N#K")`, and a
  target/action that sends `menuSelect` with its ref. Setting `NSMenuItem.identifier` alone does
  **not** reach accessibility (checked on macOS 27.0.1: `accessibilityIdentifier()` stayed empty);
  `NSMenuItem` adopts `NSAccessibility`, so the explicit setter works.
- **While the menu is open** AppKit runs the main run loop in event-tracking mode. The host's
  frame hop (`MainHop`) uses `DispatchQueue.main.async`, which is serviced in that mode, so a
  frame that changes the menu reaches the main thread while it is open (CFRunLoop drains the
  main queue in every common mode, and common modes include event tracking). Timers the host owns
  (the effects lane's) must be scheduled in `.common` modes: `Timer.scheduledTimer` uses the
  default mode and stalls while a menu is open. **Not confirmed:** that changing an item's title,
  state or the menu's structure *while it is displayed* shows up live. NSMenu.h only promises it
  for item views, and an old report says titles don't update. The spike (section 7) must measure
  it; if it doesn't, the fallback is that the open menu keeps what it showed at open (Lean's
  check on `menuSelect` keeps that safe) and `menuNeedsUpdate` applies the newest frame at the
  next open.
- **Not inside the open/close callbacks.** NSMenu.h: "Do not modify the structure of the menu or
  the menu items from within" `menuWillOpen`/`menuDidClose`. The host only sends `menuOpen` there;
  the frame it causes arrives later through the hop.
- **Removal and visibility.** The status item gets a fixed `autosaveName`; the host doesn't set
  `.removalAllowed`, and observes `isVisible` (the system can hide status items, for example
  behind the notch). Being hidden doesn't change what Lean sees in M2.
- **Shortcuts** are `keyEquivalent` and `keyEquivalentModifierMask`, honoured by AppKit while the
  menu is open. An accessory app has no main menu, so ⌘Q does nothing while the menu is closed;
  that matches Yap.

## 2. The overlay panel

### What the host fixes

The panel's window behaviour is the definition of the kind, fixed in the host and listed in
trusted.md, not fields Lean sets. Lean can't observe or prove any of it, and the only app that
needs a panel needs exactly this one:

| Property | Value | Why |
|---|---|---|
| Class and style | `NSPanel`, `[.borderless, .nonactivatingPanel]` | showing it never activates Cairn |
| `canBecomeKey`, `canBecomeMain` | `false` (subclass) | it is never key, so keystrokes keep going to the app in front |
| `ignoresMouseEvents` | `true` | clicks, scrolls and hovers pass through to whatever is under it |
| `level` | `.statusBar` | above normal and floating windows, as Yap |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` | on every Space, over full-screen apps, not moved by Exposé, not in ⌘\` (macOS 13's `.canJoinAllApplications`, which the header recommends "for floating windows and system overlays", is the alternative to try if full-screen Spaces misbehave; at most one of it, `.primary`, `.auxiliary`) |
| `hidesOnDeactivate` | `false`, set explicitly | an accessory app is never active; the panel must not hide because of it. The documented NSPanel default is `true`; a borderless non-activating panel measured `false`, so don't rely on either |
| `isOpaque`, `backgroundColor`, `hasShadow` | `false`, `.clear`, `false` | Lean draws the rounded black card; outside it is transparent |
| Showing | `orderFrontRegardless()` when Lean shows it, `orderOut` when Lean hides it | `makeKeyAndOrderFront` would try to make it key |
| Metal layer | not opaque, cleared to transparent, premultiplied alpha | the corners and the 18 pt margin are see-through |

The view inside is the same `HostView` and render loop as the window's (one per Metal surface),
minus input: it registers no tracking area and doesn't accept first responder. Its display link
comes from the panel's view, so it follows the panel's screen.

### What Lean decides

```lean
inductive Anchor where
  /-- Horizontally centred, `offset` points above the bottom of the screen's visible frame
  (above the Dock). -/
  | bottomCenter (offset : Nat)

inductive ScreenChoice where
  /-- The screen the pointer is on when the panel is shown; it stays there until hidden. -/
  | pointer
  | main

structure PanelView where
  /-- Width in points; the height is the laid-out content's. -/
  width : Nat
  anchor : Anchor := .bottomCenter 56
  screen : ScreenChoice := .pointer
  content : Node
```

- **Shown or not**: the panel's view returns `Option PanelView`; `none` is hidden. The view is
  given the text metrics the panel is laid out with, so it can measure its own content (Yap's
  overlay eases between the heights of its old and new text). Yap's fade-out
  (0.18 s) is a host animation of `alphaValue` on hide, a look-only choice listed in trusted.md,
  unless we decide Lean should own it (open question 6).
- **Size.** Lean lays the content out at `width × ∞` (a `hug` column) and the frame carries the
  resulting size. The panel's size is an output of Lean, not an input as the window's is: the host
  never sends the panel a `resize`. The panel keeps its bottom edge as it grows, as Yap's does.
- **Placement.** The anchor is resolved by the host against the chosen screen's `visibleFrame`
  when the panel is shown and again when its size changes, never while shown on another screen.
  The alternative, a `screens` event so Lean computes absolute positions and can prove "the
  panel is inside the visible frame", is open question 3.
- **Scale.** The panel's backing scale is its screen's; the host sends the panel's own `scale`
  event when it moves to a screen with a different one.

### The waveform

Yap's waveform is a fragment shader running at 60 frames a second over a level history the host
keeps, with motion driven by a free-running clock. Cairn's renderer has rects, rounded rects,
borders, text and clips. Two ways to get there:

- **From primitives (recommended to try first).** Lean keeps the level history (the microphone
  levels subscription from workstream Q, at the rate it delivers), the cut marks, elapsed tape
  time and the phase, and draws the scope as thin rects, the ruler and cut marks as rects, and the
  meter as segments. Everything on screen is then a function of Lean state, so "the overlay shows
  the levels it was sent" and "a cut mark appears at each chunk" are theorems. Cost: one Lean step
  and frame per level sample, a few hundred rects per frame; to be measured in `bench/`. It will
  not glow like Yap's.
- **A host shader.** A new draw record `wave (rect) (params)`: Lean supplies the data (levels,
  cuts, tint, elapsed) and a trusted host shader paints it, animating its free-running traces on
  the display link between Lean frames. Closer to Yap's look; one more renderer assumption
  ("the wave shader paints the levels it is given in its rect and nowhere else"), checked by
  goldens and probes.

Which one is open question 5. Either way the decisions (when there is a waveform, what levels and
cuts it shows, which colour) stay in Lean.

### Wrapped text

The transcript wraps over about four lines. M1's text is single-line. The overlay needs wrapping
in layout: greedy line breaks at spaces using the host's measured offsets, each line its own text
draw and AX run, with a theorem that every line fits the width (or is one unbreakable word). That
belongs to the layout workstream; it is listed here because the overlay can't ship without it.
The 280-character tail and the leading "…" are ordinary view code in Lean.

### Accessibility

The panel's `HostView` exposes its AX nodes as the window's does: static text for the phase label,
the clock and the transcript. VoiceOver can read the panel by navigating to it; it has no
controls, so nothing in it can be pressed by AXPress either. That a window with
`ignoresMouseEvents` stays reachable by VoiceOver is not documented; the spike checks it with
Accessibility Inspector. Whether the live transcript should
also be spoken as it arrives (an `announcementRequested` notification, the macOS equivalent of an
ARIA live region) is open question 7: Yap doesn't, and it would talk over the person dictating.

### What can be proved

- **It takes no clicks, in Lean's terms.** The overlay's content has no controls (a theorem per
  app: `(overlay s ui).controls = []`, or by construction if the panel kind's view returns a
  control-free `Node` type). With `route_names`, no event addressed to the panel can produce an
  action. The host also never sends it pointer or key events; that it can't receive any is the
  window-server half, an assumption.
- **It shows what the state says.** The phase label is the phase's; the transcript shown is the
  tail of the current recording's preview; the panel is shown exactly while recording,
  transcribing, or within the hide delay after; **a late chunk for an older recording never
  changes it** (Yap's `owner` check, as an invariant of the dictation machine and a property of
  the view).
- **Layout facts** as in M1: the card fits the panel width; with wrapping, every line fits.
- **Not provable**: that it is never key, ignores the mouse, floats over full-screen apps, and is
  on the right screen. These are the trusted.md entries below, with conformance checks.

## 3. Several surfaces in one app

### The app type

```lean
inductive Surface (S : Type) where
  /-- M1's window. `none` closes it (not used in M2). -/
  | window (place : ClaimId) (title : String) (size : Size) (view : S → UI → Node)
  /-- A non-activating, click-through overlay (section 2). -/
  | panel (place : ClaimId) (view : S → UI → Option PanelView)
  /-- A menu bar status item and its menu (section 1). `none` removes it from the menu bar. -/
  | statusItem (place : ClaimId) (view : S → Option StatusItem)

structure App (S : Type) where
  init : S
  surfaces : List (Surface S)
  surfaces_nodup : (surfaces.map Surface.place).Nodup := by decide
  update : S → Action → S × List Effect
  claims : List ClaimInfo
  initFocus : Option ControlRef := none
```

- **Static.** The list is fixed when the app is defined; only each surface's visibility and
  content change. The host creates every surface's AppKit object at launch, and reconciling is
  per surface, never "which windows exist now". Yap needs no more; dynamic windows (documents) are
  a later milestone, and a `List` of declared surfaces leaves room for a keyed `windows` kind then.
- **Identity is a place claim.** Each surface's `place` is a `place` claim (`place ^P overlay
  "Dictation overlay"`), so the map gets one area per surface and every move says `in ^P` which
  surface it appears in. A submenu with a place (Recent Transcripts) is a place `in` the menu's
  place. A `#guard`/`decide` check in the app module that every surface's place is a declared,
  unretired place claim, like the claim commands' `in ^P` check, keeps a surface from naming a
  move.
- **Types keep kinds apart.** A status item can't be given Metal content, nor a panel a menu.
- **Compatibility.** `App.ofWindow place title size view` builds an M1-style app; Counter, Basics
  and Todo change one line, and their presence theorems, stated about `view`, still hold because
  `relayout` for a window surface is today's `relayout`.

### The runtime

`Runtime.State` keeps, per Metal surface, its `UI` and its `Laid` (hover, press, focus and size
are per surface), and, for the status item, the `StatusItem` it is showing (what `menuSelect` is
checked against). `step` re-runs the views whose input changed (the app state, or that surface's
`UI`) and repairs each surface's `UI` against its own tree, as `fixUI` does today.

Keyboard focus is per surface but only a key window receives keys: panels never do, menus are
AppKit's. With Yap having no window, M2's runtime has no keyboard focus in use at all.

The M1 theorems become per surface: `step_sound` holds for each Metal surface's `UI` against its
own `Laid`; `route_names` holds for events addressed to a surface against that surface's tree;
`menu_route_names` (above) for the menu.

### Accessory apps

An app with no `window` surface is an accessory app:

- the bundle `make yap` builds sets `LSUIElement = YES` in `Info.plist`, so there is no Dock
  icon even for the instant before code runs (Yap does this);
- the host also calls `setActivationPolicy(.accessory)`, which is what makes a bare executable
  (`make demo`) behave the same;
- the host installs no main menu (M1's Hide/Quit/Edit/Window menus): an accessory app's main menu
  is never shown, and Quit is the status menu's move;
- `applicationShouldTerminateAfterLastWindowClosed` returns `false`.

Whether an app is an accessory is derived from its surfaces, not a separate flag, so it can't
disagree with them (open question 4 asks whether an app with a window and a status item should be
able to choose).

## 4. The boundary

### Frame

The frame becomes a list of surface records; effects stay global (they are the app's, not a
surface's):

```
offset  size  field
0       4     magic "CAFR"
4       2     u16 version (next after workstream Q's)
6       2     u16 flags = 0
8       4+4   surfaces: u32 count, u32 byteLength, then the surface records
.       4+4   effects (as today, plus Q's)
```

Each surface record starts `[kind, shown, 0, 0]` then `u32 place`, then by kind:

- **window / panel:** `i32 w, i32 h` (for a panel, Lean's size), for a panel its anchor and screen
  choice, then today's draws, ax, textInput and cursor sections. A hidden surface has empty
  sections. The render thread for a surface skips every other surface's record by its length,
  as it skips the ax section today.
- **statusItem:** strings `symbol`, `title`, `label`, the status item's control ref, then the
  menu as a flat list of item records, parents before children, each with a parent index (as the
  ax list does): `[kind, enabled, checked, hasShortcut]`, control ref, parent, shortcut key and
  mods, label.

Every M1 theorem about `Frame.ofLaid` is reused per Metal surface. New ones: the menu records'
control refs are exactly the description's, in order (`controls_ofMenu`); parents come first
(`parent_lt_ofMenu`); the round trip for the new records, by the same arithmetic-spec method.

### Events

Surface-local events (pointer, key, text, resize, scale, focus) need to say which surface they are
for. Two ways:

- each such record carries a `u32 surface` (the place id) after its head; or
- one new event, `surface place`, that sets the target of the events after it in the batch.

The first is simpler to prove things about (an event is self-contained); the second keeps the
records the same size. Proposed: the first. New events: `menuOpen place`, `menuClose place`,
`menuSelect ref`.

### Ordering with workstream Q

Q (lane `effects`) is changing `App.lean`, the runtime, the ABI and both encodings for time,
requests and subscriptions. At the time of writing its branch had not been pushed and
`docs/effects.md` did not exist, so this design assumes only what GOAL.md says Q delivers:

- `update` receives the clock, and apps ask for timers: the overlay's clock text (updated every
  0.25 s while recording) is a timer subscription, not a host `TimelineView`;
- requests answer back: "Accessibility Is Off: Grant It…", Open Transcripts Folder, Edit
  Dictionary…, Edit Settings… are moves that emit open-URL or open-file requests; the status
  item's open move emits a permission check;
- subscriptions: the microphone levels the waveform shows;
- Quit is a move that emits a `quit` effect.

Surfaces need nothing else from Q, and Q needs nothing from surfaces. The one collision is the
version number and the shape of `App`: land Q first, then surfaces as the following version, and
have the surfaces lane rebase onto Q's `App` (adding `surfaces` beside Q's subscription field). If
Q models subscriptions as a declarative function of state the host reconciles (`subs : S → List
Sub`), surfaces are the same pattern and should share its reconciliation vocabulary.

## 5. Conformance and the debug socket

New socket commands:

| Command | Does | Reply |
|---|---|---|
| `{"cmd":"surfaces"}` | | every surface: place, kind, shown; for windows and panels the `NSWindow`'s frame, screen, level, `collectionBehavior`, `ignoresMouseEvents`, `canBecomeKey`, `isKeyWindow`, alpha |
| `{"cmd":"frame","surface":P}` | | that surface's applied frame (today's reply, per surface) |
| `{"cmd":"ax","surface":P}` | | that surface's AX elements |
| `{"cmd":"menu"}` | | the `NSMenu` tree as AppKit holds it: title, `state`, `isEnabled`, `identifier`, key equivalent, submenus |
| `{"cmd":"menuOpen"}` / `{"cmd":"menuClose"}` | calls the menu delegate's `menuWillOpen` / `menuDidClose` | `seq` |
| `{"cmd":"menuSelect","id":"^N#K"}` | finds the item by identifier and calls `NSMenu.performActionForItem(at:)` on its menu, AppKit's own dispatch path | `seq` |

- The driver compares `menu` with the frame's menu records after every step, as it compares the
  AX tree today, and the walk gains menu items as action groups (each enabled item's
  `menuSelect`, `menuOpen`) and disabled items as negative checks (`menuSelect` on a disabled item
  changes nothing).
- `surfaces` checks the panel's window properties against the table in section 2 after every
  step, and that no Cairn window is key while the panel is shown.
- Under the socket the status item is not added to the real menu bar (the `NSMenu` is built
  detached), and the panel is drawn without being ordered front over the person's screen
  (offscreen render, `source: "offscreen"`), unless `--show-surfaces` asks for it. The person at
  the machine keeps working, as in M1.
- An optional end-to-end check, outside `make check`, uses the real menu bar through
  accessibility (open the status item, read the `AXMenuItem`s, press one) to exercise the path the
  socket skips.

## 6. What goes into trusted.md

New entries, each an `assume` claim with its check:

- **The menu shows the description** (`menu.render`): after each frame, the `NSMenu` tree has one
  item per description item, in order, with its title, state, enabled flag, key equivalent and
  identifier. Evidence: the socket's `menu` against every frame in conformance runs; a fuzz of
  random descriptions through the reconciler, compared after each update (including updates while
  "open").
- **The item chosen is the item reported** (`menu.select`): AppKit calls an item's action only
  for the item the person (or VoiceOver, or the keyboard) chose, and the host reports that item's
  ref. Evidence: `menuSelect` through `performActionForItem(at:)` for every item in the walk; the
  optional real-menu-bar check.
- **Menu open and close** come from `menuWillOpen` and `menuDidClose`, once each per opening.
- **Reconciliation keys**: an item is updated in place when its key matches; a duplicate
  `ControlRef` in one menu updates the first (as the AX mirror).
- **Accessibility of the menu** is AppKit's: role, title, checked, enabled and `^N` identifier
  come from the `NSMenuItem`. Checked by the optional real-menu-bar check.
- **The panel never takes focus or clicks** (`panel.inert`): with the properties in section 2's
  table, the window server never makes it key, never activates Cairn because of it, and delivers
  no mouse events to it; it is shown on every Space and over full-screen apps. Evidence: the
  socket's `surfaces` after every step; a manual checklist for Spaces, full screen and Stage
  Manager (these are window-server behaviour with no API to assert from inside the app).
- **Placement**: the anchor resolves against the chosen screen's `visibleFrame`, once when shown
  and on each size change; the pointer's screen is `NSEvent.mouseLocation`'s at that moment.
- **Panel size**: the panel's content size is the frame's size, and its bottom edge stays put.
- **Fade-out**: the hide animation (if the host keeps it) is look only.
- **Transparency**: the panel's layer composites premultiplied colours over the desktop; outside
  Lean's drawn rects it is fully transparent. Goldens with alpha.
- **The wave shader** (only if chosen): paints the levels it is given, in its rect.
- **Status item image**: the SF Symbol name exists on the running macOS (fallback: a fixed
  symbol, and the substitution is logged).
- **Accessory policy**: `LSUIElement` and `.accessory` give no Dock icon and no app switcher
  entry.
- **Run-loop modes**: frames are applied during menu tracking (main-queue hop), and the host's
  timers fire then (common modes).

## 7. Order of work

1. **Spike (host only, no Lean changes):** a Swift fixture `AppCore` with a status item whose
   menu is reconciled from a hand-made description (including updates every 100 ms while open),
   and a panel with the section 2 properties drawn by the existing renderer. Confirms the
   run-loop-mode and reconciliation behaviour and the panel's window behaviour before any format
   work.
2. **Types and runtime:** `Surface`, `MenuItem`, `StatusItem`, `PanelView`; per-surface `UI` and
   `Laid`; `menuOpen`/`menuSelect`; the runtime theorems; M1 apps through `App.ofWindow`.
3. **Frame and events** (after Q's version lands): the surface list, menu records, surface ids on
   events, round trips, corpus and fuzz.
4. **Host:** surfaces created from the app, the status item reconciler, the panel, accessory
   policy, the socket commands, trusted.md.
5. **Wrapped text** (layout workstream) and the waveform (open question 5) in parallel.
6. **Yap's menu and overlay** on all of the above, with their presence, enablement and overlay
   theorems.

## What was built

The structure (types, runtime, frame v3, events v2) follows sections 3 and 4 with these
differences:

- **`Surface`** is `window place title view`, `panel place view`, `statusItem place view`
  (`lean/Cairn/App.lean`; `MenuItem`, `StatusItem`, `PanelView`, `Anchor` in
  `lean/Cairn/Surface.lean`). A window has no `size` field: the host opens it at its launch size
  and Lean lays out at whatever `resize` says, as in M1. A panel's view takes only the state
  (`S → Option PanelView`): panels ignore the mouse, so they have no hover or press `UI` to
  read. M1 apps pass `[.window place title view]` to `toApp`; `App.view` is now derived (the
  first window's view), so every M1 theorem stated about `app.view` holds unchanged.
- **At most one window.** The runtime routes window events to the first `window` surface;
  later ones are shown nowhere. Multiple windows are a later milestone.
- **No `surfaces_nodup` field.** Distinct places are checked per app with `decide` next to its
  claims, as the claim commands check `in ^P`, rather than carried as a proof obligation on
  every `App`.
- **`Runtime.State.surfaces : List Shown`** keeps, per surface, what it shows: the window's title,
  a shown panel's `PanelView`, its size and its laid tree, a shown status item's `StatusItem`. It
  is recomputed only when an action was delivered (`shows`), like the window's layout. The panel's
  height comes from `Config.panelHeight` (its content's measured height), so wrapped text can
  refine it without touching the runtime.
- **Events address a surface by wrapping**, not by a `u32` in every record: tag 21 `surface place
  e` carries one local event, and a bare local event is the window's, so M1 batches mean what
  they meant. The decoder rejects a wrapped non-local event, so wrapping never nests.
  `menuSelect` carries the status item's place as well as the ref, so an app with two status
  items can't confuse them.
- **One surface record shape** (docs/frame.md): every record has every field, at defaults for
  kinds that don't use them. A record costs about 60 bytes of defaults; in exchange the decoder
  and its proof have no per-kind branches.

The runtime theorems are in `lean/Cairn/Runtime/Proofs.lean`: `menu_route_names` (a menu event
emits only presses of refs the menu offers), `menu_select_presses` (selecting an enabled item
presses exactly it), `menu_open_presses`, `menu_select_stale` (a selection of a ref that is not
an enabled item of the menu being shown changes nothing: `step` returns the same state and no
effects), `menu_select_absent`, and `route_surface_other` (a surface event for a place that is not
the window's is dropped). `route_names` and `route_laid` now hold for every event, including
wrapped ones, by induction.

### The host

`host/Sources/CairnHost/Surfaces.swift`. `SurfaceHost.apply` reconciles each frame's surfaces:

- **Status items** (`StatusHost`, `MenuHost`). One `NSMenu` per status item, `autoenablesItems`
  off. `MenuHost.update` syncs each menu level in place when its shape (separator, submenu or
  item at each position) is unchanged and rebuilds that level otherwise; an item's title,
  enabled flag, state, key equivalent and `^N#K` identifier are set from its record. A chosen item
  sends `menuSelect(place, ref)` whether or not it is enabled: Lean decides (`menu_select_stale`).
  `menuWillOpen`/`menuDidClose` on the root menu send `menuOpen`/`menuClose`. The status item's
  button shows a template SF Symbol and title.
- **Panels** (`PanelHost`, `OverlayPanel`). Section 2's properties; placed by
  `PanelHost.placement` against the chosen screen's `visibleFrame`, the screen chosen at show and
  kept until hidden. Each panel has its own `RenderLoop` that selects its canvas from the published
  frame, drawn by `MetalRenderer` on a clear, non-opaque layer. Hiding fades over 0.18 s.
- **Modes.** `.live` puts status items in the menu bar and panels on screen. `.detached` builds the
  same AppKit objects without either; the debug socket, Tray's self test and the trusted fuzzer
  use it, so none of them touches the menu bar or the screen.
- **Launch.** `CairnApp` waits for the first frame: with a window it is `.regular`, with M1's
  main menu and window; without one it is `.accessory`, with no main menu, and closing windows
  doesn't quit it.
- **Bundles.** `make bundle APP=<App>` writes `build/apps/<App>.app`, taking `Info.plist` and
  `entitlements.plist` from `host/Bundles/<App>/` when present (Tray's sets `LSUIElement`).
  Signing is ad hoc unless `SIGN=` names an identity. This is the hook Yap's bundle needs
  (microphone usage string, audio-input entitlement, hardened runtime, stable signature).

The example is Tray (`lean/Examples/Tray.lean`, claims ^450–^462): a status item whose menu has
a status line, a ⌘O item, a checkbox item, an item enabled only while the checkbox is on, a
Recent Items submenu with keyed items and Quit, and an overlay panel with 24 moving bars and a
wrapped caption. Its theorems (`lean/Examples/Tray/Proofs.lean`): `menu_refs` (presence in every
state), `menu_enabledRefs`, `add_enabled_iff`, `keep_checked`, `quit_enabled`, and
`add_ignored_when_off`, which says that in every state the running app reaches, choosing Add Item
while it is greyed out changes nothing.

Evidence: docs/trusted.md "Surfaces" (^940–^944, fuzzed by `SurfacesSuite`), conformance with
menus (docs/conformance.md "Tray: menus"), bench/surfaces.md (50 Hz), and the manual checklist
docs/surfaces-checklist.md.

## Decisions

The open questions as first written are kept below; each was settled as follows. Every answer is
the **lead's default; Nate may override.**

1. **Native menu.** *Lead's default; Nate may override.* Presence, enablement and checked state
   are proved on the description (`controls_ofMenu`, `enabled_ofMenu`, and the example app's
   theorems). That the item AppKit reports is the item the person chose is an `assume` claim in
   the trusted range, checked through the debug socket's `menuSelect` (which goes through
   `NSMenu.performActionForItem(at:)`, AppKit's own dispatch).
2. **Disabled-but-visible controls only in menus.** *Lead's default; Nate may override.* Only
   `MenuItem.item` has `enabled`; Metal surfaces keep M1's rule that a disabled move has no
   control.
3. **The host resolves Lean's anchor.** *Lead's default; Nate may override.* Lean gives
   `Anchor.bottomCenter offset` and a `ScreenChoice`; the host places the panel against that
   screen's `visibleFrame`. Trusted, listed in docs/trusted.md.
4. **Accessory follows from having no window surface.** *Lead's default; Nate may override.*
   `App.accessory` is `true` exactly when `surfaces` has no `window`; no separate flag.
5. **Waveform from Lean primitives** (bars as rects), provided frame times allow about 50 Hz.
   *Lead's default; Nate may override.* Measured in bench/ (bench/surfaces.md).
6. **The hide fade is a host-only look effect.** *Lead's default; Nate may override.* No
   animation model in Lean; the fade changes no state Lean reads.
7. **VoiceOver doesn't announce the live transcript.** *Lead's default; Nate may override.* It
   is readable by navigating to the panel's text.
8. **The overlay may appear in screen captures.** *Lead's default; Nate may override.* Accepted,
   as Yap does.
9. **Window-server behaviour is evidenced by debug-socket checks plus a manual checklist** in
   docs/ (docs/surfaces-checklist.md). *Lead's default; Nate may override.* No test in
   `make check` uses the real menu bar.

### Open questions as first written

For a human to decide:

1. **Native menu (recommended) or a Metal popover?** Native gives up a pressable proof through hit
   testing in exchange for the system menu, real submenus, keyboard and VoiceOver; the selection
   path becomes an assumption checked through the socket. Is that trade acceptable for Cairn's
   story ("every move is pressable, proved")?
2. **Disabled controls on screen.** Menus show disabled items; M1 never did (a disabled move had
   no control). Should `Control` gain `enabled` everywhere (Metal surfaces too, greyed buttons),
   or only `MenuItem` have it, as proposed?
3. **Who places the panel?** Proposed: Lean gives an anchor, the host resolves it (trusted). The
   alternative is a `screens` event (frames, visible frames, scales, the pointer's screen) so Lean
   computes the position and can prove it is on screen, at the cost of a new event and of Lean
   seeing display configuration changes.
4. **Accessory from surfaces, or a flag?** Proposed: no window ⇒ accessory. An app with a window
   and a status item (a later app) might want either; decide when one exists?
5. **Waveform: primitives or a host shader?** Primitives keep every pixel's meaning in Lean and
   cost a Lean step per level sample; a shader keeps Yap's look and adds a renderer assumption.
   Which matters more for "Nate uses it for a day"?
6. **Animation.** Yap fades the panel out over 0.18 s and animates text changes over 0.15 s.
   Cairn has no animation model. Proposed: drop the text animation, keep the fade as a host-side
   look-only effect. Or should animation be Lean's (with Q's clock) from the start?
7. **Announce the live transcript to VoiceOver?** Yap doesn't; it would speak over the dictation.
   Proposed: no, the text is readable by navigation only.
8. **Screen capture.** Yap's overlay appears in screenshots and recordings, including the
   transcript. There is no reliable way to opt out: Apple now documents `sharingType = .none` as
   a legacy value macOS no longer honours for hiding content from capture. Proposed: accept it,
   as Yap does (and it lets `build/bin/record` film the overlay for the site).
9. **Conformance on the real menu bar.** Under the socket the status item is detached and the
   panel isn't ordered front, so the window-server half (menu bar, Spaces, full screen,
   click-through) is covered only by a manual checklist and an optional AX run. Is that enough
   evidence for the `panel.inert` and `menu.select` assumptions, or should `make check` include a
   run that shows them for real?

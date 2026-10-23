---
title: AppKit event plumbing for a single custom view (pointer, cursor, scroll, keys, menus, focus)
urls:
  - https://github.com/zed-industries/zed (crates/gpui_macos @ 604a0ff023ec)
  - https://github.com/rust-windowing/winit (winit-appkit @ d559b0567d85)
  - https://github.com/ghostty-org/ghostty (macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift @ 08a9518340e1)
  - https://github.com/kovidgoyal/kitty (glfw/cocoa_window.m, glfw/cocoa_init.m @ 3867ffa92bef)
  - https://github.com/alacritty/alacritty (alacritty/src/input/mod.rs @ 542147067dd0)
  - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventArchitecture/EventArchitecture.html
  - https://developer.apple.com/documentation/appkit/nstrackingarea
  - https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:)
  - https://developer.apple.com/documentation/appkit/nsview/performkeyequivalent(with:)
  - https://developer.apple.com/documentation/appkit/nsevent/hasprecisescrollingdeltas
  - https://developer.apple.com/documentation/appkit/nsevent/momentumphase
  - https://developer.apple.com/documentation/appkit/nsevent/ismousecoalescingenabled
date: 2026-10-23
relevance: 5
---

# AppKit event plumbing for a single custom view

Cairn's host is one `NSView` that turns AppKit events into `Event` bytes for Lean. Every project
below does the same, and each has hit the same walls. IME (`NSTextInputClient`,
`interpretKeyEvents`) is covered in the separate input-method note; this note covers what
surrounds it.

## 1. Pointer: tracking areas, hover, drags, first click

**Without a tracking area there is no `mouseMoved:`, so no hover.** Apple: "Depending on the
options specified, the owner of the tracking area receives mouseEntered(with:), mouseExited(with:),
mouseMoved(with:), and cursorUpdate(with:) messages … Currently the tracking area is restricted to
rectangles." Also: "the tracking area should be synchronized with the visible rectangle of the
view (visibleRect)".

Zed, winit and Ghostty all install one view-sized area with the same four options:

- Zed (`crates/gpui_macos/src/window.rs:2480-2499`): `MouseEnteredAndExited | MouseMoved |
  ActiveAlways | InVisibleRect`, with the comment "Track even when another application is active so
  visible windows can respond to hover without being focused."
- winit (`winit-appkit/src/view.rs:889-930`) explains each choice:
  > "`InVisibleRect` instructs the tracking area's `owner` (our `NSView`) to ignore the value we
  > provide in `rect` and keep the tracking area's bounds up to date with the current view bounds
  > automatically."
  >
  > "We do not set `AssumeInside` because we want to avoid emitting `Left` events without a
  > correspondering `Entered` … not setting this flag tells AppKit to handle this for us by
  > synthesizing entry and exit events in some cases."
- Ghostty (`SurfaceView_AppKit.swift:844-862`) recreates it in `updateTrackingAreas` with the same
  options.
- kitty differs: `NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
  NSTrackingEnabledDuringMouseDrag | NSTrackingCursorUpdate | NSTrackingInVisibleRect |
  NSTrackingAssumeInside` (`glfw/cocoa_window.m:1147-1161`).

**Mouse position can be stale after entering from another window.** winit: "In the past (?),
`mouseMoved:` events were not generated when the user hovered over a window from a separate
window … To fix this, we emit `mouse_motion` inside of mouse click, mouse scroll, magnify and other
gesture event handlers" (`view.rs:583-593`).

**Drags are separate selectors.** `mouseDragged:`, `rightMouseDragged:` and `otherMouseDragged:`
go to the view that received the `mouseDown:`, including outside its bounds (negative or too-large
coordinates). kitty forwards `mouseDragged:` to `mouseMoved:` (`cocoa_window.m:1043-1045`).

**Coalescing.** `NSEvent.isMouseCoalescingEnabled`: "Mouse movement events include mouse-moved,
mouse-dragged, and tablet events. If this property is true, coalescing is enabled … The default
value of this property is true."

**Click-through (`acceptsFirstMouse`).** Apple: "The default implementation ignores event and
returns false … Most view objects refuse a click-through attempt, so the event simply activates
the window." Zed, winit and kitty all return YES but flag the click:

- winit (`view.rs:842-855`): "Always accept the click. The following `mouseDown:` is tagged with
  `is_macos_activation_click: true` so the application can decide per click whether to act on it."
- Zed sets `lock.first_mouse = true` and returns YES (`window.rs:3558-3563`).
- Ghostty deliberately does **not** use it: "We need leftMouseDown to determine if we should focus
  ourselves when the app/window isn't in focus. We do this instead of 'acceptsFirstMouse' because
  that forces us to also handle the event" (`SurfaceView_AppKit.swift:377-380`, a local event
  monitor).

**Clicks.** `NSEvent.clickCount` is passed straight through by Zed
(`crates/gpui_macos/src/events.rs:168`, `:192`). AppKit decides what counts as a double-click
(system interval and distance).

## 2. Cursor: cursor rects vs `NSCursor.set`

Calling `NSCursor.set()` from `mouseMoved:` gets overwritten whenever AppKit re-applies cursor
rects or `cursorUpdate:` (window activation, resize, title bar, other windows), which shows up as
flicker or a stuck arrow. The three mature hosts use one of two consistent approaches:

- **Cursor rect over the whole view, invalidated on change** (Zed, winit). winit
  (`view.rs:224-235`): "We correctly invoke `addCursorRect` only from inside `resetCursorRects`",
  with `self.addCursorRect_cursor(bounds, &cursor_state.cursor)`; setting a cursor stores it and
  calls `invalidateCursorRectsForView` (`window_delegate.rs:1630-1631`). Zed is the same
  (`window.rs:2502-2530`, and `set_active_window_cursor_style` at `:379-407`, which invalidates
  only `if window_state.cursor_style != style`).
- **No cursor rects; `NSTrackingCursorUpdate` + `cursorUpdate:`** (kitty): `[window->ns.object
  disableCursorRects]` and `- (void)cursorUpdate:(NSEvent *)event { … updateCursorImage(window); }`
  (`cocoa_window.m:1028-1031`, `:1148`). winit explains why it didn't do this: "The
  cursorUpdate(with:) message is not sent when the NSTrackingCursorUpdate option is specified along
  with [`ActiveAlways`]" (`view.rs:894-899`).

Hide-while-typing: `NSCursor.setHiddenUntilMouseMoves(true)` (Zed `platform.rs:1158-1164`, Ghostty
`SurfaceView_AppKit.swift:568`).

## 3. Scroll wheel: precise deltas, phases, momentum

- Apple, `hasPreciseScrollingDeltas`: "A generic scroll wheel issues rather coarse scroll deltas.
  Some mice and trackpads provide much more precise delta. This method determines how the values of
  the scrollingDeltaX and scrollingDeltaY should be interpreted."
- Apple, `momentumPhase`: momentum events "are attached to the view that is under the cursor when
  the flick occurs", and their "location … changes as the user moves the cursor".
- winit (`view.rs:719-760`): precise → pixels (`LogicalPosition::new(x, y).to_physical(...)`),
  otherwise **lines**; and "The 'momentum phase,' if any, has higher priority than touch phase (the
  two should be mutually exclusive anyhow, which is why the API is rather incoherent) … Mouse wheels
  have neither phase. Trackpads have one of them."
- kitty multiplies precise deltas by the content scale and forwards all six momentum phases
  (`cocoa_window.m:1418-1440`).
- Ghostty is unsure of the units: "We do a 2x speed multiplier. This is subjective … TODO(mitchellh):
  do we have to scale the x/y here by window scale factor?" (`SurfaceView_AppKit.swift:1058-1078`).
- Alacritty accumulates sub-unit pixel deltas, resets the accumulator on `TouchPhase::Started`, and
  locks to one axis: "When the angle between (x, 0) and (x, y) is lower than ~25 degrees (cosine is
  larger that 0.9) we consider this scrolling as horizontal." (`alacritty/src/input/mod.rs:737-753`,
  `:771-827`).

## 4. Keys: performKeyEquivalent, keyDown, the missing keyUp

**The order** (Apple, Event Architecture): "The application object handles key equivalents by
going *down* the view hierarchy in the key window, sending each object a `performKeyEquivalent:`
message until an object returns `YES`. If the message isn't handled by an object in the view
hierarchy, `NSApp` then sends it to the menus in the menu bar." Then keyboard interface control
("pressing the Tab key moves input focus to the next object"), then "The window object invokes the
`keyDown:` method in the first responder".

Consequences the projects work around:

- **The same keystroke can arrive twice**, once as a key equivalent and again as `keyDown:`. Zed
  (`window.rs:2661-2668`): "For certain keystrokes, macOS will first dispatch a 'key equivalent'
  event. If that event isn't handled, it will then dispatch a 'key down' event … we need to ignore
  the 'key down' event if we've already just processed its 'key equivalent' version." Ghostty does
  the same with timestamps, because "comparing NSEvent identity seems pretty nasty … some events are
  synthetic and have a zero timestamp" (`SurfaceView_AppKit.swift:1276-1302`).
- **`performKeyEquivalent:` reaches views that aren't first responder.** Ghostty: "Some key events
  like C-/ macOS appears to send to the first view in the hierarchy rather than the first responder
  … This prevents us from handling it." (`:1310-1318`, guarded with `if !focused { return false }`).
- **No `keyUp:` while Command is held.** winit overrides `NSApplication.sendEvent:`: "Normally,
  holding Cmd + any key never sends us a `keyUp` event for that key … Fun fact: Firefox still has
  this bug!" (`winit-appkit/src/app.rs:31-45`). Ghostty uses a local event monitor: "Command keyUp
  events are never sent to the normal responder chain so we send them here."
  (`SurfaceView_AppKit.swift:374`, `:711-719`).
- **Cmd-. becomes `cancelOperation:`**, not a key event. winit implements `cancelOperation:` to
  recover it (`view.rs:562-585`); Ghostty notes "Command+Period will do: performKeyEquivalent,
  doCommand ('cancel:')" and a synthetic zero-timestamp Escape (`:1281-1284`, `:1373-1380`).
- **Ctrl-Tab and Ctrl-Esc** never reach `keyDown:` unless the view answers the private
  `_wantsKeyDownForEvent:` YES. winit: "Allows us to receive Ctrl-Tab and Ctrl-Esc. Note that this
  *doesn't* help with any missing Cmd inputs." (`view.rs:833-840`, after Chromium's
  `bridged_content_view.mm`).
- **Tab via `interpretKeyEvents:` becomes `insertTab:`.** winit turns that into
  `selectNextKeyView` (`view.rs:540-560`).
- **Menu shortcuts first.** kitty's key-down monitor runs `[[NSApp mainMenu]
  performKeyEquivalent:event]` before anything else (`glfw/cocoa_init.m:848-856`).
- **Modifier-only presses come as `flagsChanged:`, not `keyDown:`** (winit `view.rs:534-537`,
  Ghostty `:1428`).

## 5. Edit menu routing with a custom first responder

- Zed puts the standard selectors on its menu items so system panels behave: "Add menu item
  handlers so that OS save panels have the correct key commands", registering `cut:`, `copy:`,
  `paste:`, `selectAll:`, `undo:`, `redo:` and `validateMenuItem:` on the app delegate
  (`crates/gpui_macos/src/platform.rs:97-125`). Undo and redo are the exception: "'undo:' and
  'redo:' are always disabled in our case, as we don't have a NSTextView/NSTextField to enable
  them on." so those items use the custom `handleGPUIMenuItem:` (`platform.rs:370-376`).
  Validation asks the app per item (`platform.rs:1487-1511`).
- Zed turns off key-equivalent localisation so shortcuts stay where it put them:
  `item.setAllowsAutomaticKeyEquivalentLocalization(false)` (`platform.rs:405-407`).
- Ghostty puts `@IBAction func copy(_:)` / `paste(_:)` on the view itself
  (`SurfaceView_AppKit.swift:1639-1663`) and validates through `NSMenuItemValidation`, enabling Copy
  only with a selection (`:2257-2275`):
  ```swift
  case #selector(copy(_:)):
      // We only enable copy menu item when there're actual selected text
      if let text = self.accessibilitySelectedText(), text.count > 0 {
  ```

## 6. Window focus and live resize hooks

- Zed draws a frame synchronously in `windowDidBecomeKey:` "to prevent tab flicker", but not on the
  first activation, because otherwise "the focus state would remain unset until the first mouse
  click, causing keybindings to be non-functional" (`window.rs:3191-3216`).
- winit sets `layerContentsRedrawPolicy = DuringViewResize` (`view.rs:885-887`). Resize rendering
  itself is in the Metal note.

## Pitfalls

1. **No tracking area means no hover.** `mouseMoved:` isn't delivered without one. Use one
   view-sized area with `InVisibleRect` so it never needs manual resizing.
2. **`ActiveAlways` vs `ActiveInKeyWindow` is a product decision.** Hover in a background window
   is what Zed and winit chose.
3. **Drag events go to different selectors** and can carry coordinates outside the view. Forward
   them as pointer moves; don't clamp them.
4. **The first click on an inactive window is swallowed** unless `acceptsFirstMouse` returns YES.
   If it does, decide whether that click performs the action. Ghostty avoids it entirely.
5. **`NSCursor.set()` flickers or gets reset.** Use one cursor rect over the view plus
   `invalidateCursorRects(for:)` only when the cursor actually changes (Zed, winit), or
   `cursorUpdate:` with cursor rects disabled (kitty). Don't mix the two.
6. **Scroll units differ by device.** Precise deltas are points (fractional); wheel deltas are
   lines. Truncating per event to an integer loses slow trackpad scrolls entirely. Accumulate
   remainders, and reset on phase `began` (Alacritty).
7. **Momentum events keep coming after the finger lifts** and go to the view under the cursor at
   flick time. A UI that starts a new scroll target mid-momentum has to look at `momentumPhase`.
8. **Key equivalents arrive twice** (`performKeyEquivalent:`, then `keyDown:`) if you return NO
   from the first and handle the second. Deduplicate (Zed compares events; Ghostty compares
   timestamps).
9. **Cmd+key never produces `keyUp:`** without a `sendEvent:` override or a local monitor (winit,
   Ghostty, Firefox's open bug).
10. **Cmd-. arrives as `cancelOperation:`**, and Ctrl-Tab needs a private method to arrive at all.
11. **Without a main menu, Cmd-C/V/X/A/Z/Q do nothing** (or beep), because the standard path for
    them is a menu key equivalent sending `copy:` and friends to the first responder.
12. **`validateMenuItem:` runs on the main thread when a menu opens or a shortcut fires**, so it
    has to answer from state the main thread already has.

## Counter-evidence

- kitty's `cursorUpdate:` approach contradicts the "cursor rects only" advice and works for it.
  The real rule is consistency, not one particular API.
- Ghostty's rejection of `acceptsFirstMouse` shows click-through is not a universal default for
  custom views; Apple's own default is NO.
- `ActiveAlways` hover runs against the AppKit default for standard controls, which mostly track
  only in the key window.

## For Cairn

**Workstream G (host):**

- The spike's `HostView` has no tracking area, no `mouseDragged:`, no `mouseMoved:`, no
  `scrollWheel:`, no `keyDown:` and no main menu. TodoMVC needs hover (the delete button "shown on
  hover"), double-click (edit), keys and Edit-menu copy/paste, so all of these are M1 work.
- Hover: add one tracking area (`mouseEnteredAndExited, mouseMoved, activeAlways or
  activeInKeyWindow, inVisibleRect`). Send `pointerMove` from `mouseMoved:` and every `*Dragged:`,
  and `pointerExit` from `mouseExited:`. Also send a `pointerMove` before each `pointerDown` and
  scroll (winit's stale-position fix) so Lean's hover state is correct for clicks that arrive
  without a preceding move.
- Double-click: pass `event.clickCount` into `pointerDown(clicks:)` and list "AppKit's
  double-click detection" as an assumption in `docs/trusted.md`. The conformance driver must
  post real events with the right click state (`CGEventSetIntegerValueField(...,
  kCGMouseEventClickState, 2)`), or AppKit will report `clickCount == 1`.
- `acceptsFirstMouse`: decide in Lean, not Swift. Return YES and send a flag (or a separate
  event) so Lean decides whether an activation click performs a move. Whichever way it goes, it's
  a claim-level behaviour. The conformance driver should activate the window before replaying a
  sequence, or every first click diverges from the model.
- Cursor: `Frame.cursor` changes per frame. Store it, and on change (on main) call
  `window.invalidateCursorRects(for:)`. In `resetCursorRects` add one rect for `bounds` with the
  stored cursor. Never call `NSCursor.set()` from the render thread.
- Scroll (a stretch in M1): `Event.scroll` takes `Int32`. Keep a per-axis `Double` remainder in
  the host and send only whole points, resetting on `phase == .began`. Map wheel line deltas to
  points with a fixed factor written in `trusted.md`. Optionally pass the phase so Lean can tell
  momentum from finger.
- Keys: return NO from `performKeyEquivalent:` for anything the main menu owns, so Cmd-C goes to
  `copy:`. Add a `sendEvent:` override or local monitor only if Lean ever needs Cmd keyUp (M1
  doesn't). Implement `cancelOperation:` so Escape-like Cmd-. reaches Lean as `key(.escape)` if
  TodoMVC's Escape-cancels-edit should cover it. Handle `insertTab:`/`insertBacktab:` by sending
  `key(.tab)` to Lean (Lean owns focus) rather than `selectNextKeyView`.
- Edit menu: build a main menu with an Edit menu whose items send `undo:`, `redo:`, `cut:`,
  `copy:`, `paste:`, `selectAll:` to the first responder. Implement them on `HostView` to send
  `.undo`, `.redo`, `.cut`, `.copy`, `.paste(NSPasteboard string)`, `.selectAll` (the `Event`
  cases already exist). For `validateMenuItem:`, answer from the last frame. **The frame currently
  carries no "can copy / can undo" bits, so menu validation would need the host to guess** (always
  enabled, or inferred from `textInput.selection`). Raise this with workstream E: add per-frame
  edit capabilities, computed in Lean, to `Frame`.
- Window focus: send `windowFocus(true/false)` from `windowDidBecomeKey`/`ResignKey`. On resign,
  Lean should drop press state, since a `mouseUp` may never come (a menu or modal took the mouse).

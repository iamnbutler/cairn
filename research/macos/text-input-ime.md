---
title: NSTextInputClient in custom-drawn apps (IME, dead keys, press-and-hold, dictation)
urls:
  - https://github.com/zed-industries/zed/blob/604a0ff023ec/crates/gpui_macos/src/window.rs
  - https://github.com/rust-windowing/winit/blob/d559b0567d85/winit-appkit/src/view.rs
  - https://github.com/chromium/chromium/blob/eb4f56eefdfeed72228d1436906df55c90374838/content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm
  - https://github.com/chromium/chromium/blob/eb4f56eefdfeed72228d1436906df55c90374838/content/browser/renderer_host/text_input_client_mac.h
  - https://github.com/ghostty-org/ghostty/blob/08a9518340e1/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift
  - https://github.com/kovidgoyal/kitty/blob/3867ffa92bef/glfw/cocoa_window.m
  - https://github.com/mozilla-firefox/firefox/blob/f536a878f58f97cdf167149b25a95848519a2199/widget/cocoa/TextInputHandler.mm
  - https://github.com/alacritty/alacritty/issues/8791
  - https://github.com/kovidgoyal/kitty/issues/3732
  - https://github.com/kovidgoyal/kitty/issues/10492
  - https://github.com/ghostty-org/ghostty/issues/8493
  - https://github.com/zed-industries/zed/issues/21392
  - https://github.com/zed-industries/zed/issues/46084
  - https://github.com/secondlife/viewer/pull/6459
  - https://discourse.libsdl.org/t/sdl-2-0-4-text-input-mode-on-osx/21731
  - MacOSX.sdk AppKit.framework/Headers/NSTextInputClient.h, NSTextInputContext.h
date: 2026-10-23
relevance: 5
---

# NSTextInputClient in custom-drawn apps

How GPUI, winit (Alacritty), Chromium, Ghostty and kitty implement `NSTextInputClient`, and what
broke. Chromium is the closest analogue to Cairn: like Cairn's main thread, its browser process
must answer AppKit synchronously while the text model lives somewhere it can't block on (the
renderer process).

## Findings

### 1. The protocol is synchronous and expects your model to change *during* the call sequence

- AppKit header (`NSTextInputClient.h`): `selectedRange` "Returns the selection range. The valid
  location is from 0 to the document length." `markedRange` "Returns {NSNotFound, 0} if no
  marked range." `firstRectForCharacterRange:actualRange:` "The return value is in the screen
  coordinate. The size value can be negative if the text flows to the left."
  `attributedSubstringForProposedRange:` "The range can be adjusted from various reasons (i.e.
  adjust to grapheme cluster boundary…)". All ranges are NSString (UTF-16) indices into the
  *whole document*, not into the marked text. Only `setMarkedText`'s `selectedRange` is relative
  to the marked string.
- Chromium went async on purpose. Its long comment at
  `render_widget_host_view_cocoa.mm:2440-2490` explains why it does not let the renderer drive
  `interpretKeyEvents`: "This needs many sync IPC messages sent between a browser and a renderer
  for each key event, which would probably result in key-typing jank. To avoid this problem, this
  implementation processes key events (and input method events) totally in a browser process and
  sends asynchronous input events".
- The cost is **optimistic shadow state**. `setMarkedText` (:2692-2790):
  > "Update markedRange/textSelectionRange assuming blink sets composition text as is. We need
  > this because the IME checks markedRange/textSelectionRange before IPC to blink. If
  > markedRange/textSelectionRange is not updated, IME will behave incorrectly, e.g., wrong popup
  > window position or duplicate characters."
  and `insertText` (:2841-2905):
  > "IMEs read |_availableText| preceding the insertion point as the context for predictive
  > completion. Unfortunately by the moment IME reads the text, Blink likely hasn't finished the
  > commit so the IME will read a wrong context. We hack it by temporarily inserting the committed
  > text into |_availableText|. This variable will ultimately be asynchronously updated by Blink.
  > TODO(crbug.com/40165347): Mac's IME API is synchronous and it plays badly with async APIs".
- Chromium still blocks for the two geometry queries it can't answer from cache:
  `SyncGetFirstRectForRange` and `SyncGetCharacterIndexAtPoint`. It caches the caret and
  composition bounds first (`GetCachedFirstRectForCharacterRange`, "This exists to make IMEs more
  responsive, see http://crbug.com/115920", `render_widget_host_view_mac.mm:1372-1384`). The sync
  fallback has a timeout: `text_input_client_mac.h:266-267`
  `wait_timeout_ … = base::Milliseconds(1500);`, because "Mojo sync calls do not have timeouts".
- If `firstRect` fails, Chromium cancels the composition rather than return garbage (:2538-2542
  "The call to cancelComposition comes from https://crrev.com/350261").
- GPUI is single-threaded: every NSTextInputClient method calls `with_input_handler` into the
  live app state (`window.rs:3369-3600`). So it never needs a shadow, but its main thread runs app
  code.

### 2. Key routing: interpretKeyEvents vs handleEvent vs doCommandBySelector

- winit runs `interpretKeyEvents` and then decides whether the key also goes to the app, through
  a four-state machine `Disabled | Ground | Preedit | Committed` (`view.rs:51-65`, :458-530):
  > "The `interpretKeyEvents` function might call `setMarkedText`, `insertText`, and
  > `doCommandBySelector`. It's important that we call this before queuing the KeyboardInput …
  > (doCommandBySelector means that the keyboard input is not handled by IME and should be handled
  > by the application)"
  and in `doCommandBySelector` (:419-450): "We shouldn't forward any character from just committed
  text, since we'll end up sending it twice with some IMEs like Korean one. We'll also always send
  `Enter` in that case, which is not desired given it was used to confirm IME input."
- GPUI calls `[inputContext handleEvent:]` directly, not `interpretKeyEvents`, and only sends
  the key to the IME first when composing, when the key isn't printable, or when a
  composition-type input source is active (`window.rs:2673-2740`). `doCommandBySelector` ignores
  the selector and re-dispatches the original keystroke to the keymap (`:3518-3537` "We ignore
  which selector it asks us to do because the user may have bound the shortcut to something
  else"). The method keeps a manual test plan at :2568-2593 (Brazilian dead quote, Japanese
  "a i left down up enter enter" → "愛", `cmd-ctrl-space` emoji picker).
- GPUI de-duplicates `performKeyEquivalent:` and `keyDown:` for the same keystroke
  (`window.rs:2659-2668`): "For certain keystrokes, macOS will first dispatch a "key equivalent"
  event. If that event isn't handled, it will then dispatch a "key down" event."
- Ghostty: "Command+Period will do: performKeyEquivalent, doCommand ("cancel:")". It tracks the
  event by timestamp because "comparing NSEvent identity seems pretty nasty… some events are
  synthetic and have a zero timestamp" (`SurfaceView_AppKit.swift:1280-1302`). It also found that
  rebuilding an NSEvent breaks Korean: "IMPORTANT: we MUST reuse the old event if they're equal
  because this keeps things like Korean input working. There must be some object equality
  happening in AppKit somewhere" (:1130-1135).
- Chromium keeps fn/globe shortcuts out of `interpretKeyEvents`, otherwise "Function e" (emoji
  palette) arrives as an `insertText:` placeholder and "macOS [positions] the palette at the
  upper-left corner of the webcontents instead of at the insertion point"
  (`render_widget_host_view_cocoa.mm:1594-1640`). It routes JIS Eisu/Kana keys through the private
  `processInputKeyBindings:` because "Mac Eisu Kana keys cannot be handled by
  interpretKeyEvents" (:1585-1592).
- The IME can commit on a **modifier** key: kitty runs `[input_context handleEvent:]` from
  `flagsChanged:` and handles an `insertText` that arrives there (`cocoa_window.m:1386-1397`).
- Japanese "Live Conversion": pressing ← at the start of a composition reconverts committed text
  and calls `setMarkedText` several times in one key event (Chromium :1560-1572).

### 3. Ranges arrive malformed, and the index unit is UTF-16

- Alacritty #8791 (macOS 15.2, native Pinyin): crash in winit `set_marked_text` from
  `-[NSString substringToIndex:]` out of range. winit's fix (`view.rs:308-317`): "IMEs are known
  to send both mid-surrogate and out-of-bounds offsets (e.g. native Pinyin…)", so the helper
  "snaps an offset that would split a surrogate pair down to the character boundary and clamps an
  out-of-bounds offset to the string length".
- Chromium `attributedSubstringForProposedRange` (:2585-2620): "The caller of this method is
  allowed to pass nonsensical ranges. These can't even be converted into gfx::Ranges." It rejects
  NSNotFound, zero length, overflow and reversed ranges, then intersects with the text it has.
  Ghostty gave up validating: "a lot of macOS system behaviors request bogus ranges I truly don't
  understand so we just always return the attributed string containing our selection"
  (`SurfaceView_AppKit.swift:1990-1996`).
- `setMarkedText` overflow: Chromium uses saturated casts because "`_markedRange.location +
  NSMaxRange(newSelRange)` can be larger than the maximum uint32_t. See crbug.com/40060200."
- Ghostty receives `insertText` as **separate lead and trail surrogates** in some paths and
  rejoins them (`SurfaceView_AppKit.swift:2088-2105`, "We ignore trail surrogate without a lead
  like Terminal.app").

### 4. The features that need more than insertText/setMarkedText

- **Press-and-hold accent menu** inserts the plain letter, then calls `insertText:` again with the
  accented letter and a `replacementRange` covering the first one (SDL forum report; Second Life
  viewer PR 6459 "the accent menu appended instead of replacing" before honouring the range). winit
  ignores `replacementRange` (`view.rs:271,387` "TODO: Use _replacement_range"), so the accent
  gets appended. Ghostty and kitty turn the menu off: `"ApplePressAndHoldEnabled": false`
  (Ghostty `App/AppDelegate.swift:218`, kitty `cocoa_init.m:927`). GPUI could not get the default
  to work ("it doesn't seem to work for me", `gpui/src/platform.rs:2440-2441`).
- **The menu stays open** when the app moves the caret on its own: Zed #21392 ("Move the cursor,
  (or backspace) … The menu stays open"). The header says why: `invalidateCharacterCoordinates`
  "should [be sent] whenever any of these changes occur, and -[NSTextInputContext handleEvent:]
  will not otherwise be called", and `discardMarkedText` "Notifies the system to discard the
  current conversion session. The client should clear its marked range when sending this
  message." (`NSTextInputContext.h:57-63`).
- **Dictation**: kitty `cocoa_window.m:2035-2037`: "Never return kEmptyRange (NSNotFound, 0) from
  here: macOS dictation fails if it cannot tell where text is to be inserted" (#3732). Ghostty
  #8493: the dictation indicator was drawn above the text, fixed by returning a zero-width rect at
  the caret (`SurfaceView_AppKit.swift:2056-2062`). macOS 14 adds `unionRectInVisibleSelectedRange`
  and `documentVisibleRect` "To support dictation indicator on custom text view"
  (`NSTextInputClient.h:104-116`).
- **Surrounding text**: kitty #10492: without real `attributedSubstringForProposedRange` /
  selected range, "an input method that inserts a space between Latin and CJK text has nothing to
  base that decision on and so inserts nothing" (`cocoa_window.m:1999-2006`).
- **Mouse during composition**: GPUI forwards `mouseDown` to `inputContext.handleEvent` so the
  IME can commit or close (`window.rs:2878-2887`). Zed #46084: the last marked character stayed on
  screen after backspacing the composition away.
- **Secure fields**: Chromium returns a nil `inputContext` for password fields: "There is also a
  privacy risk if the composition candidate window shows your password" (:2631-2650).

### 4b. Firefox (`widget/cocoa/TextInputHandler.mm` @ f536a878f58f)

- Korean IMEs may compose **without marked text**, rewriting the previous character through
  `replacementRange` (:2541-2554): "Korean IME (or some other simple IME) may work without marked
  text. For example, composing character may be inserted as committed text and it's modified with
  aReplacementRange. When a keydown starts new composition with committing previous character,
  InsertText() may be called twice". That's another reason `replacementRange` must reach the model.
- Cmd-. and `cancelOperation:` (:3190-3200): if the view implements `cancelOperation:`,
  "[ChildView keyDown:theEvent] becomes to be never called". Handle the command before the
  superclass does.
- Korean IMEs swallow mouse-downs (:5403-5420): "If we are inactivated during composition, active
  Korean IME keeps consuming all mousedown events of any mouse buttons. So, we should allow Korean
  IMEs to handle mousedown events only when there is composition string." Forward mouseDown to the
  input context **only while composing**.
- Secure Event Input for password fields must be released on every exit path, including widget
  destruction without blur, or "it can stay enabled process-wide and lock other apps out of
  keyboard input" (:4774-4780).

### 5. firstRect coordinate conversion

- winit (`view.rs:367-384`) and Chromium (:2550-2555) do it the robust way: view rect →
  `convertRect:toView:nil` → `window.convertRectToScreen`. Chromium flips first because its
  rects are top-left. GPUI hand-computes from `window.frame` and `contentLayoutRect`
  (`window.rs:3396-3438`), which needs a special case for full-size content views.
- Chromium shifts the rect for Google Japanese Input in vertical text (:2558-2566).

## Pitfalls

1. **Stale answers.** If `selectedRange`/`markedRange` reflect the last *frame* rather than the
   edits the IME just made, IMEs place popups wrongly and duplicate characters (Chromium's
   comment). The host needs an optimistic shadow of the field (text, selection, marked range)
   that it updates *synchronously* in `insertText`/`setMarkedText`/`unmarkText`, and then
   reconciles when Lean's frame arrives.
2. **UTF-16 everywhere at the boundary.** NSTextInputClient ranges are UTF-16 document offsets.
   Cairn's are scalar offsets. Convert at one choke point, and clamp and snap (winit) because
   IMEs send mid-surrogate and out-of-bounds values.
3. **`selectedRange` returning NSNotFound** breaks dictation (kitty) and, in practice, the
   accent menu. Always return the caret.
4. **Ignoring `replacementRange`** breaks press-and-hold accents (appends instead of replacing) and
   Japanese reconversion.
5. **Double delivery**: a key that commits a composition (Enter, Space, Korean next jamo) must not
   also reach the app as a key (winit's `Committed` state, Chromium's `_hasMarkedText ||
   oldHasMarkedText` check).
6. **Key equivalents arrive twice** (performKeyEquivalent, then keyDown), and some Cmd/Ctrl keys
   arrive as `doCommandBySelector:` (e.g. Cmd-. → `cancel:`).
7. **Don't recreate NSEvents** you pass to the input system (Korean breaks, per Ghostty).
8. **The app moving the caret** must call `discardMarkedText` (if a composition is active) and
   `invalidateCharacterCoordinates`, or the IME/accent window floats at the old place (Zed #21392).
9. **Modifier keys and mouse clicks** can commit compositions: forward `flagsChanged` and
   `mouseDown` to the input context while composing.
10. **Malformed ranges**: reject NSNotFound, zero-length, reversed and overflowing ranges without
    raising (`substringToIndex:` throws an ObjC exception, which Swift cannot catch).

## Counter-evidence

- Terminals (Ghostty, kitty) get away with stubbed `characterIndexForPoint` (returns 0) and
  `markedRange` relative to the marked text only. They are not text editors. Cairn's TodoMVC fields
  are text editors, so the stubs aren't good enough.
- GPUI avoids the shadow-state problem by running app code on the main thread. Cairn's rule "the
  main thread never waits on Lean" forbids that. Chromium shows the alternative works at scale,
  with documented hacks.
- Disabling press-and-hold (Ghostty, kitty) is a legitimate M1 option for a terminal. For text
  fields in a Mac app, users expect the accent menu.

## For Cairn

- **G — shadow field.** Keep a `TextInputShadow` on the main thread, seeded from
  `Frame.textInput` (text, selection, marked) and updated *optimistically and synchronously*
  by `insertText`/`setMarkedText`/`unmarkText`, applying the same edit Lean will apply. Answer
  `selectedRange`, `markedRange`, `hasMarkedText` and `attributedSubstringForProposedRange` from
  it. When a frame arrives whose text-input state already includes all queued edits (tag edits
  with a sequence number echoed in the frame), replace the shadow with Lean's. This is a
  host-side model of Lean's `Field.apply` and belongs in `docs/trusted.md`. The conformance driver
  can check it: after every IME op, shadow == next frame's `textInput`.
- **G — firstRect** from the last frame's caret/marked geometry, extended by the shadow's
  pending insert width. A small inaccuracy only moves the popup, so this is safe to approximate.
  Convert with `convert(_:to: nil)` + `window.convertToScreen`, remembering the view is flipped.
  Return a zero-width rect at the caret when `range.length == 0` (dictation).
- **E/G — event contract gap.** `Event.insertText(String)` and `Event.setMarked(String, selStart,
  selLen)` in `host/Sources/CairnFrame/Model.swift` carry **no replacement range**, so Lean can't
  do press-and-hold accents or reconversion. Add `replace: (start, end)?` in scalar indices
  (converted from UTF-16 by the host), or turn press-and-hold off with
  `UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])` before
  `NSApplication` finishes launching, and record that in `docs/trusted.md`.
- **G — keyDown order**: call `interpretKeyEvents([event])` (or `inputContext.handleEvent`) first,
  with an `inKeyDown` flag. Collect `insertText`/`setMarked`/`doCommandBySelector` results during
  the call, then send Lean one batch: either text ops or a `key` event, never both for the same
  keystroke (winit's Committed rule). Map `doCommandBySelector` selectors (`insertNewline:`,
  `deleteBackward:`, `moveLeft:`, `moveRight:`, `moveWordLeft:`, `cancelOperation:`,
  `selectAll:`…) to `Key`/`Event`. Do not beep: override `doCommand(by:)` to swallow unknown
  selectors.
- **G — when Lean ends a composition** (click elsewhere, blur, Escape handled by Lean), the frame
  will show `marked = nil` while AppKit still thinks it's composing. On that transition call
  `inputContext?.discardMarkedText()`, and call `invalidateCharacterCoordinates()` whenever the
  caret rect changes.
- **G — forward `mouseDown` and `flagsChanged` to `inputContext.handleEvent` only while
  `hasMarkedText`** (Firefox: Korean IMEs swallow clicks otherwise), before sending the click to
  Lean.
- **D (text editing)**: `Field` should accept a marked selection and replacement range in scalar
  indices and treat "insertText while marked" as "replace marked range" (Chromium: "Inserting text
  will delete all marked text automatically").
- **Test plan for J (conformance) / G**: Pinyin "markdown" (Alacritty #8791), Japanese Romaji "a i
  ← ↓ ↑ ⏎ ⏎" → 愛, Korean 한글 + Enter (no double newline), US-Intl dead key `'` + `e` → é,
  press-and-hold `e` → pick è, emoji picker (Ctrl-Cmd-Space) inserts at the caret, dictation
  indicator below the caret, and backspacing a whole Pinyin composition leaves nothing behind
  (Zed #46084).

# The host

`host/Sources/CairnHost` is the AppKit side of Cairn. Lean owns state, view, layout, hit testing
and focus. The host owns the window. It turns input into events for Lean and runs the effects
Lean returns. It answers the OS (accessibility, text input) from the last frame. It never blocks
on Lean. Everything it assumes is listed in [trusted.md](trusted.md).

## Running

```
make demo                      # Counter (lean/Examples/Counter.lean) in a window
make demo DEMO=CairnFixture    # the Swift fixture app: a text field, a checkbox, a list
make test                      # host unit tests (swift test)
make selftest                  # Counter driven headlessly through the real threads and AX mirror
```

Every app accepts these flags:
- `--stats`: prints latency percentiles every 2 s and at quit.
- `--latency N`: feeds N synthetic pointer events through the view's input mapping, prints the
  numbers and quits.

`CAIRN_LOG_EVENTS=1` logs every event batch sent to the app.

One executable per app. An app describes itself as a `LeanApp` and calls `CairnApp.main`:

```swift
let counter = LeanApp(module: initialize_cairn_Examples,
                      initialize: { w, h, _ in cairn_counter_new(w, h) },
                      step: { cairn_counter_step($0, $1) },
                      frame: { cairn_counter_frame($0) },
                      codec: SpikeV0Codec())
CairnApp.main(CairnApp.Config(title: "Counter", size: Size(w: 480, h: 320)) { LeanCore(counter) })
```

`AppCore` is the seam: `start(size:scalePercent:)`, `step([Event])`, `frame() -> Frame`.
`LeanCore` implements it over a `LeanApp`. `CairnFixture` implements it in Swift, as a test
double for checking IME and accessibility by hand before a Lean app has a text field. It is not
product code.

## Threads

```
main thread     AppKit events → Event → Engine.send (enqueue, returns seq); never calls Lean
                answers NSTextInputClient from the text shadow, AX from the mirror
                applies each new frame: effects, cursor, text shadow, AX mirror
Lean thread     owns the AppCore; drains the whole queue → step → frame → decode → publish
render thread   CADisplayLink (NSView.displayLink) on its own run loop; paints the latest frame
```

- **Engine.** `send` gives every event a sequence number. Consecutive pointer moves coalesce
  to the latest one, and consecutive scrolls sum their deltas. The Lean thread takes the whole
  queue as one batch, so a slow step batches input rather than falling behind. Each publish is
  a `Published{frame, version, throughSeq, inputTime}`. Other threads read the latest one under
  a lock and never wait for Lean. `wait(through:)` is for tests only.
- **Main thread.** A `MainHop` coalesces Lean→main notifications into one hop. The hop runs
  `applyLatestFrame()`, which does four things in order:
  1. runs the effects (`setClipboard` → NSPasteboard, `beep` → NSSound.beep);
  2. sets the cursor;
  3. reconciles the text shadow;
  4. updates the AX mirror.
- **Lean runtime.** The runtime is initialized on the Lean thread by `LeanRuntime.enter`. The
  first thread to enter runs `cairn_lean_init(module)`. Any later thread calls
  `cairn_lean_thread_begin`. The Lean thread has a 64 MB stack.

### Live resize

Policy: **top-left gravity, hold the old picture.**
- `setFrameSize` sends `resize` and tells the render loop the event's seq.
- Until a frame with `throughSeq ≥ that seq` arrives, the render thread keeps presenting the
  last picture. The layer's `contentsGravity` is `.topLeft`, so the old picture stays pinned
  while the window grows or shrinks around it. The wait is at most 100 ms; after that the
  stale frame is drawn rather than freezing.
- A drawable whose size doesn't match the current viewport is dropped, and the next tick
  draws.

The main thread never waits, so a slow Lean frame cannot stall AppKit's resize loop.

The trade-off against Zed's approach: Zed sets `presentsWithTransaction` and renders
synchronously inside the resize, so content and window edge move together in the same Core
Animation transaction. That needs the main thread to block on a frame, which here would mean
blocking on Lean. Cairn accepts a brief strip of background, at most one frame or 100 ms, at
the growing edge during a fast drag. Revisit if Lean frames stay under about 4 ms: a
transaction-synchronised present that waits with a short timeout would then be affordable.

## ABI

All Lean `@[export]` arguments are **owned** (consumed). The host calls `cairn_lean_inc` on
anything it keeps: `LeanCore.frame` incs the state before passing it, because the frame
function consumes it.

- v0 (now). The Counter uses the spike's exports and frame format
  ([spike-boundary.md](spike-boundary.md)). `SpikeV0Codec` adapts that format to
  `CairnFrame.Frame` and encodes pointer down/up and resize only.
- v1 (workstreams C and E). The exports are `<app>_init(w, h, scalePercent)`,
  `<app>_step(state, events : ByteArray)` and `<app>_frame(state) : ByteArray`, with the
  [frame.md](frame.md) codec. Moving an app to v1 means swapping the closures and the `codec`
  in its `LeanApp`. Nothing else in the host changes.

### Seams waiting on other workstreams

| Seam | Now | When it lands |
|---|---|---|
| `BoundaryCodec` (E) | `SpikeV0Codec` | E's v1 decoder/encoder in CairnFrame |
| `FrameRenderer` (F) | `StubRenderer`: Core Graphics into a bitmap, blitted to the drawable | `CairnRender`'s Metal renderer, passed as `Config.makeRenderer` |
| `LeanApp` (C) | `cairn_counter_*` | `cairn_app_init/step/frame` |
| Text metrics (F) | `Font.ctFont` in the stub and in `firstRect` | F's canonical font mapping |

## Input

| AppKit | Event |
|---|---|
| mouseDown/rightMouseDown | `pointerMove(p)`, then `pointerDown(p, button, clicks: clickCount, mods)` |
| mouseUp/rightMouseUp | `pointerUp(p, button, mods)` |
| mouseMoved / dragged | `pointerMove` (coalesced) |
| mouseExited | `pointerExit` |
| scrollWheel | `scroll(p, dx, dy)` through `ScrollAccumulator` |
| keyDown with no text field | `key(named or .char(lowercased), mods)` |
| keyDown in a text field | `interpretKeyEvents` → `insertText` / `setMarked` / `unmark` / selector table |
| Edit menu | `copy`, `cut`, `paste(String)` from NSPasteboard, `selectAll`, `undo`, `redo` |
| resize / backing scale | `resize(size)`, `scale(percent)` |
| window key / resign | `windowFocus(Bool)` |

- **Pointer.** Positions are logical points, y down, from the view's top-left, rounded down. A
  tracking area (`mouseMoved`, `enteredAndExited`, `activeAlways`, `inVisibleRect`) delivers
  hover even when the window is not key, so hover-to-delete works.
- **Scroll sign.** Positive `dy` scrolls toward the end of the content, like a web `wheel`
  event. AppKit's deltas already include natural scrolling. Line-based devices are scaled by
  16 points per line. Fractions carry over between events, so the sum Lean sees tracks AppKit's
  sum to within one point.
- **Keys.**
  - The main menu owns Cmd-Z/⇧Z/X/C/V/A, Q, H, M and W. A keyDown whose shortcut belongs to a
    menu item is dropped (`menuOwns`), so a shortcut never arrives twice.
  - AppKit sends no keyUp for a key pressed with Cmd. The host sends no key-up events at all,
    and Lean must not wait for one.
  - In a text field, a selector without a mapping is swallowed. The exception is `noop:` with
    Cmd or Ctrl held: that is an unbound shortcut, so it goes to Lean as a char key.
- **Selector table** (`KeyMapping`):
  - `move{Left,Right,Up,Down,Backward,Forward}` map to the arrow keys, and their
    `AndModifySelection` forms add shift.
  - Word moves are option plus arrow.
  - Line and paragraph ends are `home`/`finish`; document ends are command plus `home`/`finish`.
  - The `delete*` selectors map to backspace and delete, with option or command for word or
    line deletes.
  - `insertNewline` maps to `enter`, `insertTab`/`insertBacktab` to tab, and `cancelOperation`
    to `escape`.
  - `selectAll:`, `copy:`, `cut:`, `undo:` and `redo:` become the edit events.
- **Clicks from accessibility.** `AXPress`, toggling a checkbox and focusing a text field all
  become real clicks at the node's centre: `pointerMove`, `pointerDown`, `pointerUp`, then the
  real pointer position again (or `pointerExit`). They go through Lean's hit test like any
  click.
- **Mouse during composition.** While there is marked text, mouse events go to the input
  context first, so the IME can commit or move within the composition.

## Text input

### Index conversion

Lean indexes text by Unicode scalar. AppKit uses UTF-16 offsets in `NSRange`. `TextIndex`
converts between them.

- `utf16(i)` gives a scalar index's UTF-16 offset. `scalar(u, rounding:)` goes the other way.
  A UTF-16 offset inside a surrogate pair rounds down (to the scalar's start) or up (to its
  end).
- Every range from AppKit goes through one function, `scalars(_: NSRange) -> Range<Int>?`,
  which is defensive:
  - `NSNotFound` or a negative location gives nil;
  - the range is clamped to the string without overflow;
  - a start inside a pair moves down and an end inside a pair moves up;
  - an empty range stays empty.

  Native Pinyin sends both out-of-bounds offsets and offsets that split a pair. The tests cover
  each case (`TextIndexTests`).

### The shadow

The input system queries the client straight after `setMarkedText` and `insertText`, and the
main thread cannot wait for Lean. So the host keeps a `TextInputShadow` of the focused field,
in scalar indices. Chromium's browser process does the same.

- **Predicted edits.** `insertText`, `setMarkedText` and `unmarkText` each send their event and
  apply it to the shadow at once, using Lean's rules:
  - the target is the replacement range, else the marked text, else the selection;
  - `setMarked` puts its string there, marks it (or ends the composition if the string is
    empty) and selects within it;
  - `insert` replaces the target, unmarks, and leaves the caret after the new text.
- **Adoption.** When a frame arrives with `throughSeq` at or past the shadow's last event, the
  shadow becomes Lean's `TextInput`.
  - If nothing else that can edit the field was sent in between, the prediction is checked.
    Things that can edit it are a key, a click, an Edit-menu command or an AX click; sending
    one taints the shadow.
  - A failed check is recorded as a `ShadowDivergence`, exposed as
    `HostView.shadowDivergences`.
- **Lean acting on its own.** When Lean moves the caret or changes the text without being
  asked (a click elsewhere, Escape, a blur) and there was marked text, the host calls
  `discardMarkedText`. Any change calls `invalidateCharacterCoordinates`.
- **Never NSNotFound.** `selectedRange` never returns NSNotFound, because dictation breaks. With
  no field it returns `{0, 0}`.
- **Replacement ranges.** `Event.insertText` and `Event.setMarked` carry an optional
  replacement range in scalar indices (`ScalarRange`). This contract change is in
  `lean/Cairn/Input.lean` and `CairnFrame/Model.swift`.
- **Geometry.**
  - `firstRect(forCharacterRange:)` lays out the shadow's text with Core Text in the field's
    font, starting at the frame's drawn text origin. It takes its height from Lean's caret rect
    and returns zero width for an empty range.
  - `characterIndex(for:)` is the inverse.
  - Both are approximations until frames carry per-scalar offsets (question 2 below).
- **Input context.** `inputContext` is nil while no field is focused, so outside a text field
  keys go straight to `KeyMapping`. When a field gains or loses focus, the host activates or
  deactivates the context and calls `NSApp.updateWindows()`, which makes AppKit re-read it.
  Without this the IME never engages after a focus change.

## Accessibility

`AXMirror` keeps one `NSAccessibilityElement` subclass (`AXNodeElement`) per node.

- **Element identity.** Elements are keyed by `ControlRef.label` (`^5#12`). A node without a
  control is keyed by its parent's key, its role and an ordinal. An element is reused for as
  long as its key appears in frames. When the key disappears the element is marked dead: it
  answers empty and `.uiElementDestroyed` is posted for it.
- **Notifications.**
  - Order follows AccessKit:
    1. destroyed;
    2. `layoutChanged`, carrying the created elements;
    3. text-field value changes;
    4. selected-text changes;
    5. title changes;
    6. other value changes, with the focused element's last;
    7. focus.
  - `layoutChanged` is posted only when elements were added or removed, never per frame.
  - Nothing is posted while the view has no window (AppKit can hang).
- **Roles.**

  | Node role | AX role |
  |---|---|
  | checkbox | `.checkBox` |
  | textField | `.textField` |
  | list | `.list` |
  | listItem | `.group`, role description "list item" |
  | heading | `AXHeading` |
  | button | `.button` |
  | text | `.staticText` |
  | tab | radio button with subrole `AXTabButton` |
  | link | `.link` |
  | group | `.group` |

- **Attributes.** The identifier is the ControlRef label. A checkbox's value is 1 or 0; a text
  field's value is its text. The text-field range attributes are in UTF-16, converted through
  `TextIndex`.
- **Frames.** `accessibilityFrame` is overridden to return screen coordinates, converted from
  the frame's view rect through the window. This avoids parent-relative y-up maths.

## Latency

These were measured on this machine (macOS 27, Apple silicon) on 2026-10-23, with the release
build, `CairnCounter --latency 600`. Input → present depends on the display's refresh rate and
on whether the window is frontmost.

| | p50 | p95 | p99 | max |
|---|---|---|---|---|
| Lean step+frame+decode | 0.01 ms | 0.01 ms | 0.01 ms | 0.02 ms |
| input → frame published | 0.02 ms | 0.03 ms | 0.04 ms | 0.05 ms |
| input → present | 25.6 ms | 32.8 ms | 33.2 ms | 33.3 ms |

An earlier debug-build run with the window frontmost gave input → present p50 9.7 ms and
p95 17.2 ms. Input → present is dominated by waiting for the next display-link tick plus the
compositor's one or two frames, not by Lean.

`CairnCounter --bench` (release) measures one frame across the FFI as Lean frame time plus
Swift decode time:

| Nodes | Lean | Swift decode |
|---|---|---|
| 100 | 0.039 ms | 0.001 ms |
| 1,000 | 0.385 ms | 0.013 ms |
| 10,000 | 4.085 ms | 0.110 ms |

## Open questions

1. **Edit-menu capabilities.** The frame doesn't say what can be copied or undone, so the Edit
   items are always enabled and Lean ignores what doesn't apply. A `canCopy`/`canUndo` bit
   field in `TextInput` or `Frame` would let the menu grey out properly.
2. **Per-scalar offsets.** `firstRect` relayouts text with Core Text. If F's metrics and the
   frame's text origin disagree, IME candidate windows sit slightly off. Per-scalar x offsets
   for the focused field in the frame would remove the host's own layout.
3. **ControlRef uniqueness.** The mirror assumes each ControlRef labels at most one node per
   frame (duplicates: the first one wins). A theorem on the Lean side would discharge this.
4. **`presentedTime`.** It reads 0 for a windowed layer on macOS 27, so the presented handler's
   own time is used instead.

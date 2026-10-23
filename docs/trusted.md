# Trusted base

Everything the proofs rely on but do not prove, and how each item is checked instead. Each
entry is an `assume`: a statement about the world we take as given, with its evidence. Add
entries in the section of the workstream that introduces the assumption.

Items marked **Fuzzed** are also checked by the trusted-base fuzzer (`make fuzz-trusted`,
docs/fuzz.md "Trusted base"), against Lean's proved side or an independent oracle, and are
declared as `assume` claims ^901–^907 in `lean/Cairn/Fuzz/Trusted/Claims.lean`, each naming its
check; `build/fuzz/trusted.json` holds the evidence. Items not marked are checked only by the
tests and reviews they list.

## Renderer and text (workstream F)

See docs/render.md for the design.

### Text metrics match what is painted (`assume`)

**Statement.** For every font and string, the caret offsets, ascent and descent that
`TextMetrics.host` returns are those of the Core Text line the renderer draws for the same
`Draw.text`: the glyphs of a text draw at baseline origin `o` lie within
`[o.x, o.x + width] × [o.y − ascent, o.y + descent]`, where `width` is the last offset, and the
caret offset at scalar boundary `i` is Core Text's primary caret offset there, rounded up to a
whole point.

**Scope.** Text is single-line and left-to-right in M1. Right-to-left and bidirectional text are
out of scope: their offsets are made nondecreasing by a running max and are not meaningful
carets. Scalar boundaries inside a grapheme cluster report the cluster's end, so several
consecutive offsets can be equal (the caret appears to stall over "é" written as e + U+0301, or
a ZWJ emoji); grapheme clusters are not modelled in M1. Italic and some fallback scripts
(Arabic) overhang the box by up to 1 pt of ink.

**What is not assumed.** `TextMetrics.Valid` (offsets start at 0, never decrease, one per
scalar boundary; ascent and descent nonnegative) is *proved* for `TextMetrics.host`
(`Cairn.TextMetrics.host_valid`): Lean normalises whatever bytes the host returns. Layout
theorems quantify over every valid metrics, so they hold for Core Text's whatever it reports.

**Trusted code.** `host/Sources/CairnRender/TextSystem.swift` (shaping, UTF-16 boundary mapping,
rounding), `Fonts.swift` (Font → CTFont), `Metrics.swift` (the C export),
`lean/c/text_host.c` (the Lean ABI glue and the weak stand-in), and Core Text itself.

**Evidence.**
- `LeanMetricsTests`: Lean's `TextMetrics.host`, called through the real `@[extern]`, glue and
  export, equals the renderer's shaped line for 5 fonts × 11 strings, and the Swift
  implementation (not the weak stand-in) is linked.
- `MetricsTests`: the host's output is already valid (no normalisation needed) for 8 fonts ×
  24 strings including emoji, CJK, combining marks, RTL, NUL and BOM; offsets come from one line
  (kerning); boundaries never land mid-surrogate.
- `InkTests`: the painted pixels of every sample text draw lie inside the box Lean computes
  (upright LTR text: exactly; italic and RTL: within 1 pt), at 1x and 2x.
- **Fuzzed** (^906 `text.metrics`): `cairn_text_metrics` across families, sizes 0 to 2³²−1,
  weights, italic, edge text and invalid UTF-8 returns `TextMetrics.Valid`'s shape, its
  truncated and null-buffer forms agree, and Lean's `TextMetrics.host` sees the same numbers.
- **Fuzzed** (^907 `text.metrics.carets`): on left-to-right text, the caret after each grapheme
  is at or right of the glyphs painted before it. This found Core Text answering 0 for real
  caret positions (before a trailing control, and after some fallback runs); `TextSystem` now
  takes those from the glyph runs. Core Text's own caret can still sit inside a LastResort or
  contextually spaced CJK glyph (fuzz.md, finding 5): that part of the statement holds only up
  to such glyphs.
- To do (workstream G/J): log every measurement in the running app and replay the log against a
  fresh Core Text in conformance runs, as the `assume` claim's runtime evidence.

### The renderer paints the frame (`assume`)

**Statement.** `Renderer` paints `frame.draws` in order, later on top; a rect paints exactly the
device pixels whose centres lie inside it (edges snapped `⌈v·s − ½⌉`), with its border inside it
and its corners rounded; nothing paints outside the intersection of the clips pushed around it;
text paints its glyphs at the positions Core Text gives, relative to its baseline origin.

**Trusted code.** `host/Sources/CairnRender/Renderer.swift`, `Shaders.swift`,
`GlyphAtlas.swift`, Metal and the GPU driver, Core Graphics' glyph rasterisation.

**Evidence.** Golden images at 1x, 1.5x and 2x with tolerances; pixel-probe tests (exact fills,
borders, clips, order, seams, antialiasing width); `Renderer.probe` for conformance checks that
each control's box is painted (workstream J). Choices that affect only the look, not what is
painted where: grayscale antialiasing with font smoothing off, gamma-space blending into
`bgra8Unorm`, sRGB colours (the host must set the layer's colour space to sRGB).

**Also assumed.** Frames have balanced `pushClip`/`popClip`; an extra `popClip` is ignored and
counted (`RenderStats.unbalancedPops`) rather than trusted.

## Frame encoding (workstream E)

See [frame.md](frame.md) for the format. Lean's side is proved (`decodeFrame_encodeFrame`,
`decodeEvents_encodeEvents`, `encodeFrame_eq_put`); the Swift side is not.

### The Swift codec matches Lean's (`assume`)

**Statement.** For every byte buffer Lean's `encodeFrame` produces, `Frame(bytes:)` returns the
Swift mirror of the encoded `Frame`, and it throws on every buffer Lean's `decodeFrame` rejects.
For every `[Event]`, `encodeEvents` produces bytes that Lean's `decodeEvents` decodes to the
Lean mirror of those events.

**Trusted code.** `host/Sources/CairnFrame/Decode.swift`, `Encode.swift`, and the hand-written
correspondence between `Model.swift` and `Cairn/Frame.lean` / `Cairn/Input.lean`.

**Evidence.** The corpus (`make test`, frame.md "Canonical dump and the corpus"): 300 frames
and 300 event batches from Lean, compared through a canonical text dump and byte for byte; 202
Swift-encoded batches decoded by Lean; truncated, corrupted and invalid-UTF-8 frames rejected.
The comparison itself goes through two dump printers, one per language, which could share a
bug; the dump is deliberately simple (one line per item, every field printed).

**Fuzzed** (^901 `frame.decode`, ^902 `events.encode`): random Lean frames and their mutations
(bit flips, length and count fields, truncation, splices, inserted and deleted bytes) must be
accepted or rejected alike by `Frame(bytes:)` and Lean's `decodeFrame`, with equal dumps; random
Swift event batches must decode in Lean to equal dumps and re-encode to the same bytes. This
found the Swift decoder ignoring the reserved flags field (fixed).

**Also assumed.**
- **Key characters.** `Key.char` in Swift holds a `Character`, Lean's a single scalar. The
  encoder sends the `Character`'s first scalar; a multi-scalar character (an emoji with a skin
  tone) arrives as its base. Shortcuts are single scalars, and text arrives as `insertText`.
- **Font saturation.** Font fields above `2^32 − 1` are clamped in the encoder exactly as
  `Cairn.Text.Host.sat` clamps them for measurement (proved: `satU32_eq_host_sat`), so Swift
  paints at the size Lean measured.

## Host (Swift, AppKit): `host/Sources/CairnHost`

See [host.md](host.md) for how each piece works.

### Input

- **AppKit event delivery.** We trust AppKit to deliver mouse, key and scroll events to the
  view in the order the user produced them. Its `clickCount` is used as is: the double-click
  interval and distance are the user's system settings, not Lean's.
- **Pointer positions.** View coordinates are rounded down to integer logical points (y down,
  from the top-left). Lean never sees sub-point positions.
- **Coalescing.** Consecutive pointer moves become the last move, and consecutive scrolls
  become one scroll with summed deltas. The host assumes no app needs the intermediate
  positions.
- **Scroll.** Positive `dy` means toward the end of the content. A line is 16 points for
  line-based devices. Fractions are carried, so Lean's total scroll is within one point of
  AppKit's.
- **Key mapping.**
  - With a text field focused, AppKit's key bindings (`interpretKeyEvents`) decide which
    command a key is, and `KeyMapping`'s selector table turns the command into a Lean event.
    The table is reviewed by hand, not derived.
  - Outside a text field, keys map by virtual key code and `charactersIgnoringModifiers`, one
    key per character when a synthesized event carries several.
  - The host sends no key-up events. AppKit sends none for keys pressed with Cmd.
- **Menu shortcuts.** A keyDown whose shortcut belongs to a main-menu item is dropped, so a
  shortcut reaches Lean once, through the menu action.
- **Edit menu.** For M1, Undo, Redo, Cut, Copy, Paste and Select All are always enabled. The
  frame doesn't say what applies, so Lean ignores commands that don't apply.
- **Paste.** The string read from `NSPasteboard.general` (plain text type) is passed to Lean
  as is.
- **Accessibility actions.** AXPress, a checkbox toggle and focusing a text field all become a
  real click at the centre of the node's rect: move, down, up, then the real pointer position
  again. This assumes the node's AX rect is inside its hit region and not covered by another
  control. The assumption holds when Lean's AX rect and hit rect agree (workstream C).

### Text input

- **Index conversion.** `TextIndex` converts UTF-16 offsets to scalar indices. Unit tests
  cover it, and nothing proves it. Out-of-range offsets are clamped. A range that splits a
  surrogate pair is widened to whole scalars. **Fuzzed** (^903 `text.index`) against Swift's
  own string views, with AppKit's `NSNotFound`, negative and `Int.max` ranges.
- **IME behaviour.** We trust the system input methods (Japanese, Chinese, Korean, dictation,
  dead keys) to drive `NSTextInputClient` as documented. Their behaviour is not modelled,
  only reflected.
- **Shadow prediction.** Between an input-method call and the frame that reflects it, the host
  answers from its own copy of the field. It updates that copy with rules it assumes match
  Lean's:
  - the target is the replacement range, else the marked text, else the selection;
  - `setMarked` marks its string and selects within it;
  - `insert` unmarks and leaves the caret after the text;
  - `unmark` keeps the text;
  - line breaks (LF, CR, VT, FF, U+0085, U+2028, U+2029) become spaces, as `Field.clean` makes
    them.

  Lean's frame always replaces the copy. Any prediction that disagrees is recorded in
  `HostView.shadowDivergences` for the conformance driver. **Fuzzed** (^904 `text.shadow`):
  random input-method sequences against a Lean field app; after each call the copy must be what
  Lean's next frame shows. This found the line-break rule missing (fixed).
- **Text geometry for the IME.** `firstRect` and `characterIndex(for:)` use
  `TextSystem.shared.shape`, the renderer's shaping, to get caret offsets. The offsets are
  measured from the frame's `textOrigin`, in the font of the text draw at that origin, which
  is assumed to be the field's text. **Fuzzed** (^905 `text.input-client`): selected and marked
  ranges equal Lean's, `firstRect` at the selection is Lean's caret, `characterIndex(for:)` at
  the caret round-trips, and every answer is a scalar boundary or `NSNotFound`. This found the
  geometry lost in a scrolled field, when the text draw starts left of the field (fixed).

### Accessibility

- **AX mirror.** The `NSAccessibilityElement` tree is a translation of the frame's AX nodes:
  roles, labels, values, focus and frames. The table in host.md lists the role mapping. It is
  reviewed by hand.
- **ControlRef uniqueness.** The mirror assumes a ControlRef labels at most one node per
  frame. On duplicates, lookups find the first node.
- **Screen frames.** AX frames come from the view's rect through `convert(to: nil)` and
  `window.convertToScreen`.

### Output

- **Rendering.** `MetalRenderer` hands each frame to F's `Renderer` (see the section above).
  The host sets the layer to `bgra8Unorm` with an sRGB colour space, as F requires. While the
  render loop holds a frame back during a resize, the screen shows an older frame than the
  latest one.
- **Effects.** `setClipboard` writes a plain string to the general pasteboard. `beep` calls
  `NSSound.beep()`.
- **Cursor.** The frame's cursor becomes an NSCursor through cursor rects over the whole view.
- **Live resize.** While a resize is in flight, the last picture is shown for up to 100 ms. It
  can briefly not match the window's size.

### Measurement

- **Present time.** `CAMetalDrawable.presentedTime` reads 0 for this windowed layer on
  macOS 27. Input → present then uses the time the presented handler runs, which comes just
  after the present.

### Boundary

- **Decoder.** The Swift decoder is trusted to turn the frame's bytes into exactly the
  `Frame` Lean encoded: the v1 decoder in `CairnFrame` (`FrameV1Codec`), for every app. See
  "Frame encoding (workstream E)" for v1's evidence (fuzzed, ^901).
- **Lean runtime.** The runtime is initialized once, on the Lean thread, and the `Cairn`
  module is initialized before the app's module. Every other thread that calls Lean registers
  with `lean_initialize_thread` (`cairn_lean_thread_begin`). The main and render threads never
  call Lean.
  - The Lean thread's 64 MB stack is assumed to be enough for the app's recursion depth.
  - Release builds keep Lean's default panic behaviour, where `panic!` returns a default value
    and execution continues. Debug builds abort on panic.

## Conformance (workstream J)

See [conformance.md](conformance.md). A passing run means that, for the sequences it ran, the
app showed exactly what the model says, judged through the pieces below. Each one is trusted.

- **Injection at the view.** The debug socket builds `NSEvent`s and calls `HostView`'s
  responder methods (`mouseDown(with:)`, `keyDown(with:)`, …), `NSTextInputClient` and
  `NSApp.sendAction` directly. That bypasses the window server's routing and
  `NSWindow.sendEvent`, so window-level hit testing, key-window and first-responder routing
  aren't covered. The socket also sets `clickCount` itself, so the user's double-click interval
  isn't exercised.
- **The events are like the keyboard's.** Key events carry the key code, characters,
  `charactersIgnoringModifiers` and flags a US keyboard would produce (the table is in
  `DebugServer.key`). AppKit's key bindings read these, and so does the host outside a field.
  A wrong synthesized field reads as a host bug. One did: Shift-Tab, conformance.md "Bugs
  found".
- **IME shapes.** Compositions are `setMarkedText`/`insertText`/`unmarkText` calls shaped like
  an input method's. No real input method runs.
- **Key bindings.** Results inside a field go through the current user's AppKit key bindings
  (`interpretKeyEvents`). They match the standard bindings unless the user customized them.
- **Effects through the hook.** Under the socket, effects pass through `HostView.effectHook`.
  A clipboard write goes to a private pasteboard through the host's own code, and a beep is
  recorded but not sounded. `NSSound.beep` and the general pasteboard aren't exercised.
- **DebugRenderer for MetalRenderer.** Under the socket, the window draws through
  `DebugRenderer`. It uses the same `Renderer`, clear colour and layer format, and adds a blit
  and a GPU wait. Pixels are read from that copy of the presented drawable, so the compositor
  and the display aren't covered. When the window isn't drawing, the socket falls back to
  `Renderer.probe` (reported as `source: "offscreen"`). The Basics run never needed it.
- **`ignoresMouseEvents` and no activation.** The app runs as an accessory app with its window
  not key. Nothing in Basics reads window focus, so this doesn't change its frames. An app that
  reads `UI.windowFocused` would see `true`, the runtime's default.
- **Restart.** Sequences reset with `Engine.restart`, which re-runs `cairn_app_init` in the same
  process. Host-side state that survives (the AX mirror's element identities, the pointer's last
  position in AppKit, the cursor) isn't reset. Each sequence's initial frame and AX tree are
  checked.
- **The model's metrics.** The generator links the host's Core Text metrics (`CairnMetrics`,
  through `-force_load` over the weak fallback). Its frames are the app's only if both measure
  on the same machine with the same fonts.
- **The comparison code.** Frames are compared through two JSON printers, `Conformance.jframe`
  in Lean and `DebugJSON.frame` in Swift. The expected AX tree is derived in the driver from the
  host's table (`expectedAx` in driver.ts). That table is written by hand, like the mirror's.

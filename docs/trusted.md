# Trusted base

Everything the proofs rely on but do not prove, and how each item is checked instead. Each
entry is an `assume`: a statement about the world we take as given, with its evidence. Add
entries in the section of the workstream that introduces the assumption.

Items marked **Fuzzed** are also checked by the trusted-base fuzzer (`make fuzz-trusted`,
docs/fuzz.md "Trusted base"), against Lean's proved side or an independent oracle, and are
declared as `assume` claims ^7, ^214, ^901–^915, ^940–^944, ^960–^975, ^1000–^1012 and ^1020–^1022 in `lean/Cairn/Fuzz/Trusted/Claims.lean`, each naming its
check; `build/fuzz/trusted.json` holds the evidence. Items not marked are checked only by the
tests and reviews they list.

## New in M4

Every assumption M4 (Sky, docs/goals/m4.md) added to the trusted base, and the trusted fuzzer's
check for each (`make fuzz-trusted`). Each has its entry below.

| Claim | Assumption | Fuzz check |
|---|---|---|
| ^972 `hostKeychain` | The Keychain keeps what it was given for this app, one Security call at a time | `effects.secret.keychain` (with `keychain.concurrent`, live) |
| ^973 `hostCapture` | Captured reply fields go to the Keychain and never to Lean | `effects.http.capture` |
| ^974 `hostHttpSecret` | `http` sends a secret header from the Keychain as from the environment, and a request with a secret never follows a redirect | `effects.http` |
| ^975 `hostEnvSecret` | An environment secret is read from the environment or its file, and never shown (reissues ^971 now that a secret can be a Keychain item) | `effects.secret` |
| ^1012 `hostScroll` | The host reports scrolls where they happen, toward the end positive | `pointer.scroll` |
| ^1020 `hostSecureInput` | Secure event input is on exactly while a secure field has focus | `text.secure-input` |
| ^1021 `hostAxScroll` | Assistive apps reach only what a scroll area shows | `ax.scroll` |
| ^1022 `hostAxSecure` | A secure field shows assistive apps nothing typed, and the debug socket shows no secret | `ax.secure` |

What M4 added on the Lean side is proved, not assumed: the clamp on every scroll offset, a
scroll never reaching `update`, the rows a virtual list lays and its anchor, `Action.appear`,
secure fields' frames and dumps (`SecureField.view_agree`, `Dump.secure_canvas`), and that no
Lean value holds a token. Secure fields' undo, copy and cut are Lean's (`SecureField`). One
M4 change in the host is reviewed by hand and not fuzzed: its text-input shadow writes a bullet
for each scalar typed into a secure field (`FieldState.secure`), as Lean's frame does, so its
prediction holds no typed text; `text.shadow` fuzzes the shadow on plain fields only.

## Renderer and text (workstream F)

See docs/render.md for the design.

### Text metrics match what is painted (`assume`)

**Statement.** For every font and string, the caret offsets, ascent and descent that
`TextMetrics.host` returns are those of the Core Text line the renderer draws for the same
`Draw.text`: the glyphs of a text draw at baseline origin `o` lie within
`[o.x, o.x + width] × [o.y − ascent, o.y + descent]`, where `width` is the last offset, and the
caret offset at scalar boundary `i` is Core Text's primary caret offset there, rounded up to a
whole point. On a tracked line it is instead the furthest pen position (glyph position plus
advance, tracking included) among the glyphs drawn for the text before `i`, because Core Text's
tracked carets sit inside glyphs (fuzz.md, finding 11).

**Scope.** Text is left-to-right in M1; a text draw is one line (wrapped text is several draws, below). Right-to-left and bidirectional text are
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
  weights, italic, the four widths, tracking from −2³¹ to 2³¹−1 hundredths of a point,
  tabular digits, edge text and invalid UTF-8 returns `TextMetrics.Valid`'s shape, its
  truncated and null-buffer forms agree, and Lean's `TextMetrics.host` sees the same numbers.
- **Fuzzed** (^907 `text.metrics.carets`): on left-to-right text, the caret after each grapheme
  is at or right of the glyphs painted before it. This found Core Text answering 0 for real
  caret positions (before a trailing control, and after some fallback runs); `TextSystem` now
  takes those from the glyph runs; and wrong carets on every tracked line, which now come from
  the pen positions (finding 11). Core Text's own caret can still sit inside a LastResort or
  contextually spaced CJK glyph (fuzz.md, finding 5): that part of the statement holds only up
  to such glyphs.
- To do (workstream G/J): log every measurement in the running app and replay the log against a
  fresh Core Text in conformance runs, as the `assume` claim's runtime evidence.

### Wrapped lines are what Core Text paints (`assume`, ^990, ^991)

**Statement.** Lean breaks `Node.para` text (docs/layout.md, "Wrapped text") using the caret
offsets of *one* shaping of the whole string: a line `[a, b)` is taken to be `o b − o a` wide.
The renderer then paints each line as its own `Draw.text`, which Core Text shapes again on its
own. ^990: on left-to-right text, that second shaping is within `1 + ⌈0.15 em⌉` points of what
Lean measured, so a line Lean proved fits the width paints within that slack of it. ^991: Lean's
breaks are the ones Core Text's typesetter would choose, except near the width and inside cut
words.

**Why it can differ.** Kerning across the dropped break space (", " pairs) and across a cut in
an over-wide word is lost when the line is shaped alone, and Core Text rounds and cuts by its own
fractional widths. A host that wanted exact agreement would have to report per-line widths,
which would make the breaks depend on a host round trip per candidate line.

**Scope.** Left-to-right only. Right-to-left, bidirectional and complex scripts are not
modelled (their offsets are a running max, see above). Tabs, line separators (U+2028/2029) and
other controls are not break opportunities and shape unpredictably; the fuzzer skips them.
Breaks are only at U+0020, and over-wide words are cut at scalar boundaries, which can split a
grapheme cluster (an emoji sequence or a combining mark); the fuzzer counts and skips such lines.
Strings that need fallback fonts can shape differently alone than in context; the fuzzer only
counts those.

**What is not assumed.** That every line fits, the lines tile the text, the count respects
`maxLines`, `tail` keeps the last lines and the height is lines × line height are *proved* over
every valid metrics (`Cairn.Text.WrapProofs`, `Cairn.Layout.Para`).

**Trusted code.** As for text metrics above; no new host code paints wrapped text.

**Evidence.**
- **Fuzzed** (^990 `text.wrap.painted`): random letters, digits, spaces and `TextPool` strings
  at random families, sizes, weights and widths, laid out by Lean's `layout` through the real
  export; each line sits at x 0, `i` line heights down, and its width and carets re-shaped alone
  agree with Lean's to the slack. Counters split exact, off-by-one, cut-kerning and
  space-kerning lines.
- **Fuzzed** (^991 `text.wrap.coretext`): on plain text, Lean's lines against
  `CTTypesetterSuggestLineBreak`'s; a difference must be a line within 1 pt of the width
  (`roundingDiffers`) or a cut within two scalars (`cutDiffers`).

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
painted where: grayscale antialiasing with the system's font smoothing (its level picked from the text colour), gamma-space blending into
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
- **Clicks where they happen** (`assume`, ^7 `hostClicks`). A click reaches Lean as
  `pointerMove p`, `pointerDown p primary` and `pointerUp p primary`, in order and with nothing
  between, where `p` is the clicked point rounded down as above, with the event's modifiers.
  Every press of every app relies on it.
- **A double click is a second click** (`assume`, ^214 `doubleClick`). The second click of a
  double click reaches Lean as another `pointerMove p` and a `pointerDown p primary` with
  `clicks: 2` at the same point, then its `pointerUp`; the runtime turns that release into a
  `doublePress` (TodoMVC's `cairn_examples^205` relies on it). Which clicks make a double click
  (the interval and distance) is AppKit's, from the user's settings.

  ^7 and ^214 were declared by the Counter and TodoMVC examples (now in cairn_examples); they keep
  their ids and statements and now live with the other assumptions in `Cairn.Fuzz.Trusted.Claims`,
  since every app relies on them.

  **Trusted code.** `HostView`'s `mouseDown`, `mouseUp` and `point` (`host/Sources/CairnHost/HostView.swift`),
  the engine's queue (`Engine.swift`), AppKit's hit testing and its `clickCount`.

  **Evidence.** **Fuzzed** (^7 `pointer.click`, ^214 `pointer.double-click`): a titled window
  (never shown) of random size whose content view is the host's `HostView`, given AppKit mouse
  events for random clicks, double clicks and triple clicks (`clickCount` 1, 2, 3, within the
  double-click interval) with random modifiers, at fractional points and on the content's edges,
  each sent to the view AppKit's hit testing picks. The events the app's core receives must be
  exactly the expected ones, with `p` computed from the window location and the content height,
  not by the host's own conversion. Mutating the host to round to nearest, or to drop
  `clickCount`, fails both checks. Not covered: AppKit's choice of `clickCount` itself, and
  routing by `NSWindow.sendEvent` in a shown window.
- **Coalescing.** Consecutive pointer moves become the last move, and consecutive scrolls
  become one scroll with summed deltas. The host assumes no app needs the intermediate
  positions.
- **Scroll.** Positive `dy` means toward the end of the content. A line is 16 points for
  line-based devices. Fractions are carried, so Lean's total scroll is within one point of
  AppKit's. Load-bearing since #203: the runtime moves a scroll box by exactly these numbers
  (^1012, "Scrolling (M4)" below).
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
- **Scrolled-out children.** A scroll box's node is an `AXScrollArea`, and the mirror leaves
  out what is scrolled out of it: `assume` ^1021, fuzzed. See "Accessibility of scroll areas and
  secure fields (M4)" below.
- **ControlRef uniqueness.** The mirror assumes a ControlRef labels at most one node per
  frame. On duplicates, lookups find the first node.
- **Screen frames.** AX frames come from the view's rect through `convert(to: nil)` and
  `window.convertToScreen`.
- **Secure fields.** A frame node with `secure` set is an `AXSecureTextField` that shows
  nothing typed: `assume` ^1022, fuzzed. See "Accessibility of scroll areas and secure fields
  (M4)" below.

### Output

- **Rendering.** `MetalRenderer` hands each frame to F's `Renderer` (see the section above).
  The host sets the layer to `bgra8Unorm` with an sRGB colour space, as F requires. While the
  render loop holds a frame back during a resize, the screen shows an older frame than the
  latest one.
- **Effects.** `setClipboard` writes a plain string to the general pasteboard. `beep` calls
  `NSSound.beep()`. `quit` calls `NSApp.terminate`. `focus`, `setTimer` and `cancelTimer` are
  the runtime's and ignored. `request` and the subscription commands go to the `World`
  ("Effects (workstream Q)" below).
- **Closing the window.** Closing the app's window quits the app (docs/host.md, "Closing the
  window"). AppKit is trusted to post `willClose` before it tears the window down, and
  `NSApp.terminate` to end the process; between the two, the view applies no frame and runs no
  effect, so effects in frames published after the close are dropped. Checked by
  `Fixture --close-test` (`make selftest`), not proved.
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

## Effects (workstream Q)

See [effects.md](effects.md). Lean decides everything: which timers are set and when they fire,
which replies are delivered, which subscriptions run; the runtime's side is proved
(`steps_book`, `step_reply`, `step_sub_ignored`, `diffSubs_*`, effects.md "Theorems"), whatever
the host sends. What the host is trusted with is that what it sends is true: the time, the
deadline, and the outcome of each request. Trusted code: `host/Sources/CairnHost/World.swift`
(HostClock, Handlers, Files, Sounds, HTTP, World) and the clock and wake parts of
`Engine.swift`. Each item is an `assume` claim with a fuzz check (docs/fuzz.md, "Trusted base");
`WorldTests` and the fixture's self test (its Flash timer, `make selftest`) cover them end to
end. Clock's self test (clock, timers and wake, file reads and writes, a subscription) runs only
in cairn_examples' `make check`, against the released Cairn.

- **Fuzzed** (^908 `clock.monotonic`): every batch starts with exactly one clock; `mono` is
  `CLOCK_MONOTONIC` in ms (it counts sleep), never decreases between batches, is not ahead of
  the batch's arrival and at most 40 ms behind it; `wall` is `Date` within 1 s; `zone` is the
  current UTC offset. The runtime does not rely on monotonicity for safety (it keeps
  `max old new`, `tick_mono`), only for timers to come due.
- **Fuzzed** (^909 `clock.wake`): a frame's `wake` brings a clock-only batch at or after the
  deadline (never early: the strict dispatch timer runs on uptime, which never gets ahead of
  the monotonic clock), within 40 ms under load (typically under 1 ms, bench/effects.md), and
  none after a later frame cleared or met it. A wake missed entirely would only delay timers
  until the next input; a wake early would only cost a step, since Lean fires nothing before
  it is due.
- **Fuzzed** (^910 `effects.read-file`, ^911 `effects.write-file`): files round-trip exactly
  under random Unicode names; replacement is atomic against a concurrent reader; failed writes
  leave the file alone; missing, unreadable, directory, NUL and file-system-refused paths map
  to the faults effects.md lists. `~/` is the only path rewriting. This found NUL in a path
  silently cutting the path (now `invalid`) and APFS's `EILSEQ` for unassigned code points
  mapped to `other` (now `invalid`).
- **Fuzzed** (^912 `effects.sound`): every system sound name resolves; any other name is
  `failed notFound`, answered once. Playing is checked only with `CAIRN_FUZZ_SOUND=1` (it is
  audible). That the sound is actually heard is not checked.
- **Fuzzed** (^974 `effects.http`, which reissues the retired ^913 now that `http` carries a
  secret and captures): against a `URLProtocol` stub, the method, URL (as
  Foundation parses it), headers and body arrive as given; status, headers (sorted) and body
  come back exactly; connection failures are `network`, a silent server `timeout` after the
  requested time; bad schemes, methods, header names and CR/LF/NUL in values are `invalid`
  and send nothing (no header injection). With a secret (environment or Keychain), the header
  is `scheme ++ value`; a missing one is `notFound` and one with CR, LF or NUL `invalid`, neither
  sent; a redirect is followed without a secret and answered as the 302 with one, so the
  secret never reaches the other URL (the stub redirects to another host; removing the
  host's redirect refusal makes this check fail). Not covered: real TLS, proxies, HTTP/2
  specifics; those are Foundation's.
- **Fuzzed** (^914 `effects.reply-once`): with handlers that answer zero to three times, from
  other threads, late, every request is answered at most once and, when its handler answers,
  exactly once, under its own id with the first answer; a kind with no handler is answered
  `invalid`; after `reset` returns no earlier answer is sent (replies are sent under the
  world's lock, which `reset` takes). The runtime drops duplicates anyway (`Book.reply_once`).
- **Fuzzed** (^915 `subs.every`): ticks only for started, not stopped ids (all commands and
  ticks are on one serial queue), at most one per period, at least one over many periods, and
  `running` equals the model after every frame. The runtime ignores ticks of stopped ids anyway
  (`step_sub_ignored`); the engine coalesces a run of identical ticks.
- **Also assumed.** The handler table's code runs on global queues and must not call Lean.
  `NSSound` is used on the main thread. `writeFile`'s atomicity is Foundation's
  `Data.write(options: .atomic)` on one volume.

## Yap's host effects (workstream T)

See [effects.md](effects.md), "Yap's host effects". As for workstream Q's effects, Lean decides
what to do with every answer and the runtime's handling is proved whatever the host sends;
the host is trusted to report the world truly and to do what was asked. Trusted code:
`host/Sources/CairnHost/FileEffects.swift` (Files.append, list, delete; FileSignature),
`SystemEffects.swift` (Apps, PermissionSystem, Permissions), the `watchFile` part of
`World.swift`, and under them POSIX, `NSWorkspace` and TCC. Each item is an `assume` claim
with a fuzz check (docs/fuzz.md, "Trusted base"; suites `fileops` and `system`), which runs
in a scratch directory and never prompts.

- **Fuzzed** (^960 `effects.append-file`): after `done` the file is its old bytes followed by
  exactly the new ones; a new file is mode 600 under created directories; appenders on 2–4
  threads each land whole and in their own order; a directory, a path under a file, a
  read-only file, NUL and refused names fail and leave the file as it was. **Also assumed:**
  an append that fails part way (a full disk, an I/O error) can leave a prefix of its bytes;
  this is not fuzzed (it needs a full disk). Lean's reader of a JSON-lines file must treat a
  bad line as one lost entry. Directories it makes are mode 700 (fuzzed with ^960); a failure's
  message is Foundation's text for the errno, as Yap shows it (`Files.appendFailure`; not
  checked against Foundation's own failing calls, which need a full disk).
- **Fuzzed** (^1003 `effects.make-dir`): after `done` the path is a directory; each directory
  made is mode 700 whatever the umask, and one already there keeps its mode; again is `done`;
  over a file, under a file, a read-only parent, NUL and the empty path fail.
- **Fuzzed** (^961 `effects.list-dir`): exactly the names made (files, directories, links,
  random Unicode), sorted by UTF-8 bytes, byte for byte what `FileManager` lists; missing is
  `notFound`, a file `invalid`, unreadable `denied`. (FileManager drops a leading U+FEFF from a
  name and `readdir` doesn't, so that comparison ignores one.) **Also assumed:** a name that is not
  valid UTF-8 is left out (APFS has none; other file systems might).
- **Fuzzed** (^962 `effects.delete-file`): a file or a link (never its target) is gone after
  `done`; a second delete is `notFound`; a directory is `invalid` and stays; a read-only
  parent is `denied` and the file stays.
- **Fuzzed** (^963 `subs.watch-file`): with polls of 5–20 ms (and, in half the cases, a
  shorter look after one that saw a change, as the live world's 2 s and 50 ms), every write in place, atomic
  replacement, append, deletion, creation, `touch` and `chmod` is followed by one `changed`
  (two only when the operation's own system calls, such as truncate then write, land a whole
  poll apart: the host reports a state once it has held for a poll) within a few polls, an untouched file or
  a changed sibling brings none, and after the stop is handled none comes. **Also assumed:** a
  change that restores every one of device, inode, size, modification and change time (to
  the nanosecond) inside one poll is not seen; the file system's clock makes that impossible
  in practice. The runtime ignores events of a stopped id anyway (`step_sub_ignored`).
- **Fuzzed** (^964 `effects.frontmost-app`): the stub's pid and name come back exactly (no
  name is `""`, no app `notFound`, pid 0 or negative `failed`); the live answer is a running
  process with the name `NSRunningApplication` gives it. **Also assumed:** `NSWorkspace`'s
  answer is the app that gets the keyboard; it is updated by notifications on the main run
  loop, which a running app has. Read on a global queue, as `NSWorkspace` allows.
- **Fuzzed** (^965 `effects.permission`): against a stubbed TCC, each combination of
  permission, status, `prompt` and the person's choice gives the documented answer, the
  system is asked to prompt only when `prompt` is set (the microphone only while undecided),
  and each request is answered once; live, without prompting, the answers equal
  `AXIsProcessTrusted()` and the microphone's `authorizationStatus`. **Not checked:** the
  prompts themselves (they need a person), and that TCC's answer is right.
- **Fuzzed** (^1000 `effects.open-item`, workstream W): against a stubbed workspace, a target
  with a scheme is opened as that URL, a path (`~/` expanded) as a file URL only when it
  exists (`notFound` otherwise), the answer is `done` exactly when the workspace took it, and
  empty or NUL targets open nothing. **Not checked:** what the system opens it with (the
  Finder for a folder, the default editor for a `.txt` or `.json`, System Settings for its
  URLs); that needs a screen.
- **Fuzzed** (^1001 `effects.app-running`): the flag is whether the stub counts a running app
  with that id; live, it agrees with `NSRunningApplication` for the Finder, and an id no app
  has is not running. **Also assumed:** an app that is starting or quitting is reported as the
  system lists it at that moment; Yap (Cairn) polls every two seconds.
- **Fuzzed** (^1002 `effects.read-default`): strings, booleans, numbers, missing values and
  other types give the documented answer, read from the domain and key asked for. **Also
  assumed:** `CFPreferencesCopyAppValue` returns what another app last wrote to its domain
  (cfprefsd keeps them in step); it never writes.
- **Permissions.** None of these needs one. Accessibility and Microphone are what
  `permission` reports; they are granted to the app's code signature, so an unsigned or
  re-signed build is a new app to TCC (docs/effects.md).

## Host-drawn content and shapes (workstream Y)

A `paint` draw (docs/frame.md) hands a box to a painter: a Metal shader the app registers with
the host (`Painters.register`) and the Swift that feeds it the draw's integers and the time.
Yap's tape display is the original Yap's `Overlay.metal`, unchanged
(`host/Tests/CairnFuzzTrusted/YapTape.swift`). A `shape` draw is a rounded rect drawn by Core
Graphics: continuous corners, an inside border, and a drop shadow blurred with a Gaussian of
σ = 1.05 × radius (Accelerate), fitted to SwiftUI's `shadow(radius:)` (`shadowsAreSwiftUIs`:
within 7 levels).

**What is assumed.** ^1004 `hostPaintBounds`: a paint draw changes no pixel outside its box
(snapped to device pixels as rects are) within the clip in force. The renderer sets the
viewport to the box and the scissor to the box within the clip before the painter encodes,
and resets both after; Metal's scissor test does the rest. A painter must not change the
viewport, the scissor or the pipeline; nothing enforces that but review. A paint is part of a
box's style and adds no control of its own: hit testing and the accessibility tree come from
the laid tree's controls (`controls_ofLaid`), so a box whose only content is a paint is inert.

**Not assumed, and not proved.** What a painter paints inside its box: Yap's tape is compared
with the original by eye and by pixel (yap-cairn's docs/yap.md, "Overlay parity"). Shapes paint outside
their rect on purpose (the shadow) and are not covered by ^1004.

**Trusted code.** `host/Sources/CairnRender/Renderer.swift` (paint batches),
`Painters.swift`, `Shapes.swift`, `host/Tests/CairnFuzzTrusted/YapTape.swift`, Metal and Core
Graphics.

**Evidence.**
- **Fuzzed** (^1004 `render.paint.bounds`): random frames with paint draws between rects, text
  and clips, at 1x to 3x and random times, rendered offscreen with and without their paint
  draws; every pixel outside the paint boxes is the same. Painters: Yap's tape with random and
  malformed data, one whose triangle covers 100 times the viewport, one whose triangles land
  anywhere, and an unregistered name. Removing the scissor from the paint batch makes it fail
  in the first 50 cases.

## Images (M3)

`loadImage` (docs/effects.md, "Images") reads a file or a URL, decodes it with ImageIO and keeps
the pixels in the host (`ImageStore`); Lean gets only the pixel size or the fault. An `image`
draw (docs/frame.md) names the source, the box and the destination rect Lean computed; the
renderer uploads the pixels to a texture with mipmaps once per decode and draws it scaled to the
destination, scissored to the box within the clip.

**What is assumed.**
- ^1006 `hostLoadImage`: `loadImage` answers once, with the image's pixel size after its EXIF
  orientation, or with the fault as docs/effects.md lists it; the image is kept for draws naming
  the same source; without `reload` a kept source is answered without reading, with `reload` it
  is read again and a failure drops it.
- ^1007 `hostImageBounds`: an image draw changes no pixel outside its box (snapped as rects are)
  within the clip in force, whatever its destination; a draw naming a source the host holds no
  image for changes nothing.
- ^1008 `hostImagePixels`: the oriented image is scaled to the destination: each quadrant lands
  in the same quadrant of the destination, in its colour (within 8 per channel, 40 for JPEG and
  HEIC).

**Also assumed, not fuzzed.** Pixels are kept at most 4096 on their long side (larger images are
scaled down on decode; the reply still gives the full size). Kept images are never evicted
unless the app runs an `imageCache` subscription (^1011, below): without one, an app that loads
many large sources holds them all. Animated GIFs show their first frame. A
relative path is resolved against the working directory, which a host app sets to its resource
bundle. Redirects, caching and cookies are Foundation's (an ephemeral session, as for `http`).

**Trusted code.** `host/Sources/CairnHost/ImageEffects.swift`,
`host/Sources/CairnRender/Images.swift`, `Renderer.swift` (image batches, `image_fragment` in
`Shaders.swift`), ImageIO, Core Graphics and Metal.

**Evidence.**
- **Fuzzed** (^1006 `effects.load-image`): files and stubbed URLs holding PNG, JPEG, TIFF, GIF,
  BMP and HEIC images of random sizes (4–220 pixels a side, some 4097–6000 on one) with all eight EXIF
  orientations answer their oriented size once and are kept; missing, unreadable, directory,
  empty, NUL, garbage and truncated sources and HTTP 304/401/403/404/410/418/500 and failed connections
  answer their faults; a second load without `reload` reads nothing, with it the new bytes are
  read, and a failed reload drops the source; many loads at once each answer with their own
  size.
- **Fuzzed** (^1007 `render.image.bounds`): random frames with image draws between rects and
  clips, boxes and destinations anywhere in or across the frame, at 1x to 3x, rendered
  offscreen with and without the image draws; every pixel outside the boxes is the same. A
  draw naming an unknown source changes nothing.
- **Fuzzed** (^1008 `render.image.pixels`): a four-quadrant image of random format, size and
  orientation drawn into a box, minified and magnified, at 1x to 3x; the centre of each quadrant
  of the destination has that quadrant's colour.
- **Tested** (in cairn_examples' `make check`, against the released Cairn; not in Cairn's):
  Gallery's self test (`swift run CairnGallery --selftest`) loads its five local sources through the
  real handler and renders them.

### Cancelling a request (`assume`, ^1009)

`cancelRequest id` (docs/effects.md, "Requests in flight") asks the host to stop a request it
was sent. Lean's runtime proves the cap, the queue and that the cancelled request's answer
reaches no app; what it relies on from the host is that the answer still comes.

**What is assumed.**
- ^1009 `hostCancelRequest`: a cancelled request is still answered exactly once; if its work is
  running it is stopped (an `http` or a `loadImage` from a URL has its `URLSession` task
  cancelled) and answered promptly, `failed`; a request cancelled before its handler starts is
  answered `failed other "cancelled"` without running; a cancelled `loadImage` with `reload`
  leaves the image the store held for its source; a cancel of an id already answered, or never
  sent, changes nothing.

**Also assumed, not fuzzed.** Kinds without a stop (file reads and writes, `typeText`,
`upload`'s part assembly) run to the end and answer as usual; only their answer is ignored.
`upload` cancels its `URLSession` task like `http`.

**Trusted code.** `host/Sources/CairnHost/World.swift` (`Cancellation`, `World.run`,
`World.perform`, `HTTP.run`), `host/Sources/CairnHost/ImageEffects.swift`, `URLSession`.

**Evidence.**
- **Fuzzed** (^1009 `effects.cancel`): 1–12 `http` and `loadImage` requests a case, served by a
  `URLProtocol` stub that holds some open until they are stopped; cancels in the same frame,
  while running and after the answer, and cancels of ids never sent. Every request answers
  exactly once; every held load that started was stopped and answered `failed`; cancelled
  reloads keep the stored image; stray cancels are answered by nothing.
- **Tested** (in cairn_examples' `make check`, against the released Cairn; not in Cairn's):
  Gallery's self test asks for 24 thumbnails from a slow stub server, checks it never serves more
  than six at once, cancels mid-load and checks the stopped requests ended at the server and the
  queued ones never reached it.

## Yap's devices: recording, keys, typing, uploads (workstream T)

The microphone, the keyboard, other apps and the network, for Yap (docs/effects.md,
"Recording, keys, typing, uploads"). Trusted code: `host/Sources/CairnHost/AudioEffects.swift`
(LevelMeter, WAV, Clips, Microphone.live), `InputEffects.swift` (KeyWatch, KeySource.live,
Typing, Typist.live), `UploadEffects.swift` (SecretSource, Upload), the `record` and
`globalKey` parts of `World.swift`, and under them AVAudioEngine, `NSEvent` monitors,
`CGEvent` posting, `NSRunningApplication` and TCC. The fuzz suites (`audio`, `input`,
`upload`) replace every device with a fake (`Devices`): `make check` records no audio,
installs no monitor, types into no app and reads no real secret.

- **Fuzzed** (^966 `subs.record`): with a fake microphone on another thread, the clip is
  exactly the samples delivered; the `audio` events cover a prefix of them in order, each with
  its batch's frames and peak, and their windows are the levels of that prefix computed
  directly, however the buffers were split; nothing is sent after the stop or reset returns; a
  failing microphone is one `failed` event and an empty clip. **Also assumed:** that
  `AVAudioEngine`'s tap and `AVAudioConverter` deliver the microphone's audio at 16 kHz in
  order without gaps (Yap's capture path, used as is), and that after `removeTap` and `stop`
  return no tap block is still running (if one were, its samples would be dropped by the
  stopped flag, but could still be appended to the clip after it finished). Not checked live:
  this session must not record.
- **Fuzzed** (^1005 `subs.record-start`): with a fake microphone whose `start` blocks for a
  while (sometimes delivering samples meanwhile) or fails, the subscription's first event is one
  `started`, sent only after `start` returned and before every `audio` event, with a monotonic
  time read no earlier than the return; a failing microphone sends `failed` and never `started`.
  **Also assumed:** that `AVAudioEngine.start()` returning means the input is running (Yap's
  `begin` relies on the same: it shows "Listening…" and the overlay once `capture.start`
  returns), and that the `started` time and key events' times come from the same monotonic
  clock. Lean waits for `started` before showing anything (^349) and replays the key events
  that arrived meanwhile from that time (^351).
- **Fuzzed** (^967 `effects.clip-wav`): every range is the header and exactly those samples;
  bad ranges, unknown and forgotten clips fail; a clip finishing while asked for is waited for;
  at most 8 clips are kept. **Also assumed:** a clip still recording after the one-second wait
  is cut at what it has; Lean asks for a range it has seen the windows of, or for the end after
  stopping.
- **Fuzzed** (^968 `subs.global-key`): `KeyWatch` equals a state-table model of PushToTalk on
  random streams; through the world the events are the model's, in order; without
  Accessibility nothing is installed. **Also assumed:** that the global and local monitors
  together see every key event of the session once (global: other apps; local: this app),
  which is how Yap works; and that the monitors deliver in order on the main thread. Not
  checked live: this session must not watch the keyboard.
- **Fuzzed** (^969 `effects.type-text`): the runs are the text's UTF-16, whole characters, at
  most 20 units unless one character is longer; with a fake typist, nothing is posted unless
  trusted, the app exists and it came forward, and then exactly the runs and Return as asked.
  **Also assumed:** that posting at the HID tap reaches the app in front, as Yap relies on, and
  that the app is still in front while the burst is posted (the person could switch apps in
  those milliseconds; Yap has the same window). Not checked live: nothing types into another
  app from a test.
- **Fuzzed** (^970 `effects.upload`): the server receives the parts in order with each WAV
  spliced in and the secret header; failures send nothing. **Also assumed:** what ^974 assumes
  of `HTTP.run`.
- **Fuzzed** (^975 `effects.secret`, which reissues the retired ^971 for environment secrets
  now that a secret can also be a Keychain item, below): the dotenv reader against files of known meaning;
  environment first; the value in no reply, message or debug description. **Also assumed:**
  the environment and the file are the person's (anyone who can write them can choose the key);
  the file should be mode 600 in a 700 directory, as Yap's is; the host doesn't check.
- **Permissions.** `typeText` and `globalKey` need Accessibility; `record` needs the
  microphone, an `NSMicrophoneUsageDescription` in the bundle's Info.plist and the
  `com.apple.security.device.audio-input` entitlement under the hardened runtime. Each fails
  with an ordinary `failed denied` without its permission, and none of them prompts.

## Secrets in the Keychain (M4)

A request's secret header can come from a Keychain item, a 2xx JSON reply's top-level string
fields can be captured into items and blanked before Lean sees the body, and `forgetSecret`
deletes an item (docs/effects.md, "Secrets in the Keychain"; #205). Trusted code:
`host/Sources/CairnHost/SecretEffects.swift` (`SecretStore`, `KeychainStore`, `MemoryStore`,
`JSONCapture`, `SecretHTTP`, `ForgetSecret`), `SecretSource.resolve` and `header` in
`UploadEffects.swift`, `HTTP.run`'s redirect refusal in `World.swift`, and under them
Security.framework's `SecItem*` calls and `JSONSerialization`. The fuzz suite is `secrets`
(`host/Tests/CairnFuzzTrusted/SecretsSuite.swift`).

### The Keychain keeps what it was given for this app (`assume`, ^972)

**Statement.** As the claim says: reading an account gives exactly the value last written to it
until it is deleted, one account's write changes no other, `forgetSecret` deletes and answers
`done` (also when there was nothing), and a request whose item is missing answers `notFound`
without sending.

**Scope.** One generic password item per account, service = the app's bundle identifier
(`cairn.<process name>` outside a bundle), in the person's login keychain; never synchronized
to iCloud (`kSecAttrSynchronizable` false); no access group. Values are UTF-8 text. One account
per item name Lean chooses; several accounts, several apps sharing items and other platforms
are out of scope (docs/goals/m4.md, "Not in M4").

**Which keychain, and why.** The file-based login keychain, not the data-protection keychain
(`kSecUseDataProtectionKeychain` false). The data-protection keychain needs the app signed with
a team identifier and a keychain access group (`keychain-access-groups` /
`application-identifier` entitlements, which on macOS come with a provisioning profile);
development builds, `swift run`, the fuzzer and ad-hoc signed bundles have none, and would get
`errSecMissingEntitlement`. The file-based keychain works for all of them. Its cost: an item's
access list trusts the app that created it by its code signature, so a rebuilt app with a
different signature (an ad-hoc development build) may make macOS ask the person to allow access
to the item it made before; a Developer ID signed app (`cairn bundle --sign`) keeps its
designated requirement across builds and is not asked. Moving to the data-protection keychain
later is a change of `KeychainStore.query` and this entry, not of Lean.

**One call at a time.** The host makes every Security call, from every store and effect (a
request's secret header, a capture's reads and writes, `forgetSecret`), on one serial queue for
the whole process (`KeychainStore.serialized`), so no two of them overlap. "Last written" is
then the last write in that queue's order. Two requests in flight at once still reach the
Keychain in whichever order the host runs them, as before: the queue adds no order between
effects, only takes away overlap. Security itself is assumed correct only for calls that don't
overlap: concurrent `SecItemDelete` and `SecItemCopyMatching` on one service deadlock in the
file-based keychain (#237). Calls from another process, or from code in the app that calls
Security without `KeychainStore.serialized`, are outside the claim.

**Also assumed.** That the login keychain is unlocked while the person uses the app (macOS
unlocks it at login); a locked or denied keychain is `failed denied` (or `other`, with
Security's status) rather than a value. That nothing else writes the app's items. That a value
written is not readable by other apps without the person's consent (the keychain's access list:
Apple's, not checked).

**Findings.** The live check found the file-based keychain answering success to `SecItemUpdate`
with empty data while keeping the old value; `KeychainStore.write` now deletes and re-adds the
item for an empty value. Sky's selftest found a concurrent `SecItemDelete` (`forgetSecret`) and
`SecItemCopyMatching` on one service deadlocked inside Security (#237); the host now serializes
every call. The full run (`make fuzz-trusted`, 20,000 cases) found `KeychainStore.read` dropping
a value's leading byte order mark (`String(data:encoding:)` strips one); it now decodes with
`String(validating:as:)`.

**Evidence.**
- **Fuzzed** (`effects.secret.keychain`): random writes (generated text: ASCII, edge Unicode,
  quotes, backslashes, empty values, values of 500–3000 characters), reads, overwrites,
  deletes and `forgetSecret` over three accounts, against a dictionary model, on the in-memory
  store and on the **live login keychain** under a throwaway service
  (`dev.cairn.fuzz-trusted.keychain.<pid>.<random>`), every account checked at the end and
  each case deleting the items it made and checking they're gone; the live items' attributes
  (service, account, not synchronizable, no access group). Through the world with a stub
  server: a Keychain secret's value is sent as `scheme ++ value`, a missing item is `notFound`
  and reaches no server, `forgetSecret` answers `done` twice; the value is in no reply, event
  bytes, event dump or debug description. **Concurrency** (`keychain.concurrent`, once per
  worker): a child process makes 6 × 40 calls at once on one throwaway service (reads, writes,
  deletes, `forgetSecret`, `http` reading a Keychain secret for its header, `http` capturing into
  an item) and must finish in 30 s; on a hang the parent kills it and fails the check, and either
  way deletes its items (a deadlocked process can't, and only the same executable may). Without
  the queue it hangs every time; with it, about 3 s. The live part is skipped when `CI` is set
  (a CI runner has no unlocked login keychain, and nothing may prompt there) or with
  `CAIRN_FUZZ_KEYCHAIN=0`; the counter `liveSkipped:<reason>` says so, as ^968's "not checked
  live" does. The fuzzer never reads, prints or deletes an item outside its own service.

### Captured reply fields go to the Keychain and never to Lean (`assume`, ^973)

**Statement.** As the claim says: on a 2xx JSON object reply, each listed top-level string
field is stored exactly and blanked to `""` in the body Lean gets, every other byte as sent; a
missing, repeated or non-string field or a body that isn't an object is `invalid` and writes
nothing; a failed write restores the items; other replies pass through.

**What is not assumed.** That Lean holds no token is by construction: no Lean value ever
receives one (the reply's body has `""` where it was), and `cairn_atproto` and Sky prove what
they do with the names (M4, #207, #209).

**Also assumed.** The JSON is read twice, by `JSONSerialization` (is it a valid object?) and by
`JSONCapture.scan` (where is each top-level member?); the scan trusts the first's validation
and both must agree on what a top-level member is. A captured value that also appears
elsewhere in the body (another field, a nested object) is not looked for and would reach Lean;
capture is for values a server sends once. Bodies in UTF-16 or UTF-32 that `JSONSerialization`
accepts are refused by the scan (`invalid`).

**Evidence.**
- **Fuzzed** (`effects.http.capture`): random JSON objects (shuffled members, random
  whitespace, keys and values with `\u` escapes and surrogate pairs, nested objects that reuse
  the captured names, decoy strings, numbers past 64 bits) whose captured fields hold planted
  markers, served by a `URLProtocol` stub with 2xx statuses; variants with a field missing,
  repeated, or not a string, bodies that aren't objects (arrays, truncated, trailing garbage,
  a bare string), statuses outside 2xx, no captures, and a store that fails one write. A valid
  capture stores each marker exactly and the body Lean gets equals the generated body with
  just those values written `""`; every other variant fails `invalid` (or `other` for the
  failed write) or passes through, with the store as it was. No marker (whole, or its
  unescaped core) is in any reply, failure message, the events' bytes (what Lean decodes), the
  event dump or the request's debug description. Mutations checked by hand: not blanking, or
  storing one capture too few, fail the check.

## Accessibility of scroll areas and secure fields (M4)

The frame gives every node its visible rect, so a control scrolled out of its box has an empty
one, and a secure field's node and text input hold bullets (Lean's, `FieldView.secure`). What
assistive apps are shown of either is the host's mirror (`AXMirror`, docs/host.md
"Accessibility"). The fuzz suite is `ax` (`host/Tests/CairnFuzzTrusted/AXSuite.swift`).

### Assistive apps reach only what a scroll area shows (`assume`, ^1021)

**Statement.** The tree an assistive app walks from the view (`accessibilityChildren`) holds
exactly the frame's nodes that are not scrolled out, each once, under its frame parent and in
frame order, with that parent as its `accessibilityParent`. A node is scrolled out when it, or
a node above it, has an empty rect and a scroll area somewhere above that. A scroll area is an
`AXScrollArea`. `accessibilityHitTest` answers the view or an element in the tree whose frame
holds the point. The focused element is the focused node's even when it is scrolled out, as
typing still goes to it; its parent is then the view, which doesn't list it.

**Also assumed.** Frames list a parent before its children (Lean's `Frame.ofLaid` does; a
later parent is ignored). A scrolled-out element is kept, not destroyed, so VoiceOver's cursor
on it survives scrolling back; that VoiceOver handles a focused element outside the tree is
Apple's.

**Trusted code.** `host/Sources/CairnHost/AXMirror.swift` (`update`, `hidden`, `hitTest`),
`host/Sources/CairnHost/HostView.swift` (`accessibilityChildren`,
`accessibilityFocusedUIElement`, `accessibilityHitTest`).

**Evidence.**
- **Fuzzed** (^1021 `ax.scroll`): trees of 1–40 nodes of every role, scroll areas nested
  anywhere, applied as 1–4 frames (the same tree with new rects: empty with a width, a height or
  both 0, or visible; one focused node or none) to a real `HostView` in a window never shown,
  through an `Engine` as the app's frames are. After each frame the suite walks the tree through
  AppKit's public accessibility API and compares it with an oracle that walks each node's
  parents itself; 8 hit tests at random points of the view; the focused element. Mutations
  checked by hand: hiding only nodes with both sides 0 fails it.
- **Tested**: `AXKeyTests` (`AXMirror.hidden`); the fixture's self test scrolls its rows and
  presses those it shows.

### A secure field shows assistive apps nothing typed (`assume`, ^1022)

**Statement.** A node marked `secure` is an `AXTextField` with subrole `AXSecureTextField`:
no value, no characters, no selected text, an empty selected and visible range, and an empty
string for any range, whatever its node's value or the text input holds, so not even the bullets
reach an assistive app. No other element shows its text. The debug socket's description of an
`http` request (`DebugJSON.describe`) shows its method, its URL unless it is `redact`, the
secret's header name and the number of captures, and never a header value, body or secret.

**Also assumed.** That the system's own secure-field handling (VoiceOver announcing "secure text
field", not echoing keys) follows the subrole, as it does for `NSSecureTextField`. What the frame
and the dumps hold is Lean's and proved (docs/text.md, "Secure fields").

**Trusted code.** `host/Sources/CairnHost/AXMirror.swift` (`AXNodeElement`: `accessibilitySubrole`,
`accessibilityValue`, `text`, `accessibilitySelectedTextRange`),
`host/Sources/CairnHost/DebugJSON.swift` (`request`).

**Evidence.**
- **Fuzzed** (^1022 `ax.secure`): the same trees, half their text fields secure, with planted
  text in each secure node's value and in the focused secure field's text input (where Lean
  would put bullets); every attribute of every element in the tree and of the focused element is
  searched for it, and each secure element's role, subrole, value, count and ranges checked. A
  plain field's value must be its text, so a check that read nothing would fail. Four `http`
  requests a case, with planted header values and bodies, redacted or not (a planted URL when
  redacted), with or without a Keychain secret and captures, through `DebugJSON.describe`.
  Mutations checked by hand: giving a secure field its node's value fails it.
- **Tested**: the fixture's self test (`^9`) checks the Passcode field's AX element is an
  `AXSecureTextField` with no value.

## Surfaces: menus and overlay panels (workstream S)

See [surfaces.md](surfaces.md). Presence, enablement and checkmarks are proved on the menu
*description* (`Frame.controls_ofMenu`, `Frame.enabled_ofMenu`, Tray's theorems in cairn_examples),
and a stale or unknown selection is proved to change nothing (`Runtime.menu_select_stale`). What
AppKit does with the description is assumed. The host code is
`host/Sources/CairnHost/Surfaces.swift` (`SurfaceHost`, `MenuHost`, `StatusHost`, `PanelHost`).

Every check below runs `SurfaceHost` in `.detached` mode: the menus and panels are real AppKit
objects, but no status item is added to the menu bar and no panel is ordered onto the screen.
The fuzz suite is `SurfacesSuite` (`host/Tests/CairnFuzzTrusted/SurfacesSuite.swift`); random
menu records (nested submenus, some disabled, separators, status lines, checkmarks, shortcuts
over the whole `Key` table) and random panel frames, several updates per case so items are
updated in place and rebuilt.

### The native menu shows the frame's records (`assume`, ^940)

**Statement.** As the claim says: after each frame the `NSMenu` tree is the records, in order,
whether `MenuHost.update` changed items in place or rebuilt a menu.

**Finding.** AppKit reports an item inside a *disabled submenu* as `isEnabled == false`
whatever its own flag. Lean's menus never disable a submenu (`MenuItem.submenu` has no
`enabled`), so this never shows in an app; the oracle and the conformance model both use the
effective flag (the item's and every enclosing submenu's).

**Evidence.**
- **Fuzzed** (`menu.render`): after every update the tree is compared with an independent
  reading of the records (titles, kind, effective enablement, state, identifier, key equivalent
  and modifier mask through the suite's own key table, submenu nesting). Counters: records,
  rebuilds.
- Conformance (`cairn conformance --app Tray` in cairn_examples, by hand; it was never in
  `make check`): the socket's `menu` against the model's menu after every step.
- `CairnTray --selftest` (in cairn_examples' `make check`, against the released Cairn; not in
  Cairn's): the tree, ⌘O on Show Overlay, the checkmark, a submenu rebuilt when its shape changes
  and the same `NSMenuItem` updated in place when it doesn't.

### Choosing an item reports its ref (`assume`, ^941)

**Statement.** As the claim says. The host does *not* filter disabled items: a choice that
reaches `choose(_:)` is sent, and Lean decides. That is what makes a choice that raced a menu
update harmless (`menu_select_stale`).

**Evidence.**
- **Fuzzed** (`menu.select`): in a third of the updates, one random enabled item is chosen
  through `NSMenu.performActionForItem(at:)` (AppKit's dispatch, about 60 ms per call, which is
  why it is sampled) and exactly one `menuSelect(place, ref)` must arrive; for a disabled item,
  `performActionForItem` must send nothing (`disabledNotSent`).
- Conformance (Tray, in cairn_examples, by hand): every enabled item is chosen through
  `performActionForItem`, and greyed-out items are chosen directly, with the model expecting no
  change.

### Opening and closing are reported once each (`assume`, ^942)

**Statement.** As the claim says. The host takes `menuWillOpen`/`menuDidClose` on the root menu
only.

**Evidence.** **Fuzzed** (`menu.open-close`): the delegate methods on the root and on every
submenu; one event per root call, none for submenus. Not covered: that the window server calls
the delegate when a person clicks the status item (manual checklist,
[surfaces-checklist.md](surfaces-checklist.md)).

### The panel never takes focus or clicks (`assume`, ^943)

**Statement.** As the claim says. What is checked is the panel's *properties*
(`[.borderless, .nonactivatingPanel]`, `canBecomeKey`/`canBecomeMain` false,
`ignoresMouseEvents`, `.statusBar` level, `[.canJoinAllSpaces, .fullScreenAuxiliary,
.stationary, .ignoresCycle]`, `hidesOnDeactivate` false, not opaque). That the window server
honours them (no focus change, clicks pass through, shown over full-screen apps and on every
Space) is window-server behaviour with no API to assert from inside the app: manual checklist.

**Evidence.** **Fuzzed** (`panel.inert`): the properties after every random frame, shown or hidden.
`CairnTray --selftest` (in cairn_examples' `make check`, against the released Cairn; not in Cairn's)
and the socket's `surfaces` read the same properties.

### The panel is where its anchor says (`assume`, ^944)

**Statement.** As the claim says. The hide fade (0.18 s, then `orderOut`) is look only
(decision 6).

**Evidence.** **Fuzzed** (`panel.place`): `PanelHost.placement` against the suite's own
arithmetic on random visible frames, sizes and offsets; the screen is chosen at show and kept
through size changes until hidden.

### Also trusted, not fuzzed

- **Status item image.** The SF Symbol name exists on the running macOS; a missing one is logged
  once and the button shows only its title.
- **Accessory policy.** `.accessory` (chosen when the first frame has no window) gives no Dock
  icon and no app-switcher entry. Manual checklist.
- **Run-loop modes.** Frames are applied, and the menu updated, while the menu is tracking.
  Manual checklist (the detached checks don't track).
- **Under the debug socket** the `quit` effect is recorded and not run, as a beep is; the
  driver ends the app with the socket's `quit`.

## The window's minimum size (M3)

An app asks for its window's smallest content size in every state (`App.minSize`, carried by
the frame's window record, docs/frame.md). Lean proves what the view does at every size from
that one up (Gallery's `cairn_examples^511` with `Grid.minBox`: every tile at least 180 points
wide); that the window never gets smaller is the host's.

### The window is never smaller than the app's minimum size (`assume`, ^1010)

**What is assumed.**
- ^1010 `hostWindowMinSize`: the host (`WindowSizer`, the window's delegate) sets
  `contentMinSize` to the window record's minimum (a negative side as 0), clamps every live
  resize AppKit proposes (`windowWillResize(_:to:)`) to it, and grows a window already smaller
  (the first frame's, after the saved frame is restored, or a later frame's larger minimum) to
  it, keeping its top-left corner; a minimum the window meets leaves its frame alone. So every
  `resize` Lean hears after a frame with a minimum is at least that minimum.

**Also assumed, not fuzzed.** That AppKit proposes a person's drag through the delegate and
honours `contentMinSize` while tracking it (window-server behaviour, watched in the demo video).
Programmatic `setContentSize`/`setFrame` calls bypass both; the host makes none but `apply`'s.
A minimum larger than the screen gives a window larger than the screen.

**Trusted code.** `host/Sources/CairnHost/WindowSize.swift` (`WindowSizer`),
`host/Sources/CairnHost/CairnApp.swift` (applying each frame's minimum), AppKit.

**Evidence.**
- **Fuzzed** (^1010 `window.min-size`): a resizable window (never shown) with the sizer as its
  delegate; 1–12 steps a case of new minimums (negative, 0, 1–2400 a side, many larger than the
  window) and drags to 1–2600 × 1–1600, proposed to the delegate and set as AppKit does. After
  every step `contentMinSize` is the minimum, the content and the view's whole-point size are at
  least it, a met minimum moved nothing, a grown window kept its top-left corner, and a drag at
  or above the minimum was left as proposed.
- **Tested** (in cairn_examples' `make check`, against the released Cairn; not in Cairn's):
  Gallery's self test checks the window record asks for 1020 × 536 and that the pictures are 180 ×
  135 there.

## The image cache's budget (M3)

An app that subscribes to `Sub.imageCache bytes` has the host keep its decoded images within
that budget (docs/effects.md, "A budget on the host's images"). Lean proves, in a model of the
table, the store and the messages between them (`Images.Cache.ready_held_quiet`), that an image
the app takes for ready has its pixels with the host once every message is heard, given the
host's two moves below; the app's side (`Images.evicted`) is proved, and Gallery's
`cairn_examples^513` keeps its dropped thumbnails not loaded until loaded again.

### The image cache reports every image it drops (`assume`, ^1011)

**What is assumed.**
- ^1011 `hostImageCache`: while an `imageCache` subscription runs, the store keeps within the
  smallest running budget by dropping the entries used least recently (put, or drawn by a
  published frame), never one the latest published frame draws nor the one just put, and only
  while over budget; it sends `evicted source` to every running `imageCache` for every entry it
  drops, a failed reload's removal included, after the entry is gone. `loadImage` answers ready
  only after the store held the pixels for that load (it put them, or found them there).

**Also assumed, not fuzzed.** That the engine delivers the host's events in the order they are
sent (one queue). The renderer's textures of dropped images are released on its next frame.

**Trusted code.** `host/Sources/CairnRender/Images.swift` (`ImageStore`: `setBudget`,
`setDrawn`, `put`, `remove`), `host/Sources/CairnHost/World.swift` (`imageCache`,
`World.drawing`), `host/Sources/CairnHost/Engine.swift` (`publish` calls `drawing` before a frame
can be drawn), `host/Sources/CairnHost/ImageEffects.swift`.

**Evidence.**
- **Fuzzed** (^1011 `images.cache`), two ways. The store alone: 5–60 random puts (4–32 pixels a
  side), removals, drawn sets and budget changes against a least-recently-used model; after
  each step the entries, the bytes held and the drops (in order) are the model's, nothing drawn
  or just put was dropped, the store is over budget only when nothing more can go, and each drop
  was reported once, after the entry was gone. Through the `World`: 3–10 files, a random budget,
  4–30 steps of concurrent `loadImage` requests (with and without `reload`), frames drawing
  what the app takes for ready, files deleted and restored; the events, fed in order to a copy of
  Lean's `Images` table, leave every image it takes for ready in the store once every request is
  answered.
- **Tested** (in cairn_examples' `make check`, against the released Cairn; not in Cairn's):
  Gallery's self test loads 24 thumbnails under its 8 MiB budget, checks some are evicted and every
  drawn image is in the store, pages, and checks again.

## Secure fields (M4)

A secure field (`FieldView.secure`, docs/text.md "Secure fields") shows bullets, keeps no undo
history and refuses copy and cut; Lean proves that its view, and so every frame and dump built
from it, depends only on its length and selection (`SecureField.view_agree`,
`Dump.secure_canvas`). Keeping other processes from reading the keystrokes is the host's.

### Secure event input is on exactly while a secure field has focus (`assume`, ^1020)

**What is assumed.**
- ^1020 `hostSecureInput`: the host turns the system's secure event input on
  (`EnableSecureEventInput`) when the applied frame's text input is a secure field, its window
  is key and the view is live, and off (`DisableSecureEventInput`) when any of those stops, when
  the view is shut down and when it is released. It calls them in pairs, never twice the same way
  in a row: the system counts enables, so an extra one would leave secure input on for the
  process. While it is on, other processes' event taps and global monitors see no keystrokes.

**Also assumed, not fuzzed.** That AppKit posts `didBecomeKey`/`didResignKey` for every change of
the window's key state (the host re-decides on each, on every applied frame, when the view
moves to a window and on shut down). That secure event input does what Apple documents (it is a
system service; this process can't watch another's event tap).

**Trusted code.** `host/Sources/CairnHost/SecureInput.swift` (`SecureInputGate`),
`host/Sources/CairnHost/HostView.swift` (`updateSecureInput` and its call sites, `deinit`),
Carbon (`EnableSecureEventInput`, `DisableSecureEventInput`, `IsSecureEventInputEnabled`).

**Evidence.**
- **Fuzzed** (^1020 `text.secure-input`): 1–30 steps a case of the applied frame's text input
  (none, plain, secure), the window's key state and the view's life, ending closed, given to the
  gate as `HostView` gives them. After every step the gate is on exactly when it should be and its
  calls alternate on, off, starting with on; one case in eight makes the system's calls and reads
  `IsSecureEventInputEnabled` back: on while the gate is on, as before the case once it is off.
- **Tested**: the fixture's self test types into its Passcode field (`^9`) and checks the frame
  carries bullets and `secure`, the AX element is an `AXSecureTextField` with no value, and Enter
  clears it.

## Scrolling (M4)

The runtime owns every scroll box's offset (docs/runtime.md, "Scrolling"); Lean proves each
offset stays within `[0, max 0 (content − viewport)]` after every step (`step_clamped`) and that
a scroll changes no app state (`step_scroll`). Which way and how far a gesture moves the box
is the host's.

### The host reports scrolls where they happen, toward the end positive (`assume`, ^1012)

**What is assumed.**
- ^1012 `hostScroll`: for each `scrollWheel` AppKit gives the view, the host sends `scroll p dx
  dy` at the logical point under the pointer (flipped, rounded down), with AppKit's
  `scrollingDeltaX`/`scrollingDeltaY` negated (positive toward the end: right, down) and times
  16 for line deltas (`hasPreciseScrollingDeltas` false). Fractions carry to the next event and
  are dropped when a gesture begins, so a gesture's total in Lean is within a point of AppKit's.
  The engine may coalesce consecutive scrolls into one with the summed deltas.

**Also assumed, not fuzzed.** That AppKit's deltas already include the person's natural-scrolling
setting, so "negated" means "the way the content should move"; that momentum events arrive as
more `scrollWheel`s (the host treats them like any other); and that AppKit delivers
`scrollWheel` to the view under the pointer.

**Trusted code.** `host/Sources/CairnHost/HostView.swift` (`scrollWheel`, `point`),
`host/Sources/CairnHost/Scroll.swift` (`ScrollAccumulator`), `host/Sources/CairnHost/Engine.swift`
(queue, coalescing).

**Evidence.**
- **Fuzzed** (^1012 `pointer.scroll`, `ScrollSuite`): one gesture a case, in a window of random
  size, at a random point with fractional coordinates and edges: 1–30 events of trackpad pixel
  deltas (phase `began`, then `changed`) or mouse-wheel line deltas in 1/64ths, along either
  axis or both, made with `CGEvent(scrollWheelEvent2Source:)` and read back as `NSEvent`s so
  the deltas, precision and phase are AppKit's. What the app's core receives is only `scroll`
  events at the oracle point, summing to within one point of the negated (and scaled) deltas,
  with the sign of a total of a point or more. Each case starts from no carried fraction (a
  trackpad `began` with no movement): a wheel has no phases, so the host rightly carries a
  fraction from one wheel gesture into the next, which the full run once saw as a gesture off
  by 1.25 points.
- **Tested**: the fixture's self test scrolls its rows 1,616 points through the engine and
  checks rows 51 to 56 show and are pressed where they show.

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
- **Yap runs silent under the socket.** `CairnYap --debug-socket` gets a world whose every
  request handler waits forever and whose devices are inert (`silentWorld()` in
  yap-cairn's `host/Sources/CairnYap/main.swift`), because the model the driver compares against hears no
  replies, ticks or subscription events. So conformance covers Yap's menu and its moves from
  launch, not dictation; the host's devices and effects are covered by the trusted fuzz suites
  and the self test's fakes (yap-cairn's docs/yap.md). `World.watchPath` (identity outside the self test)
  is how the self test moves `~/` watches into a scratch home; the real app never sets it.
- **The comparison code.** Frames are compared through two JSON printers, `Conformance.jframe`
  in Lean and `DebugJSON.frame` in Swift. The expected AX tree is derived in the driver from the
  host's table (`expectedAx` in driver.ts). That table is written by hand, like the mirror's.

# Frame and event format, v1

Two byte buffers cross the boundary between Lean and the Swift host, and nothing else does:

- **Frame** (Lean → host): what to paint, the accessibility tree, the focused field's
  text-input state, the cursor and effects. Lean builds a `Cairn.Frame` with `Frame.ofLaid`
  and encodes it with `encodeFrame`; the host decodes it with `Frame(bytes:)`.
- **Events** (host → Lean): a batch of input events. The host encodes them with
  `encodeEvents`; Lean decodes them with `decodeEvents`.

| Piece | Where |
|---|---|
| Model (both sides) | `lean/Cairn/Frame.lean`, `lean/Cairn/Input.lean`, `host/Sources/CairnFrame/Model.swift` |
| Byte layer: integers, strings, sections | `lean/Cairn/Frame/Bytes.lean` |
| Frame encoder, decoder, round trip | `lean/Cairn/Frame/Encode.lean` |
| Event encoder, decoder, round trip | `lean/Cairn/Frame/Events.lean` |
| `Frame.ofLaid` and its theorems | `lean/Cairn/Frame/Build.lean` |
| The runtime's `Boundary` | `lean/Cairn/Frame/Boundary.lean` |
| Canonical text dump | `lean/Cairn/Frame/Dump.lean`, `host/Tests/CairnFrameTests/Dump.swift` |
| Swift frame decoder | `host/Sources/CairnFrame/Decode.swift` |
| Swift event encoder | `host/Sources/CairnFrame/Encode.swift` |
| Corpus generator, verifier, bench | `lean/FrameCorpus.lean` (`lake exe framecorpus`) |

This document is the specification. It is meant to be enough to write a third implementation;
where it and the Lean specification (`Wire.Enc.*`) disagree, Lean is right and this is a bug.

## Conventions

- **Integers are little-endian.** `u8`, `u16`, `u32` are unsigned; `i32` is two's complement.
- **Booleans** are one byte, `0` or `1`. Any other value is an error.
- **Reserved bytes** (shown as `0`) are written as zero and ignored when read. They keep fixed
  fields 4-byte aligned relative to the record's start.
- **Strings** are a `u32` byte length followed by that many bytes of UTF-8. No terminator, no
  padding after the bytes. Invalid UTF-8 (overlong forms, surrogates, scalars above U+10FFFF,
  truncated sequences) is an error.
- **Sections** are a `u32` byte length followed by the body. The body must decode to exactly
  its length: leftover bytes inside a section are an error.
- **Lists** are a `u32` count, then a section holding `count` records back to back.
- **Records** begin with a 4-byte head: the tag, up to two small fields, then zeros. Each record
  is a fixed part followed by its strings, so a reader learns its size by reading the fixed part
  and the string lengths.
- **Trailing bytes** after the last field of a buffer are an error.
- **Codes** are `u8`. An unknown code is an error.
- **Coordinates** are integer logical points, x right and y down from the window's top-left.
  Rects are `i32 x, i32 y, i32 w, i32 h` (16 bytes); points are `i32 x, i32 y` (8 bytes).
- **Colors** are 4 bytes, `r g b a`, sRGB, not premultiplied.
- **Control refs** are `u32 claim, u32 key` (8 bytes).
- **Ranges** are two `u32` (8 bytes): scalar indices `[start, end)` into a string, counted in
  Unicode scalars (not UTF-16 units, not bytes).

### What fits

Lean's model uses unbounded `Int` and `Nat`. The round trip is exact for every value that fits:
`i32` fields in `[-2^31, 2^31)`, `u32` fields in `[0, 2^32)`, strings under 4 GiB of UTF-8, and
every list and section under 4 GiB. `fitsFrame` and `fitsEvent` are executable checks of
exactly this. A value that does not fit is written modulo 2^32, with one exception:

- **Font fields saturate.** A text draw's `family`, `size` and `weight` are written as
  `min(n, 2^32 − 1)`, the same clamp `Cairn.Text.Host.sat` applies when Lean asks Core Text for
  metrics (`satU32_eq_host_sat`). A huge font size is painted at the size it was measured at,
  not at a wrapped one.

Swift's model uses `Int32` and `UInt32` for these fields, so every Swift value fits.

## Frame

```
offset  size  field
0       4     magic "CAFR" (43 41 46 52)
4       2     u16 version = 1
6       2     u16 flags = 0
8       4     i32 window width
12      4     i32 window height
16      4+4   draws: u32 count, u32 byteLength, then the draw records
.       4+4   ax: u32 count, u32 byteLength, then the ax records
.       4..   textInput record (always present; its head says whether there is one)
.       4     cursor: [code, 0, 0, 0]
.       4+4   effects: u32 count, u32 byteLength, then the effect records
```

A decoder rejects any other magic, version or flags. A future incompatible format changes the
version; flags are reserved for compatible additions and must be zero in v1.

The section lengths are there so the two host threads can each decode only what they use: the
render thread reads the size and draws and skips the rest by length; the main thread skips the
draws and reads the accessibility tree and the tail. `FrameSections` in Swift exposes this.

### Draw records

Paint order: later draws paint over earlier ones.

```
rect      [0, hasFill, hasBorder, 0]                                         36 bytes
          4  rect
          20 fill color          (0,0,0,0 and ignored when hasFill = 0)
          24 u32 corner radius
          28 u32 border width    (0 and ignored when hasBorder = 0)
          32 border color        (0,0,0,0 and ignored when hasBorder = 0)

text      [1, italic, 0, 0]                                             28 + string
          4  point: baseline origin (left end of the baseline)
          12 u32 font family (saturating, see above)
          16 u32 font size in points (saturating)
          20 u32 font weight, 100–900 (saturating)
          24 color
          28 string: the text

pushClip  [2, 0, 0, 0]  4 rect                                               20 bytes
popClip   [3, 0, 0, 0]                                                        4 bytes
```

`pushClip` intersects the clip with its rect until the matching `popClip`. Frames from
`Frame.ofLaid` are balanced (`balanced_ofLaid`).

### Accessibility records

One per node, parents before children (`parent_lt_ofLaid`).

```
ax        [role, focused, selected, checked]                      36 + two strings
          4  hasControl (bool), 5  hasParent (bool), 6  0, 7  0
          8  control ref         (0,0 and ignored when hasControl = 0)
          16 u32 parent index    (0 and ignored when hasParent = 0)
          20 rect: the visible rect (the node's rect intersected with its clip)
          36 string: label
          .  string: value
```

`checked` is `0` none (not checkable), `1` false, `2` true. `parent` indexes this frame's ax list.

### Text input

```
none      [0, 0, 0, 0]                                                        4 bytes
some      [1, hasMarked, 0, 0]                                          68 + string
          4  control ref of the focused field
          12 rect: the field
          28 rect: the caret
          44 range: selection (start ≤ end, scalar indices)
          52 range: marked text  (0,0 and ignored when hasMarked = 0)
          60 point: text origin, the left end of the text's baseline in window coordinates
             after horizontal scroll (where scalar 0 starts)
          68 string: the field's text
```

The host's input-method client answers from this record: `firstRect`, `characterIndex(for:)`
and the marked range measure from `textOrigin` with the same shaping Lean measured with.

### Cursor and effects

Cursor codes: `0` arrow, `1` pointer (hand), `2` text (I-beam).

```
setClipboard  [0, 0, 0, 0]  4 string                                   4 + string
beep          [1, 0, 0, 0]                                                   4 bytes
```

Effects run once, in order, after the frame that carries them.

### Codes

| Role | Code | | Role | Code |
|---|---:|---|---|---:|
| group | 0 | | link | 5 |
| button | 1 | | list | 6 |
| checkbox | 2 | | listItem | 7 |
| text | 3 | | heading | 8 |
| textField | 4 | | tab | 9 |

## Events

```
offset  size  field
0       4     magic "CAEV" (43 41 45 56)
4       2     u16 version = 1
6       2     u16 flags = 0
8       4     u32 count
12      ..    count event records, back to back (no section length)
```

Each record is a 4-byte head `[tag, a, b, 0]`, then fixed fields, then at most one string.
`mods` is a bitfield: bit 0 shift, 1 command, 2 option, 3 control; values of 16 or more are an
error. `button` is `0` primary, `1` secondary.

| Tag | Event | `a` | `b` | Then | Size |
|---:|---|---|---|---|---:|
| 0 | pointerMove | 0 | 0 | point | 12 |
| 1 | pointerDown | button | mods | point, u32 clicks | 16 |
| 2 | pointerUp | button | mods | point | 12 |
| 3 | pointerExit | 0 | 0 | | 4 |
| 4 | scroll | 0 | 0 | point, i32 dx, i32 dy | 20 |
| 5 | key | key code | mods | u32 scalar | 8 |
| 6 | insertText | hasReplace | 0 | range replace, string | 12 + s |
| 7 | setMarked | hasReplace | 0 | range replace, u32 selStart, u32 selLen, string | 20 + s |
| 8 | unmark | 0 | 0 | | 4 |
| 9 | copy | 0 | 0 | | 4 |
| 10 | cut | 0 | 0 | | 4 |
| 11 | selectAll | 0 | 0 | | 4 |
| 12 | undo | 0 | 0 | | 4 |
| 13 | redo | 0 | 0 | | 4 |
| 14 | paste | 0 | 0 | string | 4 + s |
| 15 | resize | 0 | 0 | i32 w, i32 h | 12 |
| 16 | scale | 0 | 0 | u32 backing scale × 100 | 8 |
| 17 | windowFocus | focused (bool) | 0 | | 4 |

- **Keys.** Codes `0` enter, `1` escape, `2` tab, `3` backspace, `4` delete, `5` left,
  `6` right, `7` up, `8` down, `9` home, `10` end, `11` pageUp, `12` pageDown, `13` char.
  For `char` the `u32` is the Unicode scalar and must be a valid scalar (not a surrogate, at most
  U+10FFFF); for every other key it is written as 0 and ignored.
- **Replacement ranges.** `insertText` and `setMarked` carry `replace : Option (Nat × Nat)`:
  with `hasReplace = 1` the text replaces that `[start, end)` scalar range of the focused field
  (what `NSTextInputClient` passes as `replacementRange`) instead of the marked text or
  selection. With `hasReplace = 0` the range is written as `0,0` and ignored. `hasReplace`
  other than 0 or 1 is an error.
- **setMarked** `selStart`, `selLen` select within the marked string, in scalars.

Lean drops a batch that fails to decode, whole (`Frame.boundary`): the host's encoder is
checked against Lean's decoder, so a bad batch means a host bug.

## From layout to frame: `Frame.ofLaid`

`Frame.ofLaid (ui : UI) (l : Laid) : Frame` (`Build.lean`); the runtime then fills in `cursor` and
`effects`. Focus comes from `ui.focus`, the runtime's one source of truth.

- **Draws**, back to front, depth first. A box paints one `rect` (only if it has a background
  or a border), then its children, wrapped in `pushClip`/`popClip` of its rect when it clips.
  Text paints one `text` at its baseline origin `(rect.x, baseline)`. A field paints its
  background and border, then, clipped to its rect: one rect per selection rect in
  `Frame.selectionColor` (accent blue at 30%), its text (or its placeholder at half alpha when
  the text is empty), and a caret rect in the text colour when it is focused and its selection
  is empty.
- **Accessibility.** One node per control (a box with a control, or a field) and per text, in
  paint order. A node's parent is the nearest enclosing control; its rect is its laid rect
  intersected with its clip. Text nodes have role `text` and the content as label. Fields have
  role `textField` and their text as value; `focused` is `ui.focus == some ref`.
- **Text input** describes the first field, in paint order, whose control has focus.

## What is proved

| Theorem | Statement |
|---|---|
| `decodeFrame_encodeFrame` | `fitsFrame f → (encodeFrame f).size < 2^32 → decodeFrame (encodeFrame f) = some f` |
| `decodeEvents_encodeEvents` | `es.all fitsEvent → es.size < 2^32 → decodeEvents (encodeEvents es) = some es` |
| `encodeFrame_eq_put` | `@[csimp]`: the executable `ByteArray` encoder equals the `List UInt8` specification |
| `controls_ofLaid` | the ax tree's control refs are exactly the laid tree's controls' refs, in order |
| `mem_ax_ofLaid` | a ref has an ax node iff some laid control has that ref |
| `ax_refs_nodup` | distinct refs in the laid tree give distinct refs in the ax tree |
| `parent_lt_ofLaid` | every ax parent index points at an earlier node |
| `balanced_ofLaid` | `pushClip`/`popClip` are balanced and never pop an empty stack |
| `satU32_eq_host_sat` | the font-field clamp is `Cairn.Text.Host.sat` |

The specification is arithmetic over `List UInt8` (`/`, `%`, `toNat`), and the round trips close
with `omega`. The fast encoder (`Put.*`) writes into a presized `ByteArray` with shifts and is
proved equal to the specification once per builder, then installed with `@[csimp]`. No
`implemented_by`. Event decoding runs the specification directly: batches are small.

**Not proved: the Swift side.** `Decode.swift` and `Encode.swift` are trusted
([trusted.md](trusted.md)) and checked by the corpus.

## Canonical dump and the corpus

Both sides print frames and event batches in one text format, one item per line, so tests can
compare them line by line (`Dump.lean`, `Dump.swift`):

```
frame W H
draws N
rect X Y W H fill=R,G,B,A|none radius=N border=W:R,G,B,A|none
text X Y font=FAMILY,SIZE,WEIGHT,ITALIC color=R,G,B,A "STRING"
push X Y W H
pop
ax N
node role=CODE control=CLAIM#KEY|none parent=I|none rect=X Y W H focused=B selected=B checked=B|none label="…" value="…"
textInput none
textInput control=C#K rect=… caret=… selection=A B marked=A B|none origin=X Y text="…"
cursor CODE
effects N
clipboard "…"
beep

events N
move X Y | down X Y BUTTON CLICKS MODS | up X Y BUTTON MODS | exit | scroll X Y DX DY
key CODE SCALAR MODS | insert "…" replace=A B|none | marked "…" START LEN replace=A B|none
unmark | copy | cut | selectAll | undo | redo | paste "…" | resize W H | scale P | focus B
```

Strings print printable ASCII (U+0020–U+007E) as itself except `"` and `\`; every other scalar
prints as `\u{HEX}`, uppercase hex, no leading zeros. Booleans print as `0`/`1`.

`make test` runs the corpus:

1. `framecorpus gen build/corpus` writes 300 frames and 300 event batches (`.bin` plus Lean's
   `.txt` dump), random from a fixed seed plus fixed edge cases: the empty frame, every field at
   its maximum and minimum, `Frame.ofLaid` frames with a focused field and marked text, and
   strings with NUL, combining marks, emoji, CJK and U+10FFFF. It checks each round trip in Lean.
2. `swift test` (`CorpusTests`): Swift decodes every frame to Lean's dump; Swift re-encodes
   every event batch (parsed from Lean's dump) to Lean's bytes exactly; Swift rejects
   corrupted and truncated frames and invalid UTF-8; each section decodes alone. It writes 202
   Swift-encoded batches to `build/corpus/swift-events/`.
3. `framecorpus verify build/corpus` decodes Swift's batches with Lean's decoder and compares
   them with Swift's dumps.

## Design notes

- **Fixed records, strings at the end.** Every fixed field sits at a constant offset from its
  record's start, so the Swift decoder does one bounds check per record and loads fields by
  offset (`loadUnaligned`), with no per-field branching.
- **Sections.** Draws and the accessibility tree are decoded on different threads; a length
  per section lets each skip the other without parsing it.
- **Absent optionals take their space.** An absent fill, border, control, parent or marked
  range is written as zeros with a flag in the head, so record sizes don't depend on them.
- **Strict decoding.** Unknown codes, booleans other than 0/1, leftover section bytes and
  trailing bytes are errors on both sides. The format has one encoding per value, which is what
  makes byte-for-byte corpus comparison meaningful.
- **No Lean structures cross.** Only `ByteArray`s; Lean lays out structure fields in its own
  order.
- **Integer arithmetic on the hot path.** Lean boxes `Int` values outside 32 bits and reduces
  `% 2^32` through GMP, so the fast path converts through `UInt32`
  (`i32Word`, proved equal) instead. See [bench/frame.md](../bench/frame.md).

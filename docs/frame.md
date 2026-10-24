# Frame and event format: frames v3, events v2

Two byte buffers cross the boundary between Lean and the Swift host, and nothing else does:

- **Frame** (Lean → host): one record per surface (docs/surfaces.md): for the window and each
  panel what to paint, the accessibility tree, the focused field's text-input state and the
  cursor; for a status item its button and menu. Then the effects, subscription commands and
  the wake deadline (docs/effects.md). Lean builds each canvas with `Frame.ofLaid`, each menu
  with `Frame.ofStatus` (`Cairn/Frame/Menu.lean`), and encodes the frame with `encodeFrame`; the
  host decodes it with `Frame(bytes:)`.
- **Events** (host → Lean): a batch of input events. The host encodes them with
  `encodeEvents`; Lean decodes them with `decodeEvents`.

| Piece | Where |
|---|---|
| Model (both sides) | `lean/Cairn/Frame.lean`, `lean/Cairn/Input.lean`, `host/Sources/CairnFrame/Model.swift` |
| Byte layer: integers, strings, sections | `lean/Cairn/Frame/Bytes.lean` |
| Frame encoder, decoder, round trip | `lean/Cairn/Frame/Encode.lean` |
| Event encoder, decoder, round trip | `lean/Cairn/Frame/Events.lean` |
| `Frame.ofLaid` and its theorems | `lean/Cairn/Frame/Build.lean` |
| `Frame.ofMenu`, `Frame.ofStatus` and their theorems | `lean/Cairn/Frame/Menu.lean` |
| The runtime's `Boundary` | `lean/Cairn/Frame/Boundary.lean` |
| Canonical text dump | `lean/Cairn/Frame/Dump.lean`, `host/Tests/CairnFrameTests/Dump.swift` |
| Swift frame decoder | `host/Sources/CairnFrame/Decode.swift` |
| Swift event encoder | `host/Sources/CairnFrame/Encode.swift` |
| Corpus generator, verifier, bench | `lean/FrameCorpus.lean` (`lake exe framecorpus`) |

This document is the specification. It is meant to be enough to write a third implementation;
where it and the Lean specification (`Wire.Enc.*`) disagree, Lean is right and this is a bug.

## Conventions

- **Integers are little-endian.** `u8`, `u16`, `u32`, `u64` are unsigned; `i32` and `i64` are
  two's complement. A `u64` is written as two `u32`s, low word first.
- **Booleans** are one byte, `0` or `1`. Any other value is an error.
- **Reserved bytes** (shown as `0`) are written as zero and ignored when read. They keep fixed
  fields 4-byte aligned relative to the record's start.
- **Strings** are a `u32` byte length followed by that many bytes of UTF-8. No terminator, no
  padding after the bytes. Invalid UTF-8 (overlong forms, surrogates, scalars above U+10FFFF,
  truncated sequences) is an error.
- **Bytes** (raw data: file contents, HTTP bodies) are a `u32` length followed by that many
  bytes, unchecked, no padding after.
- **Headers** (HTTP) are a `u32` count, then each name and value as two strings.
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
`i32` fields in `[-2^31, 2^31)`, `u32` fields in `[0, 2^32)`, `u64` in `[0, 2^64)`, `i64` in
`[-2^63, 2^63)`, strings and bytes under 4 GiB, and every list and section under 4 GiB. `fitsFrame` and `fitsEvent` are executable checks of
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
4       2     u16 version = 4
6       2     u16 flags = 0
8       4+4   surfaces: u32 count, u32 byteLength, then the surface records
.       4+4   effects: u32 count, u32 byteLength, then the effect records
.       4+4   subs: u32 count, u32 byteLength, then the subscription commands
.       12    wake: [hasWake, 0, 0, 0], u64 deadline (monotonic ms; 0 when absent)
```

A decoder rejects any other magic, version or flags. A future incompatible format changes the
version; flags are reserved for compatible additions and must be zero. Version 1 (M1) ended
after the effects; version 2 added `subs` and `wake` and the effect records 3–6; version 3
replaced the single window (size, draws, ax, text input, cursor after the header) with the list
of surface records; version 4 added the font's width, tracking and tabular digits to the text
record and the `paint` and `shape` draws.

### Surface records

Every surface of the app, in the app's order (`App.surfaces`), every frame. One record shape
for every kind: fields a kind doesn't use are at their defaults (empty title, empty canvas,
empty status), so a decoder never branches on the kind to find the next field.

```
surface   [kind, shown, anchor, screen]                                12 + fields
          4  u32 place: the surface's place claim, its identity across frames
          8  u32 anchor offset (points)
          12 string: window title
          .  canvas
          .  status
```

- **Kinds**: `0` window, `1` panel, `2` status item.
- **shown**: `0` for a panel or status item whose view returned `none` this frame (the host
  hides it; its canvas and status are empty). Windows are always shown.
- **anchor** `0` bottomCenter: the panel is centred horizontally, `offset` points above the
  bottom of its screen's visible frame. **screen** `0` pointer (the screen the pointer is on when
  the panel is shown), `1` main. Both are `0` for other kinds. The host resolves them
  (docs/trusted.md).

A **canvas** is what one Metal surface shows:

```
canvas    i32 width, i32 height                                          8 + fields
          draws: u32 count, u32 byteLength, then the draw records
          ax: u32 count, u32 byteLength, then the ax records
          textInput record (always present; its head says whether there is one)
          cursor: [code, 0, 0, 0]
```

A window's size is the size Lean laid out at (the last `resize`); a panel's is its `width` and
its laid content's height. Coordinates in a canvas are relative to that surface's top-left.

A **status** is a status item's button and menu:

```
status    control ref: the button's control (opening the menu presses it)
          string symbol (SF Symbol name), string title, string label (VoiceOver)
          menu: u32 count, u32 byteLength, then the menu records
```

### Menu records

The menu flattened depth first (`Frame.ofMenu`): a submenu's record comes before its items,
whose `parent` is its index (`parent_lt_ofMenu`, `MenuParentsOk`).

```
menuItem  [kind, enabled, checked, hasShortcut]                       32 + string
          4  hasControl, 5  hasParent, 6  hasPlace, 7  shortcut key code
          8  control ref           (0,0 and ignored when hasControl = 0)
          16 u32 parent index      (0 and ignored when hasParent = 0)
          20 u32 place             (0 and ignored when hasPlace = 0)
          24 u32 shortcut scalar   (0 unless the key is `char`)
          28 shortcut mods, 29–31 0
          32 string: label
```

- **Kinds**: `0` item (has a control), `1` info (a status line, shown disabled), `2` submenu
  (a label, maybe a place), `3` separator.
- `checked` uses the ax codes: `0` not a checkbox, `1` off, `2` on.
- The shortcut's key code, scalar and mods are the event codes below. Without a shortcut they
  are written as zero and ignored.
- The item's `control` is the move a selection presses; the runtime presses it only if it is
  still an enabled item of the current menu (`menu_select_stale`).

### Draw records

Paint order: later draws paint over earlier ones.

```
rect      [0, hasFill, hasBorder, 0]                                         36 bytes
          4  rect
          20 fill color          (0,0,0,0 and ignored when hasFill = 0)
          24 u32 corner radius
          28 u32 border width    (0 and ignored when hasBorder = 0)
          32 border color        (0,0,0,0 and ignored when hasBorder = 0)

text      [1, italic, width, tabular]                                   32 + string
          4  point: baseline origin (left end of the baseline)
          12 u32 font family (saturating, see above)
          16 u32 font size in points (saturating)
          20 u32 font weight, 100–900 (saturating)
          24 i32 tracking: extra advance per character, hundredths of a point (saturating)
          28 color
          32 string: the text

pushClip  [2, 0, 0, 0]  4 rect                                               20 bytes
popClip   [3, 0, 0, 0]                                                        4 bytes

paint     [4, 0, 0, 0]                                        28 + string + int lists
          4  rect: the box the host draws in
          20 u64 origin: monotonic ms the painter's clock counts from
          28 string: the painter's name
          .  ints: scalars (u32 count, then i32 each)
          .  u32 count, then that many ints: arrays

shape     [5, hasFill, hasBorder, hasShadow]                                 56 bytes
          4  [corner, 0, 0, 0]   (0 circular, 1 continuous)
          8  rect
          24 fill color          (0,0,0,0 and ignored when hasFill = 0)
          28 u32 corner radius
          32 u32 border width    (0 and ignored when hasBorder = 0)
          36 border color        (0,0,0,0 and ignored when hasBorder = 0)
          40 shadow color        (all of the shadow 0 and ignored when hasShadow = 0)
          44 u32 shadow radius
          48 i32 shadow x offset
          52 i32 shadow y offset
```

`width` is `0` standard, `1` condensed, `2` expanded, `3` compressed (the system font's width
axis); `tabular` (bool) asks for monospaced digits. Text metrics measure with all three, so a
para is laid out with what is painted.

`paint` is host-drawn content: the host draws the box's pixels with the painter registered under
that name, feeding it the scalars, the arrays and the seconds since `origin`, every display frame
while the draw is on screen. It paints nothing outside its box (trusted, `render.paint.bounds`)
and nothing at all if no painter has the name. `shape` is a rounded rect drawn by Core Graphics:
continuous corners, a border inside the edge, and a shadow (blur radius in points, offset)
under the fill.

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
setClipboard  [0, 0, 0, 0]     4 string                                4 + string
beep          [1, 0, 0, 0]                                                   4 bytes
focus         [2, 0, 0, 0]     4 u32 claim  8 u32 key                      12 bytes
setTimer      [3, 0, 0, 0]     4 u32 ms  8 string name                 8 + string
cancelTimer   [4, 0, 0, 0]     4 string name                           4 + string
request       [5, kind, 0, 0]  4 u32 id  8 request fields              8 + fields
quit          [6, 0, 0, 0]                                                   4 bytes
```

Request kinds and their fields:

| Kind | Request | Fields |
|---:|---|---|
| 0 | readFile | string path |
| 1 | writeFile | string path, bytes data |
| 2 | playSound | string name |
| 3 | http | u32 timeoutMs, string method, string url, headers, bytes body |
| 4 | appendFile | string path, bytes data |
| 5 | listDir | string path |
| 6 | deleteFile | string path |
| 7 | frontmostApp | (none) |
| 8 | permission | `[permission, prompt, 0, 0]`: permission `0` accessibility, `1` microphone; prompt a bool |
| 9 | typeText | u32 pid, `[pressReturn, 0, 0, 0]`, string text |
| 10 | upload | u32 timeoutMs, string method, string url, headers, secret, u32 count, parts |
| 11 | forgetClip | u32 clip |
| 12 | openItem | string target |
| 13 | appRunning | string bundleId |
| 14 | readDefault | string domain, string key |
| 15 | makeDir | string path |

An upload's `secret` is `[0, 0, 0, 0]` for none, or `[1, 0, 0, 0]` and four strings: the header
name, the scheme written before the value (`"Bearer "`), the `KEY=value` file and the key. Only
these names cross the wire; the host reads the value as it sends. Each part is
`[0, 0, 0, 0]` and bytes, or `[1, hasStop, 0, 0]`, u32 clip, u32 start window, u32 stop window
(`hasStop` a bool; the stop is written as 0 and ignored when it is 0): the clip's WAV for
those 20 ms windows.

Effects run once, in order, after the frame that carries them. `focus`, `setTimer` and
`cancelTimer` are the runtime's (focus has moved and the timer table has changed when the
frame is built; the host ignores them; they are on the frame for tools and tests). `request`
is run by the host's handler table and answered by a `reply` event; `quit` ends the app.

### Subscription commands and wake

```
start  [0, sub, 0, 0]  4 u32 id  8 subscription fields                8 + fields
stop   [1, 0, 0, 0]    4 u32 id                                          8 bytes
```

| Sub | Subscription | Fields |
|---:|---|---|
| 0 | every | u32 ms |
| 1 | watchFile | string path |
| 2 | record | u32 clip |
| 3 | globalKey | u32 key code, `[hasModifier, 0, 0, 0]`, u32 modifier flag (0 and ignored without one) |

Commands run in order after the frame's effects. `wake`, when present, asks the host to send a
batch (whose `clock` is all it holds, if nothing else is waiting) once the monotonic clock
reaches the deadline. A deadline in the past means at once.

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
4       2     u16 version = 2
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
| 18 | clock | 0 | 0 | u64 mono ms, i64 wall ms since 1970, i32 zone (s east of UTC) | 24 |
| 19 | reply | reply code | fault | u32 id, reply fields | 8 + fields |
| 20 | subEvent | event code | fault | u32 id, event fields | 8 + fields |
| 21 | surface | 0 | 0 | u32 place, then one local event record | 8 + event |
| 22 | menuOpen | 0 | 0 | u32 place | 8 |
| 23 | menuClose | 0 | 0 | u32 place | 8 |
| 24 | menuSelect | 0 | 0 | u32 place, control ref | 16 |

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
- **Replies.** Codes `0` done (no fields), `1` bytes (bytes data), `2` http (u32 status,
  headers, bytes body), `3` failed (string message; `b` is the fault: `0` notFound, `1` denied,
  `2` timeout, `3` network, `4` invalid, `5` other). For codes other than `3`, `b` is written as
  0 and must be 0. Code `4` names (u32 count, then each name as a string), `5` app (u32 pid,
  string name), `6` flag (`[granted, 0, 0, 0]`, granted a bool).
- **Subscription events.** Codes `0` tick and `1` changed (no fields); `2` audio (u32 frames,
  u32 peak, u32 count, then each window as u64 sum of squares and u32 peak: 12 bytes);
  `3` keyDown, `4` keyUp, `5` otherKey (u64 monotonic ms); `6` failed (string message; `b` is
  the fault, coded as for replies). For codes other than `6`, `b` is written as 0 and must be 0.
- **Surfaces.** A bare local event (tags 0–17) is the window's, as in version 1. `surface`
  addresses a local event to the surface with that place: its inner record must be a local
  event (not `clock`, `reply`, `subEvent`, `surface` or a menu event), else the batch is an
  error, so `surface` never nests. Panels ignore the mouse, so today the host sends `surface`
  only from tests; the runtime routes it to the window when the place is the window's and drops
  it otherwise (`route_surface_other`).
- **Menus.** `menuOpen` and `menuClose` come from the status item's `NSMenuDelegate`;
  `menuOpen` is a press on the item's `control`. `menuSelect` names the status item's place and
  the chosen item's control ref.
- **Global events.** `clock`, `reply` and `subEvent` belong to the app, not to a surface.

Version 1 had tags 0–20 only.

Lean drops a batch that fails to decode, whole (`Frame.boundary`): the host's encoder is
checked against Lean's decoder, so a bad batch means a host bug.

## From layout to frame: `Frame.ofLaid`

`Frame.ofLaid (ui : UI) (l : Laid) : Canvas` (`Build.lean`); the runtime then fills in `cursor`
(`Boundary.frame` in `Runtime/Abi.lean` builds one surface record per `Shown` surface). Focus comes from `ui.focus`, the runtime's one source of truth.

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
| `decodeFrame_encodeFrame` | `fitsFrame f → (encodeFrame f).size < 2^32 → decodeFrame (encodeFrame f) = some f`, over every record including surfaces, menus, requests, subscription commands and wake |
| `decodeEvents_encodeEvents` | `es.all fitsEvent → es.size < 2^32 → decodeEvents (encodeEvents es) = some es` |
| `encodeFrame_eq_put` | `@[csimp]`: the executable `ByteArray` encoder equals the `List UInt8` specification |
| `controls_ofLaid` | the ax tree's control refs are exactly the laid tree's controls' refs, in order |
| `controls_ofLaid_layout` (`Cairn/Frame/Layout.lean`) | with `Layout.layout_controls`: the ax tree's control refs are exactly the view's controls' refs, in order |
| `mem_ax_ofLaid` | a ref has an ax node iff some laid control has that ref |
| `ax_refs_nodup` | distinct refs in the laid tree give distinct refs in the ax tree |
| `parent_lt_ofLaid` | every ax parent index points at an earlier node |
| `controls_ofMenu`, `enabled_ofMenu` | a menu's records carry exactly the description's item refs (`MenuItem.refs`), and the enabled ones exactly its enabled refs, in order |
| `parent_lt_ofMenu` | every menu record's parent is an earlier submenu record |
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
frame
surfaces N
surface kind=K place=P shown=B anchor=A offset=O screen=S title="…"
canvas W H
draws N
rect X Y W H fill=R,G,B,A|none radius=N border=W:R,G,B,A|none
text X Y font=FAMILY,SIZE,WEIGHT,ITALIC,WIDTH,TRACKING,TABULAR color=R,G,B,A "STRING"
shape X Y W H fill=R,G,B,A|none radius=N border=W:R,G,B,A|none corner=0|1 shadow=R,G,B,A:RADIUS:X:Y|none
paint X Y W H origin=N shader="NAME" scalars=[A,B,…] arrays=[[A,…],[…]]
push X Y W H
pop
ax N
node role=CODE control=CLAIM#KEY|none parent=I|none rect=X Y W H focused=B selected=B checked=B|none label="…" value="…"
textInput none
textInput control=C#K rect=… caret=… selection=A B marked=A B|none origin=X Y text="…"
cursor CODE
status control=C#K symbol="…" title="…" label="…"
menu N
item kind=K control=C#K|none parent=I|none place=P|none enabled=B checked=B|none shortcut=CODE,SCALAR,MODS|none label="…"
effects N
clipboard "…"
beep
focus CLAIM#KEY
timer "NAME" MS | cancelTimer "NAME" | quit
request ID readFile "PATH" | request ID writeFile "PATH" BYTES | request ID sound "NAME"
request ID http "METHOD" "URL" timeout=MS HEADERS body=BYTES
request ID appendFile "PATH" BYTES | request ID listDir "PATH" | request ID deleteFile "PATH"
request ID frontmostApp | request ID permission CODE PROMPT
request ID typeText PID RETURN "TEXT" | request ID forgetClip CLIP
request ID open "TARGET" | request ID appRunning "ID" | request ID readDefault "DOMAIN" "KEY"
request ID makeDir "PATH"
request ID upload "METHOD" "URL" timeout=MS HEADERS secret=none|"HEADER" "SCHEME" "FILE" "NAME" parts=N PART…
subs N
start ID every MS | start ID watchFile "PATH" | start ID record CLIP
start ID globalKey CODE MODIFIER|none | stop ID
wake MS|none

events N
move X Y | down X Y BUTTON CLICKS MODS | up X Y BUTTON MODS | exit | scroll X Y DX DY
key CODE SCALAR MODS | insert "…" replace=A B|none | marked "…" START LEN replace=A B|none
unmark | copy | cut | selectAll | undo | redo | paste "…" | resize W H | scale P | focus B
clock MONO WALL ZONE | sub ID 0 | sub ID 1 | sub ID 2 FRAMES PEAK N SUMSQ:PEAK…
sub ID 3 T | sub ID 4 T | sub ID 5 T | sub ID 6 FAULT "…"
surface P EVENT | menuOpen P | menuClose P | menuSelect P CLAIM#KEY
reply ID done | reply ID bytes BYTES | reply ID http STATUS HEADERS body=BYTES | reply ID failed FAULT "…"
reply ID names N "…"… | reply ID app PID "NAME" | reply ID flag B
```

`BYTES` is `x` followed by two lowercase hex digits per byte (`x` alone when empty);
`HEADERS` is `headers=N` followed by each name and value as strings; `PART` is `bytes BYTES` or
`wav CLIP START STOP|none`.

Strings print printable ASCII (U+0020–U+007E) as itself except `"` and `\`; every other scalar
prints as `\u{HEX}`, uppercase hex, no leading zeros. Booleans print as `0`/`1`.

`make test` runs the corpus:

1. `framecorpus gen build/corpus` writes 300 frames and 300 event batches (`.bin` plus Lean's
   `.txt` dump), random from a fixed seed plus fixed edge cases: the empty frame, every field at
   its maximum and minimum, `Frame.ofLaid` frames with a focused field and marked text, and
   strings with NUL, combining marks, emoji, CJK and U+10FFFF. It checks each round trip in Lean.
2. `swift test` (`CorpusTests`): Swift decodes every frame to Lean's dump; Swift re-encodes
   every event batch (parsed from Lean's dump) to Lean's bytes exactly; Swift rejects
   corrupted and truncated frames and invalid UTF-8. It writes 202
   Swift-encoded batches to `build/corpus/swift-events/`.
3. `framecorpus verify build/corpus` decodes Swift's batches with Lean's decoder and compares
   them with Swift's dumps.

## Design notes

- **Fixed records, strings at the end.** Every fixed field sits at a constant offset from its
  record's start, so the Swift decoder does one bounds check per record and loads fields by
  offset (`loadUnaligned`), with no per-field branching.
- **Sections.** Every list carries its byte length, so a reader can skip one without parsing
  it, and a record that doesn't fill its section is caught where it happens.
- **One record per surface, every frame.** The host reconciles: a surface whose place it has
  not seen is created, a record with `shown = 0` hides its surface, and a menu is updated in
  place (docs/surfaces.md). Records are small next to the draws.
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

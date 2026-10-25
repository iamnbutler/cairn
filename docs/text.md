# Text editing

`Cairn.Text.Field` (`lean/Cairn/Text/Field.lean`) is the model behind every text field: what
each `TextOp` does to the text, caret, selection, IME composition and undo history. It is pure
Lean, so its behaviour is a set of theorems (`lean/Cairn/Text/Proofs.lean`) rather than a
description of what AppKit happens to do. This page is the spec; the code follows it, and each
op below is compared with macOS's `NSTextView` (the field editor behind `NSTextField`).

The `NSTextView` column was measured, not remembered: `tools/nstextview-probe/` drives a real
`NSTextView` and `NSTextField` on macOS 27.0.1 and prints the results quoted here.

## State

| Field | Meaning |
|---|---|
| `text : List Char` | Unicode scalars. Never contains a line break. |
| `caret : Nat` | The insertion point; the end of the selection that moves. |
| `anchor : Nat` | The end of the selection that stays put. Selection is `[lo, hi)` with `lo = min caret anchor`, `hi = max caret anchor`. |
| `marked : Option (Nat × Nat)` | IME composition in progress, `[start, end)` of `text`. |
| `undoStack`, `redoStack : List Snapshot` | Most recent first. A `Snapshot` is text, caret and anchor. |
| `typing : Bool` | A typing undo step is open (see Undo). |
| `placeholder : String` | Shown by the view when the text is empty. |

**Indices** are Unicode scalar positions: the unit of `String.length`, `TextMetrics.offsets` and
`FieldView`. Not UTF-8 bytes, not UTF-16 code units, not grapheme clusters. The host converts
AppKit's UTF-16 ranges (`NSRange` in `setMarkedText:selectedRange:` and in every
`NSTextInputClient` query) to and from scalars at the boundary.

**Why `List Char` and not `String`.** Every edit is a splice, `take a t ++ s ++ drop b t`, and
core Lean's lemmas about `take`, `drop`, `length` and `++` on lists make each theorem a few lines.
Lean's `String` is UTF-8 bytes with byte-indexed positions, so every statement about scalar
index `i` would first have to go through decoding. The cost is O(n) edits on a list, which is
nothing at the length of a single-line field. `view` converts once with `String.ofList`, and
`String.length_ofList` makes the indices mean the same thing on both sides.

**Line breaks** are `\n`, `\r`, VT, FF, NEL, U+2028 and U+2029 (`isLineBreak`). A field is
single-line, so inserted, pasted and composed text has each of them replaced by one space
(`clean`). That is exactly what `NSTextField` does in single-line mode (measured: `"x\ny"` →
`"x y"`, `"x\r\ny"` → `"x  y"`, U+2028 → space, tab kept), whether the text arrives by
`insertText:` or by paste. Return never reaches the field as text: the runtime turns it into
`submit`.

**Words** are maximal runs of word characters: ASCII letters, digits and `_`, and every
non-ASCII scalar except the Unicode spaces (U+00A0, U+1680, U+2000–U+200A, U+202F, U+205F,
U+3000). Everything else (ASCII spaces and punctuation) separates words. Option-Left
(`wordLeft`) goes back over separators, then back over one word; Option-Right (`wordRight`) goes
forward over separators, then over one word.

### Well-formedness

`Field.WF f` says: `caret ≤ length`, `anchor ≤ length`, a marked range `(a, b)` has
`a ≤ b ≤ length`, the text has no line break, and every snapshot on either stack satisfies the
same bounds for its own text. The empty field and `ofString s` are well-formed, and every op
maps a well-formed field to a well-formed one (`wf_apply`), so every field reachable from an
empty one is well-formed (`wf_reachable`). Ops never need to clamp an index they read from the
state, only indices that come from outside (`setCaret`, `setMarked`'s selection).

## Ops

`Field.apply : TextOp → Field → Field × List Effect`. Below, `len` is the text's length, the
**target** is the marked range if there is one and the selection otherwise, and "commits the
composition" means `marked` becomes `none` with the text left as it is.

| Op | Cairn | NSTextView (measured) |
|---|---|---|
| `insert s` | Replaces the target with `clean s`; caret collapsed after it; commits the composition. | Same: `insertText:` replaces marked text if any, else the selection (`"aにほb"` + insert `"日本"` → `"a日本b"`, caret 3). |
| `deleteBackward` | Deletes the selection if non-empty, else the one scalar before the caret (nothing at 0). | Deletes the selection, else one **grapheme cluster**: `"a👍🏽"` → `"a"`, `"é"` → `""`. Cairn deletes one scalar, so a skin-toned emoji takes two Backspaces. |
| `deleteForward` | Same, forwards. | Same, by cluster. |
| `deleteWordBackward` | Deletes the selection if non-empty, else `[wordLeft caret, caret)`. | Same on ASCII: `"hello big world␣␣"` → `"hello big "`. |
| `deleteWordForward` | Deletes the selection if non-empty, else `[caret, wordRight caret)`. | Same: `"hello, world"` from 0 → `", world"`. |
| `moveLeft false` | Collapses a selection to its start; else caret one scalar left (stays at 0). | Same (`"one two three"`, `two` selected → caret 4). |
| `moveRight false` | Collapses a selection to its end; else one scalar right (stays at `len`). | Same. |
| `moveLeft true` / `moveRight true` | Caret moves one scalar, anchor stays. | Same (caret 2, Shift-Left twice → `[0, 2)`; `[2,4)` Shift-Right → `[2,5)`, Shift-Left → `[2,3)`). |
| `moveWordLeft e` | Caret to `wordLeft` of the caret (extending) or of the selection's start (not extending). | Same anchor rule (`two` selected, Option-Left → 0, Option-Right → 13). Word boundaries differ, below. |
| `moveWordRight e` | Caret to `wordRight` of the caret (extending) or of the selection's end. | Same. |
| `moveHome e` / `moveEnd e` | Caret to 0 / `len`; anchor stays when extending. | Matches Cmd-Left/Right (and Shift). In `NSTextView` the Home and End *keys* scroll without moving the caret; mapping keys to ops is the runtime's job, and in a single-line field there is nothing to scroll. |
| `setCaret i e` | Caret to `min i len`; anchor stays when extending (Shift-click). | Same. |
| `selectAll` | Selection `[0, len)`, caret at `len`. | Same range. |
| `setMarked s i n` | Replaces the target with `clean s` and marks it; selection becomes `[i, i+n)` inside it, clamped to its length (anchor at `i`, caret at `i+n`). An empty `s` ends the composition, leaving the text as before it. | Same: `"ab"` caret 1, marked `"k"` (sel 1,0) → `"akb"` caret 2; `"か"` → `"aかb"`; `"にほ"` (sel 0,2) → selection `[1,3)`; empty marked text → no marked text. |
| `unmark` | Commits the composition; text and selection unchanged. | Same. |
| `copy` | No change. Emits `setClipboard` with the selected text if the selection is non-empty, nothing otherwise. | Same text (`"ell"`); with an empty selection Copy is disabled and the pasteboard is untouched. |
| `cut` | Copy, then delete the selection (its own undo step). Nothing with an empty selection. | Same. |
| `paste s` | Like `insert`, but its own undo step (unless it replaces a composition, which joins the composition's step). The host reads the pasteboard and sends the string. | Same: paste is its own step, and typing after it starts a new one. |
| `undo` / `redo` | See below. `beep` when the stack is empty. | `NSBeep` when Undo is unavailable from the keyboard. |

Any op other than `setMarked` ends a composition: movement, deletion and selection keep the
marked text as ordinary text. While composing, the IME normally consumes arrows and Backspace
itself, so this only happens when the user clicks elsewhere or a command arrives mid-composition.

### Undo

Each undo entry is the text and selection from before an edit. An edit is any op that changes
the text; ops that don't change it (movement, copy, `unmark`, a Backspace at 0) record nothing
and don't clear redo. Every edit clears the redo stack.

**Coalescing.** The `typing` flag is set by an `insert`, `deleteBackward` or `deleteForward`
that changes the text, and cleared by every other op that touches the field (`copy`, and `cut`
with nothing selected, leave the field exactly as it was).

- `insert`, `deleteBackward` and `deleteForward` at a collapsed caret, with `typing` set, join
  the open step: nothing is pushed. So typing `abc` and one Backspace is one undo step, and
  moving the caret starts a new one.
- Deleting a selection, deleting a word, `cut` and `paste` are always their own step.
- A composition is one step: the first `setMarked` that changes anything pushes; later
  `setMarked`s and the commit (`unmark`, or an `insert` that replaces the marked text) don't.

`undo` pops the top entry, pushes the current text and selection onto redo, and restores the
entry's text, caret and anchor exactly, with no composition. `redo` is the mirror image.

Compared with `NSTextView` (measured, with the run loop turning between steps, as with real
key events):

- **Same:** typing coalesces (`a`, `b`, `c`, Undo → empty); moving the caret ends the step;
  Backspace joins an open typing step (`a`, `b`, Backspace, Undo → empty) and consecutive
  Backspaces coalesce; paste is its own step; a composition undoes as a unit; redo restores.
- **Different, deliberately:** `NSTextView` restores the text but puts the caret at the end of
  the restored range (cut `ell` from `hello`, Undo → caret 4, nothing selected; Select All,
  type, Undo → caret 3). Cairn restores the selection as it was, which is what the undo theorem
  states and what most editors do.
- **Different, deliberately:** `NSTextView` folds a composition committed straight after typing
  into the typing step (type `x`, compose and commit `か`, Undo → before `x`). Cairn makes the
  composition its own step, so Undo removes only the composed text.

### Word boundaries compared

`NSTextView` uses ICU word boundaries with dictionaries. Cairn's rule agrees on ASCII words
separated by spaces and punctuation, on `_` (`foo_bar` is one word in both) and on accented
Latin (`café`). It differs where ICU joins across punctuation or splits within a script:

| Text | NSTextView | Cairn |
|---|---|---|
| `a.b`, Option-Left from end | 0 (one word) | 2 |
| `don't stop`, Option-Right from 0 | 5 | 3 |
| `日本語のテキスト`, Option-Left from end | 4 (dictionary split before `テキスト`) | 0 (one run) |

A grapheme- and ICU-aware rule would need tables Lean doesn't have without the host. If it
matters later, the host can send boundaries the way it sends text metrics, as an `assume` claim.

## View

`Field.view f focused : FieldView` carries the text as a `String`, caret, anchor, marked range,
placeholder and focus. Layout places the caret and selection from `TextMetrics.offsets`; the
indices it receives are in bounds (`view_wf`) and the text has no newline (`view_no_newline`).

## Secure fields

A password field is a `Text.SecureField` (`lean/Cairn/Text/Field.lean`): a `Field` wrapped, not
flagged, so `Field.apply` and every theorem and claim stated with it stay as they are.

- **What it does.** `SecureField.apply` is `Field.apply`, except that `copy`, `cut`, `undo` and
  `redo` beep and change nothing (`NSSecureTextField` refuses them too), and the undo and redo
  stacks are emptied after every op, so no earlier text is kept. Typing, deleting, moving,
  selecting, IME composition and paste work as in a `Field`.
- **What it shows.** `SecureField.view` puts one bullet (U+2022) per scalar in `FieldView.text`,
  with the field's caret, selection, marked range and placeholder, and sets
  `FieldView.secure`. Layout measures, places the caret on and draws the bullets; nothing
  downstream ever has the text. The frame marks the field (`AxNode.secure`, `TextInput.secure`,
  docs/frame.md), writes its accessibility value as `""`, and the host's mirror makes it an
  `AXSecureTextField` with no value. While it has focus in the key window the host turns on
  secure event input (`EnableSecureEventInput`; trusted ^1020, docs/trusted.md).
- **Where its text goes.** Only where the app sends it. A request built from it should be
  `Request.http … (redact := true)`: dumps print it as `<redacted N bytes>`, the debug socket as
  `<redacted>`, and the fuzzer fails a run that dumps planted secure text anywhere
  (docs/fuzz.md, "Secure fields"). The fixture's Passcode field (`fixture^9`) does this.

| Property | Theorems (`Cairn.Text.SecureField`) |
|---|---|
| Copy and cut never set the clipboard: every effect is a beep | `apply_copy`, `apply_cut`, `apply_effects`, `apply_no_clipboard` |
| Undo history stays empty, after any op and any sequence from an empty field | `history_empty`, `applyAll_history` |
| Other ops edit as `Field.apply` does; refused ops change nothing | `apply_edit`, `apply_other`, `apply_refused` |
| Every index stays in bounds | `wf_apply`, `forget_wf` |
| The view is bullets, and depends only on length, selection, marked range and placeholder | `view_text`, `view_agree` (in `Field.lean`) |
| So any frame's or canvas's dump is the same for two such fields: it holds none of the text | `Dump.secure_frame`, `Dump.secure_canvas` (`Cairn/Frame/Dump.lean`) |

## Theorems

All in `lean/Cairn/Text/Proofs.lean`, namespace `Cairn.Text.Field`, checked by `make check`
with no axioms beyond Lean's standard three.

| # | Property | Theorems |
|---|---|---|
| 1 | Every index stays in `0 … length`, for every op from every well-formed field | `wf_empty`, `wf_ofString`, `wf_apply`, `wf_applyAll`, `wf_reachable`, `view_wf` |
| 2 | Typing a string at a collapsed caret (no composition), then Backspace once per scalar, restores the text, caret and anchor | `insert_deleteBackward`, `insert_deleteBackward'` |
| 3 | Undo restores | `undo_apply`, `undo_typing_run`, `undo_composition`, `redo_undo` |
| 4 | Insert over a selection is `before ++ s ++ after` (and over a replacement range) | `insert_replaces_selection`, `insert_replaces_selection'`, `insert_replace` |
| 5 | Copy changes nothing and emits exactly the selection | `apply_copy`, `selected_spec` |
| 6 | Movement never edits | `apply_movement_text` |
| 7 | The text never contains a line break | `WF.single`, `singleLine_apply`, `view_no_newline` |

What theorem 3 states, precisely, given coalescing:

- `undo_apply`: for any op other than `undo`/`redo` that changes the text, applied to a field
  with no open typing step (`typing = false`) and no composition, `undo` afterwards restores the
  text, caret and anchor exactly, with no composition and the undo stack as it was.
- `undo_typing_run`: from a field with no open typing step, no composition and a collapsed
  caret, any run of `insert`/`deleteBackward`/`deleteForward` in which every step changes the
  text is undone by a single `undo` to the text and selection before the run.
- `undo_composition`: from a field with no composition, `setMarked` with a non-empty string,
  any number of further non-empty `setMarked`, then `unmark`, is undone by a single `undo`.
- `redo_undo`: redo after undo restores the text and selection undo replaced.

When `typing` is set, a typing op is not its own step, so undo after it goes back to the start
of the run (`undo_typing_run`), not to the state just before the keystroke.

Tests: `#guard` checks in `Field.lean` cover every op on concrete strings, including the
IME sequence `setMarked "k"` → `setMarked "か"` → `unmark`, composition inside existing text,
composition over a selection and its undo, and every coalescing case above.

## Assumptions at the boundary

- The host converts AppKit's UTF-16 `NSRange`s to scalar indices before sending `setMarked` and
  after reading `FieldView`, including for characters outside the BMP.
- **Replacement ranges are not in the contract yet.** `insertText:replacementRange:` and
  `setMarkedText:selectedRange:replacementRange:` carry a range the input system wants replaced:
  press-and-hold accents (`e`, then `è` replacing it), reconversion, and Korean IMEs that rewrite
  the last syllable without marked text (`research/macos/text-input-ime.md` §4). `TextOp.insert`
  and `TextOp.setMarked` have no field for it. `Field.insert` and `Field.setMarked` already take
  an optional `replace : Option (Nat × Nat)` (scalar indices, clamped into the text, a reversed
  range collapses to its end) and the bounds theorems cover it (`wf_insert`, `wf_setMarked`,
  `insert_replace`); `apply` passes `none`. Adding `(replace : Option (Nat × Nat) := none)` to
  both `TextOp` constructors and the matching `Event`s is a contract PR for the lead; until then
  the host should turn press-and-hold off or drop the range.
- `paste` carries plain text; the host reads `NSPasteboard` and the field never sees rich text.

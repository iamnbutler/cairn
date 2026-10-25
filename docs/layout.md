# Layout

`Cairn.Layout.layout (m : TextMetrics) (window : Size) (n : Node) : Laid` turns a view into
rects, clips, baselines, carets and selections. It is total and pure and uses integer logical
points (origin top-left, y down). The code is in `lean/Cairn/Layout/`:

| File | What |
|---|---|
| `Core.lean` | `measure`, `arrange`, `layout` |
| `Facts.lean` | `Node.controls`, `Laid.controls`, `Laid.Everywhere`, the per-node facts, `Facts` |
| `Proofs.lean` | the theorems, ending in `Cairn.Layout.facts` |
| `Bridge.lean` | `Pressable`, and the bridge to the runtime's `LayoutFacts` |
| `Para.lean` | wrapped text (`Node.para`): its lines fit, tile the text, respect `maxLines`, and its height |
| `Tests.lean` | `#guard` checks on concrete trees with `TextMetrics.mono` |

It is a small subset of flexbox. Anything not described here is not supported in M1:
text wraps only in `Node.para` (below); there is no shrinking and no min/max sizes. Scroll boxes
(below) scroll by an offset the view gives them.

## Two passes

1. **Measure**, bottom-up (`measure m aw : Node → Sized`). Each node gets a *preferred size*,
   stored in a `Sized` tree so that no subtree is measured twice:
   - `aw` is the width the parent offers, used only by wrapped text: the window's width at the
     root, and inside a box its `fixed` width (or the width it was offered) less its horizontal
     padding. Every child of a row is offered the row's whole content width;
   - `fixed n` on an axis prefers `n`;
   - `hug` and `fill` prefer the *intrinsic* size, floored at zero:
     - text: `m.width font s` by `m.lineHeight font`;
     - field: the width of its text (or of its placeholder when the text is empty) plus one
       point for a caret at the end, by the line height; plus padding;
     - row: the sum of the children's preferred widths plus gaps, by the largest preferred
       height; plus padding. A column is the same with the axes swapped. A stack is the
       largest preferred width by the largest preferred height, plus padding;
     - wrapped text: see "Wrapped text".
2. **Arrange**, top-down (`arrange m clip rect : Sized → Laid`). The parent decides each
   child's rect; the node keeps the rect it is given and places its children inside its
   *content box*, `rect.inset padding`.

The root is placed at the origin. On each axis it takes the window's length if it is `fill`,
and its preferred length otherwise. The window is floored at zero size.

## Rows and columns

A row lays its children out left to right (the *main* axis is horizontal, the *cross* axis
vertical); a column lays them out top to bottom. With `k` children, the gaps total
`gap × (k − 1)`.

**Main-axis lengths.** A `fixed n` child gets `n`; a `hug` child gets its preferred length; a
`fill` child starts at 0. The *leftover* is

```
L = max 0 (content length − sum of those lengths − gaps)
```

and the `f` fill children share it: the `j`-th fill child (counting from 0) gets
`⌊L(j+1)/f⌋ − ⌊Lj/f⌋`. The shares telescope, so they add up to exactly `L`; they differ by at
most one, and the larger ones come last. When the children don't fit, `L` is 0, fill children
get nothing and the others keep their lengths and overflow: nothing shrinks in M1. Text is
always `hug`.

**Main-axis positions (`justify`).** The *free* space is the content length minus the
children's lengths and the gaps. It is zero whenever there is a fill child and the line fits.
Children follow one another with `gap` between them, starting at the content box's start plus:

| `justify` | offset | spacing |
|---|---|---|
| `start` | 0 | `gap` |
| `center` | `free / 2` (rounded down; negative when overflowing) | `gap` |
| `finish` | `free` | `gap` |
| `stretch` | 0 | space-between: `gap` plus an equal share of `free` (shared like fill children), so the last child ends at the content box's end; only when `free > 0` and `k > 1`, otherwise `gap` |

**Cross axis (`align`).** With content cross length `cc` (floored at zero), a `fixed n` child
gets `n`, a `fill` child gets `cc`, and a `hug` child gets its preferred length, or `cc` when
`align` is `stretch`. Text is never stretched: its rect is always its measured box. Positions:
`start` and `stretch` at the content start, `center` at `(cc − length) / 2` (rounded down),
`finish` at `cc − length`.

## Stacks

A stack places every child in the whole content box, later children on top. Each axis is
handled like a cross axis: horizontally with `justify`, vertically with `align`. So `fill`
covers the content box, and `center` on both centres the child.

## Clips

Each `Laid` node's `clip` is the region it may paint in: the intersection of the rects of all
its clipping ancestors (`style.clip`, or a scroll box), starting from the window rect at the root. A node does
not clip itself, only its children; its visible part is `rect.inter clip`.

`Rect.inter` places an empty intersection inside its first argument, so an intersection is
always inside the clip it cuts down (see "Contract changes").

## Scroll boxes

`Style.scroll : Option Int` makes a box a scroll box. With `scroll := some o`:

- The box lays its children out as its axis says (a stack stacks them), with the box's own
  rect, padding and gap, exactly as it would without `scroll`; then it moves every child back by
  `o` along its axis: up in a column or stack, left in a row (`Rect.scrollBy`, `scrolled`).
- A scroll box always clips (`Style.clips = clip || scroll.isSome`), so each child's clip is the
  box's clip cut down to the box's rect.
- `Laid` keeps the real rects, which may lie anywhere above, below or beside the box. What
  shows of a node is its visible part, `rect ∩ clip` (`Laid.visible`, `Target.visible`); it is
  empty for a child scrolled wholly out.
- The offset is a number the view supplies. Layout doesn't clamp it or remember it: the runtime
  owns it, moves it by wheel and keys, clamps it, and scrolls the focus into view, for every box
  that names itself with `Style.scrollRef` (docs/runtime.md, "Scrolling"). A view passes the
  runtime's offset with `ui.scrolling ref style`.

What the rest of the pipeline does with a scroll box:

| Where | What |
|---|---|
| hit testing | tests the visible part, so a pointer outside the box never reaches a scrolled child |
| frame (`Frame/Build.lean`) | draws only the children whose visible part is nonempty, inside the box's clip |
| AX tree | the box gets a node of its own, role `scrollArea` (AXScrollArea), parenting its children; the host exposes only children with a nonempty rect (`docs/trusted.md`) |
| `Fits` | a scroll box fits when its padding is non-negative and each child fits across its axis; along the axis the children may run past the box |

Theorems, for every scroll box, any children, any metrics and any window. `Scroll.lean` has the
three below; the rest is in `Proofs.lean` and `Bridge.lean`:

- `scroll_rects`, `scroll_column_rects`: the children are where the same box without `scroll`
  puts them, moved back by the offset (in a column, `y` less the offset; `x`, width and height
  unchanged). They rest on `arrange_scroll` and `measure_scroll` (`scroll` doesn't change
  measuring).
- `layout_scrollApart`: in a row or column scroll box, the children's rects are pairwise disjoint
  and every nonempty visible part under the box is inside it. It rests on
  `layout_siblingsDisjoint` (moving every sibling by the same offset keeps them apart) and
  `layout_clipContained` (`Facts.clipContained`: under every clipping box, every nonempty visible
  part is inside the box's rect).
- `pressed_where_visible`: in a `Pressable` view, a control with a nonempty visible part is hit
  at that part's centre (`hitTest_center_of_pressable`), and one with an empty visible part is
  the hit at no point (`not_hit_of_hidden`).

These are theorems, not claims: a Cairn claim is a move, place, flow or invariant of an app's
machine, or an `assume` about the host, and a framework theorem has no machine. The test fixture
(test/fixture) has a scroll box of 200 rows at the runtime's offset, and its claims `fixture^12`,
`fixture^13` and `fixture^15` state the three for it, in every state and at every offset
(`fixture^11` stated the first at a fixed offset, before the runtime owned it, and is retired).

## Grids

`Cairn.UI.Grid` lays equal cards out as many to a row as the box's width fits: `columns` is
the most cards of `minWidth` that fit with their gaps, and at least one. The cards share the
width, keep their aspect ratio (plus a fixed caption height), and shrink together when the rows
would be taller than the box, so nothing is drawn outside it. Card `i` is at row `i / columns`,
column `i % columns`. It is arithmetic on the box's size; a view passes the size it derives
from `UI.size`, which every `resize` event sets, so the host only reports the window's size.
`Grid.node` builds a column of rows of fixed-size clipping cells, laid out by the ordinary pass:
no new kind of node, and nothing in `Node`, `Style` or `Laid` changed.

Proved for every size and card count: the column count is the largest that fits
(`columns_fits`, `le_columns`, `not_fits_succ`); every cell is inside the box (`cell_inside`);
later cards come later in reading order, so no two overlap (`cell_before`, `cell_disjoint`); the
laid cells are exactly `Grid.rects` (`cells_rects`); and a point in cell `i` hits what cell `i`
alone would (`hitTarget_cell`). Gallery (cairn_examples) uses it for its tiles
(`cairn_examples^510`).

**A floor on card size.** Shrinking every card so the rows fit the height means a short window
gives tiny cards. `Grid.minBox n cols` is the smallest box with `cols` columns (at least one) in
which every one of `n` cards is at least `minWidth` wide: `cols` cards of `minWidth` and their
gaps across, and as many rows of `minCardH` (`minWidth` at the aspect ratio, rounded up, plus
the caption) and their gaps down. An app adds what it lays out around the grid and returns it
as `App.minSize`; the host keeps the window at least that big (^1010). Proved for every card
count and column count: in any box at least `minBox`, every card is at least `minWidth` wide
(`minW_le_cardW`, `minBox_cells`): a wider box has as many columns or more, so no more rows. And
it is the smallest: it has exactly `cols` columns (`columns_minBox`); a narrower box has fewer
columns, or with one column cards narrower than `minWidth` (`minBox_narrower`); a shorter one
with `cols` columns has narrower cards (`minBox_shorter`, when the gap is no taller than a
card). Gallery's window is at least 1020 × 536, three columns of 180-point tiles
(`cairn_examples^511`).

## Text

A `text` node is one line. A text node's rect is its measured box at the position its parent chose, and its
`baseline` is `rect.y + ascent`.

## Wrapped text

`Node.para style wrap s` is text that wraps to the width it is offered. `Wrap` has `width`
(default `fill`) and `height` (default `hug`) sizings, `maxLines : Option Nat`, `keep`
(`head` or `tail`: which lines survive `maxLines`) and `align` (`start`, `center`, `finish`:
where each line sits across the width).

Lean chooses the breaks (`lean/Cairn/Text/Wrap.lean`). It measures the string once,
`m.offsets font s` (Core Text shapes the whole string once and caches it), and a line of scalars
`[a, b)` is `offs[b] − offs[a]` wide. The width `W` is the para's `fixed` width or the width it
was offered.

1. **Words** are maximal runs of scalars other than U+0020. Lines break only between words, and
   the spaces at a break are dropped. A line runs from its first word's start to its last word's
   end, keeping the spaces between its own words.
2. **Greedy fill**: a line takes the next word while the line, measured from its first scalar to
   that word's end, is at most `W` wide.
3. **Over-wide words**: a word that doesn't fit on a line of its own is cut into pieces. Each
   piece is the longest run of scalars, from where the last one ended, that fits, and never less
   than one scalar. Every piece but the last is a line; the last starts a line that later words
   may join.
4. **`maxLines n`** keeps the first `n` lines (`head`) or the last `n` (`tail`).

`measure` turns a para into exactly what a view could have written by hand: a clipping column
(`paraStyle`: the para's sizings and alignment, `clip := true`) of one `text` per line, each
`(offs[b] − offs[a]) × lineHeight`. A `hug` height is lines × line height. Everything after
`measure` is unchanged: `arrange`, `Laid`, the frame, hit testing and the accessibility mirror
see ordinary text nodes. No frame-format change; each line is painted as a text draw of its
substring.

**Theorems.** Over every metrics (`Cairn.Text.WrapProofs` on offsets, `Cairn.Layout.Para` on
the laid-out lines), with no `sorry`, `native_decide` or new axioms:

| Theorem | Statement |
|---|---|
| `allLines_fit`, `para_lines_fit` | every line is at most `W` wide, or is a single scalar (a cut over-wide word) |
| `allLines_tiles`, `para_lines_tile` | the text is the lines, in order, with only U+0020 between and around them (`Tiles`): nothing lost, reordered or invented |
| `lines_length_le`, `para_count` | at most `maxLines` lines |
| `lines_tail`, `para_lines_tail` | with `tail`, the lines shown are exactly the last `min n k` of all `k` lines (all lines = some prefix ++ the lines shown) |
| `lines_head`, `para_lines_head` | with `head`, exactly the first `min n k` |
| `para_height`, `layout_para_height` | a `hug` para is lines × line height tall |
| `fitsIn_arrange` (`FitsIn.para`), `facts` | the layout theorems hold with paras in the tree: a para is a clipping box of text, so it never breaks `Fits` or `Pressable` and has no controls |

The examples in `WrapProofs.lean` and `Tests.lean` check the rules with `#guard`
(`TextMetrics.mono`), and the trusted fuzzer compares Lean's lines with what Core Text paints
and where Core Text itself would break (docs/trusted.md, ^990 and ^991).

**Limits.**

- Breaks only at U+0020. `\n`, tabs, U+2028/2029 and other whitespace are ordinary scalars (no
  hard line breaks), and there is no hyphenation and no ellipsis at a `maxLines` cut.
- Over-wide words are cut at scalar boundaries, which can split a grapheme cluster (an emoji
  sequence, a combining mark).
- Left-to-right only. Right-to-left, bidirectional and complex-script line breaking are not
  modelled.
- A line is painted by shaping its substring alone, so kerning across a dropped space or a cut
  is lost: up to about 1 + 0.15 em off what Lean measured (^990).
- Every child of a row is offered the row's whole content width, not its share. A para inside a
  row with siblings measures as if it had the row to itself.
- The accessibility mirror reads each line as its own text element.
- An empty or all-space string has no lines (height 0 when `hug`).

## Fields

Given the field's rect and content box `c`, with `offs := m.offsets font text`:

- The line is centred vertically: `top = c.y + (c.h − lineHeight) / 2`.
- `co := offs[caret]` (an out-of-range index reads as the text's width).
- The text scrolls horizontally just enough for the caret to be visible:
  `scroll = max 0 (co + 1 − c.w)`. Layout has no memory, so this is the least scroll that shows
  the caret, which means the caret sits at the right edge once the text is longer than the box.
- `textOrigin = ⟨c.x − scroll, top + ascent⟩` (left edge of the text, baseline).
- `caret = ⟨textOrigin.x + co, top, 1, lineHeight⟩`.
- `selection` is empty when `anchor = caret`, and otherwise one rect from the offset of
  `min anchor caret` to the offset of `max anchor caret`, `top` to `top + lineHeight`.

The renderer should clip a field's text, caret and selection to its content box (the field
does not set `clip` on itself because it has no children). IME marked ranges are not laid out
here; the frame can underline them using the same offsets.

## Theorems

Every theorem holds for all metrics; those about text positions assume `m.Valid`. Everything a
caller needs is packaged in `Cairn.Layout.Facts m window n l`, and
`Cairn.Layout.facts (hm : m.Valid) window n : Facts m window n (layout m window n)` proves all
of it. `l.Everywhere P` means `P` holds at every node of `l`.

| Fact (field of `Facts`) | Theorem | Statement |
|---|---|---|
| `controls` | `layout_controls` | `(layout m w n).controls = n.controls`: the controls in paint order (node before children) are exactly the view's; none lost, invented or reordered |
| `rootClip` | `layout_rootClip` | the root's clip is `windowRect w` |
| `rootOrigin` | `layout_rootOrigin` | the root's rect starts at the origin |
| `childClips` | `layout_childClips` | each child's clip is its parent's clip, intersected with the parent's rect if the parent clips |
| `clipInside` | `layout_clipInside` | every clip has non-negative size and contains each child's clip |
| `clipContained` | `layout_clipContained` | under a box that clips (every scroll box), every nonempty visible part of every node is inside the box's rect |
| `rectNonneg` | `layout_rectNonneg` | every rect has non-negative size |
| `siblingsDisjoint` | `layout_siblingsDisjoint` | in a row or column, earlier children's rects end before later ones start, so distinct children are disjoint (index form: `SiblingsDisjoint.get`) |
| `fillExact` | `layout_fillExact` | in a row or column with a fill child, if the other children, gaps and padding fit, children + gaps + padding equal the parent's main length exactly |
| `childrenInside` | `layout_childrenInside` | if a container doesn't scroll and its children fit its content box (each in size, and in a row or column all of them plus gaps along the main axis), every child's rect is inside the content box |
| `caretPlaced` | `layout_caretPlaced` | in each field, `caret.x = textOrigin.x + offs[caret]`, `textOrigin.x ≤ caret.x ≤ textOrigin.x + width`, the caret is 1 wide and a line high, it is inside the content box whenever that is at least 1 wide, and the selection is empty when collapsed and otherwise spans the offsets of its ends |

Also `TextMetrics.mono_valid : TextMetrics.mono.Valid`.

`childrenInside` and `siblingsDisjoint` together are what a pressability proof needs: when a
view fits, a child's whole subtree stays inside the child, and siblings don't overlap, so
nothing in one sibling can be on top of another. `childClips` and `clipInside` say what is
visible.

### How the proofs are organised

Each fact is proved for a single `arrange` step and lifted to the whole tree by
`arrange_everywhere`, the only induction over the nested `Sized` tree. Facts that need
something of the incoming clip or rect (non-negative sizes) use its invariant form. List-level
lemmas about one line (`Line.go_pairwise`, `Line.go_fill`, `Line.go_upper`) carry the
arithmetic.

## Bridge to the runtime

The runtime's pressability theorems (`Cairn.Runtime.hitTest_center`, `click_center_presses`)
assume `Cairn.Runtime.LayoutFacts laid t`: the control's visible rect (`rect ∩ clip`) is nonempty and a pointer
at its centre reaches it, which means no other target's visible rect covers that point later in
paint order. `Bridge.lean` proves this for every control of `layout m w n` under four
conditions an app can check of its laid-out view, packaged as `Pressable w l`:

| Field | Condition |
|---|---|
| `rootInside` | the root's rect is inside the window rect (the window is at least the view's size) |
| `fits` | everywhere, either the box clips and holds only text (a label: the text may overflow, the clip holds it), or padding is non-negative, each child is no larger than its parent's content box, and in a row or column the children plus gaps fit along the main axis, or the box scrolls, its padding is non-negative and each child fits across its axis (`Fits`) |
| `stackTop` | in a stack, only the last child may contain controls (`StackTop`) |
| `controlLeaf` | a box with a control has no controls below it (`ControlLeaf`), so a label inside a button routes to the button |

Theorems:

- `reaches_of_pressable`: a pointer at *any* point of a control's visible rect reaches it.
- `layoutFacts_of_pressable (hp : Pressable w (layout m w n)) (ht : t ∈ targets (layout m w n))
  (hne : t.visible.nonempty) : LayoutFacts (layout m w n) t`.
- `hitTest_center_of_pressable`: so `hitTest` at the centre of the control's visible part
  returns it.
- `not_hit_of_hidden`: a control with an empty visible part is hit nowhere.
- `visible_eq_rect`: in a view with no scroll boxes (`NoScroll` everywhere, from
  `layout_noScroll` when `n.scrolls = false`), the visible part is the whole rect.

The conditions are stated on the laid-out tree, not on the `Node`, because "fits" depends on
the window and the metrics. For a concrete view, window and metrics, `Check.lean` decides them
(`checkPressable`, closed with `decide +kernel`).

### Rigid views: every state, every metrics (`Rigid.lean`)

A view whose size depends on its state (a list of any length) and on text widths can't be
checked one layout at a time. `FitsIn n w h` is a condition on the `Node` alone: in a *rigid*
view every box and field is `fixed` or `fill` on both axes, so no rect depends on a string's
width, and text sits only in boxes that clip and hold nothing but text. Node by node it asks
that fixed lengths and gaps fit the content box, that each child fits at the size it will get
(a `fill` child at every length from `⌊leftover / fills⌋` up, `fillShare_ge`), and that
controls have positive size. Rows and columns only; stacks aren't covered.

- `fitsIn_arrange`: if `FitsIn n w h`, then `n` laid out in any `w × h` rect, with any clip and
  any `TextMetrics`, meets `Fits`, `StackTop` and `ControlLeaf` everywhere, and every control's
  rect is nonempty.
- `hitTest_center_of_fitsIn`: for a `fill × fill` root that fits the window, hit testing at
  the centre of every control's visible part, when that is nonempty, returns that control.
- `hitTest_center_of_fitsIn_flat`: if the view also has no scroll boxes (`Node.scrolls`), every
  control is visible whole and hit at its centre.
- `FitsIn.line` asks that the children fit along the main axis only when the box doesn't
  scroll.
- `exampleList_pressable`: a column of any number of 44-point buttons with any labels is
  pressable whenever the window is wider than zero and at least `44 · k` tall.

The honest limit: a list outside a scroll box fits only while it fits the window, and labels are
clipped rather than wrapped. A para fits anywhere (`FitsIn.para`): it clips its
lines.

The runtime uses this layout: `Cairn.Runtime.Config.layout` defaults to
`Cairn.Layout.layout`, and the stub layout in `Runtime/Stub.lean` is gone.

## Contract changes

- `Rect.inter` (`lean/Cairn/Geometry.lean`) now clamps the origin of an empty intersection
  into its first argument (`x := min (max a.x b.x) (a.x + a.w)`, likewise `y`). Non-empty
  intersections are unchanged. Without this, intersecting a clip with a rect outside it gave a
  zero-size rect *outside* the clip, and "every clip is inside its parent's clip" was false.
- Runtime (workstream C's files): `Config.layout` defaults to `Cairn.Layout.layout`
  (`Runtime/Step.lean` imports `Cairn.Layout.Core`); the test layout was removed from
  `Runtime/Stub.lean`; `Runtime/Tests.lean` runs on the real layout (its test field gained
  padding); `docs/runtime.md` says so.
- `Node.controls` and `Laid.controls` (paint-order controls) are new, in `Layout/Facts.lean`.
- `measure` takes the offered width (`measure m aw n`), for wrapped text; `layout` passes the
  window's width. `Node.para` is new (`UI/Node.lean`).

## Performance

See `bench/layout.md`: about 0.3 µs per node on an M4 Max, linear in the node count.

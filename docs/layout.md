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
| `Tests.lean` | `#guard` checks on concrete trees with `TextMetrics.mono` |

It is a small subset of flexbox. Anything not described here is not supported in M1:
there is no wrapping, no shrinking, no min/max sizes and no scrolling containers.

## Two passes

1. **Measure**, bottom-up (`measure : Node → Sized`). Each node gets a *preferred size*,
   stored in a `Sized` tree so that no subtree is measured twice:
   - `fixed n` on an axis prefers `n`;
   - `hug` and `fill` prefer the *intrinsic* size, floored at zero:
     - text: `m.width font s` by `m.lineHeight font`;
     - field: the width of its text (or of its placeholder when the text is empty) plus one
       point for a caret at the end, by the line height; plus padding;
     - row: the sum of the children's preferred widths plus gaps, by the largest preferred
       height; plus padding. A column is the same with the axes swapped. A stack is the
       largest preferred width by the largest preferred height, plus padding.
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
its clipping ancestors (`style.clip`), starting from the window rect at the root. A node does
not clip itself, only its children; its visible part is `rect.inter clip`.

`Rect.inter` places an empty intersection inside its first argument, so an intersection is
always inside the clip it cuts down (see "Contract changes").

## Text

Single line. A text node's rect is its measured box at the position its parent chose, and its
`baseline` is `rect.y + ascent`.

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
| `rectNonneg` | `layout_rectNonneg` | every rect has non-negative size |
| `siblingsDisjoint` | `layout_siblingsDisjoint` | in a row or column, earlier children's rects end before later ones start, so distinct children are disjoint (index form: `SiblingsDisjoint.get`) |
| `fillExact` | `layout_fillExact` | in a row or column with a fill child, if the other children, gaps and padding fit, children + gaps + padding equal the parent's main length exactly |
| `childrenInside` | `layout_childrenInside` | if a container's children fit its content box (each in size, and in a row or column all of them plus gaps along the main axis), every child's rect is inside the content box |
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
assume `Cairn.Runtime.LayoutFacts laid t`: the control's visible rect is nonempty and a pointer
at its centre reaches it, which means no other target's visible rect covers that point later in
paint order. `Bridge.lean` proves this for every control of `layout m w n` under four
conditions an app can check of its laid-out view, packaged as `Pressable w l`:

| Field | Condition |
|---|---|
| `rootInside` | the root's rect is inside the window rect (the window is at least the view's size) |
| `fits` | everywhere, padding is non-negative, each child is no larger than its parent's content box, and in a row or column the children plus gaps fit along the main axis (`Fits`) |
| `stackTop` | in a stack, only the last child may contain controls (`StackTop`) |
| `controlLeaf` | a box with a control has no controls below it (`ControlLeaf`), so a label inside a button routes to the button |

Theorems:

- `reaches_of_pressable`: a pointer at *any* point of a control's visible rect reaches it.
- `layoutFacts_of_pressable (hp : Pressable w (layout m w n)) (ht : t ∈ targets (layout m w n))
  (hne : t.node.rect.nonempty) : LayoutFacts (layout m w n) t`. Under these conditions the
  visible rect is the whole rect.
- `hitTest_center_of_pressable`: so `hitTest` at the control's centre returns it.

The conditions are stated on the laid-out tree, not on the `Node`, because "fits" depends on
the window and the metrics. For a concrete view and window they can be checked by evaluating
the layout; there is no decidable checker yet.

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

## Performance

See `bench/layout.md`: about 0.3 µs per node on an M4 Max, linear in the node count.

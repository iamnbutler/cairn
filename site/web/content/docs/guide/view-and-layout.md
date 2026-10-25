---
title: The view and layout
nav: The view and layout
eyebrow: Building an app · Chapter 3
lede: What an app shows, as a tree of boxes and text that Lean lays out in whole points.
---

An app's view is a pure function from its state to a tree of **nodes**. Lean lays the tree out,
hit tests it, and turns it into the frame the host paints. Because all of that is Lean, "the
item's delete button is on screen" and "a click at its centre presses it" are theorems about the
code that actually runs, not about a model of it.

## The view function

A window's view takes the app's state and the **UI state**: the window's size, which control the
pointer is over, which is pressed, which has keyboard focus. The runtime keeps the UI state; the
view only reads it, for hover colours and focus rings. The fixture's button:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-button" />

A node that performs a move carries a **control**: the ref of the claim it performs, an
accessibility role and a label. Controls are how presence theorems, hit testing and the
accessibility mirror find a move on screen. The host gives each control's accessibility element
the identifier `^N`.

<bongo:include src="lean/Cairn/UI/Node.lean#node-control" />

## Nodes

There are four kinds of node: a box, a line of text, wrapped text, and a text field.

<bongo:include src="lean/Cairn/UI/Node.lean#node-node" />

A box has a style: how it lays out its children, how big it is, and how it is painted.

<bongo:include src="lean/Cairn/UI/Node.lean#node-style" />

## Layout

Layout is a small subset of flexbox, and everything is in **integer logical points**, origin at
the top left, y down. There are no floats anywhere a theorem looks.

<bongo:include src="lean/Cairn/UI/Node.lean#node-sizing" />

- A **row** lays its children out left to right, a **column** top to bottom, and a **stack**
  places them all in the same box, later ones on top.
- On each axis a node is `fixed n`, `hug` (its content's size) or `fill`. `fill` children share
  what is left over equally, to the point: the shares add up exactly, and differ by at most one.
- Nothing shrinks. When children don't fit, `fill` children get nothing and the rest overflow.
  A box with `clip` cuts its children to its rect.
- There is no scrolling yet.

Text comes from the host's measurements: Lean asks Core Text how wide a string is in a given font,
and lays it out with the answer. That the measurement matches what is painted is an
[assumption](/docs/internals/trusted-base/), checked by fuzzing; every layout theorem holds for
whatever valid measurements the host returns.

## Wrapped text and fields

`Node.para` wraps text to the width it is offered. Lean picks the line breaks from one
measurement of the whole string, so the paragraph rewraps as the window resizes, and theorems say
every line fits, nothing is lost or reordered, and `maxLines` is respected. From the fixture's
view:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-para" />

A field shows a `Text.Field`: its text, caret, selection and input-method composition. The field's
move edits it ([chapter 2](/docs/guide/moves-and-flows/)), and the view shows it:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-input-row" />

## Lists

A list is a box whose children come from the state: the fixture's view
([chapter 1](/docs/guide/first-app/#the-fixture-from-the-top)) maps `itemRow` over its items.
Each row's controls use a key, the item's id, so `^4#12` is item 12's checkbox wherever it ends
up:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-item-row" />

## Rigid views

A view whose boxes are fixed in size and clip their text is **rigid**: no rect depends on the
width of a string. For a rigid view, Cairn can prove every control is pressable in every state,
with any text measurements, in any window above a minimum size; the next chapter says how.
A counter with fixed-size buttons is rigid. The fixture isn't: its buttons hug their
labels. A view whose layout depends on its text can still be checked, one concrete layout at a
time, and the fuzzer checks every control it lays out.

## Surfaces

An app shows a fixed list of **surfaces**: at most one window, overlay panels that never take focus
or clicks, and menu bar items with native menus built from Lean. Each is identified by a place
claim. The fixture has just its window.

<bongo:include src="lean/Cairn/App.lean#app-surface" />

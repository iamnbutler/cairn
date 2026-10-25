---
title: Basics
nav: Basics
eyebrow: Example apps
lede: A text field, an Add button, a list of items you can check off or delete, and a count of what's left.
---

Basics is the first app with text input and a list. It shows keyed controls (one checkbox per
item), a field whose editing comes from the framework, wrapped text, and an invariant proved over
every reachable state.

| Id | Kind | What |
|---|---|---|
| ^101 | move | the New item field: edits, and Enter adds |
| ^102 | move | Add |
| ^103 | move, keyed | an item's checkbox, `^103#k` for item `k` |
| ^104 | move, keyed | an item's delete button, `^104#k` |
| ^105 | invariant | the count of items left is right, and item ids are distinct |
| ^106 | place | the window |
| ^107–^109 | flow | add and finish; blank text adds nothing; add, then delete |

Its map: [/map/basics/](/map/basics/). Run it with `make demo DEMO=CairnBasics`.

## State

The state keeps a running count of items left rather than recomputing it in the view. The
invariant ^105 is what makes that safe.

<bongo:include src="lean/Examples/Basics.lean#basics-state" />

## Adding an item

<bongo:include src="lean/Examples/Basics.lean#basics-add" />

The field's move answers edits and Enter; Add's answers a press. Both use the same `add`, and the
same `post`.

<bongo:include src="lean/Examples/Basics.lean#basics-type-item" />

## Keyed moves

<bongo:include src="lean/Examples/Basics.lean#basics-toggle" />

## The invariant

<bongo:include src="lean/Examples/Basics.lean#basics-invariant" />

## Flows

<bongo:include src="lean/Examples/Basics.lean#basics-flows" />

## The view

<bongo:include src="lean/Examples/Basics.lean#basics-intro" />

<bongo:include src="lean/Examples/Basics.lean#basics-input-row" />

<bongo:include src="lean/Examples/Basics.lean#basics-view" />

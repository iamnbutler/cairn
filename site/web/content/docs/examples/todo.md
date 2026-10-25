---
title: TodoMVC
nav: TodoMVC
eyebrow: Example apps
lede: The full TodoMVC spec as a native Mac app, with every behaviour a claim and the counts, filters and controls proved.
---

TodoMVC was Cairn's first milestone: a small app with a complete public spec, real text fields
and enough edge cases to need every layer. Every one of the spec's fifty requirements maps to a
claim or to code; each claim's `does` names the requirements it covers.

| Id | Kind | What |
|---|---|---|
| ^201 | place | the window |
| ^202 | move | the new-todo field: edits, and Enter adds |
| ^203 | move | toggle all |
| ^204 | move, keyed | a todo's checkbox |
| ^205 | move, keyed | double-click a todo's title to edit it |
| ^206 | move, keyed | a todo's delete button |
| ^207 | move, keyed | a todo's edit field: Enter or blur saves, Escape cancels |
| ^208–^210 | move | the filters All, Active, Completed |
| ^211 | move | Clear completed |
| ^212 | invariant | the counter is the number of active todos; ids are distinct |
| ^213 | invariant | the listed rows are the todos the filter accepts, in order |
| ^214 | assume | the host reports a double click as a second click |
| ^215 | retired | hash routes and the back button, which only make sense on the web |
| ^216–^224 | flow | witnessed paths through the app |

Its map: [/map/todo/](/map/todo/). Run it with `make demo`.

## Editing in place

Double-clicking a title starts editing it and moves keyboard focus into the new field, with a
`focus` effect the runtime carries out:

<bongo:include src="lean/Examples/Todo.lean#todo-start-editing" />

The edit field's move answers four triggers. Enter and blur save; Escape cancels. Each has its own
`post` and proof:

<bongo:include src="lean/Examples/Todo.lean#todo-edit" />

<bongo:include src="lean/Examples/Todo.lean#todo-edit-flow" />

## The view as a claim

An invariant can be about the view. ^213 says that, under any hover and focus, the rows on screen
are exactly the todos the filter accepts, in order:

<bongo:include src="lean/Examples/Todo.lean#todo-listed-rows" />

## Assumptions and retired claims

A double click is something the host must report correctly, so it is an assumption. The back
button through filters was a requirement only for the web; its id stays issued with the reason:

<bongo:include src="lean/Examples/Todo.lean#todo-double-click" />

<bongo:include src="lean/Examples/Todo.lean#todo-retire" />

## What is proved

- Every move's `post`, for every state where it is enabled.
- In every state the running app reaches, whatever events arrive: the counter equals the active
  todos, ids are distinct, and the rows are the filtered todos in order.
- Every move's control is in the view, the frame's accessibility tree and on screen exactly when
  the move is enabled.
- In any window at least 389 points wide and tall enough for the list, with any text
  measurements, a click at the centre of every control hits it. There is no scrolling yet, so
  rows below the window are outside what this says.

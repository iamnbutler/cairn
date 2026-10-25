---
title: Moves and flows
nav: Moves and flows
eyebrow: Building an app · Chapter 2
lede: Declaring what a person can do, the paths through it, and what must always hold.
---

Everything a person can do in a Cairn app is a **move**. A move is a claim: it has an id, a
title, two sentences for people and a formal statement for Lean. The app's `update` is assembled
from its moves and nothing else, so there is no behaviour without a claim. The framework proves
that once, for every app: an action no move owns changes nothing and asks nothing of the host,
and every effect an app asks for comes from an enabled move.

This chapter covers the claim kinds you write most: moves, flows and invariants. The
[claims reference](/docs/reference/claims/) has every clause.

## A move

Here is the fixture's Add:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-add-item" />

Reading it top to bottom:

- `move ^3 addItem (s : State) "Add" in ^1`: the id, a Lean name, the state's name, the title,
  and the place the control appears in.
- `does` and `sees`: what a person does and what follows. Reviewers read these, and its
  [claim pages](/docs/evidence/) show them. Both are required.
- `on press`: one block per kind of action the move answers. The triggers are `press`,
  `doublePress`, `submit`, `cancel`, `blur` and `edit`, which also binds the text operation.
- `apply`: the new state. Use `emit` instead when the move also asks the host to do something;
  it returns the new state and a list of effects.
- `post s'`: what must be true of the new state `s'`, stated against the old one, `s`.
- `sound`: the proof that `apply` meets `post`. A move without it doesn't compile.

A move can say when it is available with `enabled`. An item's delete button is only enabled for an
item in the list, and the [view](/docs/guide/view-and-layout/) only shows it then:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-delete" />

With `enabled`, `sound` may assume it: the goal is "for every key and every enabled state, `post`
holds after `apply`", which is why its proof takes three arguments (`intro s k _`).

## Keyed moves: one control per item

A list shows one checkbox per item, and they are all the same move. A **keyed** move takes a key
after the state, and each control carries it: `^4#12` is item 12's checkbox. Delete, above, is
one too, and so is the checkbox:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-toggle" />

## Text fields

A field's move answers `edit` with the text operation, and usually `submit` for Enter. The
framework's `Text.Field.apply` does the editing (the caret, the selection, undo, input methods),
and returns the effects an edit needs, such as a clipboard write for copy:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-type-item" />

## Flows

A **flow** is a goal and a path that reaches it: a list of actions, each naming a move. Lean runs
the path through the machine at compile time and checks two things: that every step is answered
by an enabled move (so the path isn't a run of no-ops), and that the end state meets the goal.

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-flow" />

A witness step names a control: `press ^3`, `press ^4#1`, `edit ^2 (.insert "milk")`,
`submit ^2`. Flows are also what the conformance driver replays against the running app.

## Invariants

An **invariant** is a property that holds in every state the app can reach. You prove it holds
at the start (`init`) and that every move keeps it (`step`). The commands then derive that it
holds in every reachable state, and the runtime theorems carry that onto the screen. The fixture's
says every item's id is below the id the next item gets, so a new item's id is never one already
in the list:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-invariant" />

The `step` proof goes one move at a time: `machine.preserves` splits it, and each move's
generated `preserves` lemma leaves one obligation per handler, stated over that handler's own
`apply`. The lemmas it uses (`add_inv`, `toggle_inv`, `delete_inv`) are ordinary theorems in the
same file. The fixture's machine also hears the world (Flash's timer), so the invariant has a
third clause, `receive`: every message keeps it too. When the invariant is decidable, the command
also makes it a runnable check, which the fuzzer runs after every step.

## Places, assumptions and retired claims

Three more kinds complete the set:

- A **place** is a region of the view where moves appear: a window, a menu, a panel.
- An **assumption** (`assume`) is something the proofs rely on but can't prove, such as "the host
  reports clicks where they happen". It is recorded, never proved, and theorems that rely on it
  take it as a hypothesis, so every use shows.
- A **retired** claim is a tombstone. Its id stays issued forever, with the reason it went.

Every app relies on that one, so Cairn's trusted base declares it, and the host fuzzer gathers its
evidence (`check`):

<bongo:include src="lean/Cairn/Fuzz/Trusted/Claims.lean#trusted-host-clicks" />

A retired claim keeps its kind, its title and the reason it went. Counter, one of the
[example apps](/docs/examples/), retired an invariant its state no longer had anything to say
about: [cairn_examples^6](/packages/cairn_examples/claims/6/).

## Ids are the contract

An id is never renumbered or reused. `claims.lock`, at the root of the repository, records every
id ever issued with a hash of its formal statement, and `make check` fails when an id disappears
without being retired, comes back after it, or changes kind. When a claim's statement changes, the
build warns: a new meaning needs a new id, or an explicit `lake exe ledger update --accept` that
shows up in review.

---
title: Proving a claim
nav: Proving a claim
eyebrow: Building an app · Chapter 4
lede: The proofs an app needs, from a move's one-liner to "Reset is on screen exactly when the count is above zero".
---

A claim's evidence comes at several strengths. The strongest is a proof that Lean's kernel has
checked, using only the three standard axioms. This chapter shows the proofs a small app has, in
the order you meet them.

## The proof a move needs

A move's `sound` clause proves that its handler meets its `post`, for every state (and every key
and text operation) where the move is enabled. For Increment, `apply` adds one and `post` says the
count went up by one, so both sides compute to the same thing and `rfl` closes it:

<bongo:include src="lean/Examples/Counter.lean#counter-increment" />

Most moves are like that: `post` restates `apply` in the terms a reader cares about, and the proof
is `rfl`, a tuple of `rfl`s, or a lemma about the model. When `apply` calls a function with real
logic, prove a lemma about that function next to it and cite it, as Basics does for adding an
item:

<bongo:include src="lean/Examples/Basics.lean#basics-add" />

## Checks you get for free

Flows are proved by evaluation: `decide` runs the witness through the machine at compile time. You
can do the same for any small fact with `example … := by decide`, and the framework's own theorem
`update_unclaimed` gives facts about every input at once:

<bongo:include src="lean/Examples/Counter.lean#counter-checks" />

<bongo:include src="lean/Examples/Counter.lean#counter-unclaimed" />

## Presence: the control is there exactly when the move is enabled

A move's `enabled` says when it is available. Whether its control is actually on screen is a
question about the view, so the app proves it. Counter's says Reset's control is in the view
exactly when Reset is enabled:

<bongo:include src="lean/Examples/Counter/Proofs.lean#counter-presence" />

The framework's layout and frame theorems carry that through to every frame the running app
shows: the accessibility tree of the frame, for any text measurements and any window size.

<bongo:include src="lean/Examples/Counter/Proofs.lean#counter-on-screen" />

## Pressable: a click at its centre presses it

Being in the tree isn't enough: another node could be painted over the control, or it could be
laid out with no size. Hit testing is Lean, so this is a theorem too. For a rigid view
([chapter 3](/docs/guide/view-and-layout/)) the framework reduces it to a condition on the view
alone, `FitsIn`, which Counter proves for any window at least 480 × 256:

<bongo:include src="lean/Examples/Counter/Proofs.lean#counter-pressable" />

The runtime's own theorems take it from there: if the pointer reaches a control at its centre, a
pointer down and up there deliver exactly a press of that control to `update`.

## Invariants

An invariant's proof is the most work in a typical app: `init` for the starting state, then one
obligation per handler, each saying that handler keeps the property. The chapter on
[moves and flows](/docs/guide/moves-and-flows/#invariants) shows the shape; the lemmas behind
Basics' ^105 are about thirty lines of ordinary list reasoning in `lean/Examples/Basics.lean`.

## Runtime checks

Some things are easier to check by running than by proving. `#guard` runs code at compile time;
Counter's tests drive the real runtime, with clicks found by hit testing and frames through the
real byte encoding:

<bongo:include src="lean/Examples/Counter/Tests.lean#counter-tests" />

## The rules

These hold for every proof that counts as evidence, and `make check` enforces them:

- **No `sorry`.** An unfinished proof fails the build.
- **Only the standard axioms**: `propext`, `Classical.choice` and `Quot.sound`. The axiom audit
  looks at every theorem.
- **No escape hatches**: `native_decide`, `bv_decide`, `implemented_by`, `debug.skipKernelTC` and
  `axiom` are rejected by a lint, and every declaration is replayed through the kernel.

What a proof still leaves you to trust, and what the other kinds of evidence add, is on
[How much to trust a claim](/docs/reference/trust/).
For proofs about geometry, `omega` does most of the work, since layout is integers. For bounded
enumerations, `decide +kernel`. For lists of nodes, write recursion structurally: `children.map f`
makes a definition that `rfl` and `decide` can't see through.

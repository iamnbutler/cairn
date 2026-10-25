---
title: Counter
nav: Counter
eyebrow: Example apps
lede: A count, an Increment button, and a Reset button that is there only when there is something to reset.
---

Counter is the smallest complete Cairn app. Every part of the stack is in it: claims, a view,
proofs that reach the screen, runtime tests, a Swift host, a self test and claim pages.
[Your first app](/docs/guide/first-app/) walks through it in order; this page is the reference.

| Id | Kind | What |
|---|---|---|
| ^1 | move | Increment, always enabled |
| ^2 | move | Reset, enabled only when the count is above zero |
| ^3 | place | the window |
| ^4, ^5 | flow | count to three; count up, then reset |
| ^6 | retired | an invariant the runtime made pointless |

Its claims: [Counter window](/packages/cairn/claims/3/).

## The model and its claims

<bongo:include src="lean/Examples/Counter.lean#counter-state" />

<bongo:include src="lean/Examples/Counter.lean#counter-increment" />

<bongo:include src="lean/Examples/Counter.lean#counter-reset" />

<bongo:include src="lean/Examples/Counter.lean#counter-machine" />

<bongo:include src="lean/Examples/Counter.lean#counter-flows" />

## The view

<bongo:include src="lean/Examples/Counter.lean#counter-button" />

<bongo:include src="lean/Examples/Counter.lean#counter-view" />

## What is proved

- Each move does what its claim says (`sound`), and each flow's path is live and reaches its goal.
- A press on anything that isn't ^1 or ^2 changes nothing.
- Reset's control is in the view, in the frame's accessibility tree, and in every frame the
  running app shows, exactly when the count is above zero.
- In any window at least 480 × 256, with any text measurements, a click at the centre of every
  control hits that control.

<bongo:include src="lean/Examples/Counter/Proofs.lean#counter-on-screen" />

## Tests

`#guard` checks that run the real runtime at compile time:

<bongo:include src="lean/Examples/Counter/Tests.lean#counter-tests" />

And the self test, run by `make check`, through the real host and its accessibility mirror:

<bongo:include src="host/Sources/CairnCounter/main.swift#counter-selftest" />

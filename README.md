# Cairn

Research into user interfaces where every thing a person can do is a claim with a durable id,
and every claim carries machine-checked evidence.

A cairn is a stack of stones that marks a trail: placed by hand, built to last, and trusted by
whoever comes next. Here the trails are a product's flows and the stones are claims about them
("pressing ^12 clears the completed items", "^12's button is visible and on top whenever there's
something to clear"), each backed by Lean proofs, model checks and conformance runs against the
real app.

The stack is Lean 4 for state, view, layout, hit testing and proofs; a thin Swift host for the
window, events, text and accessibility; and Metal for painting.

- [cairn.iamnbutler.workers.dev](https://cairn.iamnbutler.workers.dev): the site, with demo videos of
  each step.
- [GOAL.md](GOAL.md): what we are building now, M2: Yap, a dictation app Nate uses every day, rebuilt on Cairn.
- [docs/goals/m1.md](docs/goals/m1.md): M1, a proved TodoMVC on the Mac.
- [docs/architecture.md](docs/architecture.md): how the pieces fit.

MIT licensed.

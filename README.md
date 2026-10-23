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

- [GOAL.md](GOAL.md): the first demo, a proved TodoMVC on the Mac, and what done means.
- [docs/architecture.md](docs/architecture.md): how the pieces fit.

MIT licensed.

# Warrant

Research into user interfaces where every thing a person can do is a claim with a durable id,
and every claim carries machine-checked evidence.

In Toulmin's model of an argument, a claim needs a warrant: the reasoning that licenses it. Here
the claims are about a UI ("pressing ^12 clears the completed items", "^12's button is visible
and on top whenever there's something to clear") and the warrants are Lean proofs, model checks
and conformance runs against the real app.

The stack is Lean 4 for state, view, layout, hit testing and proofs; a thin Swift host for the
window, events, text and accessibility; and Metal for painting.

- [GOAL.md](GOAL.md): the first demo, a proved TodoMVC on the Mac, and what done means.
- [docs/architecture.md](docs/architecture.md): how the pieces fit.

MIT licensed.

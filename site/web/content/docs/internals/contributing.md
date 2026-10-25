---
title: Contributing
nav: Contributing
eyebrow: Internals
lede: The rules every change to Cairn follows, and the one command that checks them.
---

<bongo:note label="Today">
Cairn's repository isn't public yet, so contributions come from the people and agents already
working in it. These are the rules they follow; they will be the rules for everyone when it opens.
</bongo:note>

## The rules

- **No `sorry`, no new axioms.** Every theorem may use only `propext`, `Classical.choice` and
  `Quot.sound`. `make check` audits every theorem's axioms and fails on anything else.
- **Ids are the contract.** Never renumber, reuse or delete a claim id. Retire it instead, with a
  reason. Changing what a claim means needs a new id. The build enforces this with `claims.lock`,
  which only tools write.
- **A pure Lean core.** `update`, `view`, layout, hit testing and encoding are total, pure
  functions. Effects are data the host runs; there is no `IO` below the app boundary.
- **Integers for geometry.** Layout uses whole logical points. No floating point in anything a
  theorem talks about.
- **The host stays thin.** If the Swift host has to decide something about how an app behaves,
  that decision belongs in Lean. Every assumption the host makes is written down in the
  [trusted base](/docs/internals/trusted-base/), with how it is checked.
- **No dependencies** beyond Lean's core and standard library, to keep builds fast.
- **Measure, don't guess.** A performance claim comes with numbers, measured as in
  [profiling against a reference](/docs/internals/profiling/).

## Writing Lean for Cairn

Some of Lean's escape hatches are banned, because each one adds an assumption the axiom audit
can't see or skips a check: `implemented_by`, `native_decide`, `bv_decide`, `axiom` and skipping
the kernel's type check. `make lint` looks for them, and `make kernel` replays every declaration
through Lean's kernel.

- **Pair a specification with fast code.** Write the simple version, write the fast version,
  prove them equal and install the fast one with `@[csimp]`. A `partial def` can't be reasoned
  about, so it can't be in anything a proof needs.
- **Recursion over trees.** Mapping a function over a node's children makes the recursion
  well-founded and stops `rfl` and `decide` from working. Write a structural pair of functions
  instead, and prove things about them together.
- **Bytes.** Write encodings arithmetically over lists of bytes, close round trips with `omega`,
  and bridge to a fast `ByteArray` path once.
- **No `import Lean` in anything the host links.** It makes a small app about 100 MB. Commands and
  elaborators, like the `claims` block, live in modules apps use only at compile time.
- **Tactics.** `omega` for integer geometry; `simp only [...]` and `grind only [...]` in committed
  proofs; `decide +kernel` for bounded enumerations.

## Checking a change

`make check` is the gate. It runs the lint, builds Lean, audits every theorem's axioms, replays
the kernel, checks every claim against `claims.lock`, builds the Swift host and runs its tests,
runs each app's self test, runs a short fuzz of every app and of the trusted base, checks that each app binary stays under its size limit, and checks
that these docs are up to date with the code they include.

<bongo:include src="Makefile#make-check" />

## Changing these docs

These pages are Markdown in `site/web/content/docs`, built by [bongo](https://bongo.build/) with
`make docs`, and `make site` deploys them. Code is never pasted into a page: it is included from
compiled source by a named region, between `region:` and `endregion:` comments, with
`<bongo:include src="path#region" />`, so it can't go stale. If a region moves or disappears,
or a link points at a page or heading that isn't there, `make check` fails until the page is
fixed.

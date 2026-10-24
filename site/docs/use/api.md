---
title: API reference
nav: API reference
eyebrow: Use
lede: Every module, type and declaration in Cairn, and every claim it makes, generated from the code.
---

The API reference is at **[/docs/api/](/docs/api/)**. It is generated, never written by hand:
`cairn doc` run on Cairn itself, the way rustdoc documents a Rust crate
([issue #74](https://github.com/iamnbutler/cairn/issues/74)).

- **An index of modules**, nested by name, with the first sentence of each module's doc comment.
- **A page per module**: its declarations grouped by kind (or in source order), each with its
  signature, its doc comment, its source as `path:line`, and a `proved` chip on theorems.
- **Claims** on the page of the module that declares them, with their formal statement, the
  evidence from the build and their proofs, addressed by their `^N` id. `claims.html` lists them
  all.
- **Search** over names, doc comments and claims; `/` focuses it and `^212` finds a claim.

Anchors don't change while the name doesn't: a declaration's is its full name
(`Cairn.Layout.Core.html#Cairn.Layout.layout`), a claim's its number.

To build the same docs for an app, run `make doc APP=Todo` (output in `build/doc/Todo/dist/`).
`make site-api` regenerates `/docs/api/`. Lean code blocks in doc comments are doc tests: `make
check` compiles them, and a ` ```lean ignore ` block is shown but not checked. The design is in
`docs/doc.md`.

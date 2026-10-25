---
title: API reference
nav: API reference
eyebrow: Reference
lede: Every module, type and declaration in Cairn, and every claim it makes, generated from the code.
---

The API reference is at **[/docs/api/](/docs/api/)**. It is generated, never written by hand:
`cairn doc` run on Cairn itself, the same command an app runs on its own code.

- **An index of modules**, nested by name, with the first sentence of each module's doc comment.
- **A page per module**: its declarations grouped by kind (or in source order), each with its
  signature, its doc comment, its source as `path:line`, and a `proved` chip on theorems.
- **Claims** on the page of the module that declares them, with their formal statement, the
  evidence from the build and their proofs, addressed by their `^N` id. `claims.html` lists them
  all.
- **Search** over names, doc comments and claims; `/` focuses it and `^212` finds a claim.
- **[llms.txt](/docs/api/llms.txt)**: all of it as one Markdown file for a language model, claims and their evidence first.

Anchors don't change while the name doesn't: a declaration's is its full name
(`Cairn.Layout.Core.html#Cairn.Layout.layout`), a claim's its number.

To build the same docs for an app in its own repository, run `cairn doc` there (output in
`build/doc/<name>/`). Inside the Cairn
repository, `make doc APP=Todo` documents an example (output in `build/doc/Todo/dist/`), and
`make site` builds `/docs/api/` from the framework on each deploy. Lean code blocks in doc comments are doc tests: `make
check` compiles them, and a ` ```lean ignore ` block is shown but not checked. The design is in
`docs/doc.md`.

---
title: API reference
nav: API reference
eyebrow: Use
status: todo
lede: Every module, type and declaration in Cairn, and every claim it makes, generated from the code.
---

The API reference will be generated, never written by hand: `cairn doc` run on Cairn itself, the
way rustdoc documents a Rust crate. It will have a page per module, type and declaration, with
signatures and doc comments, and a page per claim with its statement, its proof and the evidence
from the build, addressed by its `^N` id. `cairn doc` is
[issue #74](https://github.com/iamnbutler/cairn/issues/74), and it publishes to
[/docs/api/](/docs/api/), which doesn't exist until it lands.

Until then, the [claims reference](/docs/use/claims/) covers the claim commands, and the Book's
chapters include the definitions they use (`Node`, `Style`, `App`, `Effect`, `Request`, `Sub`)
straight from the source.

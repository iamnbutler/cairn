---
title: Error index
nav: Error index
eyebrow: Use
status: todo
lede: Every error the claim commands and the claim ledger report, with what causes it and how to fix it.
---

This page will list each error you can hit while declaring claims (an id issued twice, a move
without `does`, a flow whose witness isn't live, a retired id coming back), each with a stable
code, an example, and the fix, like `rustc --explain`. Today the errors are plain messages without
codes; the [claims reference](/docs/use/claims/#what-the-build-checks) lists them. Stable codes
belong with the `cairn` tool and per-package claims, in
[issue #75](https://github.com/iamnbutler/cairn/issues/75).

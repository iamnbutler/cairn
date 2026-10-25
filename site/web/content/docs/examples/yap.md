---
title: Yap
nav: Yap
eyebrow: Example apps
lede: Porting a real dictation app to Cairn one to one, with its original as the spec.
---

Yap is a small dictation app for the Mac that its author uses every day: hold a key, talk, and
the transcript is typed into the app in front. It is about 1,500 lines of Swift, and almost all of
it lives outside its window: a global key, the microphone, timers, a network request, files,
sounds, and typing into another app. Its UI is a menu bar menu and an overlay that never takes
focus.

Yap (Cairn) is the same app rebuilt on Cairn. Its state, its decisions and its menus are Lean; the
Swift host captures audio, hears the key, makes the request, writes files and types the text, each
an effect Lean asked for. It reads and writes the original's files, so a person can switch between
the two.

This is the example to read for porting an existing app. It isn't a tutorial: the app is large,
and these sections show the decisions that matter.

Yap is also the first app that lives outside Cairn's repository. It is its own package, `yap-cairn`,
which depends on Cairn `v0.1.0` the way any app would ([release notes](/docs/reference/releases/)). Its claims are `yap^301` to `yap^399`, beside Cairn's own `cairn^N`. Because its
sources are no longer in this repository, this page can't include them yet: the parity table is
`docs/yap-parity.md` and the claims are in `lean/Yap.lean`, both in that package.

## The original is the spec

A port can drift from what it replaces in a hundred small ways: a message worded differently, a
string counted in Unicode scalars instead of characters, a file created with the wrong
permissions. So the port keeps a **parity table**: one row per behaviour of the original, with the
original's source line, what the port does, and a status.

- **same**: the port already did what the original does.
- **fixed**: it didn't, and now does, with a test.
- **bug fix**: the port deliberately differs, because the original is wrong. Each has an issue on
  the original's tracker.
- **open**: a difference that needs a decision.

Where the original leans on a system library for text (how Swift counts characters, how
`NSRegularExpression` folds case), the port was compared against that library directly, on
generated inputs, rather than against its documentation: for example 120,766 strings against
Swift's own character counting, with no mismatches.

The table has 115 rows: 58 the same from the start, 40 fixed to match, 10 deliberate bug fixes,
each with an issue on the original's tracker, and 7 open questions.

## Claims about dictation

The behaviours a person would most hate to get wrong are invariants of the app's machine, proved
over everything the host can report, in any order. A key held as part of a shortcut never sends
(`yap^311`). A transcript is saved before the request that types it is issued, so a failed type
never loses it (`yap^315`; the original saves after typing, and this is one of the bug fixes).
However replies arrive (late, twice, out of order, or never), no clip is typed twice (`yap^318`).

## What's not covered yet

- Yap's map isn't published.
- The parity table's open rows need decisions, chiefly whether the port should replace the
  original outright rather than sit beside it.
- Apps can't yet declare host effects of their own: the effects Yap needed were added to Cairn
  itself ([issue #84](https://github.com/iamnbutler/cairn/issues/84)).
- This page can't include Yap's sources now that they live in their own package
  ([issue #83](https://github.com/iamnbutler/cairn/issues/83)).

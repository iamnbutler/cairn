---
title: Cairn by Example
nav: Cairn by Example
eyebrow: Learn
lede: Four apps read through their source, from two buttons to an app used every day.
---

Counter, Basics and TodoMVC are real apps in Cairn's `lean/Examples/`, each with a Swift
executable in `host/Sources/`, and the samples on their pages are included from that source.
Yap lives in its own repository, `yap-cairn`, and depends on Cairn as a package, so its page
describes its code instead of including it.

| Example | What it shows | Run it |
|---|---|---|
| [Counter](/docs/examples/counter/) | two moves, two flows, presence and pressability proved in every state | `make demo DEMO=CairnCounter` |
| [Basics](/docs/examples/basics/) | a text field, a list with keyed controls, wrapped text, an invariant | `make demo DEMO=CairnBasics` |
| [TodoMVC](/docs/examples/todo/) | the full TodoMVC spec: editing in place, filters, double clicks, focus | `make demo` |
| [Yap](/docs/examples/yap/) | porting a real menu bar app one to one: effects, surfaces, a parity audit | `make yap`, in its own package |

Two more apps in the repository aren't written up yet: **Clock**, a stopwatch that is the example
for effects (the Book's [effects chapter](/docs/book/effects/) uses it), and **Tray**, a menu bar
item with an overlay panel, the example for surfaces.

Counter, Basics and TodoMVC each have a published [map](/docs/evidence/): every claim, its
evidence, and screenshots.

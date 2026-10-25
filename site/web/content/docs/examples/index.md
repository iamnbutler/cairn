---
title: Example apps
nav: Example apps
eyebrow: Guides
lede: Six apps built on Cairn, from two buttons to a gallery, and Yap, an app used every day.
---

The example apps are one package of their own, `cairn_examples`, which requires Cairn from the
registry the way any app does. Its claims are `cairn_examples^N`, with the numbers they had when
the apps were in Cairn's repository: TodoMVC's new-todo field, once `cairn^202`, is
`cairn_examples^202`. Cairn 0.3.0 removed them from its repository
([#137](https://github.com/iamnbutler/cairn/issues/137)); the framework's own checks run on
`test/fixture` instead, which [the guide](/docs/guide/) walks through.

See the package's [versions and how to depend on it](/packages/cairn_examples/), all its
[claims](/packages/cairn_examples/claims/), and its
[API docs](https://cairn.iamnbutler.workers.dev/docs/cairn_examples/0.1.1/) (a placeholder until
the registry builds docs).

| App | What it shows | Claims |
|---|---|---|
| Counter | two moves, two flows, presence and pressability proved in every state, a retired claim | [^1–^6](/packages/cairn_examples/claims/3/) |
| Basics | a text field, a list with keyed controls, wrapped text, an invariant | [^101–^109](/packages/cairn_examples/claims/106/) |
| TodoMVC | the full TodoMVC spec: editing in place, filters, double clicks, focus | [^201–^225](/packages/cairn_examples/claims/201/) |
| Clock | effects: time, timers, files, subscriptions | [^401–^409](/packages/cairn_examples/claims/406/) |
| Tray | a menu bar item with native menus and an overlay panel | [^450–^462](/packages/cairn_examples/claims/450/) |
| Gallery | images, loads in flight, a grid that fits every window size | [^501–^513](/packages/cairn_examples/claims/503/) |

Each app is an executable of the package, `Cairn<App>`: `cairn build --app <App>`, then
`swift run Cairn<App>`, in a checkout of it.

[Yap](/docs/examples/yap/) is a real menu bar app ported one to one: effects, surfaces, a parity
audit. It lives in its own package, `yap-cairn`.

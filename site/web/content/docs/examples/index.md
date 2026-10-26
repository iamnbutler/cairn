---
title: Apps on Cairn
nav: Apps on Cairn
eyebrow: Guides
lede: The example apps, Pairs, Sky and Yap, each a package of its own with its claims on the registry.
---

None of these apps is in Cairn's repository. Each is a package that requires Cairn from the
registry the way any app does, with claims scoped by its own name, and its claim pages are
generated from what it published. The framework's own checks run on `test/fixture` instead,
which [the guide](/docs/guide/) walks through.

| Package | What it is | Claims |
|---|---|---|
| [`cairn_examples`](/packages/cairn_examples/) | six small apps, below, each showing one part of Cairn | [cairn_examples^N](/packages/cairn_examples/claims/) |
| [`pairs`](/packages/pairs/) | a memory game whose decks are packs of images loaded from a folder or a URL ([M3](/milestones/#third-milestone-pairs)) | [pairs^N](/packages/pairs/claims/) |
| [`sky`](/packages/sky/) | a Bluesky reader: sign in with an app password, the session in the Keychain, the home feed in a virtual list with paging and refresh ([M4](/milestones/#fourth-milestone-sky-reads-bluesky)) | [sky^N](/packages/sky/claims/) |
| [`cairn_atproto`](/packages/cairn_atproto/) | a library, not an app: XRPC, Bluesky's session calls and timeline, and the session machine Sky signs in with | [cairn_atproto^N](/packages/cairn_atproto/claims/) |
| [`yap`](/packages/yap/) | a dictation app used every day, ported one to one ([below](/docs/examples/yap/)) | [yap^N](/packages/yap/claims/) |

## The example apps

The example apps are one package, `cairn_examples`. Their claims kept the numbers they had when
the apps were in Cairn's repository, before 0.3.0: TodoMVC's new-todo field, once `cairn^202`,
is `cairn_examples^202`.

| App | What it shows | Claims |
|---|---|---|
| Counter | two moves, two flows, presence and pressability proved in every state, a retired claim | [\^1–^6](/packages/cairn_examples/claims/3/) |
| Basics | a text field, a list with keyed controls, wrapped text, an invariant | [\^101–^109](/packages/cairn_examples/claims/106/) |
| TodoMVC | the full TodoMVC spec: editing in place, filters, double clicks, focus | [\^201–^225](/packages/cairn_examples/claims/201/) |
| Clock | effects: time, timers, files, subscriptions | [\^401–^409](/packages/cairn_examples/claims/406/) |
| Tray | a menu bar item with native menus and an overlay panel | [\^450–^462](/packages/cairn_examples/claims/450/) |
| Gallery | images, loads in flight, a grid that fits every window size | [\^501–^513](/packages/cairn_examples/claims/503/) |

Each app is an executable of the package: in a checkout of it, `cairn build --app <App>`, then
`swift run Cairn<App>`.

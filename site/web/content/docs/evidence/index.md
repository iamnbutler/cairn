---
title: Claims
nav: Claims
eyebrow: Evidence
lede: Everything a person can do in a Cairn app is a claim, with an id that never changes, a promise, and a proof that the promise holds in every state.
wide: true
css: /claims/claims.css
module: /claims/page.js
---

A claim isn't a test that passed once. It is a statement Lean checks for every state the app can
be in, under an id that tests, docs, reviews and agents can cite. Here is one running.

<!-- figure: replay -->

Each step of that run is a move with its own id, and each move promises what follows, in words
for people and in a statement for Lean. The flow, ^216, is a claim too: Lean checks that every
step is offered when it's taken and that the goal holds at the end. Change the app so that any of
it stops being true, and it doesn't build.

## What's in one

Here is the whole of Reset, in Counter. The two lines in green are for people; everything under
them, in gold, is for the checker.

<!-- figure: anatomyFull -->

## What they buy you

### Every state, not one run

A test drives the app down one path and checks where it lands. A claim's proof is about every
state at once, including the ones nobody thought to try.

<!-- figure: stateField -->

### Nothing happens without one

<!-- figure: gate -->

An app's update is built only from its moves, so this holds for every Cairn app, proved once in
the framework. Every effect an app asks for (a file write, a sound, a timer) comes from some move
(`update_effect`). The list of claims is the list of what the app can do, with nothing hiding
outside it.

### One name, everywhere

The id is how everything else refers to the behaviour, and it means the same thing in all of
them:

<!-- figure: names -->

A `data-testid` names an element and drifts when someone renames it. `^204` names a behaviour
and can't be renamed: tests, docs, agents and bug reports that cite it stay right for as long as
the app exists.

### Meaning changes show up in review

Each package keeps a ledger of every id it has issued. A refactor that changes no promise passes
quietly; one that changes what a claim says is flagged, and has to take a new id or be accepted
in a commit someone reviews.

<!-- figure: ledger -->

A released claim is a promise to whoever relies on it, so retiring one needs a major version:
semver for guarantees, checked by the build. [Claims](/docs/reference/claims/) has the ledger's
rules.

## Six kinds

Moves are what people do. The other five say how moves fit together, what always holds, and what
is taken on trust.

<!-- figure: kinds -->

## How sure we are

Each claim carries the evidence it has, not only the strongest. They rule out different things:

<!-- figure: rungs -->

A proof still trusts that its statement says what you mean: `post s' := True` is easy to prove
and promises nothing. [How much to trust a claim](/docs/reference/trust/) says what each kind of
evidence still takes on faith, with a bug the tests miss and the proof catches, and
[the evidence ladder](/docs/reference/evidence/) says how the build computes them.

## Every claim, on its own page

Every package on the registry has claim pages: each version's claims, grouped by the place
(window) they belong to, and a page for each claim with what you do and see, a flow's steps, its
evidence theorems and where it's defined. They are rendered from the claims export that
`cairn publish` sends with each version, checked by the registry against the version's
`claims.lock`. Nothing on them is written by hand. You can also
[click through Todo's states](/try/todo/), every control labelled with its claim.

| Place | What it covers |
|---|---|
| [The trusted base](/packages/cairn/claims/#assumptions) | the host's assumptions, cairn^7, cairn^214, ^9xx and ^10xx |
| [Counter](/packages/cairn_examples/claims/3/) | cairn_examples^1–^6: two moves, two flows and a retired claim |
| [Basics](/packages/cairn_examples/claims/106/) | cairn_examples^101–^109: a field, a keyed list and an invariant |
| [TodoMVC](/packages/cairn_examples/claims/201/) | cairn_examples^201–^226: the full TodoMVC spec |
| [Clock](/packages/cairn_examples/claims/406/) | cairn_examples^401–^409: time, timers and files |
| [Tray](/packages/cairn_examples/claims/450/) | cairn_examples^450–^462: a menu bar item, a submenu and an overlay panel |
| [Gallery](/packages/cairn_examples/claims/503/) | cairn_examples^501–^513: images and a grid that fits the window |
| [Pairs](/packages/pairs/claims/1/) | pairs^1–^32: a deal of the pack, two cards up at most, and every game can be won |
| [Sky](/packages/sky/claims/1/) | sky^1–^36: sign in, the session, and a feed with no duplicates or gaps however its pages and refreshes race |
| [cairn_atproto](/packages/cairn_atproto/claims/) | cairn_atproto^1–^16: the session machine, one refresh at a time, each call sent at most twice |
| [Yap](/packages/yap/claims/301/) | yap^301–^399: a menu bar menu, an overlay and the dictation machine |

The pages show the evidence the export holds: proofs and their axioms, assumptions, flow
witnesses, retired and moved ids. Fuzzing, conformance and screenshots need a build that runs
the app, and a claim lists them as not shown yet until CI publishes them. A version published
before the export existed shows its ledger alone.

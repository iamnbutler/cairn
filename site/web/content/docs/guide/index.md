---
title: Building an app
nav: Building an app
eyebrow: Guides
lede: Building an app in Cairn, one chapter at a time, for someone who has never seen it.
---

This guide walks through one idea at a time, mostly on Cairn's own test app, `test/fixture` in
the repository: a list with a text field, a checkbox and a delete button per item, and a Flash
button that sets a timer. Every code sample is the real source, included by the docs build, so
what you read is what compiles. The [example apps](/docs/examples/) go further.

You will need to read some Lean 4. You don't need to be good at proofs: most of the proofs an app
needs are one line, and the guide shows where the longer ones come from.

## Chapters

1. [Your first app](/docs/guide/first-app/): what a Cairn app is made of, running the fixture,
   and starting an app of your own.
2. [Moves and flows](/docs/guide/moves-and-flows/): declaring what a person can do, and the paths
   through it.
3. [The view and layout](/docs/guide/view-and-layout/): what the app shows, as a tree of boxes
   laid out in whole points.
4. [Proving a claim](/docs/guide/proving/): the proofs a move needs, and the ones that reach the
   screen.
5. [Effects and the host](/docs/guide/effects/): time, timers, files and other requests, and
   subscriptions.
6. [Shipping](/docs/guide/shipping/): checking, bundling and signing an app, and publishing it.

## What Cairn is for

Most UI frameworks let you say what an app looks like. Cairn also asks you to say what it does,
in a form a machine can check. Pressing an item's delete button, `^5`, means "the item is gone,
and its checkbox and delete button with it": that sentence sits in the source next to a Lean
statement of it and a proof, and the app doesn't compile without the proof. The id `^5` means
Delete for as long as the app exists, so a bug report, a test or a review can cite it.

To make those claims mean something, the code they talk about has to be the code that runs. So
everything a person can observe is computed in Lean, and the Swift host only carries events in
and pixels out.

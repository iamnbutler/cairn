---
title: The Cairn Book
nav: The Cairn Book
eyebrow: Learn
lede: A guide to building an app in Cairn, for someone who has never seen it.
---

The Book walks through one idea at a time, mostly on two small apps from the repository: Counter,
a count with an Increment and a Reset button, and Clock, a stopwatch that talks to the outside
world. Every code sample is the real source, included by the docs build, so what you read is what
compiles.

You will need to read some Lean 4. You don't need to be good at proofs: most of the proofs an app
needs are one line, and the Book shows where the longer ones come from.

## Chapters

1. [Your first app](/docs/book/first-app/): what a Cairn app is made of, running Counter, and
   adding an app of your own today.
2. [Moves and flows](/docs/book/moves-and-flows/): declaring what a person can do, and the paths
   through it.
3. [The view and layout](/docs/book/view-and-layout/): what the app shows, as a tree of boxes
   laid out in whole points.
4. [Proving a claim](/docs/book/proving/): the proofs a move needs, and the ones that reach the
   screen.
5. [Effects and the host](/docs/book/effects/): time, timers, files and other requests, and
   subscriptions.
6. [Shipping](/docs/book/shipping/): checking, bundling and signing an app, and publishing its
   map.

## What Cairn is for

Most UI frameworks let you say what an app looks like. Cairn also asks you to say what it does,
in a form a machine can check. Pressing `^2` in Counter "sets the count to zero, and Reset
disappears": that sentence sits in the source next to a Lean statement of it and a proof, and the
app doesn't compile without the proof. The id `^2` means Reset for as long as the app exists, so
a bug report, a test or a review can cite it.

To make those claims mean something, the code they talk about has to be the code that runs. So
everything a person can observe is computed in Lean, and the Swift host only carries events in
and pixels out.

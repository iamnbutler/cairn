---
title: Writing host effects
nav: Writing host effects
eyebrow: Master
lede: How a new kind of request reaches the host, and what it takes to trust the answer.
---

An app asks the outside world for something by returning a **request** effect with an id it
chooses. The host runs it and sends back exactly one **reply** under that id. The
[effects chapter](/docs/book/effects/) shows the app's side. This page is about the other side:
adding a new kind of request to Cairn itself.

:::note Today
Apps can't declare their own effects yet. The set of requests is fixed by Cairn, and adding one
means changing Cairn: the Lean types, the encoding and the Swift host, as below. Letting an app
bring its own effects is part of the planned `cairn` tool's work
([#75](https://github.com/iamnbutler/cairn/issues/75)).
:::

## The pieces

A request is a constructor of `Request`. Each one has a kind, and the kind decides which replies
can answer it:

<!-- include lean/Cairn/Effects.lean#effects-request -->

<!-- include lean/Cairn/Effects.lean#effects-reply -->

`Reply.answers` is what the runtime uses to keep its promise to the app. It keeps a table of
pending ids and their kinds, and it delivers a reply only when the id is pending and the reply has
a shape that answers that kind; `failed` answers anything. A duplicate, late or misshapen reply is
dropped. This is proved, whatever the host sends, so the app sees each request answered at most
once, with a reply of the right shape.

On the host, each kind has one handler in a table, keyed by the kind's code:

<!-- include host/Sources/CairnHost/World.swift#world-handlers -->

A handler runs on a global queue and calls `reply` once. The callback is guarded, so a second
answer is ignored; a kind with no handler is answered `failed invalid`. Handlers must not call
Lean. When the app restarts, answers to earlier requests are dropped and every subscription
stops. Tests swap the table: Clock's self test sends files to a scratch directory and plays no
sound.

## Adding a kind of request

1. **The constructor.** Add it to `Request` in `lean/Cairn/Effects.lean`, with its `Kind`, and
   add the cases of `Reply.answers` that answer it. If no existing reply fits, add a `Reply`
   constructor too.
2. **The encoding.** Give it a record in the frame encoder (`lean/Cairn/Frame/Encode.lean`) and,
   for a new reply, in the event encoder (`lean/Cairn/Frame/Events.lean`). Extend the round-trip
   proofs; they close with `omega` once the new case is written arithmetically. Add it to the
   canonical dump, which the corpus compares.
3. **The Swift mirror.** Add the case to the Swift model and decoder in `host/Sources/CairnFrame`,
   and to the debug JSON the conformance driver reads.
4. **The handler.** Write it, and add it to `Handlers.standard`. Keep it to doing what was
   asked and reporting what happened: anything that decides app behaviour belongs in Lean.
5. **The assumption.** The handler is trusted code, so state what it promises as an `assume`
   claim, write a fuzz check that gathers evidence for it, and add an entry to the
   [trusted base](/docs/master/trusted-base/). Say what it does on bad input: empty strings, NUL,
   names the file system refuses, a network that never answers.

`make check` then runs the round trips, the corpus and a short fuzz of the new check.

## What makes a good host effect

- **Failure is a reply.** A missing file, a refused permission or a timeout is `failed` with a
  fault and a message, never a missing reply. An HTTP 500 is not a failure: it is a reply with
  status 500, and the app decides.
- **The app chooses the id**, so it can tell a late answer to an old request from a new one.
- **Fake the device.** A handler that touches hardware or other apps (the microphone, the
  keyboard, typing into another app) takes its device as a parameter, so the fuzz suite and the
  self tests run against fakes and `make check` never records audio or types anywhere.
- **Ask for permission explicitly.** A request that needs a macOS permission fails with
  `failed denied` without it. Whether to prompt is a separate request the app makes on purpose.

## Subscriptions

An ongoing input, like a repeating timer, a file watch, recording or a global key, is a
**subscription** rather than a request. The app returns the set it wants after each step; the
runtime works out what to start and stop, and the host sends events tagged with the
subscription's id. Adding a kind follows the same steps: a `Sub` constructor, its command
encoding, its events, a handler in the host's world, and an assumption with a fuzz check.

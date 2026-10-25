---
title: Effects and the host
nav: Effects and the host
eyebrow: Building an app · Chapter 5
lede: Time, timers, files, sounds and the network, without a line of IO in the app.
---

A Cairn app never performs an effect. It returns effects as **data**, and the host performs them.
What the host learns comes back as messages, decoded by a proved decoder. That keeps every
function in the app pure, so everything in the previous chapters still applies.

This chapter follows the fixture's Flash button, which sets a timer and hears it fire, and the
framework's own types for the rest. Clock, in the [example apps](/docs/examples/), is a stopwatch
with Start, Lap, Reset, and Save and Load buttons that write the laps to a file and read them back;
it uses all of it ([its claims](/packages/cairn_examples/claims/406/)).

## Two ways in

A person's actions arrive through `update`, as before: every one names a control on screen.
Everything else, the clock, timers, replies to requests and outside inputs, arrives through a
second function, `receive`, as a **message**.

<bongo:include src="lean/Cairn/Effects.lean#effects-msg" />

Both return the new state and a list of effects:

<bongo:include src="lean/Cairn/Input.lean#input-effect" />

Keeping the two apart is what lets every claim theorem keep saying "every action names a control":
messages from the world name none.

## Time

The host stamps every batch of events with the time, and the app hears it first, before any action
or message in that batch. So an app that stores the time always has the current time when any of
its functions run, including when a button is pressed. Clock keeps it in its state, from the
`clock` message, to show the time since Start.

The monotonic clock never goes backwards in the runtime, whatever the host sends; that is a
theorem, not a promise.

## Timers

An app sets a named timer with `setTimer name ms` and cancels it with `cancelTimer name`. The
timers are kept by the runtime, in Lean, and the host's only job is to wake it at the earliest
deadline. So "a cancelled timer never fires" is proved, with no race between a host timer that
already fired and a cancel on its way. The fixture's timer is named, with how long the note shows:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-flash-timer" />

Flash sets it. A move that asks for effects uses `emit` instead of `apply`: the new state, and the
effects:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-flash" />

When the timer comes due, `receive` hears it by name and takes the note down:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-receive" />

## Requests

A request asks the host to do something that answers back: read or write a file, play a sound,
make an HTTP request, and more. The app picks the request's id, and the reply comes back to
`receive` under that id, exactly once. Failure is an ordinary reply: a missing file is
`failed notFound`, never an exception. The request kinds, today:

<bongo:include src="lean/Cairn/Effects.lean#effects-request" />

The runtime keeps a table of pending requests and delivers a reply only to a pending id, in a
shape that answers its kind. A duplicate, late or misshapen reply is dropped before the app sees
it. Clock's Save asks for a `writeFile` and its Load a `readFile`, and its `receive` takes the
`done` and the `bytes` that come back:

<bongo:include src="lean/Cairn/Effects.lean#effects-reply" />

## Subscriptions

Some inputs keep coming: a tick every second, a file that changes, the microphone, a global key.
An app doesn't start and stop them. It says which ones it wants in each state, and after every
step the runtime starts exactly the new ones and stops exactly the ones no longer wanted. An event
from a stopped subscription never reaches the app, however late it arrives.

<bongo:include src="lean/Cairn/Effects.lean#effects-sub" />

## Putting it together

The machine gains its `receive`:

<bongo:include src="test/fixture/lean/Fixture.lean#fixture-machine" />

`toApp` carries it into the `App`, which also has the app's subscriptions and the effects to run
at launch, once the clock is known. The fixture has neither. Clock sets both on what `toApp`
returns: a tick every second, and a `readFile` of its saved laps at launch.

<bongo:include src="lean/Cairn/App.lean#app-app" />

## Proving things about the world

Claims about the outside world are proved the same way. An invariant of a machine with `receive`
has a third clause, `receive`, proving the property is kept by every message too. It then holds
whatever the host sends, in any order with the person's actions. The fixture's ^7 has one: the
timer's message changes nothing it talks about
([chapter 2](/docs/guide/moves-and-flows/#invariants)). Clock's
[cairn_examples^409](/packages/cairn_examples/claims/409/) says pending requests always have ids
below the next one, so a reply to a later request is never taken for an earlier one, and Clock
proves that a tick arriving after Stop changes nothing.

## What the host promises

Each kind of effect is an **assumption**, an `assume` claim saying what the host does ("writeFile
is atomic, and replies done only when the bytes are there"), checked by a fuzzer against the real
host. They are listed on the [trusted base](/docs/internals/trusted-base/) page, and
[writing host effects](/docs/internals/host-effects/) covers adding one.

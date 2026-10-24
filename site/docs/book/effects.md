---
title: Effects and the host
nav: Effects and the host
eyebrow: The Cairn Book · Chapter 5
lede: Time, timers, files, sounds and the network, without a line of IO in the app.
---

A Cairn app never performs an effect. It returns effects as **data**, and the host performs them.
What the host learns comes back as messages, decoded by a proved decoder. That keeps every
function in the app pure, so everything in the previous chapters still applies.

This chapter follows Clock, a stopwatch with Start, Lap, Reset, and Save and Load buttons that
write the laps to a file and read them back. Run it with `make demo DEMO=CairnClock`.

## Two ways in

A person's actions arrive through `update`, as before: every one names a control on screen.
Everything else, the clock, timers, replies to requests and outside inputs, arrives through a
second function, `receive`, as a **message**.

<!-- include lean/Cairn/Effects.lean#effects-msg -->

Both return the new state and a list of effects:

<!-- include lean/Cairn/Input.lean#input-effect -->

Keeping the two apart is what lets every claim theorem keep saying "every action names a control":
messages from the world name none.

## Time

The host stamps every batch of events with the time, and the app hears it first, before any action
or message in that batch. So an app that stores the time always has the current time when any of
its functions run, including when a button is pressed. Clock keeps it in its state:

<!-- include lean/Examples/Clock.lean#clock-state -->

The monotonic clock never goes backwards in the runtime, whatever the host sends; that is a
theorem, not a promise.

## Timers

An app sets a named timer with `setTimer name ms` and cancels it with `cancelTimer name`. The
timers are kept by the runtime, in Lean, and the host's only job is to wake it at the earliest
deadline. So "a cancelled timer never fires" is proved, with no race between a host timer that
already fired and a cancel on its way. Start and Stop:

<!-- include lean/Examples/Clock.lean#clock-startstop -->

<!-- include lean/Examples/Clock.lean#clock-startstop-move -->

## Requests

A request asks the host to do something that answers back: read or write a file, play a sound,
make an HTTP request, and more. The app picks the request's id, and the reply comes back to
`receive` under that id, exactly once. Failure is an ordinary reply: a missing file is
`failed notFound`, never an exception.

<!-- include lean/Examples/Clock.lean#clock-save -->

The runtime keeps a table of pending requests and delivers a reply only to a pending id, in a
shape that answers its kind. A duplicate, late or misshapen reply is dropped before the app sees
it. Clock's `receive` handles the time, its tick, and the replies to its save and load:

<!-- include lean/Examples/Clock.lean#clock-receive -->

The request kinds, today:

<!-- include lean/Cairn/Effects.lean#effects-request -->

## Subscriptions

Some inputs keep coming: a tick every second, a file that changes, the microphone, a global key.
An app doesn't start and stop them. It says which ones it wants in each state, and after every
step the runtime starts exactly the new ones and stops exactly the ones no longer wanted. An event
from a stopped subscription never reaches the app, however late it arrives.

<!-- include lean/Cairn/Effects.lean#effects-sub -->

## Putting it together

The machine gains its `receive`, and the app its subscriptions and the effects to run at launch,
once the clock is known:

<!-- include lean/Examples/Clock.lean#clock-machine -->

<!-- include lean/Examples/Clock.lean#clock-app -->

## Proving things about the world

Claims about the outside world are proved the same way. Here, a tick that arrives after Stop
changes nothing:

<!-- include lean/Examples/Clock.lean#clock-stopped-tick -->

An invariant of a machine with `receive` has a third clause, `receive`, proving the property is
kept by every message too. It then holds whatever the host sends, in any order with the person's
actions. Clock's ^409 says pending requests always have ids below the next one, so a reply to a
later request is never taken for an earlier one.

## What the host promises

Each kind of effect is an **assumption**, an `assume` claim saying what the host does ("writeFile
is atomic, and replies done only when the bytes are there"), checked by a fuzzer against the real
host. They are listed on the [trusted base](/docs/master/trusted-base/) page, and
[writing host effects](/docs/master/host-effects/) covers adding one.

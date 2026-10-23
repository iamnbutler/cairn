# Effects: time, requests, subscriptions

M1's apps lived inside one window: every input was a person's move and every effect was a
clipboard write or a beep. M2's Yap lives almost entirely outside it: a global key, the
microphone, timers, a network request, files, sounds and typing into another app. This document
is how the framework, not the app, talks to the outside world. GOAL.md, "Done means" item 2.

The rule stays the one in AGENTS.md: **Swift performs effects, Lean decides.** Everything the
host does is asked for by a value Lean computed, and everything it learns comes back as an
event Lean decodes with a proved decoder. No `IO` below the app boundary.

| Piece | Where |
|---|---|
| Types: `Time`, `Request`, `Reply`, `Fault`, `Sub`, `SubEvent`, `Msg` | `lean/Cairn/Effects.lean` |
| `Effect` (grows `setTimer`, `cancelTimer`, `request`), `Event` (grows `clock`, `reply`, `subEvent`) | `lean/Cairn/Input.lean` |
| `App.receive`, `App.subscriptions`, `App.initEffects` | `lean/Cairn/App.lean` |
| The runtime's world: clock, timers, pending requests, active subscriptions | `lean/Cairn/Runtime/World.lean` |
| Delivery and `step` | `lean/Cairn/Runtime/Step.lean` |
| Theorems | `lean/Cairn/Runtime/WorldProofs.lean` |
| Wire format | [frame.md](frame.md) (frame v2, new event tags), `lean/Cairn/Frame/{Encode,Events}.lean` |
| Host: clock, wake, the handler table, subscriptions | `host/Sources/CairnHost/World.swift`, `Engine.swift` |
| Example | `lean/Examples/Clock.lean`, `host/Sources/CairnClock` |
| Trusted claims ^908–^915 | `lean/Cairn/Fuzz/Trusted/Claims.lean`, [trusted.md](trusted.md) |

## The app's side

```lean
structure App (S : Type) where
  init : S
  view : S → UI → Node
  update : S → Action → S × List Effect          -- a person's moves (unchanged)
  receive : S → Msg → S × List Effect := ...      -- the outside world (default: ignore)
  subscriptions : S → List Sub := fun _ => []     -- outside inputs, as data (default: none)
  initEffects : List Effect := []                 -- effects to run once the clock is known
  claims : List ClaimInfo
  initFocus : Option ControlRef := none
```

`update` is untouched: it still sees only `Action`s, every one naming a control, so the claim
machinery (`move`, `dispatch`, flows, invariants) and every M1 app work as before. The outside
world arrives through a second function, `receive`, as a `Msg`:

```lean
inductive Msg where
  | clock (t : Time)               -- the time, before anything else is delivered (below)
  | timer (name : String)          -- a timer the app set has come due
  | reply (id : Nat) (r : Reply)   -- the answer to the app's request `id`
  | sub (s : Sub) (e : SubEvent)   -- an event from an active subscription
```

Both return effects, and the runtime treats the effects of either the same way.

Why two functions and not one `Msg` type wrapping `Action`: the claim language is built on
"every action names a control" (`Action.control`, `dispatch_unclaimed`, the map). Messages from
the world name no control. Folding them into `Action` would make every one of those theorems
carry a side condition. Keeping them apart costs one more field with a default. A claim kind
for messages ("when a reply arrives, …") is future work: today `receive` is ordinary Lean that
apps prove things about directly, as P's Yap machine does.

## Time

**Decision: the clock arrives on every event, and the app hears it before anything else.**

- The host stamps every batch: its first event is `clock t`, and the host sends a `clock`
  event before any later event in the batch whose arrival time differs by a millisecond or
  more. So the runtime's time is the time the input arrived, not the time Lean got to it.
- `Time` is `{ mono : Nat, wall : Int, zone : Int }`: monotonic milliseconds (Darwin's
  `CLOCK_MONOTONIC`, which counts sleep), wall-clock milliseconds since the Unix epoch, and the
  local offset from UTC in seconds. `mono` is what timers and durations use; `wall` and `zone`
  are for dates (Yap's "today's transcripts file", retention). The runtime keeps
  `mono := max old new`, so its clock never goes back whatever the host sends (proved,
  `tick_mono`). `wall` can jump; nothing in the runtime reads it.
- The runtime delivers `Msg.clock t` to `receive` **lazily**: immediately before the first
  delivery (action or message) after the clock changed. An app that stores the time therefore
  always has the current time when any `update` or `receive` runs, including a button press
  (a stopwatch's Start reads `s.now`). A clock event that delivers nothing else (no timer due)
  delivers nothing at all and does not re-run `view`, so idle input stays as cheap as in M1.
- There are no tick events from the host for their own sake. An app that wants to redraw as
  time passes asks for it: a timer, or the `every` subscription.

Both: time on every event (lazily heard), and periodic ticks when the app subscribes to them.

### Timers

```lean
| setTimer (name : String) (ms : Nat)   -- (re)start `name`, due at now + ms
| cancelTimer (name : String)           -- forget `name`; nothing if it isn't set
```

Timers are the runtime's, not the host's. The runtime keeps a table `name ↦ due` and the frame
carries one number, `wake`: the earliest due time, if any. The host's only job is to send a
`clock` event no later than `wake` (it waits on a deadline on the Lean thread). When a clock
event arrives, the runtime fires every timer due at the new time, earliest first (ties in the
order they were set), **re-checking the table before each one**: a timer whose handler cancels
or re-sets another due timer stops that one from firing. A timer is removed from the table
before it is delivered, so it fires once. Timers set during a firing wait for the next clock
event, even with `ms = 0` (`wake` is then in the past, so the host wakes at once), so one event
does a bounded amount of work.

Because the table is in Lean, cancellation is exact: there is no race between a host timer that
already fired and a cancel on its way. "A cancelled timer never fires" is a theorem, not a host
property (below).

Names are strings so an app can keep one timer per purpose (`"autostop"`, `"clearStatus"`);
setting a name that is set restarts it.

## Requests

```lean
| request (id : Nat) (r : Request)      -- an Effect; answered by `Msg.reply id _`

inductive Request where
  | readFile (path : String)
  | writeFile (path : String) (data : ByteArray)     -- atomic
  | playSound (name : String)
  | http (method url : String) (headers : List (String × String)) (body : ByteArray)
      (timeoutMs : Nat)

inductive Reply where
  | done                                              -- writeFile, playSound
  | bytes (data : ByteArray)                          -- readFile
  | http (status : Nat) (headers : List (String × String)) (body : ByteArray)
  | failed (fault : Fault) (message : String)          -- any request

inductive Fault where
  | notFound | denied | timeout | network | invalid | other
```

- **The app chooses the id.** It is how the app matches a reply to what it asked; Yap will use
  a clip's sequence number, so a late reply for an old clip is recognisably old.
- **Failure is a reply.** Every request gets exactly one reply; a missing file, a refused
  permission, an HTTP error transport or a timeout is `failed fault message`. An HTTP status
  of 404 or 500 is not a failure: it is `http 500 …`, and the app decides.
- **The runtime keeps the pending table** `id ↦ kind`. A request whose id is already pending is
  refused: it is not put on the frame (so the host never sees it) and gets no reply. A reply is
  delivered only if its id is pending and its shape answers that kind (`Reply.answers`: `bytes`
  answers `readFile`, `done` answers `writeFile` and `playSound`, `http` answers `http`,
  `failed` answers anything); the id leaves the table as it is delivered. So the app sees each
  request answered at most once, with the id it asked with and a reply of the right shape,
  whatever the host sends (proved, `reply_delivers`, `reply_once`). A duplicate or misshapen
  reply is dropped.
- **Paths** are strings the host uses as given, except that a leading `~/` is the user's home
  directory. `writeFile` creates missing parent directories and replaces the file atomically
  (write to a temporary file in the same directory, then rename), so a reader sees the old
  bytes or the new ones, never a mix.
- **Sounds** are named system sounds (`NSSound(named:)`: "Tink", "Pop", "Basso", …). The reply
  is `done` once the sound has started, or `failed notFound` for an unknown name.
- **HTTP** is `URLSession` with the given method, headers, body and timeout; the reply carries
  the status, the response headers (names as the server sent them, in the order Foundation
  gives them) and the body. The host follows redirects (Foundation's default) and keeps no
  cookies or cache (an ephemeral session).

### The host side is a table

`host/Sources/CairnHost/World.swift` has one handler per request kind, each a function from the
request to a reply, run off the main thread; the reply goes back through `Engine.send` as a
`reply` event. Adding a kind is a constructor in `Request`, its encoding (with the round-trip
proof extended), a `Reply.answers` case, and one handler. Each handler is an `assume` claim
with a fuzz check (below).

### What Yap needs next, and where it slots in

| Need | Shape | Status |
|---|---|---|
| Transcribe | `http` (multipart body built in Lean) | implemented as `http` |
| Read and write files, config, transcripts | `readFile`, `writeFile` | implemented |
| Sounds | `playSound` | implemented |
| Type text into the front app | `request id (.typeText s)`, reply `done` / `failed denied` | designed, not built |
| Record the microphone | `request id (.record maxMs)` answered when recording stops with `bytes` (the encoded clip) or `failed`; stop with `request id' (.stopRecording)`; levels as a subscription | designed, not built |
| The global key | `Sub.globalKey key` with `SubEvent.keyDown/keyUp/otherKey` | designed, not built |
| Microphone levels | `Sub.micLevel ms` with `SubEvent.level n` | designed, not built |
| `config.json` live reload | `Sub.watchFile path` with `SubEvent.changed` | designed, not built |

Audio bodies: a 10-minute clip is a few MB. Passing it through Lean costs a copy each way and
the event decoder runs the list specification (a few hundred ns a byte); if that shows up in
the key-up-to-text benchmark, the decoder gets a `ByteArray` fast path proved equal to the
specification, as the frame encoder has.

## Subscriptions

```lean
subscriptions : S → List Sub

inductive Sub where
  | every (ms : Nat)        -- a tick every `ms` milliseconds (at least 1)
inductive SubEvent where
  | tick
```

Subscriptions are data derived from state, as in Elm. After every step that delivered
anything, the runtime evaluates `app.subscriptions` on the new state and diffs it against the
active set (by value): it **stops exactly the active subscriptions no longer wanted and starts
exactly the wanted ones not already active**, giving each new one a fresh id
(`diffSubs_starts`, `diffSubs_stops`, `diffSubs_active`). A subscription asked for twice is one
subscription. The frame carries the diff as `start id sub` and `stop id` commands; the host
keeps a table `id ↦ running thing` and sends `subEvent id e` events. The runtime delivers
`Msg.sub sub e` only for an id that is active at that moment, so an event from a stopped
subscription, however late, never reaches the app (`subEvent_delivers`).

`every ms` is implemented by the host (a `DispatchSourceTimer`), to prove the mechanism end to
end through the host. It is not how an app should keep exact time: ticks can be late or
coalesced; the clock that precedes each tick is the truth.

## Wire format

The frame becomes **version 2**: after the effects list it has a subscription-command list and
a `wake` record. The effect list grows three record kinds; the event batch (still version 1,
the additions are new tags) grows `clock`, `reply` and `subEvent`. New primitives: `u64`, `i64`
and `bytes` (a `u32` length and raw bytes). Every addition has its round trip in
`decodeFrame_encodeFrame` and `decodeEvents_encodeEvents`, which are restated over the bigger
types, not added beside them. The byte layout is in [frame.md](frame.md).

## Order within a step

For one event:

1. **World first.** `clock t`: advance the clock; on the first clock, run `app.initEffects`;
   collect the timers now due. `reply id r`: check and remove `id` from the pending table.
   `subEvent id e`: look `id` up in the active set. Every other event is routed as in M1.
2. **Deliver**, in order: `Msg.clock` first if the app hasn't heard the current time; then
   the event's actions (to `update`) or messages (to `receive`). After each delivery its
   effects are absorbed at once: timers set and cancelled, requests admitted to the pending
   table. A due timer is delivered only if it is still set and due when its turn comes.
3. **Commit**, if anything was delivered: focus requests, the subscription diff, view, layout,
   settle (docs/runtime.md). Otherwise only the world changed, and the view is not re-run.

The frame for a batch carries the batch's effects (refused requests removed), the
subscription commands, and `wake`.

## Theorems

In `Cairn.Runtime` (`WorldProofs.lean`), for every app; none assume anything about the host.

| Theorem | Statement |
|---|---|
| `tick_mono`, `step_clock_mono` | the runtime's clock never decreases |
| `fire_guard` | firing `n` delivers `Msg.timer n` only if `n` is set and due at that moment, and removes it |
| `absorb_cancel` | after effects whose last timer effect for `n` is `cancelTimer n`, `n` is not set |
| `cancelled_never_fires` | if `n` is not set before a step (or batch) and nothing in it sets `n`, no `Msg.timer n` is delivered |
| `reply_delivers` | a `reply id r` event delivers `Msg.reply id r` exactly when `id` is pending and `r` answers its kind, and nothing else but the clock |
| `reply_once` | after that delivery `id` is no longer pending unless the app asked again |
| `absorb_request` | a request is admitted exactly when its id is not pending, and then becomes pending with its kind |
| `diffSubs_starts`, `diffSubs_stops`, `diffSubs_active` | the diff starts exactly the added, stops exactly the removed, and leaves the active set equal (as a set) to what the app asked for |
| `subEvent_delivers` | a subscription event is delivered exactly when its id is active, as the subscription it was started for |
| `decodeFrame_encodeFrame`, `decodeEvents_encodeEvents` | round trips, now over every new record |

The step-level theorems are stated with `App.logged`, which wraps any app so that its state
records every `Action` and `Msg` delivered to it; since the runtime is generic in the app, what
it delivers to the wrapper is what it delivers to any app.

## What is trusted

Each kind of host effect is an `assume` claim naming a check of the trusted-base fuzzer
(docs/fuzz.md, "Trusted base"), ids ^908–^915:

| Id | Claim | Check |
|---|---|---|
| ^908 | the host's clock is monotonic milliseconds | `clock.monotonic` |
| ^909 | the host wakes Lean by `wake` | `clock.wake` |
| ^910 | `readFile` replies with the file's bytes, or `failed` | `effects.read-file` |
| ^911 | `writeFile` is atomic, and replies `done` only when the bytes are there | `effects.write-file` |
| ^912 | `playSound` starts a known sound and refuses an unknown one | `effects.sound` |
| ^913 | `http` sends the request as given and returns the response as received | `effects.http` |
| ^914 | the host answers every request exactly once, with its id | `effects.reply-once` |
| ^915 | `every ms` ticks while started and never after it is stopped | `subs.every` |

The new records are also covered by ^901 and ^902 (the Swift codecs against Lean's), whose
generators now produce them.

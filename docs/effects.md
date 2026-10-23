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
| `Effect` (grows `setTimer`, `cancelTimer`, `request`, `quit`), `Event` (grows `clock`, `reply`, `subEvent`) | `lean/Cairn/Input.lean` |
| `App.receive`, `App.subscriptions`, `App.initEffects` | `lean/Cairn/App.lean` |
| The runtime's world: clock, timers, pending requests, active subscriptions | `lean/Cairn/Runtime/World.lean` |
| Delivery and `step` | `lean/Cairn/Runtime/Step.lean` |
| Theorems | `lean/Cairn/Runtime/WorldProofs.lean` |
| Wire format | [frame.md](frame.md) (frame v2, new event tags), `lean/Cairn/Frame/{Encode,Events}.lean` |
| Host: clock, wake, the handler table, subscriptions | `host/Sources/CairnHost/World.swift`, `Engine.swift` |
| Example | `lean/Examples/Clock.lean`, `host/Sources/CairnClock` |
| Trusted claims ^908–^915, ^960– | `lean/Cairn/Fuzz/Trusted/Claims.lean`, [trusted.md](trusted.md) |
| Yap's host effects (files, watch, frontmost app, permissions) | `host/Sources/CairnHost/FileEffects.swift`, `SystemEffects.swift`; "Yap's host effects" below |

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
carry a side condition. Keeping them apart costs one more field with a default.

A claim machine has the same split: `Machine.receive` (default: ignore the world) beside its
moves, and `toApp` passes it through. An `invariant` must then also be kept by `receive` (its
`receive` clause), and it holds over any interleaving of actions and messages
(`Invariant.reachableAll`) and on screen through the runtime, whatever the host sends
(`steps_reachableAll`, built on `Cairn.Runtime.step_fed`: every step is some updates and
messages). Clock's ^409 is one. A claim kind for messages themselves ("when a reply arrives,
…", with a `post` like a move's) is future work.

## Time

**Decision: the clock arrives on every event, and the app hears it before anything else.**

- The host stamps every batch: its first event is `clock t`, read as the batch is taken off
  the queue (`Engine.timed`). One clock per batch, not one per event: events that queued up
  while Lean was busy share the time the batch started, at most one step's duration (a few ms,
  bench/effects.md) after they arrived.
- `Time` is `{ mono : Nat, wall : Int, zone : Int }`: monotonic milliseconds (Darwin's
  `CLOCK_MONOTONIC`, which counts sleep), wall-clock milliseconds since the Unix epoch, and the
  local offset from UTC in seconds. `mono` is what timers and durations use; `wall` and `zone`
  are for dates (Yap's "today's transcripts file", retention). The runtime keeps
  `mono := max old new`, so its clock never goes back whatever the host sends (proved,
  `tick_mono`). `wall` can jump; nothing in the runtime reads it.
- **The first clock boots the app**: the runtime delivers `Msg.clock t`, then runs
  `app.initEffects` (so a launch request already knows the time). The host sends that first
  clock on its own right after the first frame.
- After that the runtime delivers `Msg.clock t` to `receive` **lazily**: immediately before the
  first delivery (action or message) after the clock changed. An app that stores the time therefore
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
`clock` event once the monotonic clock reaches `wake`. It arms a strict `DispatchSourceTimer`
for it on every publish (`Engine.scheduleWake`): `NSCondition.wait(until:)` on the Lean thread
ran about 7 ms late on a 100 ms wait (timer coalescing), the strict timer about 0.1 ms. It runs
on its own queue, not the main run loop, so it keeps firing while a menu is open. When a clock
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
  | appendFile (path : String) (data : ByteArray)    -- Yap's host effects, below
  | listDir (path : String)
  | deleteFile (path : String)
  | frontmostApp
  | permission (p : Permission) (prompt : Bool)

inductive Reply where
  | done                                              -- writeFile, appendFile, deleteFile, playSound
  | bytes (data : ByteArray)                          -- readFile
  | http (status : Nat) (headers : List (String × String)) (body : ByteArray)
  | failed (fault : Fault) (message : String)          -- any request
  | names (names : List String)                       -- listDir
  | app (pid : Nat) (name : String)                   -- frontmostApp
  | flag (granted : Bool)                             -- permission

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
  whatever the host sends (proved, `step_reply`, `step_reply_ignored`, `steps_book`). A
  duplicate or misshapen reply is dropped.
- **Paths** are strings the host uses as given, except that a leading `~/` is the user's home
  directory. An empty path, a path with NUL in it (the file system would cut it there) and a
  name the file system refuses (APFS: unassigned code points and noncharacters, `EILSEQ`) are
  `failed invalid`. `writeFile` creates missing parent directories and replaces the file
  atomically (write to a temporary file in the same directory, then rename), so a reader sees
  the old bytes or the new ones, never a mix.
- **Sounds** are named system sounds (`NSSound(named:)`: "Tink", "Pop", "Basso", …). The reply
  is `done` once the sound has started, or `failed notFound` for an unknown name.
- **HTTP** is `URLSession` with the given method, headers, body and timeout (0: 60 s); the
  reply carries the status, the response headers sorted by name, and the body. Only `http` and
  `https` URLs; the method is letters and `-`; header names are RFC 9110 tokens and values have
  no CR, LF or NUL (no header injection); anything else is `failed invalid` and sends nothing.
  Foundation percent-encodes characters a URL can't hold. The host follows redirects
  (Foundation's default) and keeps no cookies or cache (an ephemeral session).
- **Quit** (`Effect.quit`) ends the app (`NSApp.terminate`), for a menu bar app's Quit item
  (docs/surfaces.md). It is not a request: there is no one to reply to.

### The host side is a table

`host/Sources/CairnHost/World.swift` has one handler per request kind (`Handlers.standard`,
keyed by the request's kind code), each a function from the request and a `reply` callback,
started on a global queue; the reply goes back through `Engine.send` as a `reply` event. The
callback is once-guarded (a handler that answers twice sends one reply), a kind with no
handler is answered `failed invalid`, and when the app starts over (`Engine.restart`) the
world's generation moves on, so answers to earlier requests are dropped and every
subscription is stopped. A test or a tool swaps the table (the Clock self test redirects `~/`
to a scratch directory and plays no sound). Adding a kind is a constructor in `Request`, its encoding (with the round-trip
proof extended), a `Reply.answers` case, and one handler. Each handler is an `assume` claim
with a fuzz check (below).

### What Yap needs next, and where it slots in

Yap's machine (`lean/Examples/Yap/Model.lean`, PR #40) talks to the host through its own
`Input` and `Cmd`. Each `Cmd` is one of three shapes, and each shape has its slot here:

| Yap `Cmd` / `Input` | Shape | Slot | Status |
|---|---|---|---|
| `transcribe req …`, `transcribeChunk req …` → `reply req` | request by id | `request req (.http …)`, multipart body built in Lean from the clip's bytes | `http` implemented; the clip's bytes come from `record` |
| `saveConfig req c` → `reply req` | request by id | `request req (.writeFile configPath json)` | implemented |
| `save req t` (append to today's file) → `reply req` | request by id | `request req (.appendFile dayPath line)` | implemented |
| `type req clip pid text ret` → `reply req` | request by id | `request req (.typeText pid text ret)`, reply `done` / `failed denied` | designed, not built |
| `startRecording clip`, `stopRecording clip`, `Input.audio`, `Input.micFailed` | request by id + subscription | `request clip (.record maxMs)` answered with `bytes` or `failed` when it stops; `request _ (.stopRecording clip)`; levels as `Sub.micLevel ms` | designed, not built |
| `wakeAt t` → `Input.tick t` | timer | `setTimer name (t - now)`; the clock arrives with it (`Msg.clock`, then `Msg.timer`) | implemented |
| `readConfig`, `readDictionary` → `Input.config`, `Input.dictionary` | request, then subscription | `readFile` now, `Sub.watchFile path` for changes (`SubEvent.changed`, then read again) | implemented |
| `listen k` → `keyDown`, `keyUp`, `otherKey` | subscription | `Sub.globalKey k` with `SubEvent.keyDown/keyUp/otherKey` | designed, not built |
| `listDays` → `transcriptDays`, `deleteDays ds`, `loadRecent n` → `recentLoaded` | request by id | `listDir path` (names), `deleteFile path`, `readFile` per day | implemented |
| `play s` | one-way | `request _ (.playSound name)`, reply ignored | implemented |
| `copy text` | one-way | `setClipboard` | implemented (M1) |
| `storePrefs p`, `Input.launch p` | one-way, and at launch | `writeFile`/`readFile` of a prefs file (`initEffects`), or a `UserDefaults` kind | implemented as files |
| `overlay clip o` | one-way | the overlay surface's frame (docs/surfaces.md), not an effect | surfaces' work |
| `Input.trust` | request | `request _ (.permission .accessibility prompt)`, reply `flag granted` | implemented |
| `keyDown t front` (the app in front) | request | `request _ .frontmostApp`, reply `app pid name` | implemented |

So the three shapes need no new mechanism: a new kind is a `Request` constructor, its encoding
and round-trip case, a `Reply.answers` case and a handler. What Yap's machine would change to
run on this runtime is its entry point: `Input` splits into the `Msg`s above (to `receive`) and
the menu's `Action`s (to `update`), and `Cmd` into `Effect`s.

Audio bodies: a 10-minute clip is a few MB. Passing it through Lean costs a copy each way and
the event decoder runs the list specification (a few hundred ns a byte); if that shows up in
the key-up-to-text benchmark, the decoder gets a `ByteArray` fast path proved equal to the
specification, as the frame encoder has.

## Subscriptions

```lean
subscriptions : S → List Sub

inductive Sub where
  | every (ms : Nat)        -- a tick every `ms` milliseconds (at least 1)
  | watchFile (path : String)  -- `changed` when the file changes (below)
inductive SubEvent where
  | tick | changed
```

Subscriptions are data derived from state, as in Elm. After every step that delivered
anything, the runtime evaluates `app.subscriptions` on the new state and diffs it against the
active set (by value): it **stops exactly the active subscriptions no longer wanted and starts
exactly the wanted ones not already active**, giving each new one a fresh id
(`diffSubs_stop`, `diffSubs_starts`, `diffSubs_fresh`, `diffSubs_active`). A subscription asked
for twice is one subscription. The frame carries the diff as `start id sub` and `stop id`
commands; the host keeps a table `id ↦ running thing` and sends `subEvent id e` events. The
runtime delivers `Msg.sub sub e` only for an id that is active at that moment, so an event from
a stopped subscription, however late, never reaches the app (`step_sub`, `step_sub_ignored`,
`diffSubs_stopped`).

`every ms` is implemented by the host (a `DispatchSourceTimer` on the serial queue
`cairn.world`, which also handles every start and stop, so once a frame's `stop` has been
handled no tick of it is sent). It proves the mechanism end to end through the host. It is not
how an app should keep exact time: ticks can be late, and the engine coalesces consecutive
ticks of one subscription that Lean has not caught up with into one; the clock that precedes
each tick is the truth.

## Yap's host effects

What Yap needs beyond the effects above (GOAL.md "Done means" 1 and 2), as more kinds of the
same three shapes. Each is a constructor, its encoding and round-trip case (frame.md), a
`Reply.answers` case, a host handler, and an `assume` claim (^960–^989) with a trusted fuzz
check that touches nothing outside a scratch directory and prompts no one.

| Effect | Answer | Host | Claim, check |
|---|---|---|---|
| `appendFile path data` | `done` | `open(O_APPEND\|O_CREAT, 0600)` after creating parent directories, then `write` until every byte is out | ^960 `effects.append-file` |
| `listDir path` | `names` | `readdir`, without `.`, `..` and names that aren't UTF-8, sorted by UTF-8 bytes | ^961 `effects.list-dir` |
| `deleteFile path` | `done` | `lstat`, then `unlink`; a directory is `failed invalid` and stays | ^962 `effects.delete-file` |
| `Sub.watchFile path` | `changed` events | polls `stat` every 250 ms on the world's queue | ^963 `subs.watch-file` |
| `frontmostApp` | `app pid name` | `NSWorkspace.frontmostApplication` | ^964 `effects.frontmost-app` |
| `permission p prompt` | `flag granted` | `AXIsProcessTrustedWithOptions`; `AVCaptureDevice.authorizationStatus`/`requestAccess` | ^965 `effects.permission` |

Decisions, and why:

- **`appendFile`, not `writeFile` of the whole day.** Yap's day file is JSON lines so that a
  save is an append and a half-written line costs one entry; rewriting the day would put every
  earlier transcript at risk on each save and make Lean hold the whole day. New files are
  mode 600, as Yap's are: transcripts are private. An append is not atomic: a failure part way
  (a full disk) can leave a prefix, which the JSON-lines reader skips as one bad line.
  Appends from several requests at once each land whole (one `write` per chunk with
  `O_APPEND`; fuzzed up to 70 KB a chunk).
- **`listDir` sorts.** Byte order of UTF-8 is what Lean's `String` comparison is, so Lean gets
  the same answer for the same directory whatever order `readdir` gives. Hidden files are
  included; Lean filters (Yap: names like `2026-10-23.jsonl`).
- **`deleteFile` never removes a directory**, so a wrong path can cost at most one file.
- **`watchFile` polls.** A kqueue watch on the file is lost when an editor saves by renaming a
  new file over it, and one on the directory misses in-place writes; Yap itself polls
  `config.json`'s date every 2 s for that reason. The host compares `stat`'s device, inode,
  size, modification and change times (nanoseconds) every 250 ms (`World.watchPeriodMs`), so
  a write, a replacement, an append, a creation, a removal, a `touch` and a `chmod` all count.
  Two changes inside one poll are one `changed`; Lean reads the file again, so nothing is lost.
  The first poll's state is taken when the subscription starts, with no event: an app reads
  the file once (`readFile`) when it subscribes. A change between that read and the start is
  missed until the next one (a window of one step). A symbolic link is followed.
- **`frontmostApp` is a request**, made when the key goes down: the pid is where the
  transcript will be typed. `name` is `""` when the app has none.
- **`permission` covers Accessibility and the microphone**, the two Yap's menu reports.
  `prompt = false` only reads; `prompt = true` shows the system's Accessibility prompt (it
  opens System Settings; the answer is the state now, so ask again after the person comes
  back, as Yap re-checks when its menu opens) or asks for the microphone while it is
  undecided, answering with the person's choice. A refused permission is never asked again
  by the system; the person changes it in System Settings.

## Wire format

The frame becomes **version 2**: after the effects list it has a subscription-command list and
a `wake` record. The effect list grows three record kinds; the event batch (still version 1,
the additions are new tags) grows `clock`, `reply` and `subEvent`. New primitives: `u64`, `i64`
and `bytes` (a `u32` length and raw bytes). Every addition has its round trip in
`decodeFrame_encodeFrame` and `decodeEvents_encodeEvents`, which are restated over the bigger
types, not added beside them. The byte layout is in [frame.md](frame.md).

## Order within a step

For one event:

1. **World first.** `clock t`: advance the clock; on the first clock, hear it and run
   `app.initEffects`; fire the timers now due. `reply id r`: if `id` is pending and `r` answers
   its kind, the app hears the clock, then the id leaves the pending table and the reply is
   delivered (re-checked after the clock, whose handler could itself have asked again).
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
| `tick_mono`, `step_clock`, `steps_clock` | the runtime's clock never decreases, over a step or a batch, and a booted app stays booted |
| `step_clock_reaches` | a `clock t` event brings the runtime's clock at least to `t` |
| `step_book`, `steps_book` | **timers and replies**: over any batch after boot, every message delivered is allowed by the specification `Book` (a timer only while armed, so never after its `cancelTimer` and once per `setTimer`; a reply only to a pending request, in a shape that answers its kind, once), and the runtime's tables agree with the book after |
| `Book.cancel_disarms` | a timer whose last word in a delivery's effects is `cancelTimer` is not armed after it |
| `Book.reply_once` | once a reply is delivered, no second reply to that id is admitted |
| `step_reply` | a reply to a pending request, in the right shape, reaches `receive` under the id it was requested with |
| `step_reply_ignored` | a reply to an id not pending, or in the wrong shape, reaches no one |
| `step_sub`, `step_sub_ignored` | a subscription event is delivered as its subscription's message exactly when its id is active |
| `diffSubs_stop`, `diffSubs_starts`, `diffSubs_fresh`, `diffSubs_active`, `diffSubs_stopped` | the diff stops exactly the running subscriptions no longer wanted, starts exactly the wanted ones not running, each under a fresh id, leaves the active set equal (as a set) to what the app asked for, and a stopped id is gone |
| `decodeFrame_encodeFrame`, `decodeEvents_encodeEvents` | round trips, now over every new record (`u64_enc`, `i64_enc`, `headers_enc`, `requestBody_enc`, `effect_enc`, `subCmd_enc`, `wake_enc`, `replyBody_enc`) |
| `step_delivers_quiet` (`Proofs.lean`) | for an app whose `receive` ignores every message, a step delivers exactly what M1's did, so M1's claim proofs carry over |

The step-level theorems are stated with `logged`, which wraps any app so that its state
records every `Action` and `Msg` delivered to it with the effects it returned; since the runtime
is generic in the app, what it delivers to the wrapper is what it delivers to any app.
`Book.run` replays such a log against the specification.

## Example: Clock

`lean/Examples/Clock.lean` (host: `host/Sources/CairnClock`, run with `cd host && swift run CairnClock`)
is a stopwatch: Start/Stop (^401) sets and cancels a 100 ms `tick` timer, Lap (^402) records
the reading and plays "Tink", Reset (^403), Save (^404) writes the laps to
`~/Library/Application Support/Cairn/Clock/laps.txt`, Load (^405) reads them back (also once
at launch, from `initEffects`), and the time of day comes from an `every 1000` subscription.
`stopped_tick` proves a tick that arrives after Stop changes nothing; the invariant ^409
(pending requests have ids below the next request's) is kept by its moves and by `receive`,
and `freshRequests_on_screen` (`Examples/Clock/Proofs.lean`) carries it through the runtime. Its self test drives the
real host threads: launch read, the reading moving with no input, cancel on Stop (no `wake`,
reading frozen), save, reset, load, and measures the numbers below.

Measured on an Apple M4 Max, debug host build (bench/effects.md):

| | p50 | p90 | max |
|---|---|---|---|
| request round trip: click → `readFile` → reply → frame | 1.5 ms | 2.0 ms | 6.6 ms |
| a timer's clock after its deadline (0.5 ms polling, upper bound) | 1 ms | 2 ms | |

## Surfaces

The new events are global: a clock, a reply and a subscription event belong to the app, not
to a window, so docs/surfaces.md's per-surface frames and surface-tagged input events can be
added beside them without changing these tags (18–20). Host-owned timers (the wake timer and
`every`) run on dispatch queues, not the main run loop, so they keep firing while a menu is
open.

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
| ^960 | `appendFile` adds exactly the bytes at the end, or fails and adds nothing | `effects.append-file` |
| ^961 | `listDir` lists exactly the directory's names, sorted | `effects.list-dir` |
| ^962 | `deleteFile` removes a file or a link, never a directory | `effects.delete-file` |
| ^963 | `watchFile` reports every change to its file, and nothing after its stop | `subs.watch-file` |
| ^964 | `frontmostApp` answers the app in front | `effects.frontmost-app` |
| ^965 | `permission` answers whether the app holds it, and prompts only when asked | `effects.permission` |

The new records are also covered by ^901 and ^902 (the Swift codecs against Lean's), whose
generators now produce them. The suites (`clock`, `world`, `files`, `http`, `sound`, `fileops`, `system` in
`host/Tests/CairnFuzzTrusted`) are described in docs/fuzz.md.

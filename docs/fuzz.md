# Fuzzing

Every app built with Cairn gets claim-driven randomized testing, in the spirit of GPUI's
`#[gpui::test(iterations = N)]`: random operations from a seeded generator, checked against the
app's claims after every step, with failing seeds replayed and shrunk. It needs no per-app code
beyond the claims the app already makes.

```sh
cairn fuzz --iterations 1000         # in an app package (test/fixture): every target, into build/fuzz
cairn fuzz Fixture --seed 1234 --iterations 1 --steps 80 -v   # replay one seed, step by step
cd lean && lake exe fuzz --list       # every fuzzable app of the package
```

Code: `lean/Cairn/Fuzz/`, and an app's `lean_exe fuzz` (test/fixture/lean/FuzzMain.lean).
Output: `build/fuzz/<App>.json`.

### An app package

`cairn fuzz` (docs/cli.md, "Checks") fuzzes an app in its own package. The package declares the
executable, since the targets are found at compile time from what its root imports:

```lean
-- lakefile.lean
lean_exe fuzz where
  root := `FuzzMain

-- FuzzMain.lean
import Checks              -- the app (and anything else to fuzz)
import Cairn.Fuzz.Collect
import Cairn.Fuzz.Main

def targets : List Cairn.Fuzz.Target := fuzz_targets%

def main (args : List String) : IO UInt32 := Cairn.Fuzz.main targets args
```

### Targets and dependencies

`fuzz_targets%` sees every machine the root imports, a dependency's too: an app that requires
cairn_atproto imports its session machine. Which package a machine is in comes from Lake (the
package each module was built in), and a target is named for it:

| Machine | Target name | Run by `cairn fuzz` |
|---|---|---|
| in the fuzz executable's own package, module `Sky.Claims` | `Claims`: the module's last component, and the machine's when the module declares several (`Gallery.machine`) | always |
| in a dependency, module `CairnAtproto.Claims` of package `cairn_atproto` | `cairn_atproto/Claims`: its package, `/`, then the same | with `--deps`, or when named |

So `lake exe fuzz --list` (and `cairn fuzz` with no targets) is the package's own machines; a
dependency fuzzes its own in its own package. `--list --deps` and `cairn fuzz --deps` add the
dependencies'. Any target can be named: `cairn fuzz cairn_atproto/Claims`, whose report is
`build/fuzz/cairn_atproto/Claims.json`.

Two machines with one target name are an error, not one shadowing the other: `fuzz_targets%`
fails to compile, naming both (two of the package's modules ending in `Claims`; rename one), and
`Cairn.Fuzz.main` refuses a list with a name twice (exit code 2). test/fuzz-scope (`make
fuzz-scope`) is an app and a dependency with a machine in `Claims` each. (Through Cairn 0.3.0 a
dependency's machine was the app's own and could share its name, and then only one of them ever
ran: cairn#221.)

## What the claims give the fuzzer

| From | Used as |
|---|---|
| the machine's moves, each with `enabled` and its triggers | the alphabet, filtered to what is enabled in the current state |
| each `invariant`'s generated `check` (below) | an oracle after every step |
| each move's `enabled` against the frame | **presence**: a control `^N#k` is in the laid tree, or is an enabled control on a shown status item (its button, or an item of its menu), iff `^N` is enabled for `k` |
| `Layout.Check` and hit testing | **pressable**: at sizes at or above the minimum, every enabled pointer move's control is hit at its centre, and `checkPressable` accepts the tree |
| purity of `update`, `view`, `layout` | determinism: a seed replays a run exactly |

The fuzzer finds every `Machine` in the app's modules at compile time (`fuzz_targets%` in
`Cairn/Fuzz/Collect.lean`), with its moves, invariants and the `App` built from it, so a new app is
fuzzable as soon as the fuzz executable's root imports it. An app with a machine and no `App` would
be fuzzed at the model level only: actions straight into `machine.update`, checked against its
invariants. Every app has an `App` now (Counter since it moved to v1), so both run through the
runtime.

**Runnable invariants.** `invariant` now also generates `name.check : S → Bool :=
fun s => decide (holds s)` when `Decidable` can be synthesized for `holds s` (unfolding the
definitions at the head of its body). An invariant without one is reported as "not runnable".
`check` is `decide`, so it agrees with `holds` by construction.

## What is generated

A run is `--iterations N` sequences of `--steps K` operations. Each sequence starts from the
app's `init` with its own window size and text metrics:

- **Window size:** random, at least the app's minimum. The minimum is the app's
  `Custom.minSize`; else the `App.minSize` it asks the host for, since the host keeps the window
  at least that (trusted ^1010) and a person never sees it smaller; else, for an app that asks
  for none (`0 × 0`), the root's preferred size in the current state (`measure`). A resize
  operation picks a new size at or above the current minimum; one in twenty goes below it to
  exercise clipping (pressability is not checked there, and the skip is counted).
- **Text metrics:** a random `TextMetrics` that is `Valid` by construction (prefix sums of
  non-negative per-scalar widths, chosen per font from the seed, some zero for combining marks;
  random ascent and descent), or `TextMetrics.mono` in one sequence in eight.

The sequence starts with the host's first clock (a random time from the seed), which boots the
app: it hears the time and its `initEffects` run. Each operation is one of:

| Operation | Weight | Performed as (app level) |
|---|---|---|
| `host h`: the host's move (below) | 20–60% while the host has something to say (a request outstanding, a timer set, a subscription running), more as requests pile up; 3% otherwise | a batch of the clock and the host's event |
| `act a`: an action of an enabled move, for an enabled key | ~70% of the rest | the events a person would use: a press is move, down, up at the control's centre; a double press adds a second down with `clicks = 2`; `edit`, `submit`, `cancel` click the field unless it has focus, then send the text event or key (Enter, Escape); `blur` focuses the field, then Tab |
| `click p`, `move p` at a random point | ~12% of the rest | pointer events, whatever is there |
| `tab`, `shift-Tab`, a bare key (Enter, Escape, Backspace, arrows) | ~10% of the rest | key events |
| `scroll p dx dy` | ~16% of the rest when a scroll box is on screen (2% otherwise) | a pointer move to `p`, then the scroll: at a point in a visible scroll box three times in four, by a tick (±48), a flick (±1,200) or one in nine ±1,000,000 (past either end), sideways one time in six |
| a scroll key (Page Up/Down, Home, End, arrows, space), shift one in four, command one in eight | ~8% of the rest when a scroll box is on screen | key events |
| `resize`, `pointerExit`, `windowFocus` | ~8% of the rest | window events |

Every batch starts with the host's clock, as the real host's does (^908), and ends with the
runtime's two frame events (`Runtime.frameEvents`), as `steps` runs them: the `appear` moves a
step delivers are among its actions. The fuzzer never chooses an `appear` move itself; only
the runtime delivers one.

Keys for keyed moves come from the frame (every `^N#k` on screen), plus keys seen earlier in the
run and one past the largest, so "enabled but missing" is caught too.

**Weights** (cairn#226). An `act` picks among the enabled (control, trigger) pairs on screen in
proportion to the control's weight, `Custom.weights s ref` (default 1). Weight a move that is
only reachable deep in an app up, one that ends the state under test (Sign out) down, or a few
keys up so that presses race their own replies. A weight of 0 never picks the control, but its
presence is still checked; if every weight is 0, the operation is noise instead. The report
counts presses per move as before (`performed`).

```lean
def fuzz : Cairn.Fuzz.Custom State where
  -- Most presses on post 1's Like, so a press races its own write's reply; never Sign out.
  weights := fun _ r => if r.claim = 21 then (if r.key = 1 then 12 else 2)
    else if r.claim = 11 then 0 else 1
```

**Text edits** use the default generator unless the app supplies one: inserts drawn from words,
blanks, emoji with modifiers and ZWJ sequences (`👍🏽`, `👨‍👩‍👧`), combining marks (`e` +
U+0301), CJK, long strings; deletes and word deletes; caret and word moves, with and without
extend; select all; copy, cut, paste; undo, redo; and IME compositions (one to three
`setMarked` steps, then a commit `insert` or `unmark`), each step its own event.

**Custom generators.** An app may define `fuzz : Cairn.Fuzz.Custom State` in its namespace
(`Cairn.Fuzz.Custom` is a pure module, so the app library still doesn't link `Lean`):

```lean
def fuzz : Cairn.Fuzz.Custom State where
  edits := fun s id => if id = 101 then some (Cairn.Fuzz.Gen.oneOf [imeKana, emojiBurst]) else none
  minSize := fun _ => some ⟨360, 240⟩
  budgetNs := 4_000_000
```

`edits` returns a generator of `TextOp` scripts for a field's `edit` moves; `none` keeps the
default. The host's hooks are below ("The host").

## The host

`cairn fuzz` plays the host's side too (`Cairn/Fuzz/Host.lean`, cairn#181). It keeps what the
frames asked of it (the requests and cancels each step's effects put on the frame, the
subscriptions the runtime runs, the frame's `wake`, the images it draws) and answers the way
the real host is allowed to, as the trusted claims state it (docs/trusted.md):

| Host move | When | What the claims allow |
|---|---|---|
| `reply id r` to an awaited request | any request outstanding, picked at random, so replies come late and in any order | ^914: each request is answered exactly once, under its id, with a reply of its kind's shape (`Reply.answers`) or `failed` (one in six by default) |
| `reply id r` to a request the app cancelled after it was sent | the frame carried its `cancelRequest` | ^1009: still answered once, `failed other "cancelled"`, or its ordinary answer if its work had finished (or has no stop: files, sounds); the runtime swallows it and frees the slot |
| `load id w h` | a `loadImage` not answered yet | ^1006/^1011: the pixels are put before the answer is sent, so an eviction can cross the answer |
| `wake late` | the frame has a `wake` | ^909: a clock at the deadline or up to 40 ms after it; the due timers fire |
| `advance ms` | always | ^908: the clock moves on (1 ms to an hour; `mono` never goes back, wall time sometimes jumps a day) |
| `sub s e` | a subscription is running | `every`'s ticks at most one a period (^915), `watchFile`'s `changed`, `record`'s `started` once then `audio` or `failed`, `globalKey`'s down, up and other keys |
| `late id e` | the runtime stopped a subscription lately | an event that crossed the stop; the runtime drops it (`step_sub_ignored`) |
| `evict src` | an `imageCache` runs and the held pixels are over its smallest budget | ^1011: the least recently used image (put, or drawn by a frame) that the latest frame doesn't draw and that wasn't just put is dropped, and every running `imageCache` hears `evicted` |
| `stray id r` | rarely, once the app has made a request | beyond the contract: a reply to an id the runtime doesn't hold (answered before, or never sent); the runtime drops it (`step_reply_ignored`) |

Images follow ^1006: a `loadImage` without `reload` of a source the host holds is answered with
the held size; a reload is read again; a failed reload drops the source (and says `evicted` if
an `imageCache` runs); a cancelled reload leaves what was held. The host never sends a
duplicate reply, a reply of the wrong shape or a clock that goes back: those are outside the
trusted claims, and the runtime is proved to drop the first two anyway.

**Contents are app-agnostic by default:** a file read gets random bytes or a word, an HTTP
request a status (200, 201, 204, 301, 304, 400, 401, 403, 404, 410, 429, 500, 503) and random
bytes, a `loadImage` a random size from 1 to 1600 pixels a side, a directory a few names, and
any request a random `Fault`. An app that needs structured replies plugs in a generator:

```lean
def fuzz : Cairn.Fuzz.Custom State where
  -- The JSON a pack parser expects, by request; `none` keeps the default.
  replies := fun _ _ r => match r with
    | .http _ url .. => some do
        if ← Cairn.Fuzz.Gen.chance 1 10 then return .failed .network "fuzz"
        return .http 200 [] (manifestFor url).toUTF8
    | _ => none
  -- A claim about every step, as a relation over a `Transition`: the state before, the host's
  -- message (`none` for a person's operation), the state after and the frame's effects.
  -- (Pairs's ^28: a reply to a request not waited for changes nothing.)
  relations := [(28, fun t => match t.msg with
    | some (.reply id _) => t.before.reqs.isLive id || t.after.core == t.before.core
    | _ => true)]
  -- Checked once the sequence is over and the host has answered everything outstanding.
  drained := [(30, fun s => s.core.loading.isNone)]
  -- Checked after every step against the ids the runtime still holds for the app.
  -- (Pairs's ^27: no request is lost.)
  outstanding := [(27, fun s ids => ids.mergeSort == s.reqs.live.mergeSort)]
```

- `replies s id r`: a generator for request `r` (id `id`) in state `s`. A reply that doesn't
  answer the request's kind becomes `failed`, since the host never sends one.
- `subEvents s sub`: the same for a running subscription's events.
- `relations`: claims stated about every step rather than every state (∀ over `update` and
  `receive`) are "not runnable" as invariants; an app can check them per step as relations.
  Counted as `relation` under the claim. A message the runtime drops (a reply to a cancelled
  or unknown id, an event of a stopped subscription) never reaches the app through the runtime,
  so it is also given straight to `receive` and the relations checked on that: a claim about
  every message is then tested on the messages the runtime shields the app from.
- `drained`: after the last operation the host answers everything outstanding, oldest first,
  with `replies` or the default (up to 1,000 replies), and these are checked. Counted as
  `drained`. Only run when the app has some.
- `outstanding s ids`: checked after every step, the first frame included, with the ids of the
  requests the runtime holds for the app: sent and not answered, or queued behind the in-flight
  limit (`App.maxInFlight`), and not cancelled (`World.entries`, sent oldest first, then
  queued). Those are exactly the ids a reply can still reach the app under, so a claim that the
  app's own bookkeeping matches them ("no request is lost") is checkable at every step, not
  only once drained. A step's `effects` can't stand in for this: a queued request goes on a
  later step's frame. Counted as `outstanding`; a failure shrinks like any other.

**Determinism.** The host's every decision (which request, what reply, how far the clock moves,
what to drop) is drawn from the sequence's seed and recorded in the operation, so a seed
replays exactly, and a shrunk subsequence replays without it: a reply to a request the replayed
sequence never made, an eviction the host couldn't make, or a wake with no timer set is
skipped, like an `act` whose control is gone. Draining uses its own stream from the seed.

**What it adds to the checks.** Every check above runs after every host move, so a reply, a
timer, a tick or an eviction that breaks an invariant or presence, or moves a control off its
click, fails as a person's move would. One check is new, and runs after every step:

- **Images held:** every image source the frame draws (the window's and shown panels'
  `Style.image`) is one the host holds pixels for. An app takes an image for ready only from
  the host's answer, and forgets it when told it was dropped (`Images.Cache.ready_held`); a
  frame that draws a source the host doesn't hold paints nothing there. Counted as `image`
  under the window's place claim.

A failure that needs the host's moves can't be printed as a flow (a witness is actions only);
the printout says so and gives the replay command and the shrunk steps.

## A server

`Custom.replies` keeps no state between replies, so a claim can't be stated against what the
server holds ("once every reply is in, each post shows what the server holds"). An app (or a
library with a fake server, like cairn_atproto's fake PDS) can give the fuzz host a **server**
with a world of its own (cairn#246; `Cairn.Fuzz.Server` in `lean/Cairn/Fuzz/Rng.lean`, a module,
so it needs no `Lean`):

```lean
structure Server (S : Type) where
  W : Type                                   -- what the server holds
  init : Gen W                               -- the world a sequence starts with, from its seed
  handles : Request → Bool := fun _ => true  -- which requests go to it
  handle : W → Nat → Request → Gen (W × Reply)  -- request `id` reaches it: world after, reply
  tick : W → Gen W := pure                   -- the world acting on its own between steps
  fault : Request → Gen Reply := …           -- what the app hears for a fault: timeout, network
  checks : List (ClaimId × (S → W → Bool)) := []   -- after every step
  drained : List (ClaimId × (S → W → Bool)) := []  -- once everything is answered
  describe : W → String := fun _ => ""       -- the world in a failure's message
  failBefore : Nat := 3                      -- weights, against 30 for handling and replying
  loseAfter : Nat := 3
  ticks : Nat := 4
  retransmit : Nat := 0
```

```lean
def fuzz : Cairn.Fuzz.Custom State where
  server := some server
```

**Scheduling.** A request the server takes (one it `handles`; never a `loadImage`, whose answer
the host's images follow) is answered in two moves, each picked at random among everything the
host could do, so replies are still late and out of order:

| Host move | What happens to the world | What the app hears |
|---|---|---|
| `serve id seed`: the request reaches the server | `handle` runs on it (seeded `seed`); its reply waits | nothing yet |
| `reply id r`, after `serve` | nothing more | the reply `handle` gave |
| `lose id r`, after `serve`: **lost after** | nothing more: it already changed | `r`, a fault (`Server.fault`: a timeout or a network failure) |
| `fail id r`, before `serve`: **failed before** | nothing: the request never reached it | `r`, the same kind of fault |
| `tick seed` | `tick` runs: other accounts like, post, the AppView catches up | nothing |
| `serve id seed` again, after `serve` (`retransmit`, off by default) | `handle` runs again (a proxy's retry) | the second answer |

The two faults look the same to the app, which is the point: it can't tell whether a lost write
happened, and has to find out (read it back). A claim stated against the world can tell. A
request the app cancelled is answered `failed other "cancelled"` before it reaches the server,
or with its reply (or lost) after (^1009). `retransmit` is off by default: a second delivery
refused after the first was applied is a "refused" write that happened, which no client can
tell from its reply, so turn it on only for a server that answers a repeated request as it did
the first time. Requests the server doesn't take are answered as without one, by `replies` or
the default.

**In conformance.** `cairn conformance` answers the running app's requests from the same server
when the app's generator module passes its `Custom` (docs/conformance.md, "The world"), so the
model and the app hear the same replies, faults included.

**Checks.** `checks` run after every step (the first frame included) on the app's state and the
world, counted under the claim as `server`; `drained` once the sequence is over and the host has
answered everything outstanding, every request reaching the server first and no faults, counted
as `serverDrained`. A failure's message has the world in words (`describe`).

**What the host promises** (theorems in `lean/Cairn/Fuzz/Walk.lean`, over `hostStep`, which
does the host's move with a server, `Server.empty` standing for none):

- **Each request is answered at most once**, with or without a server: a `reply`, `lose` or
  `fail` answers only a request the host holds, and it holds it no more after
  (`hostStep_answers_once`), so no second answer to it can happen
  (`hostStep_no_second_answer`). A cancelled request is answered once too, and the runtime
  swallows it, as before.
- **A failed-before answer leaves the world as it was**, by construction
  (`hostStep_fail_world`), as do a lost-after answer and a reply: only `serve` and `tick`
  change the world.

**Replay and shrinking.** Every server move records the seed its generator runs from, so a
sequence replays without the stream it came from, and the world is rebuilt as the sequence
replays: a shrunk sequence keeps the requests reaching the server that its failure needs. A
`reply` to a request that never reached the server in the replay is skipped, like a reply to a
request the replay never made. The report names each fault where it was injected (here
`lake exe likeMutant`'s, which prints the same shrunk operations):

```
lost taken for refused: server ^22 failed at seed 0: ^22 is false after this step, against the server's world: liked [false, true, true, false], others [18, 30, 8, 25], 2 writes
  shrunk 27 → 6 operations:
    press ^21#3
    press ^21#4
    press ^21#1
    press ^21#2
    host: #3 reaches the server, which handles it (reply not sent yet)
    host: LOST AFTER: the server handled #3, but the reply is lost; the app hears failed Cairn.Fault.network "fuzz"
```

That is the fixture's mutant (test/fixture/lean/Fixture/LikeMutant.lean, `make fuzz-quick`): a
Like that takes a lost write for a refused one and rolls back instead of reading it back. Post
4's write (#3) was lost after the server applied it, and the post rolled back to a value the
server no longer holds.

**The world is threaded, not copied.** The walk holds the only reference to the world while
`handle` and `tick` run (`perform` takes the sequence's state apart first; `hostStep` returns
the world even when the move can't happen), so an `Array` or `HashMap` in it is updated in
place. Build `init`'s arrays from the generator (not as a constant, which would be shared) and
mark them with `markLinear`; then a run with `LEAN_ABORT_ON_NONLINEAR=1` aborts on any copy. The
fixture's server does, and `make fuzz-quick` runs with it.

**Writing a fake server for a library** (cairn_atproto's fake PDS): define the world and a
`Server S` generic in the app's state, with a way for the app to say what to check, and let the
app plug it in:

```lean
-- In the library (a `module`, no `Lean`):
def Fake.server {S : Type} (shows : S → Fake.World → Bool) : Cairn.Fuzz.Server S where
  W := Fake.World
  init := Fake.World.gen
  handles := Fake.isXrpc
  handle := Fake.handle
  tick := Fake.othersAct
  checks := [(52, shows)]
  drained := [(52, shows)]
  describe := Fake.World.describe
-- In the app:
def fuzz : Cairn.Fuzz.Custom State where
  server := some (Fake.server fun s w => …)
```

The request id the host passes `handle` is the app's; a server that needs its own ids (record
keys, cursors) keeps them in the world. `handle` sees only the request, never the app's state.

## What is checked, after every step

1. **Invariants:** every runnable invariant's `check` on the app state.
2. **Performed:** an `act a` delivered `a` (the runtime's `route` returned it). A click at an
   enabled control's centre that delivers anything else is a pressability failure of that move,
   with one exception, the dropped click of TodoMVC decision T33 (docs/plan.md): when the
   pointerDown delivers a `blur` and, after that step, the control is no longer at the point
   (the edit the blur saved moved or removed it), the release lands elsewhere and presses
   nothing (docs/runtime.md). That is exactly where `Runtime.click_presses`'s hypothesis
   fails, so the click is counted under the claim's `droppedT33` check, not failed, and the
   run's `droppedClicks` totals them. A control that moves on pointerDown without a blur is
   still a failure.
3. **Presence** for every move and candidate key. A status item's controls (docs/surfaces.md)
   are on screen without being in the window's laid tree: its button whenever it is shown, and
   its menu's items whether or not the menu is open, a greyed-out item counting as absent. The
   fuzzer presses them as the host does, with `menuOpen` for the button and `menuSelect` for an
   item (Tray's `cairn_examples^453`, cairn#176).
   A control's menu (docs/surfaces.md, "Menus on controls") is in the frame whenever its control
   is laid, so its items count as present whether or not the menu is open. The fuzzer presses an
   item by right-clicking the centre of its control's visible part, then sending `menuSelect` and
   `menuClose` with the window's place, as the host does when the native menu returns. A menu bar
   item (`Surface.menuBar`) is pressed with `menuSelect` and its surface's place.
   In a virtual list (docs/layout.md, "Virtual lists") a move whose controls are keyed by their
   row's key is present iff it is enabled **and its row is laid**: the moves with a control in a
   laid row keyed like the row are found in the frame, and for them a key whose row the list
   didn't lay must be absent. Any other move keyed like a row that isn't laid may be absent. The
   probed keys include each list's first and last keys and the keys either side of the rows it
   laid. While a list seen before is off screen (hidden while the app keeps it), none of its rows
   is laid: the moves found in its rows, and any move keyed like one of its rows, may be absent.
   A list that left and isn't kept (replaced by one with a new ref) is gone and says nothing.
4. **Pressable** when the window is at or above the minimum: `hitTest` at the centre of the
   visible part of each enabled pointer move's control returns it, and
   `checkPressable && controlRectsNonempty` holds. A control scrolled out of view in a scroll
   box (an empty visible part) is not pressed, not chosen for an operation and not checked:
   nothing of it can be hit (`not_hit_of_hidden`).
5. **Images held** (above, "The host"): every image the frame draws is held by the host.
   **Scroll** (counted under the box's ref's claim, `scroll`): every scroll box's offset is within
   `[0, max 0 (content − viewport)]`, the box is laid at the runtime's offset (the view passes
   `ui.scrollOf`), and the runtime keeps no offset for a box that isn't on screen
   (`Runtime.step_clamped`). **Appear** (under the move's claim, `appear`): each `appear` move
   delivered names a move with an `on appear` handler; these count as the move's steps.
   **Virtual lists** (under the list's ref's claim, `vlist`): the rows laid are exactly those
   whose extent, by `Model.top` and `Model.height` (the specification, not the fast path the view
   used), meets the box widened by the overscan, and no more than `(viewport + 2·overscan) /
   minHeight + 2`; the spacers and rows are one under the other from the content's top less the
   offset; and every row laid was laid at the height the list laid it out by (the runtime had
   recorded it: `settleAll` didn't run out). **Anchor** (`anchor`): over an operation that doesn't
   scroll or resize (not a wheel, key, Tab or resize) or ask to (`scrollTo`), the first row
   showing in each list keeps its place in the box, unless the offset ends at 0 or the limit or
   the row is gone. **`scrollTo`** (under the box's ref's claim, `scrollTo`): after a step whose
   effects ask for it, a box on screen is at 0 for `start`, at its limit for `finish`, and for
   `key k` the row keyed `k` is the first showing, at the top of the box, unless the clamp holds
   the list at its end (`aimOff_*`, `firstF_top`). **Kept** (`kept`): a list the app keeps
   (`App.keepScroll`) keeps its offset while it is off screen, and when it comes back the row
   that was first showing when it left is first showing again at the same place, unless the
   clamp moved it or the row is gone (`fixUI_keeps_offset`, `fixUI_keeps_list`).
6. **Relations** (`Custom.relations`), for a host's move or a person's operation.
   **Badge** (`Custom.badge`, under the claim each names, `badge`): the app's checks against the
   Dock badge the host shows, which is the last `badge` effect's label or none (^1030). The
   fixture checks its badge is its count (^45).
7. **Outstanding** (`Custom.outstanding`): the app's checks against the requests the runtime
   still holds for it. **Server** (`Server.checks`, above, "A server"): the app's checks against
   the server's world.
8. **Secure fields** (`secure`), once a secure field (`FieldView.secure`) has been on screen:
   neither the frame's dump (`Dump.canvas` of `Frame.ofLaid`) nor any effect's dump (`Dump.effect`)
   holds the planted text, as text or as hex. See "Secure fields" below.
9. **Greyed menu items** (`menu-greyed`, under the item's claim): up to four greyed-out items of
   the control menus, status items and menu bar on screen are chosen (opening the menu first
   where it needs it), and nothing is pressed. Lean's `menu_select_stale` proves this; the check
   catches a fuzz target whose menus disagree with their moves.
10. **Frame-time budget:** wall-clock time of `Runtime.step` (update, view, layout, settle) per
   step, against `--budget-ms` (default 8, a 120 Hz frame). Over-budget states are reported with
   their seed and step, but never fail a run: timing is not deterministic.

### Secure fields

An edit of a secure field is one time in three preceded by inserting `Text.planted`
(`lean/Cairn/Fuzz/Text.lean`), a string nothing else types. Check 8 then fails the step at which
a frame or an effect carries it where a tool could print it: a view that echoes the field, a
request built from it without `redact := true`, a clipboard write. Lean proves the field's own
view safe (`Dump.secure_canvas`); the check is for what an app does with the text.

Nothing the fuzzer prints holds what was typed into a secure field: its `insert`, `paste` and
`setMarked` text is printed as bullets, one per scalar, in verbose steps, failure messages,
shrunk sequences, flows and `build/fuzz/<App>.json`. Shrinking replays the real text, so a
printed flow's witness has bullets where the text was.

Moves' `post`s and the invariants are proved, so checks 1 and 2 at the model level should never
fail; they are cheap and guard the machinery. Presence and pressability are proved per app and
per state, if at all, so that is where the fuzzer earns its keep.

## Seeds and replay

The PRNG is SplitMix64 (`Cairn/Fuzz/Rng.lean`, core only, no Plausible). Like GPUI, a run with
`--seed S --iterations N` runs the sequences with seeds `S, S+1, …, S+N−1`, and every failure
prints its own seed: `--seed <that> --iterations 1` replays it exactly. `SEED` and `ITERATIONS`
environment variables set the defaults. The default seed is 0, so `make check` is
deterministic; pass `--seed random` to start from the clock.

## Shrinking

A failure is a check kind on a claim (say "presence ^104#3"). Shrinking is delta debugging
(ddmin) over the sequence's operations: try removing chunks, halving the chunk size down to
one, keeping any shorter sequence that still fails the same check on the same claim, then a
final pass removing single operations. Operations are self-contained (an `act` names its
control and text op; a resize names its size), so a subsequence replays without the seed; an
`act` whose control isn't on screen is skipped. The window size and metrics stay fixed.

The first failure of each kind (check and claim; up to `--shrink`, default 5) is shrunk and
printed three ways:

- as a **ready-to-paste `flow`** with the next free id from `claims.lock`, whose `witness` is the
  actions the runtime delivered during the shrunk replay, minus those no move accepts (no-ops in
  the model), so `live` holds and the flow compiles in the app as it is. A flow's goal can only
  talk about the state, because claims are declared before the view, so:
  - for an invariant failure the goal is `inv.check s = true`, which fails until the fix;
  - for presence and pressability failures the flow pins the state the failure needs (its goal
    is the move's enabledness there, true as found), and a **theorem** follows for the app's
    Proofs file, over `layout TextMetrics.mono` of the app's view in the flow's final state at
    the failing window size: `present … = en`, a hit at the control's centre, or
    `checkPressable && controlRectsNonempty`, closed by `decide +kernel`. It fails until the bug is
    fixed, then stays as the regression test. If the failure was found with random metrics, the
    printout says so: the theorem uses mono metrics, so check that it fails before the fix.

  If no move reaches the failing state (only window or pointer events do), there is no witness,
  and the printout says to state it as a theorem about `init`;
- as **sequence JSON** in `build/fuzz/<App>.json` (below);
- step by step with `-v` (each operation, then the actions it delivered).

A pressability failure names the claim to blame: the control nearest the first node that fails
`fitsB`, `stackTopB` or `controlLeafB`, else an empty control rect.

## Output: `build/fuzz/<App>.json`

```json
{"app": "Basics", "module": "Basics", "mode": "runtime", "seed": 0, "iterations": 1000,
 "steps": 50, "sequences": 1000, "stepsRun": 50000, "seconds": 2.04,
 "sequencesPerSecond": 490, "stepsPerSecond": 24546, "pressableSkipped": 5869,
 "failingSequences": 0, "budgetMs": 8, "budget": {"maxMs": 0.95, "over": []},
 "claims": {"^101": {"kind": "move", "pass": true, "steps": 9120, "sequences": 1000, "seed": 0,
                     "checks": {"performed": 1793, "presence": 50000, "pressable": 4489}},
            "^105": {"kind": "invariant", "pass": true, "steps": 50000, "sequences": 1000},
            "^107": {"kind": "flow", "pass": null, "note": "n/a"}},
 "failures": [{"check": "presence", "claim": 104, "key": 3, "seed": 17, "step": 31,
               "shrunkFrom": 28, "message": "…", "sequence": {…}, "flow": "flow ^110 …"}],
 "host": {"requests": 62416, "cancels": 24452, "replies": 36830, "failedReplies": 5712,
          "cancelledReplies": 19682, "strayReplies": 2527, "clocks": 11063, "wakes": 0,
          "timersDue": 0, "subEvents": 0, "lateSubEvents": 0, "loads": 4661,
          "evictions": 12993, "maxOutstanding": 6, "leftOver": 5904}}
```

`host` totals what the host did over the run (above, "The host"): requests and cancels the
frames carried, replies to awaited requests (and how many failed), replies to cancelled ones,
stray replies, clocks sent, wakes, timers due at them, subscription events (and late ones),
pixels put before the answer, evictions, the most requests outstanding at once, and requests
still unanswered when sequences ended; with a server, `served` (requests it handled),
`retransmits`, `lostAfter`, `failedBefore` and `ticks`. A place claim's entry has the `image`
checks.

`mode` is `runtime` (through `Runtime.step` and the view) or `model` (no `App`: actions into
`machine.update`). `pass` is `true`, `false`, or `null` with a `note`: `not run` (no step
exercised it), `not runnable: no Decidable instance`, `n/a` (flows, places, assumptions), or
`retired`. The run exits 1 if any sequence failed.

**Sequence JSON** is meant for J's conformance driver to replay a fuzz sequence on the real app:

```json
{"app": "Basics", "seed": 17, "window": {"w": 512, "h": 640},
 "metrics": {"kind": "random", "seed": 9001},
 "steps": [{"trigger": "edit", "ref": "^101", "claim": 101, "key": 0,
            "op": {"kind": "insert", "text": "é"}},
           {"trigger": "press", "ref": "^102", "claim": 102, "key": 0},
           {"event": "click", "x": 40, "y": 300, "clicks": 1, "hit": "^103#1"},
           {"event": "key", "key": "tab", "shift": true},
           {"event": "resize", "w": 600, "h": 420},
           {"host": "reply", "id": 3, "reply": {"kind": "image", "w": 640, "h": 480}},
           {"host": "wake", "late": 2}]}
```

The setup also has the host's first `clock` (`mono`, `wall`, `zone`). Host steps are
`{"host": kind, …}`: `advance` (`ms`, `wallJump`), `wake` (`late`), `reply` and `stray` (`id`,
`reply`: `kind` and its fields, bytes as `hex`), `load` (`id`, `w`, `h`), `sub` (`sub`,
`event`, `dt`), `late` (`id`, `event`) and `evict` (`source`); with a server, `serve` and
`tick` (`id`, `seed`), and the two faults, `lose` and `fail` (`id`, `reply`, and `fault`:
`lostAfter` or `failedBefore`).

Action steps have exactly the shape of a flow's witness in `lake exe claims` (`trigger`, `ref`,
`claim`, `key`, `op`), which the capture already replays, with `op` extended to every
`TextOp` (`extend`, `selStart`, `selLen`). Raw pointer steps carry the point and the control it
hit in the model (`hit`), so a driver whose metrics differ (Core Text, not the fuzzer's) can
retarget by ref.

## Evidence in the docs

`tools/map/evidence.ts` (used by `cairn doc`) reads `build/fuzz/<App>.json`: a move or invariant that held in every sequence gets
a `fuzzed N` chip (N sequences), between proved and tested on the evidence ladder
(site/web/content/docs/reference/evidence.md). The claim pages don't show it yet (#95). A failure makes the claim `broken`, with the failure and its replay command as a
gap. A claim the fuzzer didn't reach, or can't run, is a gap.

## Results

Apple M4 Max, 2026-10-23, seed 0 (details in [bench/fuzz.md](../bench/fuzz.md)), on the
examples while they were in this repository; they are in cairn_examples now (`make fuzz` there):

| App | Mode | Sequences × steps | Time | Sequences/s | Steps/s | Failures |
|---|---|---|---:|---:|---:|---:|
| Basics | runtime | 1,000 × 50 | 2.0 s | 490 | 24,500 | 0 |
| Basics | runtime | 2,000 × 200 | 17.0 s | 117 | 23,600 | 0 |
| Counter | runtime | 10,000 × 200 | 46.9 s | 213 | 42,700 | 0 |

Neither app has a bug the fuzzer finds, including 2,000 × 100 more from a random seed. Mutants
show it would: dropping the delete control for done items is caught as presence ^104 and shrunk
from 28 operations to 5 (the printed flow compiles in the app; its theorem fails on the mutant
and holds on the real app); a 10 px row height is caught as pressable-check, blamed on ^103#1 and
shrunk from 13 operations to 2.

With the host (2026-10-25, seed 7000, 3,000 × 300 per app, [bench/fuzz.md](../bench/fuzz.md)):
no failures in Counter, Basics, Todo, Clock, Tray, Gallery or test/fixture, over 6.3 million
steps. The host answered 378,020 requests (60,792 failed, 89,126 after a cancel), sent 18,696
stray replies, 115,919 wakes (171,068 timers due), 138,816 subscription events (8,524 after a
stop) and 60,563 evictions. A mutant shows the image check would catch a cache that drops what
the frame draws: Gallery receiving `evicted` without cancelling the pending load is caught as
image on ^503 at step 143 and shrunk to 74 operations.

`make check` runs `make fuzz-quick`: test/fixture, with `cairn fuzz`, 200 sequences of 50 steps,
about 1.5 s plus linking the exe, host moves included. cairn_examples' `make fuzz-quick` runs the
same on its six apps, against the released Cairn.

## Yap: a random host

Yap's dictation is driven by the host, not by moves, so `lake exe yapfuzz` (yap-cairn's `make fuzz-yap`,
and in `make fuzz-quick`) plays a random host instead, in two modes, and writes one
`build/fuzz/Yap.json`:

- **host** (yap-cairn's `lean/Yap/Fuzz.lean`): inputs straight into the model's `step`, checking
  ^311–^323 as the model states them. It imports the model only, so it builds against mutants.
- **app** (yap-cairn's `lean/Yap/AppFuzz.lean`): messages into the app's `receive` and menu items
  into `menuStep`, as the Cairn runtime sends them. The host answers the requests the app made
  (files there or not, config.json and dictionary.txt good and bad, OpenAI's transcripts and
  errors, typing that fails), late, twice, out of order or never; fires the subscriptions the
  app has on (the key, the microphone, file watches, the poll) and some it doesn't; and starts
  and quits the original Yap. It keeps the day files' contents (an append, a write or a delete
  lands when its answer says it worked; a read gives what is there) and answers requests in
  any order, as the host's concurrent requests finish, so an append can land after the read
  that marks its line. It checks ^311–^323, ^346 and ^347 as `Yap` states them over
  `AppState` and effects, and ^347 on disk: once every request is answered, each transcript
  typed while kept, whose append worked, is `"typed":true` (a mark the app gives up on must
  say so in the menu). Dropping the original-Yap test from `wantsKey` is caught as ^346
  within 50 steps and shrunk; marking before the append is answered (the code before ^347) is
  caught in about one sequence in ten of 300 steps.

Each claim's entry has `hostSteps` and `appSteps`; `steps` is their sum.

## Limits

- It fuzzes the Lean model and runtime, not the host: no AppKit, Core Text or Metal. J's
  conformance driver covers the running app, and can replay fuzz sequences; the trusted-base
  fuzzer below covers the host's codecs, text input and metrics.
- The host is a model of the trusted claims, not the host: it never sends what they rule out
  (duplicate replies, wrong shapes, a clock going back), its replies' contents mean nothing
  unless the app supplies `replies`, a batch holds one host event, and it doesn't coalesce
  ticks or model the 4096-pixel cap. Images are evicted only by the least-recently-used rule
  over the pixel sizes it answered.
- A server is only as faithful as the fake: its world, its refusals and its lag are the
  app's or the library's model of the real one, and a pass says the app agrees with that model.
  Its world is printed only through `describe`, not in the sequence JSON.
- Flows are not fuzzed (their witnesses are proved live); they are n/a.
- Presence assumes every move has a control while enabled. A move meant to be keyboard-only
  would need an opt-out in `Custom`.
- In a virtual list, presence assumes a row's controls are keyed by the row's key. A move with
  controls in rows keyed otherwise is checked as if it were outside the list, and one keyed like a
  row that isn't laid is allowed to be absent.
- Wall-clock budget checks depend on the machine; they report, they don't fail.
- Printed theorems use mono metrics; a failure found only with random metrics may need a
  different size or text to fail under mono.
- Shrinking removes operations; it doesn't simplify text or renumber keys, and window size and
  metrics stay those of the seed.
- The fuzz exe links `Lean` (for `fuzz_targets%`), about 100 MB; apps and the host don't.

## Trusted base

The claim fuzzer above checks the Lean side. `make fuzz-trusted` checks the parts Lean's proofs
take on trust (docs/trusted.md): the Swift half of each boundary, run against Lean's proved half
in one process. One check per trusted item; each `assume` claim in
`Cairn.Fuzz.Trusted.Claims` (^901–^915, ^960–^975, ^990–^991) names its check with `check "…"` (docs/claims.md), so
the report is the claim's evidence.

```sh
make fuzz-trusted                 # N=20000 cases a suite, SEED=0; release build
make fuzz-trusted N=200000 SEED=7
host/.build/release/CairnFuzzTrusted --replay frame --case 1234 --seed 7   # one case, verbose
```

The executable (`host/Tests/CairnFuzzTrusted`) links the host and a small Lean library,
`TrustedFuzz` (`lean/Cairn/Fuzz/Trusted/`: generators, a one-field app and C exports, plus
`Cairn.Frame.Dump`; no `import Lean`), next to `libcairn_lean.a`. libFuzzer is not available (`-sanitize=fuzzer` is unsupported for
arm64-apple-macosx27 in Xcode 27.1), so it is a seeded loop on SplitMix64, the same PRNG as
`Cairn.Fuzz.Rng`: case `i` of seed `S` replays alone. Each suite runs in a child process that
records the case it is on, so a crash in trusted code is reported with its case and the run goes
on after it.

| Check | Claim | Trusted | Checked against | Inputs |
|---|---|---|---|---|
| `frame.decode` | ^901 | `Frame(bytes:)` | Lean's `decodeFrame`: same accept/reject, same canonical dump | Lean-encoded random frames, then bit flips, edge bytes, length and count fields ±1/±4/huge, truncation, splices of two frames, inserted and deleted bytes, header bytes, trailing bytes |
| `events.encode` | ^902 | `encodeEvents` | Lean's `decodeEvents` accepts, same dump; Lean's `encodeEvents` gives back the same bytes | random batches of every event, extreme integers, text from the pool below, multi-scalar `Key.char` |
| `text.index` | ^903 | `TextIndex` | Swift's `unicodeScalars`/`utf16` views and `NSString` | text below; offsets on, between and inside surrogate pairs; `NSNotFound`, negative, `Int.max`, `Int.min` |
| `text.shadow` | ^904 | `TextInputShadow` | the next frame of a Lean field app (`TextInput`) | 4–24 input-method calls a sequence: `insertText`, `setMarkedText` with selections and replacement ranges (valid, inverted, out of range, mid-pair), `unmarkText`, editing commands, resizes |
| `text.input-client` | ^905 | `HostView`'s `NSTextInputClient` | Lean's frame: `selectedRange`, `markedRange`, caret rect; round trips | same sequences; `firstRect`, `characterIndex(for:)` at the caret and at random points, `attributedSubstring`, after every frame |
| `text.metrics` | ^906 | `cairn_text_metrics`, `TextSystem`, `Fonts` | `TextMetrics.Valid`'s shape; Lean's `TextMetrics.host` through `cairn_text_host_check` (normalise must be the identity) | families 0, 1, 2 and random; sizes 0, 1, 2, 8–400, 1024, 1025, 2³²−1; weights 0–1000 and 2³²−1; italic; the four widths; tracking −300–600, ±100,000 and the Int32 extremes; tabular digits; text below; invalid UTF-8; short and null output buffers |
| `text.metrics.carets` | ^907 | the same, and Core Text | the glyphs Core Text lays out on a fresh `CTLine` | the same, left-to-right only |
| `clock.monotonic` | ^908 | `HostClock`, `Engine.timed` | `CLOCK_MONOTONIC` and `Date` read as each batch arrives at a Swift app (`WakeCore`) | every batch of a run through the real `Engine`; `HostClock.now()` from 2–8 threads at once |
| `clock.wake` | ^909 | `Engine`'s wake timer | the frame's `wake` and the clock of the batch that answers it | deadlines 0 (already due) to 80 ms; deadlines cleared before they come due; 1–3 a case |
| `effects.read-file` | ^910 | `Files.read` | the bytes written; the file system's state | paths of 1–3 components from the text pool (NUL, refused names), missing files, directories, unreadable files |
| `effects.write-file` | ^911 | `Files.write` | `FileManager` reads after `done`; a reader thread during replacement; POSIX `mkdir`/`open` of the same names | 0 bytes to 2 MB, replacing 1–3 times, writes under a file and over a directory, read-only directories |
| `effects.sound` | ^912 | `Sounds` | the files in `/System/Library/Sounds` | every system name; random and near-miss names (played only with `CAIRN_FUZZ_SOUND=1`) |
| `effects.http` | ^974 (was ^913) | `HTTP.run`, `SecretHTTP.run` | a `URLProtocol` stub: what it received and what it answered | methods, paths with URL-illegal characters, token headers with pool values, bodies to a few hundred bytes, statuses 100–599; refused URLs, methods and headers (CR/LF/NUL); connection failures; a server that never answers with 50–200 ms timeouts; environment and Keychain secrets present, missing or with CR/LF/NUL; redirects to another host with and without a secret |
| `effects.reply-once` | ^914 | `World` (requests) | the requests run and what each handler answered first; `reset`'s return | 1–24 requests a case with distinct random ids; handlers that answer 0–3 times, in order or racing on other threads, after 0–3 ms; a kind with no handler; a `reset` at a random moment |
| `subs.every` | ^915 | `World` (subscriptions) | the started/stopped model of the commands; the monotonic clock | 1–8 frames of 0–4 start/stop commands over 5 ids (restarts with a new period, stops of ids not running), periods 1–40 ms, 0–60 ms between frames, then `reset` |
| `effects.append-file` | ^960 | `Files.append` | the concatenation of the bytes appended; mode 600 on a new file; FileManager reads | 1–4 appends of 0 bytes to 2 MB under 1–3 random components; 2–4 threads appending 1 B–70 KB chunks at once (each chunk must land whole, in its thread's order); a directory, under a file, a read-only file, NUL and refused names |
| `effects.list-dir` | ^961 | `Files.list` | the names the case made; `FileManager.contentsOfDirectory`, byte for byte | 0–300 files, directories and dangling links with names from the text pool; missing, a file, unreadable, NUL, empty |
| `effects.make-dir` | ^1003 | `Files.makeDir` | `stat` of each component before and after | 1–3 components from the text pool, 0–all of them there already (mode 755, kept), umasks 022, 077 and 000; again; over a file, under a file, a read-only parent, NUL, empty |
| `effects.delete-file` | ^962 | `Files.delete` | `lstat` before and after; the link's target | a file, a link (the target stays), a dangling link, a directory (refused, stays), a read-only parent (refused, stays), again (`notFound`) |
| `subs.watch-file` | ^963 | `World` (`watchFile`), `FileSignature` | the changes the case made | polls of 5–20 ms; 2–5 operations a case: write in place, atomic replace, append, delete, create, `touch`, `chmod`, nothing, a sibling written; then the stop and a write after it |
| `effects.frontmost-app` | ^964 | `Apps.frontmost` | a stubbed source; for the live answer `NSRunningApplication` and `kill(pid, 0)` | pids 1 to `Int32.max`, 0 and −1; names from the text pool and none; no app |
| `effects.open-item` | ^1000 | `Opening.open` | a stubbed workspace: the URLs it was asked to open | URLs with schemes, `~/` and absolute paths that exist or not, the workspace taking them or not, empty and NUL targets |
| `effects.app-running` | ^1001 | `Opening.running` | a stubbed workspace; `NSRunningApplication` for the live Finder | 0–2 running apps; Yap's, the Finder's and random ids, empty ones; the live Finder and an id no app has |
| `effects.read-default` | ^1002 | `Opening.readDefault` | a stubbed defaults store and the value's own text | strings from the text pool, booleans, numbers, missing, data and arrays; empty domains and keys |
| `render.paint.bounds` | ^1004 | `Renderer` (paint batches), `Painters`, `YapTape` | the same frame rendered without its paint draws | 1–8 draws (rects, text, clips, paints) in a 1–160 × 1–120 frame at 1x, 1.5x, 2x, 3x; boxes inside, across, outside and far outside the frame, empty and 2³¹ wide; Yap's tape with random and malformed data, a painter covering 100× the viewport, one scattering triangles, an unregistered name; random times and origins |
| `effects.load-image` | ^1006 | `ImageLoad.run`, `ImageStore` | the sizes and orientations it encoded; a `URLProtocol` stub keyed by path | PNG, JPEG, TIFF, GIF, BMP, HEIC, 4–220 pixels a side (sometimes 4097–6000 on one), the eight EXIF orientations; files and https URLs; missing, unreadable, directories, empty, NUL, garbage, truncated; statuses 304, 401, 403, 404, 410, 418, 500, connection failures; reloads with new bytes, failed reloads, many loads at once |
| `render.image.bounds` | ^1007 | `Renderer` (image batches) | the same frame rendered without its image draws | 1–8 draws (rects, clips, images) in a 1–160 × 1–120 frame at 1x, 1.5x, 2x, 3x; boxes and destinations inside, across and outside the frame; unknown sources |
| `render.image.pixels` | ^1008 | `ImageStore.decode`, `Renderer` (image batches, `image_fragment`) | the colour of each quadrant of the oriented image | four-quadrant images of every format and orientation, boxes up to 160 × 160 (minified, and 4–12 pixel images magnified), at 1x, 1.5x, 2x, 3x |
| `window.min-size` | ^1010 | `WindowSizer` (`apply`, `windowWillResize`) | the latest minimum asked for; the window's frame before each step | 1–12 steps on a hidden resizable window: minimums negative, 0 and 1–2400 a side, drags to 1–2600 × 1–1600 proposed to the delegate and then set |
| `images.cache` | ^1011 | `ImageStore` (`setBudget`, `setDrawn`, `put`, `remove`), `World` (`imageCache`) | a least-recently-used model of the store; a copy of Lean's `Images` table fed the `World`'s events in order | 5–60 puts (4–32 pixels a side), removals, drawn sets and budgets; 3–10 files loaded concurrently with and without `reload`, deleted and restored, frames drawing what the app takes for ready, budgets of 0–3 large images |
| `pointer.click` | ^7 | `HostView` (`mouseDown`, `mouseUp`, `point`), `Engine`'s queue | the click's window location flipped and rounded down by the suite; the event's modifier flags | 1–10 clicks a case in a hidden titled window of 40–1600 × 40–1000 whose content is a `HostView` over a recording core; points fractional, whole and on the content's edges; random shift, command, option, control; each event sent to the view AppKit's `hitTest` picks |
| `pointer.scroll` | ^1012 | `HostView.scrollWheel`, `ScrollAccumulator`, `Engine`'s queue | AppKit's `scrollingDeltaX`/`Y` negated and summed (×16 for lines), within a point; the event's window location flipped and rounded down | one gesture a case at a random point of a hidden 40–1600 × 40–1000 window: 1–30 trackpad pixel deltas (began, changed) or wheel line deltas in 1/64ths, on either axis or both, from `CGEvent(scrollWheelEvent2Source:)` |
| `pointer.double-click` | ^214 | `HostView.mouseDown`'s `clickCount` | the `clickCount` of each mouse down, at the first click's point | the same cases: double and triple clicks, the later downs and ups `clickCount` 2 and 3, within the double-click interval |
| `text.secure-input` | ^1020 | `SecureInputGate` as `HostView.updateSecureInput` drives it; Carbon's `EnableSecureEventInput`, `DisableSecureEventInput` | the frame's `TextInput.secure`, the window's key state and the view's life, step by step; `IsSecureEventInputEnabled` read back | 1–30 steps a case of no, plain or secure text input, key or not, live or not, ending closed; one case in eight makes the system's calls |
| `ax.scroll` | ^1021 | `AXMirror` (`update`, `hidden`, `hitTest`), `HostView`'s accessibility overrides | the frame's AX nodes, each node's parent chain walked by the suite: scrolled out when it or a node above it has an empty rect with a scroll area above that | 1–40 nodes a case of every role, scroll areas nested anywhere, a parent before its children; 1–4 frames of one tree with new rects (empty with w, h or both 0, or visible), a focused node or none; the tree walked through `accessibilityChildren` and `accessibilityParent`, 8 hit tests a frame, in a hidden window |
| `ax.secure` | ^1022 | `AXNodeElement` (subrole, value, text, selection), `DebugJSON.describe` | text planted in secure nodes' values, the focused secure field's text input, and requests' headers, bodies and redacted URLs, looked for in every attribute and description; plain fields' values as a control | the same trees, half the text fields secure; 4 `http` requests a case, redacted or not, with or without a Keychain secret and captures |
| `dock.badge` | ^1030 | `Notices.badge` as `HostView.run` runs it | the labels sent, against `NSApp.dockTile.badgeLabel` read back | 1–3 frames a case of up to 4 effects: `badge` with none, empty, digits, `99+`, up to 40 characters or any Unicode, mixed with `announce`, `scrollTo` and `focus`, through the engine into a `HostView` in a hidden window; ends with `badge none` |
| `ax.announce` | ^1031 | `Notices.announce` as `HostView.run` runs it | the texts and priorities sent, against a recorder in place of `NSAccessibility.post` | the same frames: announcements of any text at either priority |
| `control-menu.render` | ^945 | `ControlMenuHost`, `MenuHost` | the window record's menu records as a tree (the ^940 oracle), and its owner | 1–4 frames a case to a `HostView` in a window never shown, each with a random control menu (nested submenus, greyed items, separators, status lines, checkmarks, shortcuts over the whole `Key` table) for a random owner, or none |
| `control-menu.select` | ^946 | `ControlMenuHost`, `MenuHost`, `NSMenu.performActionForItem` | `[menuSelect(window, ref), menuClose]` for an enabled item, `[menuClose]` for the rest | a random item of the open menu chosen, then the menu closed |
| `control-menu.dismiss` | ^947 | `ControlMenuHost` | the sequence numbers of the host's close and of each frame | frames with and without the menu and the window, and stale frames after a close, on a detached host |
| `ax.show-menu` | ^948 | `AXMirror` (`AXShowMenu`, role), `HostView` | the AX nodes with a menu; the events a secondary click sends | random AX trees, some nodes with menus or menu buttons; `AXShowMenu` performed on every element |
| `menubar.render` | ^949 | `MenuBarHost`, `MenuHost` | the `menuBar` record split into menus and app-menu items, and the host's own menu | 1–4 frames of random menu bar records on a detached host whose main menu is its own copy, updated in place and rebuilt |
| `menubar.select` | ^950 | `MenuBarHost`, `MenuHost`, `NSMenu.performActionForItem`, `performKeyEquivalent` | one `menuSelect(place, ref)` for an enabled item, nothing for a greyed one | items chosen by action, and by the key event a keyboard sends for every unambiguous letter shortcut |
| `world.hold` | ^1032 | `Engine.holdClock`, `World.holdRequests` | the events the case sent after the hold; handlers that record that they ran | 0–2 requests and a wake 0–5 ms away before a hold 0–4 ms later; then 1–5 rounds of clocks, replies, input, wakes due now or soon, and requests, through a real `Engine` and `World` |
| `effects.cancel` | ^1009 | `World` (`Cancellation`, `cancelRequest`), `HTTP.run`, `ImageLoad` | a `URLProtocol` stub recording which loads started and which were stopped early; the store before and after | 1–12 `http` and `loadImage` requests (with and without `reload`), some held open by the stub; cancels in the same frame, while running and after the answer; 0–2 cancels of ids never sent |
| `effects.permission` | ^965 | `Permissions.check` | a stubbed TCC: statuses and the calls made | both permissions × trusted or not × the four microphone statuses × prompt × granted or not; the live system without prompting |
| `subs.record` | ^966 | `World` (`record`), `LevelMeter`, `Clips` | a fake microphone's delivered samples; levels computed directly from them | 0–2 s of synthetic audio (silence, square waves, noise, ±32768 extremes) split into buffers of 0–4000 samples, delivered from another thread with 0–3 ms pauses; stops and resets after 0–100 ms; failing microphones; the meter over random splits |
| `effects.clip-wav` | ^967 | `Clips.wav`, `WAV`, `forgetClip` | the RIFF/WAVE layout written out field by field; the samples | 6 ranges a case in and past 0–6000 samples, to the end or not; clips that finish 20 ms after the ask; unknown and forgotten clips; 1–20 clips begun (at most 8 kept) |
| `subs.global-key` | ^968 | `KeyWatch`, `World` (`globalKey`) | a state-table model of Yap's PushToTalk; a fake key source | Yap's 7 modifier and 3 ordinary hotkeys; 0–60 events of each kind on the hotkey and others, with repeats and unrelated flag bits; untrusted; codes past 16 bits; events after the stop |
| `effects.type-text` | ^969 | `Typing.runs`, `Typing.type`, World's handler | the text's UTF-16 and Characters; a fake typist's calls | pool text, emoji runs, a 15–30-mark character, empty; trusted or not, app or not, comes forward or not, pids 0 to 2³²−1, Return or not |
| `effects.upload` | ^970 | `Upload` (`body`, `run`) | a `URLProtocol` stub: what it received | 0–5 bytes and wav parts (some bad ranges and unknown clips); Yap's multipart shape around a whole-clip wav part; statuses 200, 400, 500 |
| `effects.secret` | ^975 (was ^971) | `SecretSource` | generated `KEY=value` files with a known meaning; every reply, message and debug description | comments, blanks, `export`, quotes, spaces, `=` and `#` in values, repeated keys; environment set, empty or not; unreadable files; secrets with CR LF |
| `effects.secret.keychain` | ^972 | `KeychainStore`, `MemoryStore`, `ForgetSecret`, `SecretSource.resolve` | a dictionary model of the items; a `URLProtocol` stub | writes, reads, overwrites, deletes and `forgetSecret` over three accounts with ASCII, edge-Unicode, empty and 500–3000 character values, on memory and on the live login keychain under a throwaway service (skipped with `CI` set or `CAIRN_FUZZ_KEYCHAIN=0`); requests whose Keychain secret is present or missing; live, once per worker, a child process making 240 concurrent calls on one service (store calls, `forgetSecret`, secret headers, captures) within 30 s (#237) |
| `effects.http.capture` | ^973 | `JSONCapture`, `SecretHTTP` | generated JSON objects whose captured fields and blanked form are known; planted markers searched in replies, messages, event bytes, dumps and debug descriptions | escaped keys and values, surrogate pairs, whitespace, nested reuse of captured names, decoys; missing, repeated and non-string fields; non-objects; statuses outside 2xx; a store that fails a write |
| `text.wrap.painted` | ^990 | `TextSystem` shaping each wrapped line alone | Lean's `layout` of a `Node.para` and `Text.Wrap.allLines` through `cairn_tf_wrap_lean`: line rects, and width and carets from the whole-string shaping | plain letters, digits and spaces, or the text pool mixed in; families 0–2, sizes mostly 9–32 (sometimes 1–120), weights, italic; widths mostly 20–600, sometimes 0–20 |
| `text.wrap.coretext` | ^991 | Lean's breaks, against Core Text's | `CTTypesetterSuggestLineBreak` from the same start, trailing spaces trimmed | the plain-text cases of the same |

Text comes from one pool in both languages: ASCII, edge scalars (NUL, controls, U+0085,
U+2028/9, BOM, U+FFFD, U+FFFE/F, U+10FFFF, surrogate-adjacent, private use), ZWJ families,
skin tones, flags, tag sequences, keycaps, combining stacks, Devanagari conjuncts, CJK, Hebrew,
Arabic, bidi controls, and long runs of one scalar.

The effect suites (`clock`, `world`, `files`, `http`, `sound`, `fileops`, `system`, `audio`,
`input`, `upload`, `image`) run fewer cases than N (a
twentieth to a quarter): their cases wait on real time. Timing bounds are loose (a wake within
40 ms, a tick within twenty periods) so that a loaded machine during `make check` doesn't fail
them; the counters record the actual lateness (`late0ms`, `late1ms`, …).

The input-client suite drives a real `HostView` and `Engine` with a Lean app (one text field
with `TextMetrics.host`) in a borderless window that is never shown. It checks the shadow after
every call, and the geometry once the frame for the call has arrived.

`text.metrics.carets` checks that the caret after each grapheme lies at or right of where every
glyph painted for the text before it ends (its advance, or the next glyph's start in the same
run if sooner), less 1 pt + 0.15 em for kerning, fallback fonts and rounding. Where Core Text's
own caret already sits inside a glyph and the host passed it on unchanged, the case is counted
(`coreTextCaretInsideGlyph`) and not failed: that is Core Text's behaviour, listed below. A
tracked line's carets are the host's own (finding 11), so they are counted as `tracked` and
always checked.

`text.wrap.painted` and `text.wrap.coretext` run `N / 2` cases. The painted check allows
`1 + ⌈0.15 em⌉` points: a line shaped alone loses the kerning across the dropped break space
and across a cut (`widthSpaceKern`, `widthCutKern`; `widthExact` and `widthOff1` are the rest).
It skips bidi text (`skippedRTL`), controls and line separators (`skippedControl`), lines with
tabs (`tab`) and lines whose cut splits a grapheme cluster (`clusterCut`), and only counts
strings that need fallback fonts (`fallbackSame`, `fallbackDiffers`), which can pick another
font for a neutral character when shaped alone. The Core Text check compares the first line
where the two differ: Core Text's typesetter refuses lines a fraction of a point under the
width that Lean's rounded-up carets accept, and cuts over-wide words by its own fractional
widths; those are counted (`roundingDiffers`, `cutDiffers`) and anything else fails. At
40,000 cases (seeds 11 and 23, debug build, 70 s each): painted held in 18,700 cases and about
950,000 lines (`widthSpaceKern` 3–6, `widthCutKern` about 20,000); Core Text agreed on about
8,600 of 10,100 plain cases, the rest `roundingDiffers` (about 240) and `cutDiffers` (about
1,300).

### Output: `build/fuzz/trusted.json`

```json
{
  "version": 1, "seed": "0", "n": 20000, "seconds": 41.4, "date": "2026-10-23T…Z",
  "checks": {
    "frame.decode": {
      "title": "…", "suite": "frame", "claims": ["^901"],
      "trusted": ["host/Sources/CairnFrame/Decode.swift", "…"], "oracle": "…",
      "cases": 20000, "failingCases": 0, "pass": true,
      "evidence": "held in 20000 cases",
      "seconds": 12.0, "casesPerSecond": 1673,
      "counters": {"leanAccepts": 6272, "leanRejects": 13728, "mutated": 16877},
      "failures": [{"case": 17, "seed": "…", "message": "…", "repro": "hex:…"}]
    }
  }
}
```

- `seed` is a string (a `UInt64`); `n` is the run's size. Expensive suites run fewer cases
  (input sequences: `n / 5`), and `text.metrics.carets` counts only left-to-right cases.
- `pass` is `null` and `evidence` is `"not run"` when a check ran no cases (`--only`).
  `evidence` is otherwise `"held in N cases"` or `"failed in F of N cases"`.
- `claims` lists the `assume` claims naming the check (with `--claims`, which `make` passes).
- `failures` keeps the first 10. `repro` is a minimal input: `hex:` bytes for codecs (frame
  failures are shrunk: header first, then byte deletion), the call sequence for input, the font
  and string for metrics. A crash is a failure of the suite's first check with message
  `crashed (signal N): <the case>`. `case` and `seed` replay it with `--replay`.
- `counters` are per-check tallies of what was exercised (`mutated`, `leanAcceptsNonCanonical`,
  `rangesSplittingPairs`, `edits`, `invalidUTF8`, `coreTextZeroAfterGlyphs`, …).

The quick run in `make check` (`make fuzz-trusted-quick`) is 500 cases a suite on the debug
build, written to `build/fuzz/quick/trusted.json`: about 2 s.

### Throughput

Release build, Apple silicon, `make fuzz-trusted N=20000` (41 s in all):

| Check | Cases | Seconds | Cases/s | Notes |
|---|---:|---:|---:|---|
| `frame.decode` | 20,000 | 12.0 | 1,670 | mostly Lean decode and both dumps; about 30% accepted |
| `events.encode` | 20,000 | 0.5 | 39,600 | 179,000 events |
| `text.index` | 20,000 | 0.3 | 72,100 | |
| `text.shadow`, `text.input-client` | 4,000 sequences | 22.1 | 181 | 55,700 input-method calls and 13,740 caret checks, through the real `Engine` threads |
| `text.metrics` | 20,000 | 5.9 | 3,380 | |
| `text.metrics.carets` | 11,205 | 5.9 | 1,900 | 334,000 scalars; 4,889 right-to-left cases skipped |

### Findings

Each fix is its own commit, with a regression test holding the minimal repro.

1. **The Swift decoder ignored the frame's flags** (`frame.decode`, fixed in
   `CairnFrame/Decode.swift`). Lean rejects a nonzero flags field (reserved in v1); Swift
   accepted it. Repro: the 48-byte empty frame with byte 6 set,
   `hex:434146520100c500` followed by 40 zero bytes. Test: `FuzzRegressionTests` in
   CairnFrameTests.
2. **The text-input shadow kept line breaks** (`text.shadow`, fixed in
   `TextInputShadow.swift`). Lean's single-line field stores LF, CR, VT, FF, U+0085, U+2028 and
   U+2029 as spaces (`Field.clean`); the shadow kept them, so its prediction diverged until the
   next frame (47 of 200 sequences). Repro: `insertText("a\nb")` into an empty field: shadow
   `"a\nb"`, Lean `"a b"`. Test: `HostFuzzRegressionTests.shadowFlattensLineBreaks`.
3. **Input-method geometry was lost when a field scrolled** (`text.input-client`, fixed in
   `TextInputClient.swift`). With the caret past the field's right edge, the text draw starts
   left of the field, the host found no text draw inside the field, and
   `characterIndex(for:)` returned `NSNotFound` while `firstRect` collapsed to a zero-width rect
   at the caret (103 of 200 sequences). Now it measures from the frame's `textOrigin`. Repro:
   a 40 × "w" field drawn at x −250 in a 180-wide field; `firstRect` of scalars 30..<35, then
   `characterIndex` at its left edge, should be 30. Test: `ScrolledFieldTests`.
4. **Core Text reports some carets as 0** (`text.metrics.carets`, fixed in
   `TextSystem.swift`). `CTLineGetOffsetForStringIndex` answers 0 before a trailing control
   (`"a\u{0}"`: 0 at index 1; also U+0080, U+200E, tag characters) and for every later index
   after some fallback runs (`"\u{93F}\u{1F3FB}\\x"`: 0 at 3 and 4, though `\` and `x` are
   painted at 43 and 48 at 20 pt). The running max turned these into zero-width scalars at an
   earlier caret, so Lean's caret and hit testing sat left of painted text: 405 of 28,046
   left-to-right cases. Now a 0 at a nonzero index falls back to where the first glyph for the
   text at or after it starts, or the line's end. Tests: `RenderFuzzRegressionTests`.
5. **Core Text's own caret can sit inside a painted glyph** (not fixed; counted as
   `coreTextCaretInsideGlyph`, 170 of 11,205 cases). An unassigned private-use scalar drawn
   with LastResort: in `"\u{4AA2}L\u{FFFD}4\u{F89E}\u{100}{/"` (family 1, 22 pt, weight 900),
   the caret after U+F89E is at 63, the glyph's start, though the glyph is 24 pt wide. Runs of
   CJK brackets with contextual spacing: `"\u{300C}\u{300C}\u{300C}"` (family 1, 31 pt, weight
   886) has carets 15 and 37, glyphs starting at 23 and 45. Lean's caret lags the painted text
   by up to a glyph there. A fix would replace Core Text's caret model with one built from the
   glyph runs; that is a design change for workstream F, so it is reported, not made.

6. **A NUL in a path cut the path** (`effects.write-file`, fixed in `World.swift`). Foundation
   passes the path to the file system as a C string, so `"a\u{0}b"` named the file `a`. Now a
   path with NUL is `failed invalid`.
7. **Names APFS refuses were `failed other`** (`effects.write-file`, fixed in `World.swift`).
   APFS rejects names with unassigned code points or noncharacters (`EILSEQ`): 3 of the first
   200 cases. They are `failed invalid` now (and `ENAMETOOLONG` with them); the oracle makes
   the same names with POSIX calls to know which to expect.
8. **The list-dir oracle lost a leading BOM** (`effects.list-dir`, 61 of 256 cases at seed 0,
   N=20,000; the oracle was wrong). `FileManager.contentsOfDirectory(atPath:)` decodes names
   as NSString does, which drops one leading U+FEFF: `"\u{FEFF}a"` comes back as `"a"`, a name
   that isn't in the directory. `Files.list` reads `readdir`'s bytes, so its names are the
   real ones and its order is UTF-8 byte order, as docs/effects.md promises. The oracle now
   lists URLs and reads each one's file-system representation. Test:
   `WorldTests.listDirKeepsALeadingBOM`.
9. **One save could bring two `changed`** (`subs.watch-file`, 2 of 244 cases at seed 0,
   N=20,000; fixed in `World.swift`). An atomic replace and an append that creates the file
   each pass through two or three `stat` states within a millisecond (macOS moves the old
   file's change time before the rename, and a new file's again when it attaches its
   provenance attribute), and a poll that landed between them reported both. The host now
   reports a state once it has held for a whole poll, which also keeps Lean from reading a
   write in place half done.
10. **Pool components with a slash confused two oracles** (`effects.list-dir` seed 0 case 210,
   `effects.write-file` seed 1 cases 939 and 4157, `effects.append-file` seed 2 case 480;
   the oracles were wrong). A component such as `"(_/\u{E0067}"` is two path components:
   the host creates every missing parent, while the POSIX oracle `mkdir`'ed it as one (ENOENT,
   so it expected a refusal) and list-dir counted it as a name. Both now split by bytes (a
   `"/"` followed by a combining or tag scalar is one Swift `Character`).
11. **Core Text's carets are wrong on tracked lines** (`text.metrics.carets`, 3 of 11,043
   cases at seed 0, N=20,000, after frame v4 added tracking; fixed in `TextSystem.swift`).
   Untracked text had no failure and 1 `coreTextCaretInsideGlyph`; every failure and nearly
   all of the 19,360 inside-glyph counts were tracked. Core Text puts a tracked caret half the
   tracking short of the next glyph ("abc", 20 pt, tracking 5: glyphs at 0, 17.4, 34.7, carets
   14.9, 32.2, 47.1), and beside a control whose glyph advance is just the tracking it is
   wrong outright: in `"\u{94D}t\u{FFFD}\u{FFFD}ab\there"` (family 1, 312 pt, tracking −156)
   the caret before the tab is 1227.6, after it 1131.9, and after the h 1226.0, the middle of
   an h painted from 1130 to 1322. Large negative tracking also runs glyphs backwards
   (tracking −2³¹: the caret after `क्षि` was 0, its first glyph painted to 10). A tracked
   line's caret is now where the pen is after every glyph drawn for the text before it (the
   furthest position + advance), so it is right of everything painted before it; untracked
   lines keep Core Text's carets and their numbers are unchanged. Repros: seed 0, cases
   1131, 2037 and 3941.

Also changed while writing the suites, found by reading rather than by a failing case: a reply
checked against the world's generation and then sent outside the lock could arrive after
`reset` returned (now sent under the lock), and header names and values were passed to
Foundation unchecked (now tokens, and no CR, LF or NUL). The `http` oracle compares URLs as
Foundation parses them: it percent-encodes characters a URL can't hold (`|`, `` ` ``, `^`, a
lone `%`), which the first run reported as a difference.

Not findings: Lean accepts about 2% of mutated frames that are not canonical (reserved bytes it
ignores; `A~` in the verdict), and Swift agrees on every one. A `count` field of 2³²−1 makes
the Swift decoder reserve that many elements before failing; virtual memory absorbs it (no crash
in 20,000 cases), but a cap would be cheaper.

### Yap: a random host

Yap's dictation is driven by the host, not by moves, so `lake exe yapfuzz` (yap-cairn's `make fuzz-yap`,
and in `make fuzz-quick`) plays a random host instead, in two modes, and writes one
`build/fuzz/Yap.json`:

- **host** (yap-cairn's `lean/Yap/Fuzz.lean`): inputs straight into the model's `step`, checking
  ^311–^323 as the model states them. It imports the model only, so it builds against mutants.
- **app** (yap-cairn's `lean/Yap/AppFuzz.lean`): messages into the app's `receive` and menu items
  into `menuStep`, as the Cairn runtime sends them. The host answers the requests the app made
  (files there or not, config.json and dictionary.txt good and bad, OpenAI's transcripts and
  errors, typing that fails), late, twice, out of order or never; fires the subscriptions the
  app has on (the key, the microphone, file watches, the poll) and some it doesn't; and starts
  and quits the original Yap. It keeps the day files' contents (an append, a write or a delete
  lands when its answer says it worked; a read gives what is there) and answers requests in
  any order, as the host's concurrent requests finish, so an append can land after the read
  that marks its line. It checks ^311–^323, ^346 and ^347 as `Yap` states them over
  `AppState` and effects, and ^347 on disk: once every request is answered, each transcript
  typed while kept, whose append worked, is `"typed":true` (a mark the app gives up on must
  say so in the menu). Dropping the original-Yap test from `wantsKey` is caught as ^346
  within 50 steps and shrunk; marking before the append is answered (the code before ^347) is
  caught in about one sequence in ten of 300 steps.

Each claim's entry has `hostSteps` and `appSteps`; `steps` is their sum.

## Limits

- A seeded loop, not coverage-guided: no libFuzzer on this toolchain. Mutations are structural
  (the frame format's length and count fields) to make up for it.
- Frames and events are compared through two dump printers (Lean's `Cairn.Dump` and the
  Swift tests' `Dump`), which could share a bug. `events.encode` also compares bytes.
- Input-method calls are shaped like an input method's; no real input method runs, and the
  window is never shown or made key. `firstRect`'s screen conversion is checked only in window
  coordinates.
- `text.metrics.carets` skips right-to-left and bidi text (out of scope in M1), and its
  oracle is Core Text's own glyph layout, so it cannot catch Core Text laying glyphs out
  wrongly. Ink (painted pixels) is covered by `InkTests`, not fuzzed. Fonts are the system UI
  and monospaced families; no custom fonts.
- A worker that crashes loses up to a second of tallies (stats are flushed every second); the
  crash itself is always reported.
- The renderer (Metal) is not fuzzed.
- Wrapping: left-to-right only; right-to-left, bidi and complex-script line breaking are not
  checked, and the Core Text comparison uses plain text only (no pool strings).
- Effects: the sound is not heard, only looked up (and played with `CAIRN_FUZZ_SOUND=1`); HTTP
  goes to a stub, not a network (no TLS, redirects or proxies); files live in one temporary
  directory on the boot volume. The clock checks run while the machine is awake; sleep is not
  exercised.

# Optimistic values

`Cairn.Optimistic` (lean/Cairn/Optimistic.lean) holds values that a person changes and a server
keeps, such as whether a post is liked, a repost or a follow. A change shows in the step it is
made. The table then sends one write for it, and the server's answer confirms the change or
rolls it back. The table never talks to a server itself. The app turns its outputs into requests
and the answers to those requests into its inputs. So the same table serves Bluesky, a fake
server in Lean and the fuzzer's server.

What it guarantees, for any server that keeps a value per key (a register) and treats a repeated
write as one (idempotent writes):

- a set shows in its own step;
- at most one write is in flight per key, and the table never sends more writes than there were
  sets;
- a refused write shows the server's value again in the step the refusal arrives;
- once a key has nothing in flight and nothing in doubt, it shows what the server holds, whatever
  order the replies came in and whichever were lost before or after the server acted;
- a count over a boolean value is the server's count, and never goes below zero;
- a view, which may be stale, never moves a key written this session;
- inputs for different keys commute.

Each guarantee is a theorem and a `cairn^N` claim ([The theorems](#the-theorems)).

## The API

```lean
import Cairn          -- Cairn.Optimistic is linked, with no `import Lean`
open Cairn.Optimistic

-- Keys are anything with a lawful `Ord` (a post's URI, a DID); values anything. `same` says
-- when two values mean the same to the server. Booleans use `==`; a like record uses
-- "both liked or both not", whatever its record key.
def likes : Table String Bool := .empty false (· == ·)

let (t, outs) := likes.feed (.set uri (fun b => !b))  -- a press
t.shown uri       -- what to show: the person's last set, at once
t.server uri      -- the last value the server confirmed
t.inFlight uri    -- a write is out
t.inDoubt uri     -- a write's answer was lost; reading back
t.settled uri     -- nothing outstanding: shown is the server's (once replies are in)
```

`Table.feed t i` returns the table and a list of `Out`s, which the app carries out in order.
`Table.run` feeds a list.

### Inputs (`Input K V`)

| Input | When the app feeds it |
|---|---|
| `set k f` | the person changes key `k`: it shows `f` of what it showed |
| `acked t` | the write sent under ticket `t` succeeded (2xx) |
| `refused t why` | the server answered the write with a refusal (4xx): it did not apply it |
| `lost t` | the write's reply never came or can't be trusted (a timeout, a network failure, a 5xx): it may or may not have been applied |
| `read t v` | the read sent under ticket `t` answered: the server holds `v` |
| `readFailed t` | the read failed in any way |
| `retry k` | the timer from `retryIn k ms` fired |
| `seen k v` | a view (a feed page, a post's viewer state) says key `k` is `v` |

### Outputs (`Out K V`)

| Output | What the app does |
|---|---|
| `write t v` | send a write that sets the key to `v` (an idempotent `PUT`, a create or delete by record key) and remember that its request id belongs to `t` |
| `read t` | send the authoritative read of the key (not a cached view) under ticket `t` |
| `retryIn k ms` | set a timer that feeds `retry k` after `ms` |
| `rolledBack k r` | say so: a line such as "Couldn't like: …" and an announcement. `r` is `refused why` or `notApplied` (a lost write that the read-back found the server never applied) |

### Tickets

Every request the table asks for carries a `Ticket K`, which is the key and the request's number
among that key's requests. An answer is matched to its key by the ticket, in O(log n). An answer
whose number isn't the key's current one is stale and is ignored. So a late, duplicated or
superseded answer changes nothing.

The runtime gives the app its own request ids (`Effect.request id …`, `Msg.reply id …`), so the
app keeps a map from request id to ticket:

```lean
structure State where
  likes : Table String Bool := .empty false (· == ·)
  tickets : Std.TreeMap Nat (Ticket String) := {}   -- request id → ticket
  nextReq : Nat := 0
  line : Option String := none                      -- the rollback line

def perform (s : State) : List (Out String Bool) → State × List Effect
  | [] => (s, [])
  | o :: os =>
    let (s, e) := match o with
      | .write t v => ({ s with tickets := s.tickets.insert s.nextReq t, nextReq := s.nextReq + 1 },
                       [.request s.nextReq (writeLike t.key v)])
      | .read t => ({ s with tickets := s.tickets.insert s.nextReq t, nextReq := s.nextReq + 1 },
                    [.request s.nextReq (readLike t.key)])
      | .retryIn k ms => (s, [.setTimer s!"like-retry {k}" ms])
      | .rolledBack _ r => ({ s with line := some (say r) }, [])
    let (s, es) := perform s os
    (s, e ++ es)

-- In `receive`, take the reply's ticket and classify the reply: 2xx → `acked`, 4xx →
-- `refused`, anything else (a timeout, a network failure, a 5xx) → `lost`; for a read, a parsed
-- value → `read`, anything else → `readFailed`.
```

test/fixture/lean/Fixture/Like.lean does exactly this against the fixture's fake server.

### The rules (`Entry.step`)

Per key the table keeps an `Entry`: `server` (the last value the server confirmed), `want` (what
the person asked for last, which is what is shown), `written` (set this session), `phase`, `seq`
(the key's last request number) and `backoff`.

| Phase | Meaning |
|---|---|
| `idle` | nothing outstanding |
| `writing v` | a write of `v` is in flight |
| `doubt v` | the write of `v` was lost; a read is in flight to settle it |
| `waiting v` | that read failed; a `retryIn` is due |
| `checking` | a view disagreed with a written key; a read is in flight |

- **set**: `want := f want`. If nothing is in flight (`idle` or `checking`) and the new `want`
  differs from `server`, a write is sent. Otherwise only `want` changes, so a burst of presses
  sends at most one write at a time and the last press wins.
- **acked**: `server := v` (the value written). If `want` still differs (the person pressed
  again meanwhile), one more write is sent; otherwise the key is idle.
- **refused**: `want := server`, idle, with `rolledBack (refused why)` if what is shown changed.
- **lost**: the key goes into doubt and sends a read. It never writes again blind: a refusal of
  a blind retry would roll back to a value the server no longer holds.
- **read** in doubt: if the server holds the written value, the write was applied, so the key
  settles as for `acked`. Otherwise it was not applied, so the key rolls back
  (`rolledBack notApplied`). A **read** while `checking` adopts the server's value.
- **readFailed** in doubt: wait `backoff` (1 s, doubling, at most 30 s), then `retry` reads again.
  While `checking`, the check is dropped and the key goes idle.
- **seen**: a key never written this session takes the view (`server` and `want`). A written key
  that a view disagrees with, with nothing outstanding, sends a read (`checking`), whose answer
  is authoritative. A view never moves a written key directly, because views lag: an AppView
  that hasn't indexed the write yet would otherwise undo it.

### Counts

A count shown next to a boolean value (likes, reposts) comes from a view: `c` people, including
the person's own `v`. Shown, it is

```
count c v w = c − [v] + [w]        -- [b] is ind b: 1 if b, else 0
```

with `w = t.shown k`. When `c = o + [v]` (o is everyone else), this is `o + [w]`. Once settled,
`w` is what the server holds (`World.Ok.count`). It is never below `[w]`, so never below zero
(`count_ge`). It is exactly the server's count whenever no one else acted since the view.
Fetching a fresh view replaces `c` and `v`.

## The server model

lean/Cairn/Optimistic/Server.lean models what the table is proved against. A `World` is:

- the table;
- the server, a register per key (`srv`, read with `reg`);
- the network, a bag of packets (`net`) that any step may take any element of: requests the
  table sent that the server hasn't handled (`write`, `read`), the server's answers on their way
  back (`acked`, `refused`, `answer`, `failed`) and views (`view`);
- the history of sets and writes (`sets`, `writes`), for counting.

A step (`World.Step`) is any of:

| Step | What happens |
|---|---|
| `press k f` | the person sets `k`; the table's requests join the bag |
| `serve k p` | the server handles request `p`: applies a write (`acked`) or answers a read with what it holds now (`answer`) |
| `refuse k p` | the server refuses `p` and changes nothing (`refused`, `failed`) |
| `deliver k p` | the network delivers an answer or a view to the table |
| `lose k p` | the network loses a request (before the server) or an answer (after it): the table hears `lost` or `readFailed` |
| `retry k` | the backoff timer fires |
| `look k` | the app fetches a view: what the server holds now, delivered whenever (by then it may be stale) |

The order is arbitrary, so this covers every interleaving: late, reordered and lost replies,
lost before or after the server acted, and stale views. A write is applied at most once here,
which loses nothing, since writes are idempotent. The model has one writer per key (the
person). Other people's actions show up only as counts in views, which is how the `count`
theorem treats them.

The invariant `World.Ok` holds in every reachable world (`World.Ok.reach`). It is per key
(`KeyOk`): the key's packets in the bag are exactly what its phase says (one write or its answer
while `writing`, one read or its answer in `doubt` or `checking`, none when `idle` or `waiting`).
In `writing` the register holds `server` until the write is applied and the written value after.
Stale packets (old numbers) never carry a write. Convergence, at most one write, the write budget
and counts all follow from `World.Ok`.

## The theorems

General theorems (any key type with a lawful order, any value type, any `same` that is an
equivalence, `Same`):

| Theorem | Says |
|---|---|
| `Table.shown_set` | a set shows `f` of what was shown, in its step |
| `Table.get_feed_ne` | an input changes only its own key |
| `Table.feed_comm` | inputs for different keys commute: the same table at every key, and each one's outputs as alone |
| `Table.refused_rollback` | a refusal of the write in flight shows `server`, keeps it, and leaves the key settled |
| `Table.seen_written` | a view never changes `shown` or `server` of a written key |
| `Table.writes_le_sets` | from an empty table, for any inputs, the writes sent for a key never outnumber its sets |
| `count_exact`, `count_ge`, `count_view` | the count's arithmetic |
| `World.Ok.converges` | in every reachable world, a settled key shows what the server holds (by `same`) |
| `World.Ok.oneWrite` | at most one write (sent, or applied with its answer on the way) per key |
| `World.Ok.writes_le_sets` | writes never outnumber sets, per key |
| `World.Ok.count` | a settled key's count is the view's others plus the server's own |

The claims, in lean/Cairn/Optimistic/Claims.lean, state these for a harness machine whose state
is a `World Nat Bool` with `==`. Its moves are the steps, and a move's key picks a key or a packet:

| Id | Kind | Claim |
|---|---|---|
| cairn^1100 | move | Set a value |
| cairn^1101 | move | The server handles a request |
| cairn^1102 | move | The server refuses a request |
| cairn^1103 | move | An answer arrives |
| cairn^1104 | move | A request or answer is lost |
| cairn^1105 | move | A retry comes due |
| cairn^1106 | move | A view is fetched |
| cairn^1107 | invariant | A set shows in its own step |
| cairn^1108 | invariant | At most one write in flight per key |
| cairn^1109 | invariant | Never more writes than sets |
| cairn^1110 | invariant | A refusal rolls back in its step |
| cairn^1111 | invariant | Settled keys show what the server holds |
| cairn^1112 | invariant | Replies for different keys commute |
| cairn^1113 | invariant | A settled count is the server's |
| cairn^1114 | invariant | A view never moves a written key |

No `sorry`, and only the standard axioms (`make audit`).

## What an app still has to show

The theorems are about the table. An app that uses one keeps these in its own claims:

- it feeds every reply to the right ticket, and classifies replies as above (a 5xx is `lost`,
  not `refused`);
- its writes are idempotent (set the value; don't toggle it);
- its `read` is authoritative (the PDS's record, not an AppView's cached view);
- what it shows is `shown`, with counts through `count`.

test/fixture shows all four against a fake server that `cairn fuzz` checks
(test/fixture/README.md).

module

public import Cairn.Input

/-! The runtime's view of the outside world (docs/effects.md): the clock, the app's timers, its
pending requests and its active subscriptions. Pure tables and the functions that update them;
`Cairn.Runtime.Step` decides when they run, and `Cairn.Runtime.WorldProofs` says what they
guarantee. -/

@[expose] public section

namespace Cairn.Runtime

structure World where
  /-- The host's latest time; `mono` never decreases (`tick`). -/
  clock : Time := {}
  /-- The time the app last heard as `Msg.clock`. -/
  heard : Option Time := none
  /-- Whether the first clock event has arrived (and `App.initEffects` run). -/
  booted : Bool := false
  /-- Timers: name and due time (monotonic ms), in the order they were set. -/
  timers : List (String × Nat) := []
  /-- Requests sent and not yet answered or cancelled: id and kind. Only these replies reach the
  app. -/
  pending : List (Nat × Request.Kind) := []
  /-- Requests not yet sent, oldest first: a ticket (from `nextTicket`), the id and the request.
  Each waits for a slot (`cap`) or for its id's cancelled request to be answered. -/
  queued : List (Nat × Nat × Request) := []
  /-- Requests cancelled after they were sent: id and kind. Each keeps its slot and its id until
  the host's one reply to it, which no one hears (`takeStop`). -/
  stopping : List (Nat × Request.Kind) := []
  /-- The most requests of capped kinds (`Request.Kind.capped`) with the host at once:
  `App.maxInFlight`. -/
  cap : Nat := 6
  /-- The ticket the next queued request gets. -/
  nextTicket : Nat := 0
  /-- Active subscriptions under the ids the host knows them by. -/
  subs : List (Nat × Sub) := []
  /-- The id the next new subscription gets. -/
  nextSub : Nat := 1
deriving Repr, Inhabited

namespace World

/-- A new time from the host. The monotonic part never goes back. -/
def tick (w : World) (t : Time) : World :=
  { w with clock := { t with mono := max w.clock.mono t.mono } }

def timerNames (w : World) : List String := w.timers.map (·.1)

/-- (Re)start `n`, due `ms` from now; it goes to the end of the order. -/
def setTimer (w : World) (n : String) (ms : Nat) : World :=
  { w with timers := w.timers.filter (fun p => p.1 != n) ++ [(n, w.clock.mono + ms)] }

def cancelTimer (w : World) (n : String) : World :=
  { w with timers := w.timers.filter (fun p => p.1 != n) }

/-- `n` is set and due at the current time. -/
def dueNow (w : World) (n : String) : Bool :=
  w.timers.any fun p => p.1 == n && decide (p.2 ≤ w.clock.mono)

/-- The timers due now, earliest first; ties in the order they were set (`mergeSort` is
stable). -/
def dueNames (w : World) : List String :=
  ((w.timers.filter fun p => decide (p.2 ≤ w.clock.mono)).mergeSort
    (fun a b => decide (a.2 ≤ b.2))).map (·.1)

/-- The earliest deadline, if any timer is set: the frame's `wake`. -/
def wake (w : World) : Option Nat :=
  w.timers.foldl (fun acc p => some (match acc with | some a => min a p.2 | none => p.2)) none

/-! ### Requests in flight (docs/effects.md, "Requests in flight") -/

/-- The queued requests, without their tickets. -/
def waiting (w : World) : List (Nat × Request) := w.queued.map (·.2)

/-- The requests the app may still hear about, sent or not: id and kind. -/
def entries (w : World) : List (Nat × Request.Kind) :=
  w.pending ++ w.waiting.map fun p => (p.1, p.2.kind)

/-- What the app may still hear about `id`: its kind if it is pending or queued. -/
def live (w : World) (id : Nat) : Option Request.Kind := w.entries.lookup id

/-- `id` is pending or queued: a request under it is refused. -/
def isLive (w : World) (id : Nat) : Bool := (w.live id).isSome

/-- `id` was cancelled after it was sent and the host has not answered it yet. -/
def isStopping (w : World) (id : Nat) : Bool := w.stopping.any (·.1 == id)

/-- Requests of capped kinds with the host: pending or stopping. -/
def inFlight (w : World) : Nat :=
  w.pending.countP (·.2.capped) + w.stopping.countP (·.2.capped)

/-- A request can go to the host now: its id is not still stopping, and a capped one has a slot. -/
def canSend (w : World) (id : Nat) (k : Request.Kind) : Bool :=
  !w.isStopping id && (!k.capped || decide (w.inFlight < w.cap))

def send (w : World) (id : Nat) (k : Request.Kind) : World :=
  { w with pending := w.pending ++ [(id, k)] }

def enqueue (w : World) (id : Nat) (r : Request) : World :=
  { w with queued := w.queued ++ [(w.nextTicket, id, r)], nextTicket := w.nextTicket + 1 }

/-- Withdraw `id`: a queued request leaves the queue and was never sent (nothing on the frame);
a pending one moves to `stopping` and its cancel goes on the frame for the host. -/
def cancel (w : World) (id : Nat) : World × Bool :=
  if w.waiting.any (·.1 == id) then ({ w with queued := w.queued.filter (·.2.1 != id) }, false)
  else match w.pending.lookup id with
    | some k => ({ w with pending := w.pending.filter (·.1 != id), stopping := w.stopping ++ [(id, k)] }, true)
    | none => (w, false)

/-- Take in one effect of a delivery. Returns whether it goes on the frame now: a request whose
id is pending or queued is refused (never sent, never answered); a request that can't be sent
yet is queued (it goes on a later frame, from `promote`); a cancel goes only for a request that
was sent; everything else goes. -/
def absorb1 (w : World) : Effect → World × Bool
  | .setTimer n ms => (w.setTimer n ms, true)
  | .cancelTimer n => (w.cancelTimer n, true)
  | .request id r =>
    if w.isLive id then (w, false)
    else if w.canSend id r.kind then (w.send id r.kind, true)
    else (w.enqueue id r, false)
  | .cancelRequest id => w.cancel id
  | _ => (w, true)

/-- Take in a delivery's effects, in order; returns the ones that go on the frame. -/
def absorb (w : World) : List Effect → World × List Effect
  | [] => (w, [])
  | e :: es =>
    let (w1, keep) := w.absorb1 e
    let (w2, out) := absorb w1 es
    (w2, if keep then e :: out else out)

/-- A reply to `id`: when `id` is pending and `r` answers its kind, the world without it. -/
def takeReply (w : World) (id : Nat) (r : Reply) : Option World :=
  match w.pending.lookup id with
  | some k => if r.answers k then some { w with pending := w.pending.filter (·.1 != id) } else none
  | none => none

/-- The host's reply to a request cancelled after it was sent: it is forgotten, and its slot
and id are free again. -/
def takeStop (w : World) (id : Nat) : Option World :=
  if w.isStopping id then some { w with stopping := w.stopping.filter (·.1 != id) } else none

/-- Go through queued requests in order, sending each that can be sent at its turn and keeping
the rest (in order) in `w.queued`. -/
def promoteGo (w : World) : List (Nat × Nat × Request) → World × List Effect
  | [] => (w, [])
  | q :: rest =>
    if w.canSend q.2.1 q.2.2.kind then
      let (w', es) := promoteGo (w.send q.2.1 q.2.2.kind) rest
      (w', .request q.2.1 q.2.2 :: es)
    else promoteGo { w with queued := w.queued ++ [q] } rest

/-- After a slot or an id frees: send every queued request that can go now, oldest first.
Returns the requests for the frame. -/
def promote (w : World) : World × List Effect := promoteGo { w with queued := [] } w.queued

/-- The active subscription with this id. -/
def subOf (w : World) (id : Nat) : Option Sub := w.subs.lookup id

end World

/-! ## Subscriptions -/

/-- Number subscriptions from `next`. -/
def number : Nat → List Sub → List (Nat × Sub)
  | _, [] => []
  | n, s :: ss => (n, s) :: number (n + 1) ss

/-- The subscriptions in `want` that are not among `seen`, without repeats, in order. -/
def freshSubs (seen : List Sub) : List Sub → List Sub
  | [] => []
  | s :: ss => if seen.contains s then freshSubs seen ss else s :: freshSubs (s :: seen) ss

/-- Diff the active subscriptions against what the app asks for now. Returns the new active
set, the commands for the host (stops first, then starts), and the next free id. -/
def diffSubs (active : List (Nat × Sub)) (want : List Sub) (next : Nat) :
    List (Nat × Sub) × List SubCmd × Nat :=
  let kept := active.filter fun p => want.contains p.2
  let gone := active.filter fun p => !want.contains p.2
  let added := number next (freshSubs (kept.map (·.2)) want)
  (kept ++ added, gone.map (fun p => .stop p.1) ++ added.map (fun p => .start p.1 p.2),
   next + added.length)

end Cairn.Runtime

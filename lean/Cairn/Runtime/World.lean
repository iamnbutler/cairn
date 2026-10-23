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
  /-- Requests sent and not yet answered: id and kind. -/
  pending : List (Nat × Request.Kind) := []
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

def isPending (w : World) (id : Nat) : Bool := w.pending.any (·.1 == id)

/-- Take in one effect of a delivery. Returns whether it goes on the frame: a request whose id
is already pending is refused (never sent, never answered); everything else goes. -/
def absorb1 (w : World) : Effect → World × Bool
  | .setTimer n ms => (w.setTimer n ms, true)
  | .cancelTimer n => (w.cancelTimer n, true)
  | .request id r =>
    if w.isPending id then (w, false) else ({ w with pending := w.pending ++ [(id, r.kind)] }, true)
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

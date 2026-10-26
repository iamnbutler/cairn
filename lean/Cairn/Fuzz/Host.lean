import Cairn.Fuzz.Rng
import Cairn.Runtime

/-! # The host

`cairn fuzz`'s stand-in for the host's side of the world (docs/fuzz.md, "The host"): it keeps
what the frames asked of it and answers the way the real host is allowed to, as the trusted
claims state it (docs/trusted.md):

- **Requests** (^914 answered once; ^1009 a cancelled request is still answered once, usually
  `failed`): each request a frame carries is answered once, in any order, as late as it likes,
  with a reply of its kind's shape or a failure; a request cancelled after it was sent is
  answered too (`failed other "cancelled"`, or its answer if the work finished first), which the
  runtime swallows.
- **Images** (^1006, ^1011): a load puts its pixels before it is answered, and a source the host
  holds is answered from what it holds unless `reload`; a failed reload drops the source; while
  an `imageCache` subscription runs and the held pixels are over its budget, the host drops the
  image used least recently that the latest frame doesn't draw and isn't the one just put, and
  says so with `evicted` (which can cross a load's reply).
- **Time** (^908, ^909): every batch starts with a clock; `mono` never goes back; a frame's
  `wake` brings a clock at or up to 40 ms after it, which fires the due timers.
- **Subscriptions** (^915 and the device claims): events for active subscriptions, `every`'s
  ticks at most one a period; and, rarely, an event from a subscription the runtime just
  stopped, which crossed the stop.

Beyond the contract, and rarely: a reply to an id the runtime doesn't hold (answered before, or
never sent). The runtime drops it (`step_reply_ignored`); it is there to show nothing else
reacts.

Everything is decided by the generator from the sequence's seed and recorded in the operation
(`HostOp`), so a sequence replays without it. -/

namespace Cairn.Fuzz
open Cairn Cairn.Runtime

/-- What the host does in one step. Self-contained: replaying it needs no seed. -/
inductive HostOp where
  /-- The clock moves on by `ms` (wall time by `ms + wallJump`). -/
  | advance (ms : Nat) (wallJump : Int)
  /-- The clock reaches the frame's `wake`, `late` ms after it. -/
  | wake (late : Nat)
  /-- Answer request `id`, sent and not yet answered (cancelled or not). -/
  | reply (id : Nat) (r : Reply)
  /-- A `loadImage` request's work finishes before its answer is sent: its pixels are put. -/
  | load (id : Nat) (w h : Nat)
  /-- An event for the active subscription `s`, `dt` ms after the last batch. -/
  | sub (s : Sub) (e : SubEvent) (dt : Nat)
  /-- An event from a subscription the runtime has stopped (it crossed the stop). -/
  | late (id : Nat) (e : SubEvent)
  /-- Drop `source`'s pixels to keep within the image budget, and send `evicted`. -/
  | evict (source : String)
  /-- Beyond the contract: a reply to an id the runtime doesn't hold. -/
  | stray (id : Nat) (r : Reply)
  /-- With a server (`Custom.server`): request `id` reaches the server, which handles it with
  the generator seeded `seed` (`Server.handle`); the world changes, and its reply waits until
  the host sends it (`reply`) or loses it (`lose`). A second `serve` of the same request is a
  retransmission: the server handles it again. -/
  | serve (id : Nat) (seed : Nat)
  /-- Lost after: the server handled request `id`, but its reply is lost; the app hears `r`. -/
  | lose (id : Nat) (r : Reply)
  /-- Failed before: request `id` never reached the server, so the world is as it was; the app
  hears `r`. -/
  | fail (id : Nat) (r : Reply)
  /-- The server's world acts on its own (`Server.tick`, seeded `seed`). -/
  | tick (seed : Nat)
deriving Repr, BEq, Inhabited

/-- An image the host holds. -/
structure Held where
  source : String
  w : Nat
  h : Nat
deriving Repr, BEq, Inhabited

def Held.bytes (x : Held) : Nat := x.w * x.h * 4

/-- What the host did, over a sequence or a run. -/
structure HostStats where
  /-- Requests and cancels the frames carried. -/
  requests : Nat := 0
  cancels : Nat := 0
  /-- Replies to requests still awaited by the runtime, of which failures. -/
  replies : Nat := 0
  failed : Nat := 0
  /-- Replies to requests cancelled after they were sent (the runtime swallows them). -/
  cancelledReplies : Nat := 0
  /-- Replies the app's runtime still delivers but the app stopped waiting for are counted by
  the app, not here. Replies to ids the runtime doesn't hold. -/
  stray : Nat := 0
  clocks : Nat := 0
  wakes : Nat := 0
  /-- Timers due at a clock the host sent (they fire, unless an earlier one cancels them). -/
  timersDue : Nat := 0
  subEvents : Nat := 0
  lateSubEvents : Nat := 0
  loads : Nat := 0
  evictions : Nat := 0
  /-- The most requests the host held at once. -/
  maxOutstanding : Nat := 0
  /-- Requests still unanswered when sequences ended. -/
  leftOver : Nat := 0
  /-- With a server: requests it handled (retransmissions included), of which
  retransmissions; replies lost after it handled them; requests failed before reaching it; and
  times the world acted on its own. -/
  served : Nat := 0
  retransmits : Nat := 0
  lostAfter : Nat := 0
  failedBefore : Nat := 0
  ticks : Nat := 0
deriving Repr, Inhabited

def HostStats.add (a b : HostStats) : HostStats where
  requests := a.requests + b.requests
  cancels := a.cancels + b.cancels
  replies := a.replies + b.replies
  failed := a.failed + b.failed
  cancelledReplies := a.cancelledReplies + b.cancelledReplies
  stray := a.stray + b.stray
  clocks := a.clocks + b.clocks
  wakes := a.wakes + b.wakes
  timersDue := a.timersDue + b.timersDue
  subEvents := a.subEvents + b.subEvents
  lateSubEvents := a.lateSubEvents + b.lateSubEvents
  loads := a.loads + b.loads
  evictions := a.evictions + b.evictions
  maxOutstanding := max a.maxOutstanding b.maxOutstanding
  leftOver := a.leftOver + b.leftOver
  served := a.served + b.served
  retransmits := a.retransmits + b.retransmits
  lostAfter := a.lostAfter + b.lostAfter
  failedBefore := a.failedBefore + b.failedBefore
  ticks := a.ticks + b.ticks

structure Host where
  now : Time := {}
  /-- Requests on a frame, not yet answered: id and request, oldest first. -/
  sent : List (Nat × Request) := []
  /-- Of those, the ones a later frame cancelled. -/
  cancelled : List Nat := []
  /-- Answers decided before they are sent: a load whose pixels are already put, or a request
the server has handled (`HostOp.serve`). -/
  ready : List (Nat × Reply) := []
  /-- Ids answered lately, for stray replies. -/
  answered : List Nat := []
  /-- Images held, least recently used first. -/
  held : List Held := []
  /-- The source put last: never the next one dropped. -/
  lastPut : Option String := none
  /-- Subscription ids whose `record` has started, and `globalKey`s whose key is down. -/
  started : List Nat := []
  keysDown : List Nat := []
  /-- Subscriptions the runtime stopped lately. -/
  stopped : List (Nat × Sub) := []
  stats : HostStats := {}
deriving Inhabited

namespace Host

def isSent (h : Host) (id : Nat) : Bool := h.sent.any (·.1 == id)
def isCancelled (h : Host) (id : Nat) : Bool := h.cancelled.contains id
def request? (h : Host) (id : Nat) : Option Request := h.sent.lookup id
def heldOf (h : Host) (src : String) : Option Held := h.held.find? (·.source == src)
def heldBytes (h : Host) : Nat := h.held.foldl (· + ·.bytes) 0


/-- Put `src`'s pixels: it becomes the most recently used and the last put. -/
def put (h : Host) (src : String) (w ht : Nat) : Host :=
  { h with held := h.held.filter (·.source != src) ++ [⟨src, w, ht⟩], lastPut := some src }

def drop (h : Host) (src : String) : Host :=
  { h with held := h.held.filter (·.source != src),
           lastPut := if h.lastPut == some src then none else h.lastPut }

/-- A published frame draws these sources: they become the most recently used. -/
def touch (h : Host) (drawn : List String) : Host :=
  let (d, rest) := h.held.partition fun x => drawn.contains x.source
  { h with held := rest ++ d }

/-- Take in the effects a step put on the frame, in order. -/
def absorb (h : Host) (es : List Effect) : Host :=
  es.foldl (fun h e => match e with
    | .request id r =>
      let h := { h with sent := h.sent ++ [(id, r)], answered := h.answered.erase id,
                        stats := { h.stats with requests := h.stats.requests + 1 } }
      { h with stats := { h.stats with maxOutstanding := max h.stats.maxOutstanding h.sent.length } }
    | .cancelRequest id =>
      if h.isSent id && !h.isCancelled id then
        { h with cancelled := h.cancelled ++ [id], stats := { h.stats with cancels := h.stats.cancels + 1 } }
      else h
    | _ => h) h

/-- `id` is answered: the host forgets it. -/
def answer (h : Host) (id : Nat) : Host :=
  { h with sent := h.sent.filter (·.1 != id), cancelled := h.cancelled.erase id,
           ready := h.ready.filter (·.1 != id), answered := (id :: h.answered).take 32 }

end Host

/-- Whether request `r` goes to server `sv`: one it `handles`, never a `loadImage`, whose answer
the host's images follow (^1006). -/
def Server.takes {S : Type} (sv : Server S) (r : Request) : Bool :=
  !(r matches .loadImage ..) && sv.handles r

/-! ## What the runtime and the frame say -/

mutual
/-- The image sources a laid tree draws (`Style.image`, set once an image is ready). -/
def drawnIn : Laid → List String
  | .box _ _ st _ kids => (st.image.map (·.source)).toList ++ drawnList kids
  | .field _ _ st .. => (st.image.map (·.source)).toList
  | .text .. => []
def drawnList : List Laid → List String
  | [] => []
  | l :: ls => drawnIn l ++ drawnList ls
end

/-- Every source the latest frame draws: the window's and the shown panels'. -/
def drawnBy {S : Type} (rt : Runtime.State S) : List String :=
  drawnIn rt.laid ++ rt.surfaces.flatMap fun
    | .panel _ (some (_, _, l)) => drawnIn l
    | _ => []

/-- The active `imageCache` subscriptions: ids and budgets. -/
def imageCaches {S : Type} (rt : Runtime.State S) : List (Nat × Nat) :=
  rt.world.subs.filterMap fun
    | (id, .imageCache b) => some (id, b)
    | _ => none

/-- The image the host would drop next: while an `imageCache` runs and the held pixels are
over the smallest budget, the least recently used one the latest frame doesn't draw and that
wasn't just put (^1011). -/
def evictable {S : Type} (h : Host) (rt : Runtime.State S) : Option String :=
  match imageCaches rt with
  | [] => none
  | c :: cs =>
    let budget := cs.foldl (fun m p => min m p.2) c.2
    if h.heldBytes ≤ budget then none else
    let drawn := drawnBy rt
    (h.held.find? fun x => !drawn.contains x.source && h.lastPut != some x.source).map (·.source)

/-- The `evicted` notices for `src`, one to each running `imageCache`. -/
def notices {S : Type} (rt : Runtime.State S) (src : String) : List Event :=
  (imageCaches rt).map fun (id, _) => .subEvent id (.evicted src)

/-! ## Default answers: the reply's shape, random contents -/

namespace Gen

def bytes (lo hi : Nat) : Gen ByteArray := do
  let n ← Gen.range lo hi
  let mut b := ByteArray.emptyWithCapacity n
  for _ in [0:n] do b := b.push (← Gen.below 256).toUInt8
  return b

def fault : Gen Fault := Gen.elem [.notFound, .denied, .timeout, .network, .invalid, .other]

def failure : Gen Reply := do return .failed (← fault) "fuzz"

def word : Gen String :=
  Gen.elem ["", "a", "notes.txt", "2026-10-25.jsonl", ".DS_Store", "é", "日本語", "👍🏽", "x y"]

end Gen

/-- A reply of `r`'s kind with random contents: bytes, a status, a size, a flag, or a fault
(one in six). An image the host holds is answered with its size unless `reload` (^1006). -/
def defaultReply (h : Host) (r : Request) : Gen Reply := do
  if ← Gen.chance 1 6 then return ← Gen.failure
  match r with
  | .readFile _ | .readDefault .. =>
    if ← Gen.bool then return .bytes (← Gen.bytes 0 64)
    return .bytes (← Gen.word).toUTF8
  | .http .. | .upload .. =>
    let status ← Gen.elem [200, 200, 200, 201, 204, 301, 304, 400, 401, 403, 404, 410, 429, 500, 503]
    return .http status (← Gen.elem [[], [("content-type", "application/json")]]) (← Gen.bytes 0 96)
  | .listDir _ => return .names (← Gen.listOf (← Gen.below 6) Gen.word)
  | .frontmostApp => return .app (← Gen.below 70000) (← Gen.elem ["", "Finder", "Notes", "日本語"])
  | .permission .. | .appRunning _ => return .flag (← Gen.bool)
  | .loadImage src reload =>
    match h.heldOf src, reload with
    | some x, false => return .image x.w x.h
    | _, _ => return .image (← Gen.range 1 1600) (← Gen.range 1 1600)
  | .writeFile .. | .playSound _ | .appendFile .. | .deleteFile _ | .typeText .. | .forgetClip _
  | .openItem _ | .makeDir _ | .forgetSecret _ => return .done

/-- The reply to `id`: the app's generator if it has one for this request (a reply of the
wrong shape becomes a failure), else the default. -/
def genReply {S : Type} (c : Custom S) (s : S) (h : Host) (id : Nat) (r : Request) : Gen Reply := do
  match c.replies s id r with
  | some g =>
    let rep ← g
    return if rep.answers r.kind then rep else .failed .other "fuzz: the app's generator answered the wrong kind"
  | none => defaultReply h r

/-- The answer to a request cancelled after it was sent (^1009): `failed other "cancelled"`,
or, if its work had already finished (or can't be stopped), its ordinary answer. -/
def genCancelled {S : Type} (c : Custom S) (s : S) (h : Host) (id : Nat) (r : Request) :
    Gen Reply := do
  if let some rep := h.ready.lookup id then
    if ← Gen.bool then return rep
  if !r.kind.capped || (← Gen.chance 1 4) then return ← genReply c s h id r
  return .failed .other "cancelled"

/-- An event for an active subscription: the app's generator, else one of the kind's events in
an order the host can send them (`started` once, before any `audio`; a key's up after its down). -/
def genSubEvent {S : Type} (c : Custom S) (s : S) (h : Host) (id : Nat) (sub : Sub) :
    Gen SubEvent := do
  if let some g := c.subEvents s sub then return ← g
  let t := h.now.mono
  match sub with
  | .every _ => return .tick
  | .watchFile _ => return .changed
  | .record _ =>
    if !h.started.contains id then
      if ← Gen.chance 1 6 then return .failed (← Gen.elem [.denied, .other]) "fuzz"
      return .started t
    let frames ← Gen.range 0 4000
    let peak ← Gen.range 0 32767
    let windows ← Gen.listOf (frames / 320) do
      return { sumSq := (← Gen.range 0 320) * peak * peak / 320, peak := ← Gen.range 0 peak }
    return .audio frames peak windows
  | .globalKey .. =>
    if ← Gen.chance 1 20 then return .failed .denied "fuzz"
    if h.keysDown.contains id then
      return if ← Gen.chance 1 3 then .otherKey t else .keyUp t
    return .keyDown t
  | .imageCache _ => return .tick  -- not generated: evictions come from `HostOp.evict`

/-- The period before an event of `sub`: `every ms` ticks at most once a period (^915). -/
def subDelay (sub : Sub) : Gen Nat := do
  match sub with
  | .every ms => return max 1 ms + (← Gen.below (max 1 ms / 4 + 1))
  | _ => Gen.elem [0, 0, 1, 16, 250, 2000]

/-- How far the clock moves when the host has nothing else to say. -/
def genAdvance : Gen HostOp := do
  let ms ← Gen.weighted [(4, pure 1), (6, pure 16), (5, pure 250), (5, pure 1000),
    (3, pure 5000), (2, pure 60_000), (1, pure 3_600_000)]
  -- Wall time can jump (the person sets the clock, the machine syncs).
  let jump ← if ← Gen.chance 1 30 then Gen.int (-86_400_000) 86_400_000 else pure 0
  return .advance ms jump

/-- How often, in percent, the host moves rather than the person: one time in thirty when it
has nothing to say beyond the clock, else from one in five up to three in five as requests pile
up, so that they are answered about as fast as they are made. -/
def Host.share {S : Type} (h : Host) (rt : Runtime.State S) : Nat :=
  if !(h.sent.isEmpty && rt.world.wake.isNone && rt.world.subs.isEmpty) then
    min 60 (20 + 4 * h.sent.length)
  else 3

/-- The host's next move, given the latest frame. -/
def genHost {S : Type} (c : Custom S) (h : Host) (rt : Runtime.State S) : Gen HostOp := do
  let s := rt.app
  let srv := fun (p : Nat × Request) => c.server.any (·.takes p.2)
  -- Requests the server handles are scheduled below; the rest as without one.
  let awaited := h.sent.filter fun p => !h.isCancelled p.1 && !srv p
  let cancelled := h.sent.filter fun p => h.isCancelled p.1 && !srv p
  let unloaded := awaited.filter fun
    | (id, .loadImage ..) => (h.ready.lookup id).isNone
    | _ => false
  let active := rt.world.subs.filter fun
    | (_, .imageCache _) => false
    | _ => true
  let mut gs : List (Nat × Gen HostOp) := [(4, genAdvance)]
  unless awaited.isEmpty do
    gs := gs ++ [(30, do
      let (id, r) ← Gen.elem awaited
      let rep ← match h.ready.lookup id with
        | some rep => pure rep
        | none => genReply c s h id r
      return .reply id rep)]
  unless cancelled.isEmpty do
    gs := gs ++ [(8, do
      let (id, r) ← Gen.elem cancelled
      return .reply id (← genCancelled c s h id r))]
  unless unloaded.isEmpty do
    gs := gs ++ [(4, do
      let (id, _) ← Gen.elem unloaded
      return .load id (← Gen.range 1 1600) (← Gen.range 1 1600))]
  if rt.world.wake.isSome then
    gs := gs ++ [(14, do return .wake (← Gen.weighted [(6, pure 0), (3, Gen.range 1 5), (1, Gen.range 6 40)]))]
  unless active.isEmpty do
    gs := gs ++ [(10, do
      let (id, sub) ← Gen.elem active
      return .sub sub (← genSubEvent c s h id sub) (← subDelay sub))]
  unless h.stopped.isEmpty do
    gs := gs ++ [(1, do
      let (id, sub) ← Gen.elem h.stopped
      return .late id (← genSubEvent c s h id sub))]
  if let some src := evictable h rt then
    gs := gs ++ [(10, pure (.evict src))]
  if let some sv := c.server then
    let mine := h.sent.filter srv
    let served := fun (p : Nat × Request) => (h.ready.lookup p.1).isSome
    let unserved := mine.filter (!served ·)
    let waiting := mine.filter served
    -- A cancelled request that reached the server is answered with its reply or lost; one
    -- that didn't is answered `cancelled` without reaching it (^1009).
    let cancelled := fun (p : Nat × Request) => h.isCancelled p.1
    let faultFor := fun (p : Nat × Request) =>
      if cancelled p then pure (.failed .other "cancelled") else sv.fault p.2
    unless unserved.isEmpty do
      gs := gs ++ [(30, do return .serve (← Gen.elem unserved).1 (← Gen.seed)),
        (sv.failBefore, do
          let p ← Gen.elem unserved
          return .fail p.1 (← faultFor p))]
    unless waiting.isEmpty do
      gs := gs ++ [(30, do
          let (id, _) ← Gen.elem waiting
          return .reply id ((h.ready.lookup id).getD .done)),
        (sv.loseAfter, do
          let p ← Gen.elem waiting
          return .lose p.1 (← faultFor p)),
        (sv.retransmit, do return .serve (← Gen.elem waiting).1 (← Gen.seed))]
    gs := gs ++ [(sv.ticks, do return .tick (← Gen.seed))]
  if !h.answered.isEmpty || !h.sent.isEmpty then
    gs := gs ++ [(1, do
      let id ← if !h.answered.isEmpty && (← Gen.bool) then Gen.elem h.answered
        else do
          let top := (rt.world.entries ++ rt.world.stopping).foldl (fun m p => max m p.1) 0
          pure (top + 1 + (← Gen.below 4))
      return .stray id (← Gen.failure))]
  Gen.weighted gs

/-- The operation as a person reading the log would say it. -/
def replyText : Reply → String
  | .done => "done"
  | .bytes b => s!"{b.size} bytes"
  | .http st _ b => s!"HTTP {st}, {b.size} bytes"
  | .failed f m => s!"failed {reprStr f} {m.quote}"
  | .names ns => s!"{ns.length} names"
  | .app pid n => s!"app {pid} {n.quote}"
  | .flag b => s!"flag {b}"
  | .image w h => s!"image {w}×{h}"

def subText : Sub → String
  | .every ms => s!"every {ms}"
  | .watchFile p => s!"watchFile {p.quote}"
  | .record c => s!"record {c}"
  | .globalKey c _ => s!"globalKey {c}"
  | .imageCache b => s!"imageCache {b}"

def HostOp.text : HostOp → String
  | .advance ms j => s!"host: clock +{ms} ms{if j == 0 then "" else s!" (wall jumps {j} ms)"}"
  | .wake l => s!"host: clock reaches the wake{if l == 0 then "" else s!" +{l} ms"}"
  | .reply id r => s!"host: answers #{id} with {replyText r}"
  | .load id w h => s!"host: loads #{id}'s pixels ({w}×{h}), answer not sent yet"
  | .sub s e dt => s!"host: {reprStr e} for {subText s}{if dt == 0 then "" else s!" after {dt} ms"}"
  | .late id e => s!"host: {reprStr e} from stopped subscription {id}"
  | .evict src => s!"host: drops {src.quote}'s pixels (evicted)"
  | .stray id r => s!"host: stray reply to #{id}: {replyText r}"
  | .serve id _ => s!"host: #{id} reaches the server, which handles it (reply not sent yet)"
  | .lose id r => s!"host: LOST AFTER: the server handled #{id}, but the reply is lost; the app hears {replyText r}"
  | .fail id r => s!"host: FAILED BEFORE: #{id} never reached the server; the app hears {replyText r}"
  | .tick _ => s!"host: the server's world acts on its own"

end Cairn.Fuzz

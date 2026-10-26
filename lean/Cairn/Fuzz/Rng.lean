module

public import Cairn.Input

/-! # A seeded PRNG and generators

SplitMix64 (Steele, Lea and Flood, "Fast splittable pseudorandom number generators", 2014): a
64-bit state advanced by a constant, then mixed. Small, fast, good enough for test generation,
and pure, so a seed replays a run exactly. Core only: no Plausible.

A module, so apps can write custom generators (`Cairn.Fuzz.Custom`) without linking `Lean`. -/

@[expose] public section

namespace Cairn.Fuzz

structure Rng where
  state : UInt64
deriving Repr, Inhabited

namespace Rng

def golden : UInt64 := 0x9e3779b97f4a7c15

/-- The SplitMix64 finaliser. -/
def mix (z : UInt64) : UInt64 :=
  let z := (z ^^^ (z >>> 30)) * 0xbf58476d1ce4e5b9
  let z := (z ^^^ (z >>> 27)) * 0x94d049bb133111eb
  z ^^^ (z >>> 31)

def ofSeed (seed : Nat) : Rng := ⟨mix seed.toUInt64⟩

def next (g : Rng) : UInt64 × Rng :=
  let s := g.state + golden
  (mix s, ⟨s⟩)

end Rng

/-- A generator: a state transformer over the PRNG. -/
abbrev Gen := StateM Rng

namespace Gen

def run {α : Type} (g : Gen α) (r : Rng) : α × Rng := StateT.run g r

def u64 : Gen UInt64 := modifyGet Rng.next

/-- Uniform-ish in `[0, n)` (`0` when `n = 0`); the modulo bias is negligible for small `n`. -/
def below (n : Nat) : Gen Nat := do
  if n = 0 then return 0
  return (← u64).toNat % n

/-- In `[lo, hi]`. -/
def range (lo hi : Nat) : Gen Nat := do return lo + (← below (hi + 1 - lo))

def int (lo hi : Int) : Gen Int := do
  return lo + ((← below (hi + 1 - lo).toNat) : Int)

def bool : Gen Bool := do return (← below 2) == 1

/-- True with probability `num / den`. -/
def chance (num den : Nat) : Gen Bool := do return (← below den) < num

def elem {α : Type} [Inhabited α] (xs : List α) : Gen α := do
  return xs[← below xs.length]!

def oneOf {α : Type} [Inhabited α] (gs : List (Gen α)) : Gen α := do
  match gs[← below gs.length]? with
  | some g => g
  | none => return default

/-- Pick by weight. -/
def weighted {α : Type} [Inhabited α] (gs : List (Nat × Gen α)) : Gen α := do
  let total := (gs.map (·.1)).foldl (· + ·) 0
  let mut r ← below total
  for (w, g) in gs do
    if r < w then return ← g
    r := r - w
  return default

def listOf {α : Type} (n : Nat) (g : Gen α) : Gen (List α) := do
  let mut out := #[]
  for _ in [0:n] do out := out.push (← g)
  return out.toList

/-- One of `xs`, each picked in proportion to its weight; one of weight 0 never is. `none` when
every weight is 0 (or there is nothing to pick). -/
def pick {α : Type} (xs : List (Nat × α)) : Gen (Option α) := do
  let total := (xs.map (·.1)).foldl (· + ·) 0
  if total = 0 then return none
  let mut r ← below total
  for (w, x) in xs do
    if r < w then return some x
    r := r - w
  return none

/-- A seed for a generator to be run later (`Rng.ofSeed`), so the operation that runs it can
record the seed and replay without the stream it came from. -/
def seed : Gen Nat := do return (← u64).toNat

end Gen

/-- One step the fuzzer took, for `Custom.relations`: the state before, the message the host
sent if the step was the host's (`none` for a person's operation), the state after, and the
effects the step put on the frame. -/
structure Transition (S : Type) where
  before : S
  msg : Option Msg
  after : S
  effects : List Effect

/-- A server for the fuzz host to answer requests from (docs/fuzz.md, "A server"): a world `W`
that persists across the sequence, changed by the requests that reach it and by itself, and
checked against the app's state.

The host still schedules every reply (late, out of order, duplicated at the server, failed), and
adds two faults that differ in what happened to the world:

- **failed before**: the request never reached the server, so the world is unchanged, and the
  app hears `fault`;
- **lost after**: the server handled the request (the world changed), but its reply was lost,
  and the app hears `fault`.

The app can't tell them apart; a claim stated against `W` can. Everything is replayed from
seeds recorded in the sequence's operations, so a shrunk sequence rebuilds the world it needs.

A module (no `Lean`), so a fake server written for the fuzzer (cairn_atproto's fake PDS) can
live in a library an app imports. -/
structure Server (S : Type) where
  /-- What the server holds. Threaded through the sequence without being copied: `handle` and
  `tick` get the only reference, so an `Array` or `HashMap` in it is updated in place (run with
  `LEAN_ABORT_ON_NONLINEAR=1` and `markLinear` to check). -/
  W : Type
  /-- The world a sequence starts with, from the sequence's seed: random, so other accounts'
  likes and posts differ between sequences. A generator rather than a constant, so the world is
  built per sequence and never shared with a global. -/
  init : Gen W
  /-- Which requests go to the server. The rest (and every `loadImage`) are answered as without
  one, by `Custom.replies` or the default. -/
  handles : Request → Bool := fun _ => true
  /-- The server handles request `id`: the world after and its reply. Called each time the
  request reaches the server: once, or twice when the host delivers it twice (`retransmit`). A
  reply that doesn't answer the request's kind (`Reply.answers`) is replaced by a failure. -/
  handle : W → Nat → Request → Gen (W × Reply)
  /-- The world acting on its own between steps: other accounts liking, new posts, the
  AppView catching up. -/
  tick : W → Gen W := fun w => pure w
  /-- What the app hears for a fault (failed before, or lost after): by default a timeout or a
  network failure. -/
  fault : Request → Gen Reply := fun _ => do
    return .failed (← Gen.elem [.timeout, .timeout, .network]) "fuzz"
  /-- Checks over the app's state and the world, after every step (the first frame included).
  Counted under the claim as `server`. -/
  checks : List (ClaimId × (S → W → Bool)) := []
  /-- Checks once a sequence ends and the host has answered everything outstanding, every
  request reaching the server first (no faults): "once every reply is in, each post shows what
  the server holds". Counted under the claim as `serverDrained`. -/
  drained : List (ClaimId × (S → W → Bool)) := []
  /-- The world in words, for a failure's message. -/
  describe : W → String := fun _ => ""
  /-- How often, relative to the 30 of handling a request and of delivering its reply, the host
  injects each fault and lets the world act (0: never). -/
  failBefore : Nat := 3
  loseAfter : Nat := 3
  ticks : Nat := 4
  /-- How often the host delivers a request the server has handled to it again, before its
  reply is sent (a proxy's retry): the server handles it twice, and the app hears the second
  answer. Off by default: a refusal of the second delivery after the first was applied is a
  "refused" that did something, which no client can tell from the reply, so it only makes sense
  for a server that answers a repeated request as it did the first time. -/
  retransmit : Nat := 0

/-- No server: no world, no request handled. -/
def Server.empty {S : Type} : Server S where
  W := Unit
  init := pure ()
  handles := fun _ => false
  handle := fun w _ _ => pure (w, .failed .other "no server")

/-- What an app may add to the fuzzer, by defining `fuzz : Cairn.Fuzz.Custom State` in its
namespace (docs/fuzz.md). Every field has a default. -/
structure Custom (S : Type) where
  /-- Scripts of text operations for a field's `edit` move (by claim id), each operation sent as
  its own event; `none` keeps the default generator. -/
  edits : S → ClaimId → Option (Gen (List TextOp)) := fun _ _ => none
  /-- The smallest window the app supports in a state; `none` means the app's `App.minSize`, or
  the view's preferred size when that is `0 × 0`. -/
  minSize : S → Option Size := fun _ => none
  /-- Moves that have no control on purpose (keyboard-only), exempt from presence. -/
  noControl : List ClaimId := []
  /-- The frame-time budget for one step (update, view, layout), in nanoseconds. -/
  budgetNs : Option Nat := none
  /-- Replies for the fuzzer's host to answer request `id` with, in the current state
  (docs/fuzz.md, "The host"): for structured answers, such as the JSON a parser expects. `none`
  keeps the default, which knows only the reply's shape (random bytes, a status, a size, a
  fault). A reply that doesn't answer the request's kind (`Reply.answers`) is replaced by a
  failure, since the host never sends one. -/
  replies : S → Nat → Request → Option (Gen Reply) := fun _ _ _ => none
  /-- Events for the fuzzer's host to send an active subscription; `none` keeps the default. -/
  subEvents : S → Sub → Option (Gen SubEvent) := fun _ _ => none
  /-- Checks over one step, for claims stated about every step rather than every state (a
  reply to a request not waited for changes nothing; scores only improve). Counted under the
  claim as `relation`. A message the runtime drops (a reply to a cancelled or unknown id, an
  event from a stopped subscription) is also given straight to `receive`, so a claim about
  every message is checked on those too. -/
  relations : List (ClaimId × (Transition S → Bool)) := []
  /-- Checks once a sequence ends and the host has answered everything outstanding (with
  `replies` or the default): every load finished, nothing still waiting. Counted under the
  claim as `drained`. -/
  drained : List (ClaimId × (S → Bool)) := []
  /-- Checks against what the runtime still owes the app, after every step (the first frame
  included): the state, and the ids of the requests the runtime holds for it, sent and not
  answered or queued behind its in-flight limit, and not cancelled (`World.entries`: sent oldest
  first, then queued). These are exactly the ids the app can still hear a reply under. Counted
  under the claim as `outstanding`. -/
  outstanding : List (ClaimId × (S → List Nat → Bool)) := []
  /-- How often, relative to the others, the fuzzer picks a control's action among those
  enabled on screen (default 1): weight a move reachable only deep in the app up, one that
  ends the state under test (Sign out) down, or a few keys up so presses race their own
  replies. A weight of 0 never picks the control; its presence is still checked. -/
  weights : S → ControlRef → Nat := fun _ _ => 1
  /-- A server with a world of its own, for claims stated against what it holds (docs/fuzz.md,
  "A server"). `none` answers every request with `replies` or the default. -/
  server : Option (Server S) := none
  /-- Checks of the Dock badge, after every step: the state, and the label the host shows, the
  last `badge` effect's (none before any; ^1030). Counted under the claim as `badge`. -/
  badge : List (ClaimId × (S → Option String → Bool)) := []

instance {S : Type} : Inhabited (Custom S) := ⟨{}⟩

end Cairn.Fuzz

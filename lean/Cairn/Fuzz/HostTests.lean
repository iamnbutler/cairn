import Cairn.Fuzz.Shrink
import Cairn.UI.Images

/-! # Tests of the fuzzer's host

A toy app that asks for a file over HTTP and an image at launch, sets a timer and ticks every
100 ms, run through `runSeq`: the host answers both (the HTTP one with the app's own reply,
`Custom.replies`), fires the timer, ticks, and the frame draws the image once it is ready
(checked against what the host holds). `Custom.relations` and `Custom.drained` run, a relation
that fails is reported, and so is one that fails only on a message the runtime drops. Ids 99xx are local to this file and never issued. -/

namespace Cairn.Fuzz.HostTests
open Cairn Cairn.Fuzz

structure S where
  replies : Nat := 0
  timers : Nat := 0
  ticks : Nat := 0
  body : Option ByteArray := none
  image : ImageState := .loading

def receive (s : S) : Msg → S × List Effect
  | .reply 0 (.http _ _ b) => ({ s with replies := s.replies + 1, body := some b }, [])
  | .reply 1 r => ({ s with replies := s.replies + 1, image := Cairn.Images.ofReply r }, [])
  | .reply _ _ => ({ s with replies := s.replies + 1 }, [])
  | .timer _ => ({ s with timers := s.timers + 1 }, [])
  | .sub _ .tick => ({ s with ticks := s.ticks + 1 }, [])
  | .sub _ (.evicted _) => ({ s with image := .loading }, [])
  | _ => (s, [])

def machine : Claims.Machine S := { init := {}, moves := [], receive }

def app : App S where
  init := {}
  surfaces := [.window 9900 "Toy" fun s _ =>
    .box {} none [Node.image { source := "a.png", width := 40, height := 30, state := s.image }]]
  update := fun s _ => (s, [])
  receive
  subscriptions := fun _ => [.every 100]
  initEffects := [.request 0 (.http "GET" "https://example.test/x" [] .empty 0),
    .request 1 (.loadImage "a.png" false), .setTimer "t" 50]
  claims := []

def target (rels : List (ClaimId × (Transition S → Bool))) : Target :=
  { name := "Toy", module := "Cairn.Fuzz.HostTests", ns := "Cairn.Fuzz.HostTests",
    machineDecl := "machine", appDecl := some "app", S := S, machine, app := some app,
    keyed := [], invariants := [], claims := [],
    custom := {
      replies := fun _ _ r => match r with
        | .http .. => some (pure (.http 200 [] "{}".toUTF8))
        | _ => none
      relations := rels
      drained := [(9902, fun s => s.replies == 2 && s.body == some "{}".toUTF8)] } }

def run (rels : List (ClaimId × (Transition S → Bool))) (seed : Nat) : IO Outcome := do
  let t := target rels
  let (setup, rng) := genSetup t seed
  runSeq t setup (.gen rng 200)

/-- Replies only ever add one. -/
def oneAtATime (t : Transition S) : Bool := t.after.replies ≤ t.before.replies + 1

/-- Wrong on purpose: says no reply ever arrives. -/
def noReplies (t : Transition S) : Bool := !(t.msg matches some (.reply ..))

#eval show IO Unit from do
  let mut host : HostStats := {}
  for seed in [0:40] do
    let o ← run [(9901, oneAtATime)] seed
    if let some f := o.failure then
      throw (IO.userError s!"seed {seed}: {f.check} ^{f.claim}: {f.message}")
    host := host.add o.host
  unless host.replies ≥ 40 && host.wakes > 0 && host.timersDue > 0 && host.subEvents > 0 do
    throw (IO.userError s!"the host did too little: {reprStr host}")

/-- The toy counts every reply, even to an id it never asked with: the runtime never delivers
one, but a relation about every message sees it, since dropped messages are also given straight
to `receive`. -/
def strangersIgnored (t : Transition S) : Bool :=
  match t.msg with
  | some (.reply id _) => id ≤ 1 || t.after.replies == t.before.replies
  | _ => true

#eval show IO Unit from do
  let mut found := false
  for seed in [0:40] do
    let o ← run [(9904, strangersIgnored)] seed
    if o.failure.any (fun f => f.check == "relation" && f.claim == 9904 &&
        (f.message.splitOn "straight to receive").length > 1) then found := true
  unless found do throw (IO.userError "a relation should see replies the runtime drops")

#eval show IO Unit from do
  let o ← run [(9903, noReplies)] 0
  unless o.failure.any (fun f => f.check == "relation" && f.claim == 9903) do
    throw (IO.userError "a failing relation should be reported")

-- The app's reply generator answering with the wrong shape becomes a failure.
#guard
  let c : Custom Unit := { replies := fun _ _ _ => some (pure .done) }
  ((genReply c () {} 0 (.loadImage "a" false)).run (Rng.ofSeed 0)).1 matches .failed .other _

-- An image the host holds is answered with its size, unless `reload`.
#guard
  let h : Host := ({} : Host).put "a" 7 9
  ((defaultReply h (.loadImage "a" false)).run (Rng.ofSeed 3)).1 matches (.image 7 9) ∨
  ((defaultReply h (.loadImage "a" false)).run (Rng.ofSeed 3)).1 matches .failed ..

/-! ## Outstanding requests

A second toy makes three HTTP requests at launch with one request in flight at a time, so two wait in
the runtime's queue, and keeps the ids it still waits for. `Custom.outstanding` compares them
with the ids the runtime holds after every step: the correct toy passes; one that forgets every
request once the first is answered is caught, under the claim, and shrinks like any failure. -/

namespace Lost

structure S where
  live : List Nat := [0, 1, 2]

def receive (lose : Bool) (s : S) : Msg → S × List Effect
  | .reply id _ => ({ live := if lose then [] else s.live.erase id }, [])
  | _ => (s, [])

def app (lose : Bool) : App S where
  init := {}
  surfaces := [.window 9910 "Lost" fun _ _ => .box {} none []]
  update := fun s _ => (s, [])
  receive := receive lose
  initEffects := [0, 1, 2].map fun id => .request id (.http "GET" s!"https://example.test/{id}" [] .empty 0)
  maxInFlight := 1
  claims := []

def sorted (xs : List Nat) : List Nat := xs.mergeSort

def target (lose : Bool) : Target :=
  { name := "Lost", module := "Cairn.Fuzz.HostTests", ns := "Cairn.Fuzz.HostTests.Lost",
    machineDecl := "machine", appDecl := some "app", S := S,
    machine := { init := {}, moves := [], receive := receive lose }, app := some (app lose),
    keyed := [], invariants := [], claims := [],
    custom := { outstanding := [(9905, fun s ids => sorted ids == sorted s.live)] } }

def run (lose : Bool) (seed : Nat) : IO Outcome := do
  let t := target lose
  let (setup, rng) := genSetup t seed
  runSeq t setup (.gen rng 100)

-- The correct toy passes, and the check ran.
#eval show IO Unit from do
  for seed in [0:20] do
    let o ← run false seed
    if let some f := o.failure then
      throw (IO.userError s!"seed {seed}: {f.check} ^{f.claim}: {f.message}")
    unless ((o.stats.get? 9905).bind (·.checks.get? "outstanding")).isSome do
      throw (IO.userError "the outstanding check should run")

-- The toy that loses requests is caught, and the failure shrinks to the one reply that loses them.
#eval show IO Unit from do
  let t := target true
  let some (seed, o) ← (List.range 20).findSomeM? fun seed => do
      let o ← run true seed
      return if o.failure.isSome then some (seed, o) else none
    | throw (IO.userError "a lost request should be caught")
  let some f := o.failure | unreachable!
  unless f.check == "outstanding" && f.claim == 9905 do
    throw (IO.userError s!"seed {seed}: wrong failure {f.check} ^{f.claim}")
  let (ops, _) ← shrink t o.setup f o.ops
  unless ops.size == 1 && ops[0]! matches .host (.reply 0 _) do
    throw (IO.userError s!"seed {seed}: shrunk to {ops.size} operations: {ops.toList.map opText}")

end Lost

/-! ## A server

A toy that asks a counter server to count, once, at launch: the server's world is the count.
A 2xx reply never arrives unless the server counted (checked every step), and once everything
is answered the count is at most one (it never handles a request twice by default). A drained
check that says the app heard every count (`acked = count`) is wrong exactly when a reply is
lost after the server acted, and the fuzzer finds that and shrinks it to the lost reply. -/

namespace Counted

structure S where
  acked : Nat := 0
deriving Inhabited

def receive (s : S) : Msg → S × List Effect
  | .reply 0 (.http 200 ..) => ({ s with acked := s.acked + 1 }, [])
  | _ => (s, [])

def machine : Claims.Machine S := { init := {}, moves := [], receive }

def app : App S where
  init := {}
  surfaces := [.window 9900 "Toy" fun _ _ => .box {} none []]
  update := fun s _ => (s, [])
  receive
  initEffects := [.request 0 (.http "POST" "https://example.test/count" [] .empty 0)]
  claims := []

abbrev Checks := List (ClaimId × (S → Nat → Bool))

def server (checks drained : Checks) : Server S where
  W := Nat
  init := pure 0
  handle := fun n _ _ => pure (n + 1, .http 200 [] .empty)
  checks := checks
  drained := (9906, fun _ n => n ≤ 1) :: drained
  loseAfter := 20
  failBefore := 20

def target (checks : Checks) (drained : Checks := []) : Target :=
  { name := "Toy", module := "Cairn.Fuzz.HostTests", ns := "Cairn.Fuzz.HostTests",
    machineDecl := "machine", appDecl := some "app", S := S, machine, app := some app,
    keyed := [], invariants := [], claims := [], custom := { server := some (server checks drained) } }

def run (checks : Checks) (drained : Checks := []) (seed : Nat) : IO Outcome := do
  let t := target checks drained
  let (setup, rng) := genSetup t seed
  runSeq t setup (.gen rng 60)

-- A 2xx means the server counted; both faults happen; the checks ran.
#eval show IO Unit from do
  let mut host : HostStats := {}
  for seed in [0:40] do
    let o ← run [(9905, fun s n => s.acked ≤ n)] [] seed
    if let some f := o.failure then
      throw (IO.userError s!"seed {seed}: {f.check} ^{f.claim}: {f.message}")
    unless ((o.stats.get? 9905).bind (·.checks.get? "server")).isSome &&
        ((o.stats.get? 9906).bind (·.checks.get? "serverDrained")).isSome do
      throw (IO.userError "the server's checks should run")
    host := host.add o.host
  unless host.served > 0 && host.lostAfter > 0 && host.failedBefore > 0 && host.ticks > 0 do
    throw (IO.userError s!"the server did too little: {reprStr host}")

-- "The app heard every count" is false after a reply lost after the server counted, and the
-- failure shrinks to the request reaching the server and its reply being lost.
#eval show IO Unit from do
  let drained : Checks := [(9907, fun s n => s.acked == n)]
  let t := target [] drained
  let some (seed, o) ← (List.range 40).findSomeM? fun seed => do
      let o ← run [] drained seed
      return if o.failure.isSome then some (seed, o) else none
    | throw (IO.userError "a lost reply should be caught")
  let some f := o.failure | unreachable!
  unless f.check == "serverDrained" && f.claim == 9907 do
    throw (IO.userError s!"seed {seed}: wrong failure {f.check} ^{f.claim}")
  let (ops, _) ← shrink t o.setup f o.ops
  unless ops.size == 2 && ops[0]! matches .host (.serve 0 _) && ops[1]! matches .host (.lose 0 _) do
    throw (IO.userError s!"seed {seed}: shrunk to {ops.size} operations: {ops.toList.map opText}")

end Counted

-- Weights: a weight of 0 is never picked, and all 0 picks nothing.
#guard ((List.range 200).foldl (fun (acc : List Nat × Rng) _ =>
    let (x, r) := (Gen.pick [(0, 7), (3, 8), (0, 9)]).run acc.2
    (x.toList ++ acc.1, r)) ([], Rng.ofSeed 1)).1.all (· == 8)
#guard ((Gen.pick [(0, 7), (0, 8)]).run (Rng.ofSeed 1)).1 == none

end Cairn.Fuzz.HostTests

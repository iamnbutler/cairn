import Cairn.Fuzz.Walk
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

end Cairn.Fuzz.HostTests

import Fixture.Fuzz
import Cairn.Fuzz.Shrink

/-! # The likes' mutant, caught by the fuzzer's server

`blindReceive` is the fixture's `receive` with one plausible slip: it takes a write whose reply
was lost (a timeout, a 503) for a refused one, and rolls the post back instead of reading the
value back (`Like.wrote`'s `blind`). The tests the fixture has for presses and replies pass with
it, and ^22's proof still goes through: a rollback leaves the post showing the value last heard
from the server. What breaks is the server's side: when the server applied the write before its
reply was lost, the post rolls back to a value the server no longer holds.

Below, `cairn fuzz`'s walk runs the fixture with its server (`Fixture.fuzz`) on the real
`receive` and on the mutant: the real one passes, the mutant fails ^22's `server` check, and the
shrunk failure has a reply lost after the server acted. Nothing here declares a machine, so
`fuzz_targets%` never runs the mutant. -/

namespace Fixture.LikeMutant
open Cairn Cairn.Fuzz Fixture

/-- `receive`, but a lost write is taken for a refused one. -/
def blindReceive (s : State) (m : Msg) : State × List Effect :=
  let o := Like.receive true s.likes s.nextReq m
  ({ s with flash := if isFlash m then false else s.flash, likes := o.1, nextReq := o.2.1 }, o.2.2)

/-- The fixture as `fuzz_targets%` builds it, with `receive` replaced. -/
def target (recv : State → Msg → State × List Effect) : Target :=
  { name := "Fixture", module := "Fixture", ns := "Fixture", machineDecl := "machine",
    appDecl := some "app", S := State, machine := { machine with receive := recv },
    app := some { app with receive := recv }, keyed := [4, 5, 10, 21],
    invariants := [], claims := claimInfos, custom := fuzz }

/-- The first failure over `n` sequences of `steps` steps, with its setup and operations. -/
def firstFailure (t : Target) (n steps : Nat) : IO (Option (Failure × Setup × Array Op)) := do
  for seed in [0:n] do
    let (setup, rng) := genSetup t seed
    let o ← runSeq t setup (.gen rng steps)
    if let some f := o.failure then return some (f, setup, o.ops)
  return none

/-- Whether an operation is a reply lost after the server acted. -/
def isLose : Op → Bool
  | .host (.lose ..) => true
  | _ => false

end Fixture.LikeMutant

open Cairn Cairn.Fuzz Fixture Fixture.LikeMutant in
/-- `lake exe likeMutant` (run by `make fuzz-quick`): the real `receive` passes ^22 against the
server over 100 sequences, and the mutant fails it, with a lost-after reply in the shrunk
failure. Exit code 1 otherwise. Compiled, not `#eval`: the interpreter is too slow for the
fixture's view. -/
def main : IO UInt32 := do
  if let some (f, setup, _) ← firstFailure (target receive) 100 80 then
    IO.eprintln s!"the real receive failed, seed {setup.seed}: {f.check} ^{f.claim}: {f.message}"
    return 1
  IO.println "receive: ^22 held against the server over 100 sequences"
  let t := target blindReceive
  let some (f, setup, ops) ← firstFailure t 100 80
    | IO.eprintln "the fuzzer missed the lost write taken for a refusal"; return 1
  unless f.claim == 22 && (f.check == "server" || f.check == "serverDrained") do
    IO.eprintln s!"the mutant failed {f.check} ^{f.claim}, not ^22 against the server: {f.message}"
    return 1
  let (shrunk, _) ← shrink t setup f ops
  IO.println s!"lost taken for refused: {f.check} ^22 failed at seed {setup.seed}: {f.message}"
  IO.println s!"  shrunk {ops.size} → {shrunk.size} operations:"
  for op in shrunk do IO.println s!"    {opText op}"
  unless shrunk.any isLose do
    IO.eprintln "the shrunk failure has no reply lost after the server acted"
    return 1
  return 0

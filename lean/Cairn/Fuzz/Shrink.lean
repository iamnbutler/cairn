import Cairn.Fuzz.Walk

/-! # Shrinking, and what a failure is printed as

Delta debugging (Zeller and Hildebrandt's ddmin) over a failing sequence's operations: remove
chunks while the shorter sequence still fails the same check on the same claim, halving the
chunk size down to single operations. Operations are self-contained, so a subsequence replays
from the same setup without the seed.

The shrunk sequence becomes a ready-to-paste `flow` (with the next free id), whose witness is
the actions the runtime delivered while replaying it, minus those no move accepts (no-ops in
the model), so the witness is live. -/

namespace Cairn.Fuzz
open Cairn Cairn.Claims Cairn.Runtime

/-- Whether replaying `ops` from `setup` fails the same check on the same claim. -/
def stillFails (t : Target) (setup : Setup) (target : Failure) (ops : Array Op) : IO Bool := do
  let o ← runSeq t setup (.replay ops)
  return o.failure.any (·.same target)

def without (xs : Array Op) (lo hi : Nat) : Array Op := xs.extract 0 lo ++ xs.extract hi xs.size

/-- ddmin over complements, then a pass removing single operations. Returns the shrunk
operations and how many replays it took. -/
def shrink (t : Target) (setup : Setup) (target : Failure) (ops : Array Op) :
    IO (Array Op × Nat) := do
  let test := stillFails t setup target
  let mut cur := ops
  let mut n := 2
  let mut tries := 0
  let mut fuel := 4 * ops.size + 64
  while cur.size ≥ 2 && fuel > 0 do
    fuel := fuel - 1
    let chunk := (cur.size + n - 1) / n
    let mut reduced := false
    for i in [0:n] do
      let lo := i * chunk
      if lo ≥ cur.size then break
      let cand := without cur lo (min cur.size (lo + chunk))
      tries := tries + 1
      if ← test cand then
        cur := cand
        n := max (n - 1) 2
        reduced := true
        break
    if !reduced then
      if n ≥ cur.size then break
      n := min cur.size (2 * n)
  -- One at a time, from the end, until nothing more can go.
  let mut changed := true
  while changed do
    changed := false
    let mut i := cur.size
    while i > 0 do
      i := i - 1
      let cand := without cur i (i + 1)
      tries := tries + 1
      if ← test cand then
        cur := cand
        changed := true
  return (cur, tries)

/-- One replayed operation: the operation, the control a pointer operation hit (in the model),
and the delivered actions some move accepts. -/
structure Traced where
  op : Op
  hit : Option ControlRef
  accepted : List Action

/-- Replay operations, recording what each did. -/
def trace (t : Target) (setup : Setup) (ops : Array Op) : IO (Array Traced) := do
  let mut w := World.start t setup
  let mut out := #[]
  for op in ops do
    let hit := match op with
      | .click p _ | .move p => hitRef w.rt.laid p
      | _ => none
    let s0 := w.rt.app
    let p ← perform t setup w op
    let (_, acc) := p.acts.foldl (fun (st, acc) a =>
      let acc := if accepts t.machine.moves st a then acc.push a else acc
      ((t.machine.update st a).1, acc)) (s0, (#[] : Array Action))
    out := out.push { op, hit, accepted := acc.toList }
    w := p.world
  return out

/-! ## As Lean source -/

def capitalize (s : String) : String :=
  match s.toList with
  | c :: cs => String.ofList (c.toUpper :: cs)
  | [] => s

/-- The largest id in `claims.lock`, if it can be read. -/
def lockMax (path : System.FilePath) : IO (Option Nat) := do
  unless ← path.pathExists do return none
  let text ← IO.FS.readFile path
  let ids := (text.splitOn "\n").filterMap fun l =>
    if l.startsWith "#" then none else (l.splitOn "\t").head?.bind String.toNat?
  return ids.foldl (fun m i => some (max i (m.getD 0))) none

/-- A ready-to-paste `flow` for a shrunk failure, and for presence and pressability failures a
theorem to put beside the app's proofs. A flow's goal can only talk about the state (claims are
declared before the view), so the flow pins the state the failure needs, with a durable id,
and the theorem states what the view must do in it. -/
def flowSource (t : Target) (setup : Setup) (f : Failure) (traced : Array Traced) (id : Nat) :
    String := Id.run do
  let acts := traced.toList.flatMap (·.accepted)
  let final := acts.foldl (fun s a => (t.machine.update s a).1) t.machine.init
  let title := ((t.claims.find? (·.id == f.claim)).map (·.title)).getD s!"^{f.claim}"
  let name := s!"fuzz{capitalize ((f.check.splitOn "-").foldl (· ++ capitalize ·) "")}{f.claim}"
  let r : ControlRef := ⟨f.claim, f.key⟩
  let refT := s!"(⟨{r.claim}, {r.key}⟩ : Cairn.ControlRef)"
  let en := (t.move? f.claim).any (·.enabled final f.key)
  let enabledT := s!"((Cairn.Claims.find? {t.machineDecl}.moves {r.claim}).any fun m => m.enabled s {r.key})"
  let z := setup.size
  let app := t.appDecl.getD "app"
  let st := s!"({t.machineDecl}.run {t.machineDecl}.init {name}.witness)"
  let laid := s!"Cairn.Layout.layout Cairn.TextMetrics.mono ⟨{z.w}, {z.h}⟩ ({app}.view {st} \{ size := ⟨{z.w}, {z.h}⟩ })"
  let (goal, sees, thm) := match f.check with
    | "invariant" =>
      let d := ((t.invariants.find? fun (i : InvCheck t.S) => i.info.id == f.claim).map
        (fun (i : InvCheck t.S) => i.decl)).getD "inv"
      (s!"{d}.check s = true", s!"^{f.claim} holds.", none)
    | "presence" =>
      (s!"{enabledT} = {en}",
       s!"{r.label} is {if en then "enabled" else "disabled"}, so its control is {if en then "on screen" else "gone"}.",
       some s!"theorem {name}_present :\n    Cairn.Runtime.present ({laid}) {refT} = {en} := by\n  decide +kernel")
    | _ =>
      (s!"{enabledT} = true", s!"{r.label} is enabled, and a click at its centre reaches it.",
       some s!"theorem {name}_pressable :\n    let l := {laid}\n    ((Cairn.Runtime.find l {refT}).any fun tg =>\n      Cairn.Runtime.hitRef l tg.visible.center == some {refT}) = true := by\n  decide +kernel")
  let metricsNote := match setup.metrics with
    | .mono => ""
    | .random sd => s!"\n-- Found with random metrics (seed {sd}); the theorem uses mono, so check it fails before the fix."
  let header := s!"-- {f.check} ^{f.claim}: {f.message}\n-- Replay: lake exe fuzz {t.name} --seed {setup.seed} --iterations 1 -v"
  if acts.isEmpty then
    return s!"{header}\n-- No move leads here (the failure is in the initial state, or only window and pointer events reach it), so there is no witness: state it as a theorem about `{t.machineDecl}.init`."
  let does := s!"Found by fuzzing (seed {setup.seed}): {f.message}"
  let w := ", ".intercalate (acts.map actionLean)
  let flow := s!"flow ^{id} {name} \"{title}: {f.check} (fuzz)\" for {t.machineDecl} where\n  does {does.quote}\n  sees {sees.quote}\n  goal s := {goal}\n  witness {w}"
  match thm with
  | none => return s!"{header}\n-- The flow's goal fails until the bug is fixed; then it is the regression test.\n{flow}"
  | some th => return s!"{header}\n-- The flow pins the state with a durable id; the theorem, beside the app's proofs, fails\n-- until the bug is fixed.{metricsNote}\n{flow}\n\n{th}"

end Cairn.Fuzz

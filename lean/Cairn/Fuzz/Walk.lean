import Cairn.Fuzz.Target
import Cairn.Fuzz.Text
import Cairn.Fuzz.Metrics
import Cairn.Runtime
import Cairn.Layout.Check
import Std.Data.HashMap
import Std.Data.HashSet

/-! # The walk

One sequence: a window size, text metrics, and operations generated from the current state
(or replayed from a list), each checked against the app's claims (docs/fuzz.md).

An app with an `App` is driven through the real runtime (`Runtime.route` and `Runtime.step`):
an action is performed as the pointer and key events a person would use, so hit testing, focus
and routing are exercised along with the app. A machine without an `App` gets its actions
directly (`machine.update`). -/

namespace Cairn.Fuzz
open Cairn Cairn.Claims Cairn.Runtime Cairn.Layout

/-- One operation of a sequence. Self-contained, so a subsequence replays without the seed. -/
inductive Op where
  /-- An action of a move, performed through the UI (or delivered, without an `App`). -/
  | act (a : Action)
  | click (p : Point) (clicks : Nat)
  | move (p : Point)
  | tab (back : Bool)
  | key (k : Key) (mods : Mods)
  | resize (size : Size)
  | exit
  | windowFocus (b : Bool)
deriving Repr, BEq, Inhabited

/-! ### As text: flow witness syntax for actions -/

def refLean (c : ControlRef) : String :=
  if c.key = 0 then s!"^{c.claim}" else s!"^{c.claim}#{c.key}"

def opLean : TextOp → String
  | .insert s => s!"(.insert {s.quote})"
  | .deleteBackward => "(.deleteBackward)"
  | .deleteForward => "(.deleteForward)"
  | .deleteWordBackward => "(.deleteWordBackward)"
  | .deleteWordForward => "(.deleteWordForward)"
  | .moveLeft e => s!"(.moveLeft {e})"
  | .moveRight e => s!"(.moveRight {e})"
  | .moveWordLeft e => s!"(.moveWordLeft {e})"
  | .moveWordRight e => s!"(.moveWordRight {e})"
  | .moveHome e => s!"(.moveHome {e})"
  | .moveEnd e => s!"(.moveEnd {e})"
  | .setCaret i e => s!"(.setCaret {i} {e})"
  | .selectAll => "(.selectAll)"
  | .setMarked s a b => s!"(.setMarked {s.quote} {a} {b})"
  | .unmark => "(.unmark)"
  | .cut => "(.cut)"
  | .copy => "(.copy)"
  | .paste s => s!"(.paste {s.quote})"
  | .undo => "(.undo)"
  | .redo => "(.redo)"

def actionLean : Action → String
  | .press c => s!"press {refLean c}"
  | .doublePress c => s!"doublePress {refLean c}"
  | .edit c op => s!"edit {refLean c} {opLean op}"
  | .submit c => s!"submit {refLean c}"
  | .cancel c => s!"cancel {refLean c}"
  | .blur c => s!"blur {refLean c}"

def keyText (k : Key) (m : Mods) : String :=
  let name := match k with
    | .enter => "Enter" | .escape => "Escape" | .tab => "Tab" | .backspace => "Backspace"
    | .delete => "Delete" | .left => "Left" | .right => "Right" | .up => "Up" | .down => "Down"
    | .home => "Home" | .finish => "End" | .pageUp => "PageUp" | .pageDown => "PageDown"
    | .char c => c.toString
  (if m.command then "cmd-" else "") ++ (if m.option then "opt-" else "") ++
    (if m.shift then "shift-" else "") ++ name

/-- An operation, as a person would say it. -/
def opText : Op → String
  | .act a => actionLean a
  | .click p n => s!"{if n ≥ 2 then "double-click" else "click"} at ({p.x}, {p.y})"
  | .move p => s!"pointer to ({p.x}, {p.y})"
  | .tab back => if back then "key shift-Tab" else "key Tab"
  | .key k m => s!"key {keyText k m}"
  | .resize z => s!"resize to {z.w}×{z.h}"
  | .exit => "pointer leaves the window"
  | .windowFocus b => if b then "window gains focus" else "window loses focus"


/-- A failed check: which check, on which claim and key, after which operation. -/
structure Failure where
  check : String
  claim : ClaimId
  key : Nat := 0
  step : Nat := 0
  message : String
deriving Repr, Inhabited

def mkFail (check : String) (r : ControlRef) (step : Nat) (message : String) : Failure :=
  { check, claim := r.claim, key := r.key, step, message }

def Failure.same (a b : Failure) : Bool := a.check == b.check && a.claim == b.claim

/-- A check that ran on a claim: `(claim, check kind)`. -/
abbrev Ran := ClaimId × String

/-- How a sequence starts. -/
structure Setup where
  seed : Nat
  size : Size
  metrics : MetricsChoice
deriving Repr, Inhabited

section
variable (t : Target)

def cfgOf (m : MetricsChoice) : Config := { metrics := m.metrics }

/-- The app, or a stand-in with an empty view for a machine without one. -/
def Target.runApp : App t.S :=
  t.app.getD { init := t.machine.init, view := fun _ _ => .box {} none [],
               update := t.machine.update, claims := [] }

def Target.move? (id : ClaimId) : Option (Move t.S) := find? t.machine.moves id

def Target.isKeyed (id : ClaimId) : Bool := t.keyed.contains id

def Target.budgetNs : Nat := t.custom.budgetNs.getD 8_000_000

/-- The smallest window for a state: the app's, or the view's preferred size. -/
def Target.minSize (m : TextMetrics) (s : t.S) (ui : UI) : Size :=
  match t.custom.minSize s, t.app with
  | some z, _ => z
  | none, some app => (measure m (app.view s ui)).size
  | none, none => ⟨0, 0⟩

end

/-! ## The world a sequence runs in -/

variable {S : Type}

structure World (S : Type) where
  rt : Runtime.State S
  /-- The largest key seen on screen per keyed move, so "enabled but missing" can be probed. -/
  seen : Std.HashMap ClaimId Nat := {}

def World.start (t : Target) (setup : Setup) : World t.S :=
  { rt := Runtime.start t.runApp (cfgOf setup.metrics) setup.size }

/-- The events a text operation arrives as. `setCaret` has none (it comes from clicks). -/
def opEvents : TextOp → List Event
  | .insert s => [.insertText s]
  | .deleteBackward => [.key .backspace {}]
  | .deleteForward => [.key .delete {}]
  | .deleteWordBackward => [.key .backspace { option := true }]
  | .deleteWordForward => [.key .delete { option := true }]
  | .moveLeft e => [.key .left { shift := e }]
  | .moveRight e => [.key .right { shift := e }]
  | .moveWordLeft e => [.key .left { shift := e, option := true }]
  | .moveWordRight e => [.key .right { shift := e, option := true }]
  | .moveHome e => [.key .left { shift := e, command := true }]
  | .moveEnd e => [.key .right { shift := e, command := true }]
  | .setCaret .. => []
  | .selectAll => [.selectAll]
  | .setMarked s a b => [.setMarked s a b]
  | .unmark => [.unmark]
  | .cut => [.cut]
  | .copy => [.copy]
  | .paste s => [.paste s]
  | .undo => [.undo]
  | .redo => [.redo]

def clickEvents (p : Point) (clicks : Nat) : List Event :=
  [.pointerMove p, .pointerDown p .primary 1 {}, .pointerUp p .primary {}] ++
    (if clicks ≥ 2 then [.pointerDown p .primary 2 {}, .pointerUp p .primary {}] else [])

/-- The events that perform an operation in the current state; `none` when an action's control
isn't on screen (or can't take that action), so the operation is skipped. -/
def opToEvents (rt : Runtime.State S) : Op → Option (List Event)
  | .act a =>
    let c := a.control
    match find rt.laid c with
    | none => none
    | some tg =>
      let p := tg.visible.center
      let focus := if rt.ui.focus = some c then [] else clickEvents p 1
      match a with
      | .press _ => if tg.isField then none else some (clickEvents p 1)
      | .doublePress _ => if tg.isField then none else some (clickEvents p 2)
      | .edit _ op =>
        if tg.isField && !(opEvents op).isEmpty then some (focus ++ opEvents op) else none
      | .submit _ => if tg.isField then some (focus ++ [.key .enter {}]) else none
      | .cancel _ => if tg.isField then some (focus ++ [.key .escape {}]) else none
      | .blur _ => if tg.isField then some (focus ++ [.key .tab {}]) else none
  | .click p n => some (clickEvents p n)
  | .move p => some [.pointerMove p]
  | .tab back => some [.key .tab { shift := back }]
  | .key k mods => some [.key k mods]
  | .resize z => some [.resize z]
  | .exit => some [.pointerExit]
  | .windowFocus b => some [.windowFocus b]

/-- The result of performing one operation. -/
structure Performed (S : Type) where
  world : World S
  /-- The actions delivered to `update`, in order. -/
  acts : List Action
  /-- Whether the operation ran at all (an `act` whose control is missing is skipped). -/
  ran : Bool
  /-- The slowest event's `Runtime.step` (update, view, layout, settle), in nanoseconds. -/
  maxNs : Nat

/-- Perform an operation: through the runtime with an `App`, or straight into the machine. -/
def perform (t : Target) (setup : Setup) (w : World t.S) (op : Op) : IO (Performed t.S) := do
  let cfg := cfgOf setup.metrics
  match t.app with
  | none =>
    match op with
    | .act a =>
      let s := w.rt.app
      let s' ← IO.lazyPure fun _ => (t.machine.update s a).1
      let acts := if accepts t.machine.moves s a then [a] else []
      return { world := { w with rt := { w.rt with app := s' } }, acts, ran := true, maxNs := 0 }
    | _ => return { world := w, acts := [], ran := false, maxNs := 0 }
  | some app =>
    match opToEvents w.rt op with
    | none => return { world := w, acts := [], ran := false, maxNs := 0 }
    | some es =>
      let mut rt := w.rt
      let mut acts : Array Action := #[]
      let mut maxNs := 0
      for e in es do
        let routed := (route cfg.metrics rt e).2
        let t0 ← IO.monoNanosNow
        let rt' ← IO.lazyPure fun _ => (step app cfg rt e).1
        -- Force the new laid tree before reading the clock.
        let _ ← IO.lazyPure fun _ => (targets rt'.laid).length
        let t1 ← IO.monoNanosNow
        maxNs := max maxNs (t1 - t0)
        acts := acts ++ routed.toArray
        rt := rt'
      return { world := { w with rt }, acts := acts.toList, ran := true, maxNs }

/-! ## Checks -/

/-- Keys to probe for a move: those on screen, the largest seen so far, and one past it. -/
def probeKeys (t : Target) (w : World t.S) (id : ClaimId) : List Nat :=
  if !t.isKeyed id then [0] else
  let onScreen := (refs w.rt.laid).filterMap fun r => if r.claim = id then some r.key else none
  let top := (w.seen.get? id).getD 0
  let top := onScreen.foldl max top
  (onScreen ++ [top, top + 1, 0]).eraseDups

def World.noteSeen (w : World S) (laid : Laid) : World S :=
  { w with seen := (refs laid).foldl (fun m r => m.insert r.claim (max r.key ((m.get? r.claim).getD 0))) w.seen }

def isPointer (m : Move S) : Bool := m.triggers.any fun tr => tr == .press || tr == .doublePress

mutual
/-- The first node, in paint order, that breaks one of `Pressable`'s conditions, and which. -/
def firstBad (l : Laid) : Option (String × Laid) :=
  if !fitsB l then some ("a container's children don't fit it", l)
  else if !stackTopB l then some ("a stack has controls below its top child", l)
  else if !controlLeafB l then some ("a control has controls inside it", l)
  else match l with
    | .box _ _ _ _ kids => firstBadList kids
    | _ => none
def firstBadList : List Laid → Option (String × Laid)
  | [] => none
  | k :: ks => (firstBad k).orElse fun _ => firstBadList ks
end

/-- Every check after an operation: the checks that ran and the failures. `act?` is the
action the operation meant to perform, if it ran. -/
def checks (t : Target) (setup : Setup) (w : World t.S) (act? : Option Action)
    (acts : List Action) (stepIx : Nat) : List Ran × List Failure := Id.run do
  let s := w.rt.app
  let mut ran : Array Ran := #[]
  let mut fails : Array Failure := #[]
  -- Invariants.
  for inv in t.invariants do
    if let some ck := inv.check then
      ran := ran.push (inv.info.id, "invariant")
      unless ck s do
        fails := fails.push <| mkFail "invariant" ⟨inv.info.id, 0⟩ stepIx
          s!"^{inv.info.id} {inv.info.title} is false after this step"
  let some app := t.app | return (ran.toList, fails.toList)
  let laid := w.rt.laid
  let m := setup.metrics.metrics
  let size := w.rt.ui.size
  let min := t.minSize m s w.rt.ui
  let fitsWindow := decide (min.w ≤ size.w) && decide (min.h ≤ size.h)
  -- Performed: the action meant was delivered.
  if let some a := act? then
    let c := a.control
    if fitsWindow then
      ran := ran.push (c.claim, "performed")
      unless acts.contains a do
        fails := fails.push <| mkFail "performed" c stepIx
          s!"{reprStr a} was meant, but the runtime delivered {reprStr acts}"
  let _ := app
  -- Presence.
  for mv in t.machine.moves do
    if t.custom.noControl.contains mv.id then continue
    ran := ran.push (mv.id, "presence")
    for k in probeKeys t w mv.id do
      let r : ControlRef := ⟨mv.id, k⟩
      let on := present laid r
      let en := mv.enabled s k
      if on != en then
        fails := fails.push <| mkFail "presence" r stepIx
          (if en then s!"{r.label} is enabled but has no control in the frame"
           else s!"{r.label} is in the frame but its move is disabled")
  -- Pressable, at sizes at or above the minimum.
  if fitsWindow then
    let ts := targets laid
    let mut anyPointer := none
    for tg in ts do
      if tg.isField then continue
      let some mv := t.move? tg.ref.claim | continue
      unless isPointer mv && mv.enabled s tg.ref.key do continue
      if anyPointer.isNone then anyPointer := some tg.ref
      ran := ran.push (tg.ref.claim, "pressable")
      let hit := hitRef laid tg.visible.center
      unless hit == some tg.ref do
        fails := fails.push <| mkFail "pressable" tg.ref stepIx
          s!"{tg.ref.label}'s centre {reprStr tg.visible.center} hits {reprStr (hit.map (·.label))} at {size.w}×{size.h}"
    if let some r := anyPointer then
      unless checkPressable size laid && controlsNonempty laid do
        -- Blame the first control inside the first node that breaks a condition.
        let (why, r) := match firstBad laid with
          | some (why, n) => (why, (n.controls.head?.map fun (c : Control) => c.ref).getD r)
          | none =>
            if !insideB laid.rect (windowRect size) then ("the root is outside the window", r)
            else ("a control's rect is empty", ((targets laid).find? fun (tg : Cairn.Runtime.Target) =>
              !(decide (0 < tg.node.rect.w) && decide (0 < tg.node.rect.h))).map Cairn.Runtime.Target.ref |>.getD r)
        fails := fails.push <| mkFail "pressable-check" r stepIx
          s!"Layout.checkPressable rejects the tree at {size.w}×{size.h} (window ≥ minimum {min.w}×{min.h}): {why}, near {r.label}"
  return (ran.toList, fails.toList)

/-! ## Generating operations -/

/-- The actions available now: for each control on screen whose move is enabled, each trigger
it can take there. Without an `App`, each enabled move and probed key. -/
def candidates (t : Target) (w : World t.S) : List (ControlRef × Trigger × Bool) :=
  let s := w.rt.app
  match t.app with
  | some _ =>
    (targets w.rt.laid).flatMap fun tg =>
      match t.move? tg.ref.claim with
      | none => []
      | some mv =>
        if !mv.enabled s tg.ref.key then [] else
        mv.triggers.filterMap fun tr =>
          let ok := if tg.isField then tr != .press && tr != .doublePress
                    else tr == .press || tr == .doublePress
          if ok then some (tg.ref, tr, tg.isField) else none
  | none =>
    t.machine.moves.flatMap fun mv =>
      let keys := if t.isKeyed mv.id then List.range 17 else [0]
      keys.flatMap fun k =>
        if mv.enabled s k then mv.triggers.map fun tr => (⟨mv.id, k⟩, tr, tr == .edit) else []

def textScript (t : Target) (s : t.S) (id : ClaimId) : Gen (List TextOp) :=
  (t.custom.edits s id).getD Text.script

def genAct (t : Target) (w : World t.S) : Gen (Option (List Op)) := do
  let cs := candidates t w
  if cs.isEmpty then return none
  let (c, tr, _) ← Gen.elem cs
  match tr with
  | .press => return some [.act (.press c)]
  | .doublePress => return some [.act (.doublePress c)]
  | .submit => return some [.act (.submit c)]
  | .cancel => return some [.act (.cancel c)]
  | .blur => return some [.act (.blur c)]
  | .edit =>
    let ops ← textScript t w.rt.app c.claim
    return some (ops.map fun op => .act (.edit c op))

def genPoint (w : World S) : Gen Point := do
  let ts := targets w.rt.laid
  if !ts.isEmpty && (← Gen.bool) then
    let tg ← Gen.elem ts
    let c := tg.visible.center
    return ⟨c.x + (← Gen.int (-6) 6), c.y + (← Gen.int (-6) 6)⟩
  let z := w.rt.ui.size
  return ⟨← Gen.int 0 (max 0 z.w), ← Gen.int 0 (max 0 z.h)⟩

/-- A window size at or above the minimum, or (one in twenty) below it. -/
def genSize (min : Size) : Gen Size := do
  if ← Gen.chance 1 20 then
    return ⟨← Gen.int 0 (max 0 min.w), ← Gen.int 0 (max 0 min.h)⟩
  return ⟨min.w + (← Gen.int 0 400), min.h + (← Gen.int 0 400)⟩

def genNoise (t : Target) (setup : Setup) (w : World t.S) : Gen (List Op) := do
  if t.app.isNone then return []
  Gen.weighted
    [ (6, do return [.click (← genPoint w) (← Gen.elem [1, 1, 1, 2])]),
      (4, do return [.move (← genPoint w)]),
      (5, do return [.tab (← Gen.chance 1 4)]),
      (5, do return [.key (← Gen.elem [.enter, .escape, .backspace, .left, .right, .tab])
                            { shift := ← Gen.chance 1 4 }]),
      (6, do return [.resize (← genSize (t.minSize setup.metrics.metrics w.rt.app w.rt.ui))]),
      (1, pure [.exit]),
      (2, do return [.windowFocus (← Gen.chance 3 4)]) ]

/-- The next operations: mostly an enabled action, otherwise pointer, key or window noise. -/
def genOps (t : Target) (setup : Setup) (w : World t.S) : Gen (List Op) := do
  if t.app.isNone || (← Gen.chance 7 10) then
    if let some ops ← genAct t w then return ops
  genNoise t setup w

/-- A sequence's setup from its seed: metrics, then a window at or above the initial minimum. -/
def genSetup (t : Target) (seed : Nat) : Setup × Rng :=
  let g : Gen Setup := do
    let metrics ← MetricsChoice.gen
    let m := metrics.metrics
    let min := t.minSize m t.machine.init {}
    let size : Size := ⟨min.w + (← Gen.int 0 400), min.h + (← Gen.int 0 400)⟩
    return { seed, size, metrics }
  g.run (Rng.ofSeed seed)

/-! ## Running a sequence -/

/-- Counters for one claim. -/
structure ClaimStat where
  steps : Nat := 0
  checks : Std.HashMap String Nat := {}
  sequences : Nat := 0
  /-- The last sequence that touched it, so `sequences` counts each once. -/
  lastSeq : Option Nat := none
deriving Inhabited

abbrev Stats := Std.HashMap ClaimId ClaimStat

def Stats.record (st : Stats) (seq : Nat) (ran : List Ran) : Stats := Id.run do
  let mut st := st
  let mut touched : Std.HashSet ClaimId := {}
  for (id, kind) in ran do
    let c := (st.get? id).getD {}
    let c := { c with checks := c.checks.insert kind ((c.checks.get? kind).getD 0 + 1) }
    let c := if touched.contains id then c else
      { c with
        steps := c.steps + 1
        sequences := if c.lastSeq == some seq then c.sequences else c.sequences + 1
        lastSeq := some seq }
    touched := touched.insert id
    st := st.insert id c
  return st

/-- What one sequence did. -/
structure Outcome where
  setup : Setup
  ops : Array Op
  failure : Option Failure
  stats : Stats
  steps : Nat
  /-- Steps over the frame budget: (step, nanoseconds). -/
  over : Array (Nat × Nat)
  maxNs : Nat
  /-- Steps where pressability was skipped because the window was below the minimum. -/
  skipped : Nat

/-- Where a sequence's operations come from: the generator, or a fixed list (replay). -/
inductive Source where
  | gen (rng : Rng) (steps : Nat)
  | replay (ops : Array Op)

/-- Run one sequence, stopping at the first failure. Verbose prints each step. -/
def runSeq (t : Target) (setup : Setup) (src : Source) (stats : Stats := {})
    (verbose : Bool := false) : IO Outcome := do
  let mut w := (World.start t setup).noteSeen (World.start t setup).rt.laid
  let mut stats := stats
  let mut ops : Array Op := #[]
  let mut over : Array (Nat × Nat) := #[]
  let mut maxNs := 0
  let mut skipped := 0
  -- The initial state is checked too.
  let (ran0, f0) := checks t setup w none [] 0
  stats := stats.record setup.seed ran0
  if let some f := f0.head? then
    return { setup, ops, failure := some f, stats, steps := 0, over, maxNs, skipped }
  let (rng0, total, fixed) := match src with
    | .gen r n => (r, n, #[])
    | .replay os => (Rng.ofSeed 0, os.size, os)
  let mut rng := rng0
  let mut pending : List Op := []
  let mut i := 0
  while i < total do
    let op ← match pending, src with
      | o :: rest, _ => pending := rest; pure o
      | [], .replay _ => pure fixed[i]!
      | [], .gen .. =>
        let (os, r) := (genOps t setup w).run rng
        rng := r
        match os with
        | o :: rest => pending := rest; pure o
        | [] => pure Op.exit
    ops := ops.push op
    let p ← perform t setup w op
    i := i + 1
    w := p.world.noteSeen p.world.rt.laid
    maxNs := max maxNs p.maxNs
    if p.maxNs > t.budgetNs then over := over.push (i, p.maxNs)
    let act? := match op with | .act a => if p.ran then some a else none | _ => none
    let (ran, fs) := checks t setup w act? p.acts i
    if t.app.isSome then
      let min := t.minSize setup.metrics.metrics w.rt.app w.rt.ui
      unless min.w ≤ w.rt.ui.size.w && min.h ≤ w.rt.ui.size.h do skipped := skipped + 1
    stats := stats.record setup.seed ran
    if verbose then
      IO.println s!"  {i}. {opText op}{if p.ran then "" else "  (skipped: no such control)"} → {", ".intercalate (p.acts.map actionLean)}"
    if let some f := fs.head? then
      return { setup, ops, failure := some f, stats, steps := i, over, maxNs, skipped }
  return { setup, ops, failure := none, stats, steps := i, over, maxNs, skipped }

end Cairn.Fuzz

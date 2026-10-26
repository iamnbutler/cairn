import Cairn.Layout
import Cairn.Runtime
import Cairn.Abi

/-! `lake exe bench`: times `Cairn.Layout.layout` on three shapes of `n`-node trees (see
`bench/layout.md`), and a runtime step over a virtual list of `n` rows (`bench/vlist.md`). Frame encoding and decoding are `make bench-frame` (`bench/frame.md`). -/

open Cairn

/-- A column of `n` fixed-size buttons: the spike's shape. -/
def flatColumn (n : Nat) : Node :=
  .box { width := .fill, height := .fill, gap := 2 } none <|
    (List.range n).map fun i =>
      .box { width := .fixed 200, height := .fixed 10 } (some { ref := ⟨1, i⟩, label := "Row" }) []

/-- TodoMVC-like rows of six nodes: a row holding a checkbox, a label, a fill spacer and a
delete button with a text label. `n / 6` rows in a clipping column. -/
def todoRows (n : Nat) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨8, 8, 8, 8⟩, gap := 1, clip := true } none <|
    (List.range (n / 6)).map fun i =>
      .box { axis := .row, width := .fill, height := .fixed 40, gap := 8, align := .center,
             padding := ⟨0, 12, 0, 12⟩ } none
        [ .box { width := .fixed 20, height := .fixed 20 }
            (some { ref := ⟨2, i⟩, role := .checkbox, label := "Toggle" }) [],
          .text {} s!"Todo item number {i}",
          .box { width := .fill } none [],
          .box { padding := ⟨2, 6, 2, 6⟩ } (some { ref := ⟨3, i⟩, label := "Delete" })
            [.text {} "×"] ]

/-- `n` boxes nested one inside the next, each with 1 point of padding: the deepest tree. -/
def nested : Nat → Node
  | 0 => .text {} "leaf"
  | n + 1 => .box { padding := ⟨1, 1, 1, 1⟩ } none [nested n]

/-- Forces every rect of a laid tree. -/
partial def checksum : Laid → Int
  | .box r c _ _ kids => kids.foldl (fun a k => a + checksum k) (r.x + r.y + r.w + r.h + c.w)
  | .text r _ b _ _ => r.x + r.y + r.w + b
  | .field r _ _ _ _ _ _ c _ => r.x + c.x

partial def count : Node → Nat
  | .box _ _ kids => kids.foldl (fun a k => a + count k) 1
  | _ => 1

/-- A paragraph of `n` words of 1 to 10 letters, wrapped to the window (`Node.para`). -/
def paragraph (n : Nat) : Node :=
  let word (i : Nat) := String.ofList (List.replicate (1 + (i * 7 + i / 3) % 10) 'a')
  .para {} {} (" ".intercalate ((List.range n).map word))

def timeLayoutAt (tree : Node) (reps width : Nat) : IO (Float × Nat) := do
  let mut total := 0
  let mut sum : Int := 0
  let mut kids := 0
  for i in [0:reps] do
    let w : Size := ⟨width + i % 2, 600⟩
    let t0 ← IO.monoNanosNow
    let l := Layout.layout TextMetrics.mono w tree
    sum := sum + checksum l
    let t1 ← IO.monoNanosNow
    total := total + (t1 - t0)
    if let .box _ _ _ _ ks := l then kids := ks.length
  if sum == 0 then IO.println "empty"
  return (total.toFloat / reps.toFloat / 1000000.0, kids)

def timeLayout (tree : Node) (reps : Nat) : IO Float := do
  let mut total := 0
  let mut sum : Int := 0
  for i in [0:reps] do
    -- A different window each time, so nothing can be hoisted out of the loop.
    let w : Size := ⟨800 + i, 600⟩
    let t0 ← IO.monoNanosNow
    let l := Layout.layout TextMetrics.mono w tree
    sum := sum + checksum l
    let t1 ← IO.monoNanosNow
    total := total + (t1 - t0)
  if sum == 0 then IO.println "empty"
  return total.toFloat / reps.toFloat / 1000000.0

/-- `bench 100000` adds a size; the default is 100, 1,000 and 10,000. -/
def sizesOf (args : List String) : List Nat :=
  [100, 1000, 10000] ++ args.filterMap String.toNat?

/-- `bench --task-depth n`: lay out `nested n` on a Lean task thread (default stack), to find
how deep a tree the default thread stack takes. -/
def taskDepth (n : Nat) : IO Unit := do
  let t ← IO.asTask (prio := .dedicated) do
    let l := Layout.layout TextMetrics.mono ⟨800 + n, 600⟩ (nested n)
    return checksum l
  match t.get with
  | .ok v => IO.println s!"depth {n}: ok ({v})"
  | .error e => IO.println s!"depth {n}: {e}"

/-! ## Virtual lists (bench/vlist.md) -/

/-- The bench's list: its keys, and whether it is a `VList` or a plain scroll box of every row. -/
structure ListState where
  keys : Array Nat
  virtual : Bool := true

/-- A row like the fixture's: a button with a label, 24 to 48 points high. -/
def benchRow (k : Nat) : Node :=
  .box { width := .fill, height := .fixed (24 + 8 * (k % 4)), padding := ⟨0, 12, 0, 12⟩,
         align := .center } (some { ref := ⟨10, k⟩, label := "Row" }) [.text {} s!"Row {k}"]

def benchListRef : ControlRef := ⟨14, 0⟩

def listView (s : ListState) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨20, 20, 20, 20⟩ } none
    [if s.virtual then
       VList.node { ref := benchListRef, style := { width := .fill, height := .fill } } ui s.keys benchRow
     else
       .box (ui.scrolling benchListRef { width := .fill, height := .fill }) none
         (s.keys.toList.map benchRow)]

def listApp (s : ListState) : App ListState :=
  { init := s, surfaces := [.window 1 "Bench" listView], update := fun s _ => (s, []), claims := [] }

/-- A trackpad fling's wheel deltas, one per frame: 120 points, falling by 4% a frame until under
one point (about 120 frames, 2,900 points: a fast flick's momentum at 120 Hz). -/
def fling : Array Int := Id.run do
  let mut v : Nat := 120_000
  let mut out := #[]
  while v ≥ 1000 do
    out := out.push (Int.ofNat (v / 1000))
    v := v * 96 / 100
  return out

/-! ### A frame, by phase

What the host's Lean thread does for one batch of input (`Runtime.stepBytes`, then
`Runtime.frameBytes`): each event through `Runtime.step` (the batch's own events, then the two
`Runtime.frameEvents`), then the frame encoded. `timedStep` is `Runtime.step` written out with a
clock between its phases; `timedFrame` checks that it reaches the same state. -/

/-- Nanoseconds per phase of a frame. **update**: route the event, deliver its actions and
replies to the app, diff subscriptions (and, when the app heard something, what each surface
shows). **view**: `app.view`. **layout**: the layout of that view. **settle**: the runtime's
record of the virtual lists and the repair of hover, focus and scroll against the new tree
(`fixUI`), and any further view and layout `Runtime.settle` runs until it stops changing.
**encode**: `Runtime.frameBytes`, the frame as the host receives it. -/
structure Phases where
  update : Nat := 0
  view : Nat := 0
  layout : Nat := 0
  settle : Nat := 0
  encode : Nat := 0

def Phases.total (p : Phases) : Nat := p.update + p.view + p.layout + p.settle + p.encode

instance : Add Phases where
  add a b := { update := a.update + b.update, view := a.view + b.view, layout := a.layout + b.layout,
               settle := a.settle + b.settle, encode := a.encode + b.encode }

def nodeTag : Node → Nat
  | .box .. => 1
  | _ => 2

/-- `Runtime.step` with a clock between its phases. -/
def timedStep {S : Type} (app : App S) (cfg : Runtime.Config) (s : Runtime.State S) (e : Event) :
    IO (Runtime.State S × Phases) := do
  let t0 ← IO.monoNanosNow
  let (s1, acts) := Runtime.route cfg.metrics s e
  let c0 := Runtime.admit app s e
  if acts.isEmpty && !c0.delivered && Runtime.UI.same s1.ui s.ui then
    let s' := { s1 with world := c0.world }
    let t1 ← IO.monoNanosNow
    return (s', { update := t1 - t0 })
  let c := Runtime.act app c0 acts
  let (subs, cmds, next) :=
    if c.delivered then Runtime.diffSubs c.world.subs (app.subscriptions c.app) c.world.nextSub
    else (c.world.subs, [], c.world.nextSub)
  let ui1 := Runtime.applyFocus c.effs s1.ui
  let surfaces := if c.delivered then Runtime.shows app cfg c.app else s1.surfaces
  if surfaces.length + cmds.length == 1000000 then IO.println "many"
  let t1 ← IO.monoNanosNow
  let node := app.view c.app ui1
  if nodeTag node == 0 then IO.println "no view"
  let t2 ← IO.monoNanosNow
  let laid := cfg.layout cfg.metrics ui1.size node
  if checksum laid == -1 then IO.println "odd"
  let t3 ← IO.monoNanosNow
  let ui' := Runtime.fixUI laid s1.pointer ui1
  let (ui, laid) :=
    if Runtime.UI.same ui' ui1 then (ui', laid)
    else Runtime.settle app cfg c.app s1.pointer ui1 (Runtime.settleFuel - 1) ui'
  if checksum laid == -1 then IO.println "odd"
  let t4 ← IO.monoNanosNow
  let s' := { s1 with app := c.app, ui, laid, world := { c.world with subs, nextSub := next },
                      subCmds := s1.subCmds ++ cmds.toArray, surfaces }
  return (s', { update := t1 - t0, view := t2 - t1, layout := t3 - t2, settle := t4 - t3 })

/-- One frame of `es`, by phase: the events and `Runtime.frameEvents` through `timedStep`, then
the frame encoded. With `check`, also `Runtime.steps`' own result, which must lay the same tree
at the same offsets. -/
def timedFrame {S : Type} (app : App S) (cfg : Runtime.Config) (s : Runtime.State S)
    (es : List Event) (check := false) : IO (Runtime.State S × List Effect × Phases) := do
  let s0 := { s with effects := #[], subCmds := #[] }
  let mut st := s0
  let mut ph : Phases := {}
  for e in es ++ Runtime.frameEvents do
    let (s', p) ← timedStep app cfg st e
    st := s'
    ph := ph + p
  -- The effects, outside the clock: `timedStep` doesn't collect them.
  let (r, effs) := Runtime.steps app cfg s0 es
  st := { st with effects := effs.toArray }
  let t0 ← IO.monoNanosNow
  let bytes := Runtime.frameBytes Frame.boundary st
  if bytes.size == 0 then IO.println "empty frame"
  let t1 ← IO.monoNanosNow
  if check && (checksum r.laid != checksum st.laid || !Runtime.UI.same r.ui st.ui) then
    throw <| IO.userError "timedStep and Runtime.step disagree"
  return (st, effs, { ph with encode := t1 - t0 })

/-- Median and 95th percentile of `ns`, in ms. -/
def pcts (ns : Array Nat) : Float × Float :=
  let a := ns.qsort (· < ·)
  ((a[a.size / 2]!).toFloat / 1e6, (a[a.size * 95 / 100]!).toFloat / 1e6)

/-- `x` ms to three decimals. -/
def ms3 (x : Float) : String :=
  let n := (x * 1000.0).round.toUInt64.toNat
  s!"{n / 1000}.{(toString (n % 1000 + 1000)).drop 1}"

def fmt (p : Float × Float) : String := s!"p50 {ms3 p.1} ms, p95 {ms3 p.2} ms"

/-- The frame's median and 95th percentile, and the median of each phase, in ms. -/
def fmtPhases (ps : Array Phases) : String :=
  let med (f : Phases → Nat) := ms3 (pcts (ps.map f)).1
  s!"frame {fmt (pcts (ps.map Phases.total))}; medians: update {med (·.update)}, view {med (·.view)}, layout {med (·.layout)}, settle {med (·.settle)}, encode {med (·.encode)} ms"

/-- `reps` frames of the events `es i` from `s`, each from the state the last left; the first
five checked against `Runtime.steps`. -/
def timeFrames {S : Type} (app : App S) (s : Runtime.State S) (reps : Nat) (es : Nat → List Event) :
    IO (Array Phases × Runtime.State S) := do
  let mut s := s
  let mut ps := #[]
  for i in [0:reps] do
    let (s', _, p) ← timedFrame app {} s (es i) (check := i < 5)
    ps := ps.push p
    s := s'
  return (ps, s)

/-- Times `reps` runtime steps of `es i` from `s`, each from the state the last left. -/
def timeSteps (app : App ListState) (s : Runtime.State ListState) (reps : Nat) (e : Nat → Event) :
    IO (Array Nat × Runtime.State ListState) := do
  let mut s := s
  let mut ns := #[]
  let mut sum : Int := 0
  for i in [0:reps] do
    let t0 ← IO.monoNanosNow
    let (s', _) := Runtime.step app {} s (e i)
    sum := sum + checksum s'.laid
    let t1 ← IO.monoNanosNow
    ns := ns.push (t1 - t0)
    s := s'
  if sum == 0 then IO.println "empty"
  return (ns, s)

/-- A virtual list of `n` rows (or, `virtual := false`, a scroll box holding all of them) in an
800 × 600 window: wheel steps of 300 points, down and back up (up to 100 each way, fewer for a
short list, so that every step moves it); 300 points up from the end, 200 times (fewer for a
short list); and a row inserted at the head, settled. Then whole frames by phase
(`timedFrame`): flings (`fling`) down from the top and back up. -/
def benchList (n : Nat) (virtual : Bool) : IO Unit := do
  let keys := (Array.range n).map (· + 1)
  let app := listApp { keys, virtual }
  let s0 := Runtime.start app {} ⟨800, 600⟩
  let p : Point := ⟨400, 300⟩
  let reps := if virtual || n ≤ 1000 then 200 else 20
  -- Down and back up, `m` steps each way, so that no step is a no-op at either end.
  let m := max 1 (min 100 (n * 30 / 300))
  let (ns, s1) ← timeSteps app s0 reps fun i => .scroll p 0 (if (i / m) % 2 = 0 then 300 else -300)
  let label := if virtual then "virtual list" else "plain scroll box"
  IO.println s!"{label}, {n} rows: scroll 300 pt: {fmt (pcts (ns.extract 10 ns.size))}; offset {s1.ui.scrollOf benchListRef}, {(s1.ui.listOf benchListRef).rows.size} heights kept"
  -- Flings, whole frames by phase: two down from the top, then two back up (a short list
  -- reaches its end, and its frames there move nothing).
  let fl := fling
  let (_, sTop) ← timeSteps app s1 1 fun _ => .scroll p 0 (-100_000_000)
  let (pd, sF) ← timeFrames app sTop (2 * fl.size) fun i => [.pointerMove p, .scroll p 0 fl[i % fl.size]!]
  let (pu, _) ← timeFrames app sF (2 * fl.size) fun i => [.pointerMove p, .scroll p 0 (-fl[i % fl.size]!)]
  IO.println s!"{label}, {n} rows: fling, {pd.size + pu.size} frames: {fmtPhases (pd ++ pu)}"
  unless virtual do return
  -- Through the whole list and back (a jump to the end, then up): what is kept stays bounded.
  let (_, s2) ← timeSteps app s1 1 fun _ => .scroll p 0 100_000_000
  let (ns2, s2) ← timeSteps app s2 (min 200 (n * 30 / 300)) fun _ => .scroll p 0 (-300)
  IO.println s!"virtual list, {n} rows: scroll 300 pt up from the end: {fmt (pcts (ns2.extract 2 ns2.size))}; {(s2.ui.listOf benchListRef).rows.size} heights kept"
  -- A row inserted at the head, settled; the new keys are built before the clock starts.
  let mut ins := #[]
  let mut s := s1
  for i in [0:50] do
    let keys' := #[n + 1 + i] ++ s.app.keys
    let s' := { s with app := { s.app with keys := keys' } }
    let t0 ← IO.monoNanosNow
    let (ui, laid) := Runtime.settle app {} s'.app s'.pointer s'.ui Runtime.settleFuel s'.ui
    let c := checksum laid
    let t1 ← IO.monoNanosNow
    if c == 0 then IO.println "empty"
    ins := ins.push (t1 - t0)
    s := { s' with ui, laid }
  IO.println s!"virtual list, {n} rows: insert at the head: {fmt (pcts (ins.extract 5 ins.size))}"


def main (args : List String) : IO Unit := do
  if let ["--task-depth", n] := args then
    taskDepth n.toNat!
    return
  if args.head? == some "--vlist" then
    for n in [100, 1000, 10000, 100000] do
      benchList n true
    for n in [100, 1000, 10000] do
      benchList n false
    return
  let sizes : IO (List Nat) := pure (sizesOf args)
  for (name, mk) in [("flat column", flatColumn), ("todo rows", todoRows), ("nested", nested)] do
    for n in (← sizes) do
      let tree := mk n
      let nodes := count tree
      let _ ← timeLayout tree 5
      let ms ← timeLayout tree 50
      IO.println s!"layout {name}, {nodes} nodes: {ms} ms ({ms * 1000.0 / nodes.toFloat} µs/node)"
  for words in [100, 1000, 10000] do
    let tree := paragraph words
    for width in [200, 400, 800] do
      let _ ← timeLayoutAt tree 5 width
      let (ms, lines) ← timeLayoutAt tree 50 width
      IO.println s!"layout paragraph, {words} words at width {width}: {ms} ms ({lines} lines)"

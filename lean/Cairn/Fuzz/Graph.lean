import Lean.Data.Json
import Cairn.Fuzz.Walk

/-! # The move graph (prototype)

`lake exe fuzz <App> --graph D`: the app's moves as a graph, explored breadth first from the
first frame to depth `D` through the real runtime, as the fuzzer drives it.

A **node** is what a person can do in a state: the claim ids of the moves with a control on
screen that is enabled (`candidates`). Two states that offer the same moves are one node. A node
names only claim ids, so the nodes of two versions of an app compare directly.

An **edge** is a move performed from a node: one action per claim and trigger (the control with
the smallest key; an edit types `"milk"`), after which the host answers every request (`drain`).

The walk is over states, not nodes: typing changes no node but makes Add do something, so a node
is explored from up to `perNode` states that look different (their frames' dumps differ). The
graph is exact for the states it visited and says nothing about the others: it is evidence by
exploration, not proof. Timers and subscription events are not sent.

`tools/map/tree.ts graph` draws it as a tree and diffs two versions. -/

namespace Cairn.Fuzz.Graph
open Lean (Json toJson)
open Cairn Cairn.Claims Cairn.Fuzz Cairn.Runtime Cairn.Layout

variable {S W : Type}

/-- A node's signature: the claim ids a person can act on, sorted. -/
abbrev Sig := List ClaimId

def sigOf (t : Target) (w : World t.S W) : Sig :=
  ((candidates t w).map (·.1.claim)).eraseDups.mergeSort

/-- The text an edge's edit types. -/
def typed : String := "milk"

/-- One action per claim and trigger: the candidate with the smallest key. -/
def reps (t : Target) (w : World t.S W) : List Action :=
  let cs := (candidates t w).foldl (fun (acc : List (ControlRef × Trigger)) (c, tr, _) =>
    match acc.find? (fun (r, tr') => r.claim == c.claim && tr' == tr) with
    | some (r, _) => if c.key < r.key then
        acc.map fun x => if x.1.claim == c.claim && x.2 == tr then (c, tr) else x else acc
    | none => acc ++ [(c, tr)]) []
  let cs := cs.mergeSort fun a b => a.1.claim < b.1.claim ||
    (a.1.claim == b.1.claim && a.2.name ≤ b.2.name)
  cs.filterMap fun (c, tr) => match tr with
    | .press => some (.press c)
    | .doublePress => some (.doublePress c)
    | .edit => some (.edit c (.insert typed))
    | .submit => some (.submit c)
    | .cancel => some (.cancel c)
    | .blur => some (.blur c)
    | .appear => none

structure Node where
  sig : Sig
  depth : Nat
  /-- Whether the node's moves were explored (false past the depth or the node limit). -/
  explored : Bool := false

structure Edge where
  src : Nat
  dst : Nat
  action : Action
  /-- How many actions `update` received: 0 when the move did nothing a person could see. -/
  delivered : Nat
  /-- Effects the step put on the frame (requests, timers, …). -/
  effects : Nat
  /-- How many explored states took this edge. -/
  count : Nat := 1

def triggerOf : Action → Trigger
  | .press _ => .press | .doublePress _ => .doublePress | .edit .. => .edit
  | .submit _ => .submit | .cancel _ => .cancel | .blur _ => .blur | .appear _ => .appear

def refOf : Action → ControlRef
  | .press c | .doublePress c | .edit c _ | .submit c | .cancel c | .blur c | .appear c => c

/-- What a person sees of a state, hashed: two states with the same frame are explored once. -/
def seen (w : World S W) : UInt64 :=
  hash (Dump.canvas (Frame.ofLaid w.rt.ui w.rt.laid))

/-- Breadth first over states that look different (`seen`), to `depth` moves, exploring at most
`perNode` states of each node and `maxStates` in all. -/
def explore (t : Target) (depth perNode maxStates : Nat) :
    IO (Array Node × Array Edge × Size × Nat) := do
  let m := MetricsChoice.mono
  let min := t.minSize m.metrics t.machine.init {}
  let size : Size := ⟨max min.w 800, max min.h 600⟩
  let setup : Setup := { seed := 0, size, metrics := m }
  let (w0, _) ← drain t setup (World.start t setup) (Rng.ofSeed 0) 64
  let s0 := sigOf t w0
  let mut nodes : Array Node := #[{ sig := s0, depth := 0 }]
  let mut index : Std.HashMap Sig Nat := ({} : Std.HashMap Sig Nat).insert s0 0
  let mut states : Std.HashSet UInt64 := ({} : Std.HashSet UInt64).insert (seen w0)
  let mut queued : Array Nat := #[1]
  let mut queue : Array (World t.S t.W × Nat × Nat) := #[(w0, 0, 0)]
  let mut edges : Array Edge := #[]
  let mut edgeIx : Std.HashMap String Nat := {}
  let mut i := 0
  while h : i < queue.size do
    let (w, n, d) := queue[i]
    i := i + 1
    if d ≥ depth then continue
    if let some node := nodes[n]? then nodes := nodes.set! n { node with explored := true }
    for a in reps t w do
      let p ← perform t setup w (.act a)
      if !p.ran then continue
      let (w', _) ← drain t setup p.world (Rng.ofSeed 0) 64
      let sig := sigOf t w'
      let dst ← match index.get? sig with
        | some x => pure x
        | none => do
          let x := nodes.size
          nodes := nodes.push { sig, depth := d + 1 }
          index := index.insert sig x
          queued := queued.push 0
          pure x
      let look := seen w'
      if !states.contains look && queued[dst]!  < perNode && queue.size < maxStates then
        states := states.insert look
        queued := queued.modify dst (· + 1)
        queue := queue.push (w', dst, d + 1)
      let r := refOf a
      let k := s!"{n} {r.claim} {(triggerOf a).name} {dst}"
      match edgeIx.get? k with
      | some e => edges := edges.modify e fun x => { x with count := x.count + 1 }
      | none =>
        edgeIx := edgeIx.insert k edges.size
        edges := edges.push { src := n, dst, action := a, delivered := p.acts.length,
                              effects := p.effects.length }
  return (nodes, edges, size, queue.size)

def run (t : Target) (depth perNode maxStates : Nat) (out : System.FilePath) : IO UInt32 := do
  let (nodes, edges, size, explored) ← explore t depth perNode maxStates
  let nodeJson (i : Nat) (n : Node) : Json := Json.mkObj [("id", toJson i),
    ("sig", toJson n.sig), ("depth", toJson n.depth), ("explored", toJson n.explored)]
  let edgeJson (e : Edge) : Json :=
    let r := refOf e.action
    Json.mkObj [("from", toJson e.src), ("to", toJson e.dst), ("claim", toJson r.claim),
      ("key", toJson r.key), ("trigger", Json.str (triggerOf e.action).name),
      ("action", Json.str (actionLean e.action)), ("delivered", toJson e.delivered),
      ("effects", toJson e.effects), ("count", toJson e.count)]
  let json := Json.mkObj [("app", Json.str t.name), ("module", Json.str t.module),
    ("depth", toJson depth), ("perNode", toJson perNode), ("maxStates", toJson maxStates),
    ("states", toJson explored),
    ("window", Json.mkObj [("w", toJson size.w), ("h", toJson size.h)]), ("typed", Json.str typed),
    ("claims", Json.mkObj (t.claims.map fun c => (s!"{c.id}", Json.str c.title))),
    -- Each claim's place (`in ^P`), and each place's, so a diagram can be drawn per place.
    ("places", Json.mkObj (t.claims.map fun c =>
      (s!"{c.id}", match c.place with | some p => toJson p | none => Json.null))),
    ("placeIds", toJson ((t.claims.filter (·.kind == .place)).map (·.id))),
    ("nodes", Json.arr (nodes.mapIdx fun i n => nodeJson i n)),
    ("edges", Json.arr (edges.map edgeJson))]
  let file := out / s!"{t.name}.json"
  if let some parent := file.parent then IO.FS.createDirAll parent
  IO.FS.writeFile file (json.pretty ++ "\n")
  IO.println s!"{explored} states, {nodes.size} nodes, {edges.size} edges; wrote {file}"
  return 0

end Cairn.Fuzz.Graph

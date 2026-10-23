import Cairn.Layout

/-! `lake exe bench`: times `Cairn.Layout.layout` on three shapes of `n`-node trees (see
`bench/layout.md`). Frame encoding and decoding are `make bench-frame` (`bench/frame.md`). -/

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

def main (args : List String) : IO Unit := do
  if let ["--task-depth", n] := args then
    taskDepth n.toNat!
    return
  let sizes : IO (List Nat) := pure (sizesOf args)
  for (name, mk) in [("flat column", flatColumn), ("todo rows", todoRows), ("nested", nested)] do
    for n in (← sizes) do
      let tree := mk n
      let nodes := count tree
      let _ ← timeLayout tree 5
      let ms ← timeLayout tree 50
      IO.println s!"layout {name}, {nodes} nodes: {ms} ms ({ms * 1000.0 / nodes.toFloat} µs/node)"

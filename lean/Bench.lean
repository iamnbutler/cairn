import Examples.Counter
import Cairn.Layout

/-! `lake exe bench`: times the Lean half of a frame.

1. The spike's column of `n` boxes, laid out and encoded (`Cairn.Spike`).
2. `Cairn.Layout.layout` on two shapes of `n`-node trees (see `bench/layout.md`). -/

open Cairn

def timeIt (n reps : Nat) : IO Float := do
  let mut total := 0
  let mut size := 0
  for _ in [0:reps] do
    let t0 ← IO.monoNanosNow
    let bytes := Examples.Counter.benchFrame n.toUInt32
    size := size + bytes.size
    let t1 ← IO.monoNanosNow
    total := total + (t1 - t0)
  if size == 0 then IO.println "empty"
  return total.toFloat / reps.toFloat / 1000000.0

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

def main : IO Unit := do
  for n in [100, 1000, 10000] do
    let _ ← timeIt n 5
    let ms ← timeIt n 50
    IO.println s!"{n} boxes: {ms} ms per frame (spike layout + encode)"
  for (name, mk) in [("flat column", flatColumn), ("todo rows", todoRows)] do
    for n in [100, 1000, 10000] do
      let tree := mk n
      let nodes := count tree
      let _ ← timeLayout tree 5
      let ms ← timeLayout tree 50
      IO.println s!"layout {name}, {nodes} nodes: {ms} ms ({ms * 1000.0 / nodes.toFloat} µs/node)"

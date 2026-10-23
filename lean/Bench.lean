import Examples.Counter

/-! Times laying out and encoding a frame of `n` boxes, the Lean half of a frame. -/

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

def main : IO Unit := do
  for n in [100, 1000, 10000] do
    let _ ← timeIt n 5
    let ms ← timeIt n 50
    IO.println s!"{n} boxes: {ms} ms per frame (layout + encode)"

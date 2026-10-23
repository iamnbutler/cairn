def timeIt (label : String) (k : Unit → IO Nat) : IO Unit := do
  let t0 ← IO.monoNanosNow
  let r ← k ()
  let t1 ← IO.monoNanosNow
  IO.println s!"{label}: {(t1 - t0).toFloat / 1e6} ms (result {r})"

-- 1. in-place updates on a unique array
def fillUnique (n : Nat) : Array Nat := Id.run do
  let mut a := Array.replicate n 0
  for i in [0:n] do
    a := a.set! i (i * 2)
  return a

-- 2. same loop, but an alias keeps the original alive => copy on first write, then unique
def fillAliasedOnce (n : Nat) : Array Nat × Array Nat := Id.run do
  let orig := Array.replicate n 0
  let mut a := orig
  for i in [0:n] do
    a := a.set! i (i * 2)
  return (orig, a)

-- 3. pathological: keep every intermediate version => copy every step (O(n^2))
def fillKeepAll (n : Nat) : List (Array Nat) := Id.run do
  let mut a := Array.replicate n 0
  let mut hist := []
  for i in [0:n] do
    hist := a :: hist
    a := a.set! i (i * 2)
  return hist

-- 4. ByteArray push (encoder pattern)
def encodeBytes (n : Nat) : ByteArray := Id.run do
  let mut b := ByteArray.emptyWithCapacity (n * 4)
  for i in [0:n] do
    let x := i.toUInt32
    b := b.push x.toUInt8 |>.push (x >>> 8).toUInt8 |>.push (x >>> 16).toUInt8 |>.push (x >>> 24).toUInt8
  return b

-- 5. List build + reverse vs Array push
def listBuild (n : Nat) : List Nat := (List.range n).map (· * 3)
def arrBuild (n : Nat) : Array Nat := (Array.range n).map (· * 3)

-- 6. Tree of nodes: structural map (reset/reuse should apply)
inductive T where
  | node (w : Nat) (cs : List T)
def mk : Nat → Nat → T
  | 0, _ => .node 1 []
  | d+1, k => .node d ((List.range k).map fun _ => mk d k)
def bump : T → T
  | .node w cs => .node (w + 1) (go cs)
where go : List T → List T
  | [] => []
  | c :: cs => bump c :: go cs
def sz : T → Nat
  | .node w cs => w + go cs
where go : List T → Nat
  | [] => 0
  | c :: cs => sz c + go cs

def deep (n : Nat) : IO Unit := do
  let t := T.node 0 ((List.range n).map fun _ => .node 0 [])
  IO.println s!"wide {n}: {sz (bump t)}"

def main (args : List String) : IO Unit := do
  if let some k := args.head?.bind String.toNat? then
    deep k
    return
  let n := 1000000
  timeIt "fillUnique 1e6" fun _ => pure (fillUnique n).size
  timeIt "fillAliasedOnce 1e6" fun _ => pure (fillAliasedOnce n).2.size
  timeIt "fillKeepAll 2e4" fun _ => pure (fillKeepAll 20000).length
  timeIt "encodeBytes 1e6 u32" fun _ => pure (encodeBytes n).size
  timeIt "listBuild 1e6" fun _ => pure (listBuild n).length
  timeIt "arrBuild 1e6" fun _ => pure (arrBuild n).size
  let t := mk 6 8  -- 8^6 ≈ 262k leaves
  timeIt "tree size (~300k nodes)" fun _ => pure (sz t)
  timeIt "tree bump unique" fun _ => pure (sz (bump t))  -- t still alive => no reuse
  if args.contains "linear" then
    let a := (Array.replicate 10 0).markLinear
    let b := a.set! 0 1
    IO.println s!"{a.size} {b.size}"

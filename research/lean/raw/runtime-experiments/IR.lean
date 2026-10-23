inductive T where
  | node (w : Nat) (cs : List T)
set_option trace.compiler.ir.result true in
def bump : T → T
  | .node w cs => .node (w + 1) (go cs)
where go : List T → List T
  | [] => []
  | c :: cs => bump c :: go cs
structure P where (x y : UInt64)
set_option trace.compiler.ir.result true in
def addP (a : Array P) (i : Nat) : Array P := a.modify i fun p => { p with x := p.x + 1 }
set_option trace.compiler.ir.result true in
def sumU (a : Array UInt64) : UInt64 := a.foldl (· + ·) 0

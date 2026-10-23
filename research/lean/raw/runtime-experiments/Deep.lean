inductive T where
  | node (w : Nat) (cs : List T)
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
@[export deep_wide] def deepWide (n : USize) : USize :=
  (sz (bump (T.node 0 ((List.range n.toNat).map fun _ => .node 0 [])))).toUSize

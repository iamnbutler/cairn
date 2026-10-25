import Lean
import Cairn.Claims.Registry
import Cairn.Claims.Core

/-! Shared by `lake exe ledger` and `lake exe claims`: loading the claims of a built package, and
hashing a claim's formal statement. Compile-time tooling; never linked into the host. -/

namespace Cairn.Claims.Tool
open Lean

/-- Import `roots` (built `.olean`s) and return the environment, with the claim registry
filled from every imported module. -/
unsafe def load (roots : List Name) : IO Environment := do
  initSearchPath (← findSysroot)
  -- Run the imported modules' `initialize` declarations, so the registry's state is built
  -- from the imported entries.
  enableInitializersExecution
  importModules (roots.map ({ module := · })).toArray {} (trustLevel := 1024) (loadExts := true)

/-- Whether a constant comes from Cairn's own modules (`Cairn.*`) or from the
claim's own package, the modules under `own` (`Yap` for a claim in `Yap.Model`). -/
def ours (env : Environment) (own : Name) (n : Name) : Bool :=
  match env.getModuleIdxFor? n with
  | some idx =>
    let m := env.header.moduleNames[idx.toNat]!
    m.getRoot == `Cairn || m.getRoot == own
  | none => false

/-! ### Statement hashes

FNV-1a (64-bit) over a canonical walk of the statement's declarations. Binder names and
metadata are ignored; constants from Cairn's own modules are followed into their definitions
(theorems by their statement only, inductive types by name only), so changing a helper a `post`
uses changes the hash, while renaming a bound variable or re-proving a lemma does not. Constants
from Lean's core library count by name, and so do machines and other claims (each claim has its
own hash). -/

structure Hasher where
  h : UInt64 := 14695981039346656037
  /-- Hashes of our constants, computed once. -/
  done : Std.HashMap Name UInt64 := {}
  /-- Constants being hashed, to cut cycles. -/
  active : NameSet := {}

/-- The environment, and the root of the claim's own modules (see `ours`). -/
abbrev HashM := ReaderT (Environment × Name) (StateM Hasher)

def mixByte (h : UInt64) (b : UInt8) : UInt64 := (h ^^^ b.toUInt64) * 1099511628211

def mix64 (h x : UInt64) : UInt64 :=
  (List.range 8).foldl (fun h i => mixByte h (x >>> (8 * i).toUInt64).toUInt8) h

def mixStr (h : UInt64) (s : String) : UInt64 :=
  mixByte (s.toUTF8.foldl mixByte h) 0

def emit (x : UInt64) : HashM Unit := modify fun st => { st with h := mix64 st.h x }
def emitStr (s : String) : HashM Unit := modify fun st => { st with h := mixStr st.h s }
def emitTag (t : Nat) : HashM Unit := emit t.toUInt64

/-- Run `act` with a fresh accumulator and return what it hashed. -/
def isolated (act : HashM Unit) : HashM UInt64 := do
  let saved := (← get).h
  modify fun st => { st with h := 14695981039346656037 }
  act
  let out := (← get).h
  modify fun st => { st with h := saved }
  return out

def claimTypes : List Name :=
  [``Cairn.Claims.Machine, ``Cairn.Claims.Move, ``Cairn.Claims.Flow, ``Cairn.Claims.Invariant,
   ``Cairn.Claims.Assumption, ``Cairn.Claims.Place, ``Cairn.ClaimInfo]

mutual
partial def hashConst (n : Name) : HashM Unit := do
  let (env, own) ← read
  emitStr n.toString
  unless ours env own n do return
  -- Machines and other claims count by name: each claim has its own id and hash, so changing a
  -- move flags that move, not every flow and invariant stated against its machine.
  if let some ci := env.find? n then
    if let some h := ci.type.getAppFn.constName? then
      if claimTypes.contains h then return
  if let some v := (← get).done[n]? then emit v; return
  if (← get).active.contains n then return
  modify fun st => { st with active := st.active.insert n }
  let v ← isolated do
    match env.find? n with
    | some (.defnInfo d) => hashExpr d.type; hashExpr d.value
    | some (.thmInfo t) => hashExpr t.type
    | some (.opaqueInfo o) => hashExpr o.type
    | some (.axiomInfo a) => hashExpr a.type
    | _ => pure ()
  modify fun st => { st with done := st.done.insert n v, active := st.active.erase n }
  emit v

partial def hashExpr : Expr → HashM Unit
  | .bvar i => do emitTag 0; emit i.toUInt64
  | .fvar _ => emitTag 1
  | .mvar _ => emitTag 2
  | .sort u => do emitTag 3; emitStr (toString u)
  | .const n us => do emitTag 4; hashConst n; for u in us do emitStr (toString u)
  | .app f a => do emitTag 5; hashExpr f; hashExpr a
  | .lam _ t b _ => do emitTag 6; hashExpr t; hashExpr b
  | .forallE _ t b _ => do emitTag 7; hashExpr t; hashExpr b
  | .letE _ t v b _ => do emitTag 8; hashExpr t; hashExpr v; hashExpr b
  | .lit (.natVal n) => do emitTag 9; emitStr (toString n)
  | .lit (.strVal s) => do emitTag 10; emitStr s
  | .mdata _ e => hashExpr e
  | .proj s i e => do emitTag 11; emitStr s.toString; emit i.toUInt64; hashExpr e
end

def hex (x : UInt64) : String :=
  let s := String.ofList (Nat.toDigits 16 x.toNat)
  String.ofList (List.replicate (16 - s.length) '0') ++ s

/-- The hash of a claim's formal statement, or `-` when it has none (places, assumptions with
only prose). The claim's kind and, for moves, its triggers and keyedness are part of it. -/
def statementHash (env : Environment) (e : Entry) : String :=
  if e.statement.isEmpty then "-" else
  let act : HashM Unit := do
    emitStr e.info.kind.name
    for t in e.triggers do emitStr t
    emitTag (if e.keyed then 1 else 0)
    for n in e.statement do hashConst n
  hex ((act.run (env, e.module.getRoot)).run {}).2.h

/-- The axioms a theorem depends on beyond Lean's standard three. -/
def extraAxioms (env : Environment) (n : Name) : IO (List Name) := do
  let (axs, _) ← (collectAxioms n : CoreM _).toIO { fileName := "claims", fileMap := default } { env }
  return axs.toList.filter (· ∉ [``propext, ``Classical.choice, ``Quot.sound])

end Cairn.Claims.Tool

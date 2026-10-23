module

public import Cairn.Input

/-! # A seeded PRNG and generators

SplitMix64 (Steele, Lea and Flood, "Fast splittable pseudorandom number generators", 2014): a
64-bit state advanced by a constant, then mixed. Small, fast, good enough for test generation,
and pure, so a seed replays a run exactly. Core only: no Plausible.

A module, so apps can write custom generators (`Cairn.Fuzz.Custom`) without linking `Lean`. -/

@[expose] public section

namespace Cairn.Fuzz

structure Rng where
  state : UInt64
deriving Repr, Inhabited

namespace Rng

def golden : UInt64 := 0x9e3779b97f4a7c15

/-- The SplitMix64 finaliser. -/
def mix (z : UInt64) : UInt64 :=
  let z := (z ^^^ (z >>> 30)) * 0xbf58476d1ce4e5b9
  let z := (z ^^^ (z >>> 27)) * 0x94d049bb133111eb
  z ^^^ (z >>> 31)

def ofSeed (seed : Nat) : Rng := ⟨mix seed.toUInt64⟩

def next (g : Rng) : UInt64 × Rng :=
  let s := g.state + golden
  (mix s, ⟨s⟩)

end Rng

/-- A generator: a state transformer over the PRNG. -/
abbrev Gen := StateM Rng

namespace Gen

def run {α : Type} (g : Gen α) (r : Rng) : α × Rng := StateT.run g r

def u64 : Gen UInt64 := modifyGet Rng.next

/-- Uniform-ish in `[0, n)` (`0` when `n = 0`); the modulo bias is negligible for small `n`. -/
def below (n : Nat) : Gen Nat := do
  if n = 0 then return 0
  return (← u64).toNat % n

/-- In `[lo, hi]`. -/
def range (lo hi : Nat) : Gen Nat := do return lo + (← below (hi + 1 - lo))

def int (lo hi : Int) : Gen Int := do
  return lo + ((← below (hi + 1 - lo).toNat) : Int)

def bool : Gen Bool := do return (← below 2) == 1

/-- True with probability `num / den`. -/
def chance (num den : Nat) : Gen Bool := do return (← below den) < num

def elem {α : Type} [Inhabited α] (xs : List α) : Gen α := do
  return xs[← below xs.length]!

def oneOf {α : Type} [Inhabited α] (gs : List (Gen α)) : Gen α := do
  match gs[← below gs.length]? with
  | some g => g
  | none => return default

/-- Pick by weight. -/
def weighted {α : Type} [Inhabited α] (gs : List (Nat × Gen α)) : Gen α := do
  let total := (gs.map (·.1)).foldl (· + ·) 0
  let mut r ← below total
  for (w, g) in gs do
    if r < w then return ← g
    r := r - w
  return default

def listOf {α : Type} (n : Nat) (g : Gen α) : Gen (List α) := do
  let mut out := #[]
  for _ in [0:n] do out := out.push (← g)
  return out.toList

end Gen

/-- What an app may add to the fuzzer, by defining `fuzz : Cairn.Fuzz.Custom State` in its
namespace (docs/fuzz.md). Every field has a default. -/
structure Custom (S : Type) where
  /-- Scripts of text operations for a field's `edit` move (by claim id), each operation sent as
  its own event; `none` keeps the default generator. -/
  edits : S → ClaimId → Option (Gen (List TextOp)) := fun _ _ => none
  /-- The smallest window the app supports in a state; `none` means the view's preferred size. -/
  minSize : S → Option Size := fun _ => none
  /-- Moves that have no control on purpose (keyboard-only), exempt from presence. -/
  noControl : List ClaimId := []
  /-- The frame-time budget for one step (update, view, layout), in nanoseconds. -/
  budgetNs : Option Nat := none

instance {S : Type} : Inhabited (Custom S) := ⟨{}⟩

end Cairn.Fuzz

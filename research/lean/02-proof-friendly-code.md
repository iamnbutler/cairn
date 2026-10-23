---
title: "Proof-friendly and fast: recursion on Node, spec/impl pairs, Array/String reasoning, do-loops"
urls:
  - https://lean-lang.org/doc/reference/latest/Definitions/Recursive-Definitions/
  - https://lean-lang.org/doc/reference/latest/The-Type-System/Inductive-Types/
  - https://github.com/leanprover/lean4/pull/10714
  - https://github.com/leanprover/lean4/pull/7965
date: 2026-10-23
relevance: 5
---

# Proof-friendly and fast code in Lean 4.35

Everything marked "observed" was run on Lean 4.35.0 in `/tmp/cl/` (`Nest*.lean`, `Loop*.lean`,
`Str.lean`, `Part.lean`). Source paths are relative to the toolchain's `src/lean/`.

## 1. Recursion over `Node` (nested inductive: `children : List Node`)

Our `Node` and `Laid` (`lean/Cairn/UI/Node.lean`) are nested inductives. Four facts, all
observed:

**a. `cs.map f` makes the definition well-founded, not structural.**

```lean
def N.size : N → Nat
  | .box _ cs => 1 + (cs.map N.size).sum
  | .leaf _ => 1
```

`#print N.size` shows `@[irreducible] def N.size … := N.size._proof_1.fix …
(List.map (fun x_1 => match x_1 with | ⟨x_2, h⟩ => x x_2 ⋯) cs.attach)`: Lean auto-attached
the membership proof and used `WellFounded.fix`. Adding `termination_by structural n => n`
fails: "failed to infer structural recursion: … unexpected occurrence of recursive application".
Since 4.25 (#10714, see the digest) well-founded definitions are irreducible, so `rfl`,
`decide` and `simp` without the equation lemmas won't compute them. (`decide +kernel` and
`cbv` still can when the measure is `Nat`; note 01.)

**b. A mutual pair or a `where go` over `List` is structural.**

```lean
def N.size2 : N → Nat
  | .box _ cs => 1 + go cs
  | .leaf _ => 1
where go : List N → Nat
  | [] => 0
  | c :: cs => c.size2 + go cs
```

`#print`: `fun x => x.brecOn N.size2._f N.size2.go._f`. Structural, reducible: `example :
(N.box 3 [.leaf "ab", .box 1 []]).width = 6 := rfl` and `by decide` both go through.
Lean generates `N.width.induct` with two motives (one for `N`, one for `List N`).

**c. `induction n` does not work on a nested inductive.** "The `induction` tactic does not
support the type `Node` because it is a nested inductive type". Options that work: write the
theorem as a mutual structural recursion (observed: `N.width_ge`/`widths_ge` as a `mutual`
block of theorems proved by pattern matching), use the generated `f.induct` /
`fun_induction`, or `N.rec` with both motives.

**d. `deriving DecidableEq` fails on nested inductives.** "None of the deriving handlers for
class `DecidableEq` applied to `M`", even for `inductive M | box (w : Nat) (children : List M)
| leaf (n : Nat)`. Source: `Lean/Elab/Deriving/DecEq.lean:211-212`:
`if indVal.isNested then return false -- nested inductive types are not supported yet`.
`deriving BEq, Repr` work. A hand-written mutual `decEq`/`decEqList` (about 20 lines) works and
`decide` reduces through it (observed, `Nest3.lean`). The digest adds that `deriving LawfulBEq`
also "Does not support mutual or nested inductives" (4.25 #10351).

Counter-evidence: Cedar (note 04) uses `xs.attach.mapM` on nested data and lives with
well-founded recursion, plus one `mapM₁_eq_mapM` lemma to erase `attach` in proofs. That works
if you never need `decide`/`rfl` on concrete trees. We do want `#guard`/`decide` on concrete
views and layouts, so structural is the better default for us.

## 2. Pairing a spec with a fast implementation

**`@[csimp]`: proved replacement.** Observed:

```lean
def sumSpec : List Nat → Nat | [] => 0 | x :: xs => x + sumSpec xs
def sumFast (xs : List Nat) : Nat := go xs 0
where go : List Nat → Nat → Nat | [], acc => acc | x :: xs, acc => go xs (acc + x)
@[csimp] theorem sumSpec_eq_fast : @sumSpec = @sumFast := by funext xs; simp [sumFast, sumFast_go]
-- axioms: [propext, Quot.sound]
```

The compiler then calls `sumFast` wherever `sumSpec` appears; theorems keep talking about
`sumSpec`. Core uses this pattern itself (e.g. `List.append` / `appendTR`).

**`@[implemented_by]`: unchecked.** Observed:

```lean
def wrongImpl (n : Nat) : Nat := n + 1
@[implemented_by wrongImpl] def lies (n : Nat) : Nat := n
theorem lies_eq (n : Nat) : lies n = n := rfl   -- proves
#eval lies 5                                    -- 6
```

and `#print axioms` shows nothing. Note 04's agent reproduced the same and found SampCert ships
this pattern. The `decide +native` docstring says the same: native evaluation depends "on the
correctness of the Lean compiler and all definitions with an `@[implemented_by]` attribute"
(`Init/Tactics.lean:1462-1466`). The digest records 4.28 #11774, a real mismatch between
`foldlM` and its unsafe fast variant.

**`partial def`: opaque to proofs.** `#print loop` → `opaque loop : Nat → Nat`; `simp [loop]`
"made no progress", `decide` stuck. Anything a theorem mentions must not be `partial` (our
plan already says this).

## 3. `Array`, `ByteArray`, `String`

- `Array`: rich `@[simp]`/`@[grind]` coverage in `Init/Data/Array/` (~200 grind annotations).
  Observed: `simp` proves `(a.set i v h)[i] = v`, `grind` proves read-over-write at `j ≠ i`.
  Indexing syntax needs a bound proof for `a.set …` results: `(a.set i v h)[i]'(by simpa using h)`.
- `ByteArray`: `Init/Data/ByteArray/Lemmas.lean` exists but has no `@[grind]` annotations.
  Proving encoders over `ByteArray` directly means lemmas about `push`/`append`/`get!` by hand.
  Practical shape: spec as `List UInt8` (or `Array UInt8`), implementation over `ByteArray`,
  one bridge lemma `(enc x).data.toList = encSpec x`.
- `String`: since 4.25 a `String` is a UTF-8-valid byte array; `String.Pos : String → Type` is
  now a *dependent* valid-position type and the raw byte offset is `String.Pos.Raw` (observed via
  `#check`). `"héllo👋".length = 6`, `utf8ByteSize = 10`. Bridge lemmas are `simp`-ready:
  `String.ofList s.toList = s`, `(String.ofList l).toList = l`,
  `(s ++ t).toList = s.toList ++ t.toList`, `(s ++ t).length = s.length + t.length` all by
  `simp`. But `grind` alone failed on an insert-at-scalar-index length lemma because it does not
  know `s.toList.length = s.length` (`String.length_toList`, `Init/Data/String/Length.lean:32`);
  adding that fact and `omega` closes it.

## 4. `Id.run do` loops

Two routes, both observed on `for x in l do acc := acc + x`:

- **By hand:** `simp [mySum, List.forIn_pure_yield_eq_foldl, foldl_add]` turns the loop into a
  `foldl` and closes with a one-line induction lemma. Axioms `[propext, Quot.sound]`.
- **`mvcgen`** (`import Std.Tactic.Do`): `mvcgen invariants · ⇓⟨xs, acc⟩ => ⌜acc =
  xs.prefix.sum⌝ with grind` proves it; `invariants?` suggests a starting invariant. In 4.35 it
  prints "syntax 'Lean.Parser.Tactic.mvcgen' has been deprecated: use `vcgen` instead".
  Its replacement `vcgen` is gated by `set_option experimental.vcgen true`
  (`Lean/Elab/Tactic/VCGen/Frontend.lean:26,395-397`) and the same proof did not port directly
  (`with` "expects a `grind`-mode discharging step"; then "Unknown constant
  `Std.WP.Triple.intro`"). The verification framework is mid-migration.

## For Cairn

- **B (layout), C (runtime), E (frame):** recursion over `Node`/`Laid` as a structural pair
  (`f` + `where go : List Node → _`, or `mutual`), never `children.map f`. Prove properties as
  mutual structural theorems or with `f.induct`; don't reach for `induction n`.
- **Contracts (`Node.lean`):** `Node`/`Laid` can't derive `DecidableEq`. If any theorem or
  `decide` needs it (e.g. "frame equals expected frame"), hand-write the mutual instance once in
  the contract file. `BEq` is derived, but there is no `LawfulBEq`, so `==` facts don't turn into
  `=` facts for free.
- **E (encoding):** spec over `List UInt8`, implementation over `ByteArray` with a bridge lemma,
  or `@[csimp]` from spec to fast version. Never `@[implemented_by]` in proved code; list any
  `implemented_by`/`extern`/`unsafe` in `docs/trusted.md` (audit could grep for them).
- **D (text):** keep the field model as `List Char` / `Array Char` with scalar indices (matches
  `FieldView`) and convert to `String` at the edges, using the `simp` bridge lemmas above.
  Don't model carets as `String.Pos`: it is dependent on the string and byte-based.
- **All:** for loops, prefer structural recursion or `foldl` in definitions that theorems talk
  about; if you write `Id.run do … for …`, prove it via `forIn_…_eq_foldl` simp lemmas, not
  `vcgen`, until the framework settles.

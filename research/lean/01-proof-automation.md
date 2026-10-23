---
title: "Proof automation in Lean 4.35: what each tactic is for, and which axioms it costs"
urls:
  - https://lean-lang.org/doc/reference/latest/releases/
  - https://lean-lang.org/doc/reference/latest/The--grind--tactic/
  - https://github.com/leanprover/lean4/pull/14953
  - https://github.com/leanprover/lean4/pull/14990
date: 2026-10-23
relevance: 5
---

# Proof automation in Lean 4.35

Source paths below are relative to
`~/.elan/toolchains/leanprover--lean4---v4.35.0/src/lean/`. The release-note history is in
[raw/release-notes-4.20-4.35.md](raw/release-notes-4.20-4.35.md). All "observed" results were
run with `lean` 4.35.0 (commit eb6cafb) on scratch files in `/tmp/cl/`.

## What I ran and saw (axioms)

| Tactic | Goal | `#print axioms` |
|---|---|---|
| `omega` | `a < b → a + 1 ≤ b` | `[propext, Quot.sound]` |
| `decide` | `(List.range 50).sum = 1225` | none |
| `decide +kernel` | `(List.range 500).sum = 124750` | none |
| `decide_cbv`, `cbv` | `digits 1234 = [1,2,3,4]` (well-founded `digits`) | `[propext, Quot.sound]` |
| `grind` | `xs ≠ [] → xs.length > 0`; `Array.set` read-over-write; rect containment transitivity | `[propext, Classical.choice, Quot.sound]` |
| `simp` | `(a.set i v h)[i] = v` | `[propext]` |
| `bv_omega` | `x < 10 → x + 1 < 11` on `BitVec 8` | `[propext, Quot.sound]` |
| `bv_decide` | `x &&& y = y &&& x` (16-bit) | `[propext, Classical.choice, Quot.sound, t_bv._native.bv_decide.ax_1_5]` |
| `bv_decide` | `x + x = x <<< 1` (8-bit) | `[propext, Classical.choice, Quot.sound]` (closed by preprocessing, no SAT call) |
| `native_decide` | `(List.range 500).sum = 124750` | `[t_native._native.native_decide.ax_1_1]` |

**Correction to our working assumption.** In 4.35, `native_decide` and `bv_decide` do *not*
add `Lean.ofReduceBool`; that constant is gone. Each use adds a *fresh, per-proof axiom*:

```
axiom t_native._native.native_decide.ax_1_1 : decide ((List.range 500).sum = 124750) = true
axiom t_bv._native.bv_decide.ax_1_5 :
  Std.Tactic.BVDecide.Reflect.verifyBVExpr t_bv._expr_def_1_1 t_bv._cert_def_1_1 = true
```

The mechanism is `Lean.Meta.nativeEqTrue` (`Lean/Meta/Native.lean:31-95`): "will compile and
run that value, check that it evaluates to `true`, and if so, will add an axiom asserting
`e = true` and return that axiom" (`:31-34`); the axiom name is
``mkAuxDeclName <| `_native ++ tacticName ++ `ax`` (`:75`). Release notes: 4.29 #12217, 4.35
#14953. So an audit that greps for `ofReduceBool` would pass a `bv_decide` proof. Ours
whitelists the three standard axioms, which is the right design; keep it that way.

`bv_decide` has no kernel-checked mode: `bv_decide +kernel` fails with "Invalid configuration
option `kernel` for `Lean.Elab.Tactic.BVDecide.BVDecideConfig`" (observed; the config fields
are in `Std/Tactic/BVDecide/Syntax.lean:40-95`). The docstring says so:
"Note: `bv_decide` trusts the correctness of the code generator and adds a axioms asserting its
result." (`Init/Tactics.lean:1960`). `bv_check "file.lrat"` also goes through the same path.

## `lake check`: a second audit, already in the toolchain

New in 4.35 (#14990). `lake help check`: "Builds the default build targets, exports them, and
replays the result through the kernel, erroring on any use of non-standard axioms." The sandbox
needs `bwrap` (Linux); on macOS `--inadvisably-no-sandbox` works. Observed on a two-theorem
scratch package:

```
error: Axiom 'bad._native.native_decide.ax_1_1' is not permitted; it is used by 'bad'
Lean default kernel accepts the solution
Uses axioms: Classical.choice, propext, Quot.sound, bad._native.native_decide.ax_1_1
```

`--paranoid` also runs the bundled independent checkers (`lean4lean`, `nanoda`, `con-leche`,
`con-ron`, `leanchecker-paranoid`; all present in the toolchain's `bin/`).

## Each tactic, what it is good at, and where it stops

**`omega`** (`Init/Tactics.lean:1542-1572`): linear arithmetic over `Nat`/`Int` with `x / k`,
`x % k` for literal `k`, natural subtraction split, `min`/`max`. "It is not yet a full decision
procedure (no "dark" or "grey" shadows)". No multiplication of two variables. Our integer
geometry (`Rect` containment, centre-in-rect, `x + w/2`) is exactly its fragment: observed
`centre_in` and `inside_trans` closed by `unfold; omega`.

**`grind`** (`Init/Grind/Tactics.lean`, docs `:1-283`): congruence closure + E-matching on
`@[grind]` lemmas + case splits + built-in solvers: `lia` (linear integer arithmetic, "complete
for LIA", `:160-200`), `ring` (commutative rings, including `UInt8` as char-256), linarith
over ordered modules. Released as stable in 4.22. Core ships ~200 `@[grind …]` annotations in
`Init/Data/Array/` and ~214 in `Init/Data/List/`, but only 2 in `Init/Data/String/` and none in
`Init/Data/ByteArray/` (counted with grep). So `grind` is strong on `List`/`Array`, weak on
`String`/`ByteArray`. `grind?` prints an equivalent `grind only [...]` call (`:290`) which is
the stable form to commit. `register_grind_attr` (`Lean/Meta/Tactic/Grind/RegisterCommand.lean`)
lets a project keep its own lemma set (e.g. `@[layout_grind]`), checked with `#grind_lint`.
Failure output is a large "Goal diagnostics" dump (observed on a bit-level round trip, below):
useful for humans, noisy for agents.

**`simp`** + **simprocs** (`Init/Simproc.lean:92`): rewriting with `@[simp]` lemmas and
user procedures. Unbounded `simp` is the main source of proof breakage across Lean upgrades
(4.29/4.31/4.33 transparency changes in the digest: "simp won't unfold them either"). Use
`simp only [...]` (from `simp?`) in committed proofs. Note `linter.unusedSimpArgs` now warns
on unused simp arguments (observed).

**`decide`** (`Init/Tactics.lean:1445-1515`): evaluates a `Decidable` instance by reduction;
no axioms. Limitations quoted: "`Decidable` instances defined by well-founded recursion might
not work because evaluating them requires reducing proofs. Reduction can also get stuck on
`Decidable` instances with `Eq.rec` terms ... use `decidable_of_iff` instead."
Observed:
- `decide` *fails* on a well-founded `digits` ("reduction got stuck at match digits 1234");
  `decide +kernel` *succeeds* (its measure is `Nat`; cf. 4.27 #7965 in the digest).
- `decide` and `decide_cbv` hit `maxRecDepth` on a non-tail structural recursion of depth
  1,000; `decide +kernel` handled depth 10,000 (under 0.1 s) and 100,000 (3.0 s kernel time).
  `(List.range 100000).all p` by `decide +kernel`: 5.1 s.
- No `Decidable (∀ x : UInt8, P x)` instance in core (no `Fintype`): "failed to synthesize".
  Enumerate explicitly (`List.finRange`, a hand-written `all`) and prove the bridge lemma.
- Exhaustive check over a small finite record (`Bool × Fin 4 × Fin 3`, 24 states) by
  `decide` and `decide +kernel`: instant.

**`decide_cbv` / `cbv`** (new; `Init/Tactics.lean:2521-2561`, `Lean/Meta/Tactic/Cbv/`):
"unfolding is propositional, so `cbv` also works with functions defined via well-founded
recursion or partial fixpoints ... The proofs produced by `cbv` only use the three standard
axioms. In particular, they do not require trust in the correctness of the code generator."
Observed: works on the well-founded `digits` where `decide` fails, but recursion depth is
limited like `decide`.

**`bv_decide`**: SAT (CaDiCaL, bundled as `bin/cadical`) on `QF_BV` goals, with an LRAT
certificate checked by compiled code; per-proof native axiom (above). **Not allowed for us.**
`bv_omega` (simp to `Nat` then `omega`) is axiom-clean.

## Byte round trips: the encoding matters more than the tactic

Observed on `u32` little-endian encode/decode (`/tmp/cl/Enc.lean`, `Enc2.lean`):

- Bit-op formulation (`x >>> 8`, `.toUInt8`, `<<<`, `|||`): `bv_decide` proves it instantly but
  adds a native axiom. Without it, `toBitVec_inj` + `simp` + `bv_omega` failed, and the
  per-bit `eq_of_getElem_eq` + `simp` + `grind` route failed after a long diagnostic.
- Arithmetic formulation (`n % 256`, `n / 256 % 256`, …, decode as
  `a + 256*b + 65536*c + 16777216*d`): closes with

  ```lean
  theorem rt32a (x : UInt32) : get32a (put32a x) = some x := by
    simp only [put32a, get32a, Option.some.injEq]
    have hx := x.toNat_lt
    apply UInt32.toNat_inj.mp
    simp [UInt32.toNat_ofNat]
    omega
  ```

  `[propext, Quot.sound]`. 4.35 #14727 also routes `UIntN`/`Fin`/`BitVec` through `grind`'s
  `Nat`/`Int` translation, which points the same way.

## Counter-evidence and caveats

- Timings here were taken with a machine load of 17–20 (other agents building); `import`
  alone was reported as 12–52 s wall with under 0.5 s CPU. Treat the kernel-time numbers from
  `--profile` ("type checking took …") as the meaningful ones.
- `grind` instantiation is heuristic; a `grind` proof can start failing (or slow) when a
  dependency adds `@[grind]` lemmas. `grind only [...]` pins it.
- `decide +kernel` "ignores transparency and can unfold everything" (`Init/Tactics.lean:1459`):
  that is also why it can be slow in surprising ways on big terms. Prefer `Nat`-measured
  recursion, tail recursion and small enumerations.

## For Cairn

- **All (audit):** keep the whitelist audit; add `lake check --inadvisably-no-sandbox` to
  `make check` (sandboxed in Linux CI) as a kernel-replay second opinion. Don't search for
  `ofReduceBool`; it no longer exists.
- **E (encoding):** specify encoders arithmetically (`toNat`, `/`, `%`, `*`) and prove round
  trips with `omega`; if the fast path uses shifts and masks, prove it equal to the arithmetic
  spec once per primitive (`put16`, `put32`) and reuse. No `bv_decide`.
- **B (layout), C (runtime):** geometry on `Int`/`Nat` with linear constraints is `omega`'s
  home ground. Keep layout arithmetic linear in the variables a theorem quantifies over
  (multiplying two quantified sizes leaves `omega`; `grind`'s `ring` may help, untested here).
- **A (claims), I (TodoMVC):** for "every flow has a witness" and small invariant checks over
  enumerated states, `decide +kernel` is the axiom-free workhorse (100k-step checks in seconds).
  Write `Decidable` instances with `decidable_of_iff`; don't build them with `simp`/`rw`.
- **D (text):** expect to write `String`/`ByteArray` lemmas yourself; `grind` has almost no
  annotations there. Model text as `Array Char`/`List Char` in proofs (see note 02).
- **All:** commit `grind only [...]` / `simp only [...]` forms, not bare `grind`/`simp`.

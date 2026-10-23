---
title: Lean release notes v4.20.0 – v4.35.0, digested for Cairn
urls:
  - https://lean-lang.org/doc/reference/latest/releases/
  - https://github.com/leanprover/reference-manual/tree/main/Manual/Releases (source files v4_20_0.lean … v4_35_0.lean)
date: 2026-10-23
relevance: 4
---

# Lean release notes v4.20 – v4.35 (Cairn digest)

Source: the reference manual's release-note sources, `Manual/Releases/v4_NN_0.lean` in
`leanprover/reference-manual` (fetched 2026-10-23; the GitHub release bodies only link there).
Only items that bear on Cairn are kept: proof automation, recursion and induction, `String` /
`ByteArray` / `Array`, verification of `do` code, the compiler and runtime, FFI, the module system,
metaprogramming hooks, deriving, and axiom checking. Quotes are verbatim (lightly trimmed with
"…"); PR links go to `leanprover/lean4`. Workstream tags: **A** claims DSL, **B** layout, **C**
runtime, **D** text, **E** encoding, **all** = every workstream / `make check`.

Not covered here: v4.36 (exists upstream, after our pin).

## Cross-version threads (read this first)

| Thread | Versions | What changed | Cairn |
|---|---|---|---|
| Native computation and axioms | 4.29, 4.35 | `native_decide`/`bv_decide` now add **one auto-generated axiom per computation** (name contains `._native.`); `Lean.ofReduceBool` and `Lean.trustCompiler` are **removed** in 4.35 | all: audit must reject any axiom outside the standard three, not grep for `ofReduceBool` |
| Built-in axiom checking | 4.28, 4.35 | `leanchecker` ships with elan (4.28); `lake check` replays the build through the kernel and fails on non-standard axioms; `--paranoid` adds 4 independent kernels (4.35) | all |
| `grind` | 4.22 → 4.35 | Released in 4.22; interactive mode, `grind_pattern` guards, `#grind_lint`, `+locals`, homomorphisms to `Nat`/`Int` for `UIntN`/`Fin`/`BitVec` (4.35) | B, C, D, E |
| `cutsat` → `lia` | 4.22, 4.26–27, 4.33 | `grind`'s integer solver "supersed[es] `omega`, with model construction"; renamed `lia` (4.27); own `@[lia]` lemma set (4.33) | B, C |
| `String` rework | 4.25 → 4.31 | `String` is now a UTF-8-valid `ByteArray`; `String.Pos` is dependently typed (valid positions), `String.Slice` replaces `Substring`; old raw positions are `String.Pos.Raw` | D, E |
| Verifying `Id.run do` | 4.22 → 4.35 | `Std.Do` + `mvcgen` (4.22) → `mvcgen'` (4.31) → `vcgen` + `def` contracts `requires`/`ensures`/`invariant` (4.34–4.35, experimental) | B, C, D, E |
| New compiler (LCNF) | 4.22, 4.30 | Replaced old compiler (4.22); C emission and reset/reuse ported to LCNF (4.30); user `@&` borrow annotations honoured (4.30) | C, E |
| FFI ABI | 4.26, 4.30, 4.33, 4.34 | `IO.RealWorld` erased (4.26); `@[export]` + `@&` is an error (4.30); initializers call `lean_initialize*` themselves (4.34) | G (host), E |
| Linearity debugging | 4.35 | `markLinear` + `LEAN_ABORT_ON_NONLINEAR` detect accidental copies of `Array`/`ByteArray`/`String` | C, E, bench |
| Transparency discipline | 4.29, 4.31, 4.33, 4.35 | `isDefEq` no longer bumps transparency on implicit args; `@[implicit_reducible]`; `simp` stops seeing through non-reducible defs | all proofs |
| Well-founded recursion | 4.25, 4.27 | WF defs are irreducible (reducible WF removed, 4.25), **except** `Nat`-measured ones, which now reduce via fuel (4.27) | B, D |
| Module system | 4.21 → 4.27 | `module` keyword, private-by-default, `@[expose]`, `public`/`meta`/`all` imports; stable in 4.27 | A |

---

## v4.20.0 (2025-06-02)

- **Functional induction, unfolding variant.** "[#8088](https://github.com/leanprover/lean4/pull/8088) adds the “unfolding” variant of the functional induction and functional cases principles, under the name `foo.induct_unfolding` resp. `foo.fun_cases_unfolding`. These theorems combine induction over the structure of a recursive function with the unfolding of that function, and should be more reliable, easier to use and more efficient than just case-splitting and then rewriting with equational theorems." — B, D
- "[#8094](https://github.com/leanprover/lean4/pull/8094) fixes the generation of functional induction principles for functions with nested nested well-founded recursion and late fixed parameters." — B
- **(Co)inductive predicates by fixpoint.** "[#8097](https://github.com/leanprover/lean4/pull/8097) adds support for inductive and coinductive predicates defined using lattice theoretic structures on `Prop`. … `greatest_fixpoint` or `least_fixpoint` termination clauses…" — C (reachability), A (flows)
- **First `grind` annotations for containers.** "[#8136](https://github.com/leanprover/lean4/pull/8136) adds an initial set of `@[grind]` annotations for `List`/`Array`/`Vector`…"
- Extensional maps: "[#8004](https://github.com/leanprover/lean4/pull/8004) adds extensional hash maps and hash sets under the names `Std.ExtDHashMap`, `Std.ExtHashMap` and `Std.ExtHashSet`. … easier to use in proofs. This however makes it also impossible to regularly iterate over its entries." — A (registry), I
- Env extensions: "[#7914](https://github.com/leanprover/lean4/pull/7914) adds a function hook `PersistentEnvExtension.saveEntriesFn` that can be used to store server-only metadata such as position information and docstrings that should not affect (re)builds." — A
- Module system groundwork: "[#8090](https://github.com/leanprover/lean4/pull/8090) adjusts the experimental module system to elide theorem bodies (i.e. proofs) from being imported into other modules." — A
- FFI linking: "[#7967](https://github.com/leanprover/lean4/pull/7967) … **Breaking change:** The Lean library directory is no longer part of `getLeanLinkSharedFlags`. FFI users should provide this option separately when linking to Lean…" — G
- New compiler prep: "[#8127](https://github.com/leanprover/lean4/pull/8127) adds support for borrowed params in the new compiler…"; "[#8023](https://github.com/leanprover/lean4/pull/8023) fixes the IR expand_reset_reuse pass to correctly handle duplicate projections from the same base/index." — C
- "[#8012](https://github.com/leanprover/lean4/pull/8012) adds the option `debug.terminalTacticsAsSorry`. When enabled, terminal tactics such as `grind` and `omega` are replaced with `sorry`." (debugging only; would trip our audit, which is the point)

## v4.21.0 (2025-06-30)

- "[#8104](https://github.com/leanprover/lean4/pull/8104) makes `fun_induction` and `fun_cases` (try to) unfold the function application of interest in the goal." — B, D
- "[#8171](https://github.com/leanprover/lean4/pull/8171) omits cases from functional induction/cases principles that are implemented `by contradiction` … fewer goals to prove after using functional induction."
- **`Id` simp set.** "[#7352](https://github.com/leanprover/lean4/pull/7352) reworks the `simp` set around the `Id` monad, to not elide or unfold `pure` and `Id.run`" — relevant to proving `Id.run do` loops by `simp`. B, C, E
- "[#8313](https://github.com/leanprover/lean4/pull/8313) changes the definition of `Vector` so it no longer extends `Array`."
- Iterators: "[#8358](https://github.com/leanprover/lean4/pull/8358) introduces a very minimal version of the new iterator library … All consumers also come in a partial variant that can be used without any proofs."
- "[#8499](https://github.com/leanprover/lean4/pull/8499) changes the definition of `Array.ofFn.go` to use recursion on `Nat` (rather than well-founded recursion)."
- Module system: "[#8221](https://github.com/leanprover/lean4/pull/8221) adjusts the experimental module system to not export the bodies of `def`s unless opted out by the new attribute `@[expose]`…" — A
- `grind` containers: "[#8218](https://github.com/leanprover/lean4/pull/8218) continues adding `@[grind]` attributes for List/Array/Vector…"; "[#8246](https://github.com/leanprover/lean4/pull/8246) add `@[grind]` annotations for HashMap…"; "[#8446](https://github.com/leanprover/lean4/pull/8446) … `TreeMap`"; "[#8482](https://github.com/leanprover/lean4/pull/8482) … `List.Pairwise` and `List.Nodup`." (Nodup matters for "item ids are unique", I)
- "[#8576](https://github.com/leanprover/lean4/pull/8576) sets `ring := true` by default in `grind`."
- Soundness note: "[#8559]/[#8560] fix an adversarial soundness attack … exploits the fact that `assert!` no longer aborts execution…"

## v4.22.0 (2025-08-14)

- **`grind` released.** "Lean now includes a new SMT-style tactic `grind`, along with annotations for the Lean standard library. `grind` ships theory-specific solvers, including cutsat (superseding `omega`, with model construction) and a new Gröbner basis solver." — B, C, D, E
- **New compiler.** "The old compiler has been replaced by the new compiler ([#8577](https://github.com/leanprover/lean4/pull/8577))!" — C, E (re-measure perf; spike numbers already on new compiler)
- **`Std.Do` / `mvcgen`.** "[#8995](https://github.com/leanprover/lean4/pull/8995) introduces a Hoare logic for monadic programs in `Std.Do.Triple`, and assorted tactics: `mspec` … `mvcgen` to turn a Hoare triple proof obligation `⦃P⦄ prog ⦃Q⦄` into pure verification conditions." (experimental) — B, E
- **Module system** "available for experimentation" (enabled by `module` before imports); "[#9044](https://github.com/leanprover/lean4/pull/9044) … make `private` the default visibility modifier in `module`s, introducing `public` as a new modifier…" — A
- `let`→`have`: "[#8373](https://github.com/leanprover/lean4/pull/8373) enables transforming nondependent `let`s into `have`s so `simp` works better without zeta reduction." — proofs about `let`-heavy layout code
- `simp` hygiene: "[#8901](https://github.com/leanprover/lean4/pull/8901) adds a linter (`linter.unusedSimpArgs`)…"; "[#8865](https://github.com/leanprover/lean4/pull/8865) allows `simp` to recognize and warn about simp lemmas that are likely looping…"; "[#8419](https://github.com/leanprover/lean4/pull/8419) introduces an explicit `defeq` attribute to mark theorems that can be used by `dsimp`."
- "[#8723](https://github.com/leanprover/lean4/pull/8723) implements a `finally` section following a (potentially empty) `where` block … for discharging multiple proof obligations in the definition body" (e.g. array-index side goals in a hot loop). — B, E
- Ranges/slices: "[#8784](https://github.com/leanprover/lean4/pull/8784) introduces new syntax for ranges: `1...*`, `1...=3`, `1...<3`…"; "[#8947](https://github.com/leanprover/lean4/pull/8947) extends this syntax to slices, allowing expressions like `xs[*...end]`." — E (decoder)
- "[#9075](https://github.com/leanprover/lean4/pull/9075) adds `BEq` instances for `ByteArray` and `FloatArray` (also a `DecidableEq` instance for `ByteArray`)." — E
- `grind` containers: "[#8719]/[#8747]/[#8748]/[#8749]/[#8750]/[#8805] … grind annotations for List/Array/Vector" (`erase*`, `finRange`, `mapIdx`, `ofFn`, `zipWith`, …).
- `grind` and module system: "[#8882](https://github.com/leanprover/lean4/pull/8882) adds `@[expose]` annotations to terms that appear in `grind` proof certificates, so `grind` can be used in the module system."
- FFI: "[#8636](https://github.com/leanprover/lean4/pull/8636) adds a function called `lean_setup_libuv` that initializes required LIBUV components. It needs to be outside of `lean_initialize_runtime_module` because it requires `argv` and `argc`…" — G (only if we use libuv-backed IO from the embedded lib)

## v4.23.0 (2025-09-15)

- "[#9800](https://github.com/leanprover/lean4/pull/9800) improves the delta deriving handler … **Breaking change**: the derived instance's name uses the `instance` command's name generator…"
- "[#9818](https://github.com/leanprover/lean4/pull/9818) fixes a bug where the `DecidableEq` deriving handler did not take universe levels into account for enumerations…"
- "[#9646](https://github.com/leanprover/lean4/pull/9646) uses a more simple approach to proving the unfolding theorem for a function defined by well-founded recursion…" — B
- Module system: "[#8666](https://github.com/leanprover/lean4/pull/8666) adjusts the experimental module system to not import the IR of non-`meta` declarations…"; "[#9716](https://github.com/leanprover/lean4/pull/9716) … syntax validation of import keywords (`public`, `meta`, and `all`)…" — A (the `move` command's elaborator must be `meta`)
- Compiler: "[#9864](https://github.com/leanprover/lean4/pull/9864) adds new variants of `Array.getInternal` and `Array.get!Internal` that return their argument borrowed, i.e. without a reference count increment." — C, B
- "[#8842](https://github.com/leanprover/lean4/pull/8842) fixes the bug that `collectAxioms` didn't collect axioms referenced by other axioms. One of the results of this bug is that axioms collected from a theorem proved by `native_decide` may not include `Lean.trustCompiler`." — **all**: an audit on an older toolchain could have missed `trustCompiler`.
- "[#9729](https://github.com/leanprover/lean4/pull/9729) introduces a canonical way to endow a type with an order structure…" (`IsLinearOrder` on List/Array/Vector lemmas)

## v4.24.0 (2025-10-14)

- "**more efficient constructions of `DecidableEq` instances and `noConfusion`** ([#10152](https://github.com/leanprover/lean4/pull/10152) and [#10300](https://github.com/leanprover/lean4/pull/10300))" — big enums (`Role`, `Msg`) elaborate faster.
- "[#10271](https://github.com/leanprover/lean4/pull/10271) changes the naming of the internal functions in deriving instances like BEq to use accessible names. This is necessary to reasonably easily prove things about these functions."
- "[#10274](https://github.com/leanprover/lean4/pull/10274) changes … the linear `DecidableEq` implementation to use `match decEq` … Otherwise, the “smart unfolding” machinery will not let `rfl` decide that different constructors are different."
- **`mvcgen` invariants syntax.** "[#9927](https://github.com/leanprover/lean4/pull/9927) implements extended `induction`-inspired syntax for `mvcgen`, allowing optional `invariants` and `with` sections." Example in notes: `nodup` over `Id.run do … for x in l do …` proved with `mvcgen invariants · Invariant.withEarlyReturn … with grind`. — B, C, E
- **`grind` AC solver** "[#10105], [#10146]… associative, commutative, idempotent, and/or unital operations" (e.g. `max a (max b c) = …` by `grind only`). — B (max/min in layout)
- "[#9995](https://github.com/leanprover/lean4/pull/9995) almost completely rewrites the inductive predicate recursion algorithm…" (structural recursion over inductive predicates)
- Deriving under modules: "[#10060](https://github.com/leanprover/lean4/pull/10060) … handlers should not expose their implementation unless either the deriving item or a surrounding section is marked with `@[expose]`."
- `partial_fixpoint`: "[#10230](https://github.com/leanprover/lean4/pull/10230) adds `MonoBind` for more monad transformers. This allows using `partial_fixpoint` for more complicated monads based on `Option` and `EIO`."

## v4.25.0 (2025-11-14)

- **Reducible WF recursion removed.** "[#10714](https://github.com/leanprover/lean4/pull/10714) removes support for reducible well-founded recursion, a Breaking Change. Using `@[semireducible]` on a definition by well-founded recursion prints a warning that this is no longer effective." — B, D: WF defs do not compute in `decide`/`rfl` (see 4.27 for the `Nat`-measure exception).
- **`String` overhaul.** "[#10304](https://github.com/leanprover/lean4/pull/10304) redefines `String` to be the type of byte arrays `b` for which `b.IsValidUtf8`."; "[#10457](https://github.com/leanprover/lean4/pull/10457) introduces safe alternatives to `String.Pos` and `Substring` that can only represent valid positions/slices … `String.ValidPos` … `String.Slice`…"; "[#10624](https://github.com/leanprover/lean4/pull/10624) renames `String.Pos` to `String.Pos.Raw`."; "[#10713](https://github.com/leanprover/lean4/pull/10713) … The `HAdd` and `HSub` instances for `String.Pos.Raw` are have been removed."; "[#10634](https://github.com/leanprover/lean4/pull/10634) defines `ByteArray.validateUTF8`, uses it to show that `ByteArray.IsValidUtf8` is decidable…" — D, E
- **Spec theorems for instances.** "[#10302](https://github.com/leanprover/lean4/pull/10302) introduces the `@[method_specs]` attribute…"; "[#10346](https://github.com/leanprover/lean4/pull/10346) lets `deriving BEq` and `deriving Ord` use `@[method_specs]` … when applicable (i.e. when not using `partial`)."; "[#10351](https://github.com/leanprover/lean4/pull/10351) adds the ability to do `deriving ReflBEq, LawfulBEq` … **Does not support mutual or nested inductives.**" — Our `Node` (nested via `List Node`) cannot get a derived `LawfulBEq`; use `DecidableEq` or prove by hand.
- "[#10394](https://github.com/leanprover/lean4/pull/10394) adds the `reduceBEq` and `reduceOrd` simprocs…"
- Linear deriving: "[#10268](https://github.com/leanprover/lean4/pull/10268) … `DerivingBEq` based on comparing `.ctorIdx` … to avoid the quadratic overhead…" (threshold option `deriving.beq.linear_construction_threshold`, default 10).
- **Coinductive predicates.** "[#10333](https://github.com/leanprover/lean4/pull/10333) introduces a `coinductive` keyword…" — C (liveness-style claims), A
- **`grind` interactive mode** (`grind => …`, `finish?` emits a reproducible script with stable anchors) [#10607], [#10837]; **`grind` injective functions** `@[grind inj]` [#10445]; **`grind order`** [#10562]; **new pattern inference heuristic** [#10422] (`[grind =]`, `[grind →]`, `[grind!]`, `[grind?]`).
- **`mvcgen invariants?`** "[#10456](https://github.com/leanprover/lean4/pull/10456) and [#10566](https://github.com/leanprover/lean4/pull/10566) implement `mvcgen invariants?` to suggest concrete invariants…"
- "[#10780](https://github.com/leanprover/lean4/pull/10780) improves the error message when `decide +kernel` fails in the kernel, but not the elaborator."
- "[#10631](https://github.com/leanprover/lean4/pull/10631) … `decide` now works with `Int*` operations."
- Module porting: "[#10807](https://github.com/leanprover/lean4/pull/10807) introduces the `backward.privateInPublic` option…"
- Ranges: "[#10319](https://github.com/leanprover/lean4/pull/10319) "monomorphizes" … `Std.PRange` … nine distinct structures `Std.Rcc`, `Std.Rco`…"

## v4.26.0 (2025-12-13)

- **FFI: `IO.RealWorld` erased.** "[#10625](https://github.com/leanprover/lean4/pull/10625) implements zero cost `BaseIO` by erasing the `IO.RealWorld` parameter from argument lists and structures. This is a **major breaking change for FFI**." — G: explains "module initializers take no world argument" in `docs/spike-boundary.md`; any `IO` export also lost its world arg.
- **`grind_pattern` constraints.** "[#11189](https://github.com/leanprover/lean4/pull/11189) implements `grind_pattern` constraints. They are useful for controlling theorem instantiation…" (`where as =/= #[]`); **`#grind_lint`** "[#11157](https://github.com/leanprover/lean4/pull/11157) … identify problematic theorems that produce excessive or unbounded instance generation…" — all (anyone tagging Cairn lemmas `@[grind]`)
- "[#10991](https://github.com/leanprover/lean4/pull/10991) renames `cutsat` in configuration options and trace messages to `lia`."
- `String`: "[#10933](https://github.com/leanprover/lean4/pull/10933) adds the basic infrastructure to perform termination proofs about `String.ValidPos` and `String.Slice.Pos`."; "[#11017](https://github.com/leanprover/lean4/pull/11017) establishes `String.ofList` and `String.toList` as the preferred method for converting between strings and lists of characters and deprecates the alternatives `String.mk`, `List.asString` and `String.data`." — D
- `csimp`: "[#11139](https://github.com/leanprover/lean4/pull/11139) … actually replacing the definition. This means we not only get fast runtime behaviour, but take advantage of the special kernel support for `Nat.pow`."
- "[#10982](https://github.com/leanprover/lean4/pull/10982) changes the closure allocator to use the general allocator instead of the small object one."
- `grind +suggestions`, `simp? +suggestions` (library suggestions) [#10920], [#11032].

## v4.27.0 (2026-01-24)

- **Module system stable.** "[#11637](https://github.com/leanprover/lean4/pull/11637) declares the module system as no longer experimental…" — A
- **WF recursion on `Nat` reduces.** "With [#7965](https://github.com/leanprover/lean4/pull/7965), when the termination measure is of type `Nat`, such definitions can be reduced, and an explicit `@[semireducible]` annotation is accepted without the usual warning." Full bullet: "…This fix-point operator use structural recursion on “fuel”, initialized by the given measure, and is thus reasonable to reduce, e.g. in `by decide` proofs." — B, D (prefer `termination_by` with a `Nat` measure)
- **`String` API completed.** "This release completes the revision of the `String` API, including dependently typed `String.Pos`, full API support for `String.Slice`…"; "[#11240](https://github.com/leanprover/lean4/pull/11240) renames `String.ValidPos` to `String.Pos`…"; "[#11180](https://github.com/leanprover/lean4/pull/11180) redefines `String.take` and variants to operate on `String.Slice`…"; "[#11343](https://github.com/leanprover/lean4/pull/11343) renames `String.bytes` to `String.toByteArray`."; "[#11286](https://github.com/leanprover/lean4/pull/11286) … There is no constant-time length function on slices." — D, E
- `grind`: function-valued congruence closure `funCC` [#11323]; `grind_pattern … where guard x ≤ y` [#11428]; arbitrary term params [#11268]; "`BitVec` support in `grind ring` ([#11639]) and `grind lia` ([#11640])"; `grind -reducible` [#11480].
- "[#11330](https://github.com/leanprover/lean4/pull/11330) renames the `cutsat` tactic to `lia`…"
- "[#11620](https://github.com/leanprover/lean4/pull/11620) ports Batteries.WF to Init.WFC for executable well-founded fixpoints. It introduces `csimp` theorems to replace the recursors and non-executable definitions with executable definitions."
- Compiler/FFI: "[#11530](https://github.com/leanprover/lean4/pull/11530) introduces the new `tagged_return` attribute … mark `extern` declarations to be guaranteed to always return `tagged` return values … the compiler does not emit reference counting operations for them."; "[#11383](https://github.com/leanprover/lean4/pull/11383) fixes the compilation of structure projections with unboxed arguments marked `extern`, adding missing `dec` instructions." — F (`cairn_text_offsets` extern), G
- "[#11082](https://github.com/leanprover/lean4/pull/11082) prevents symbol clashes between (non-`@[export]`) definitions from different Lean packages."
- "[#11587](https://github.com/leanprover/lean4/pull/11587) adjusts the new `meta` keyword … not to imply `partial`…"

## v4.28.0 (2026-02-17)

- **Symbolic simulation framework (`SymM`)** "[#12143](https://github.com/leanprover/lean4/pull/12143) defines the core API … enables the implementation of verification condition generators and symbolic execution engines." (base for `vcgen`, `cbv`, `bv_decide` preprocessing later)
- **User-defined grind attributes.** "[#11765](https://github.com/leanprover/lean4/pull/11765) … `register_grind_attr my_grind` … similar to `register_simp_attr` … cannot be used in the same file it is declared." — A/all: a `cairn_grind` set for layout/hit-test lemmas.
- "[#11776](https://github.com/leanprover/lean4/pull/11776) adds the attributes `[grind norm]` and `[grind unfold]`…"
- "[#11946](https://github.com/leanprover/lean4/pull/11946) adds a `+locals` configuration option to the `grind` tactic that automatically adds all definitions from the current file as e-match theorems." / "[#11947]" same for `simp`.
- `bv_decide` solver mode [#11847]; "[#11858](https://github.com/leanprover/lean4/pull/11858) changes `bv_decide`'s heuristic for what kinds of structures to split on…" — E
- `first_par` parallel tactic combinator [#11949].
- **External checker.** "[#11887](https://github.com/leanprover/lean4/pull/11887) makes the external checker lean4checker available as the existing `leanchecker` binary already known to elan…" — all
- "[#11438](https://github.com/leanprover/lean4/pull/11438) renames the namespace `Std.Range` to `Std.Legacy.Range`. Instead of using `Std.Range` and `[a:b]` notation, the new range type `Std.Rco` and its corresponding `a...b` notation should be used." — all loops
- "[#11737](https://github.com/leanprover/lean4/pull/11737) replaces `ffi.md` with links to the corresponding sections of the manual…" (FFI docs live in the reference manual now)
- "[#11774](https://github.com/leanprover/lean4/pull/11774) fixes a mismatch between the behavior of `foldlM` and `foldlMUnsafe` in the three array types. … only exploitable through `native_decide`." — counter-evidence for trusting `implemented_by` pairs.

## v4.29.0 (2026-03-27)

- **One axiom per native computation.** "[#12217](https://github.com/leanprover/lean4/pull/12217) implements RFC #12216: native computation (`native_decide`, `bv_decide`) is represented in the logic as one axiom per computation, asserting the equality that was obtained from the native computation. `#print axiom` will no longer show `Lean.trustCompiler`, but rather the auto-generated names of these axioms (with, for example, `._native.bv_decide.` in the name)." — **all**: `bv_decide` proofs fail our three-axiom audit.
- **Transparency change.** "[#12179](https://github.com/leanprover/lean4/pull/12179) … removing this transparency level bump as the default path." New `@[implicit_reducible]` [#12247]; "`simp` and `dsimp` no longer process typeclass instances" [#12244]. — all
- **Simpler `noncomputable`.** "[#12028](https://github.com/leanprover/lean4/pull/12028) … `noncomputable` is now needed whenever an axiom or another `noncomputable` def is used by a def except … uses of functions marked `@[extern]/@[implemented_by]/@[csimp]` are ignored"
- **Extensible `do` elaborator** [#12459] (opt-in; default in 4.32).
- `mvcgen` local-context specs [#12395]; `grind` higher-order Miller patterns [#12483] (helps `List.foldl`-style lemmas).
- Startup: "[#12082](https://github.com/leanprover/lean4/pull/12082) and [#12044](https://github.com/leanprover/lean4/pull/12044) reduce startup time by storing closed terms directly in the binary, where possible, and initializing the remaining ones lazily…" — G (embedded init time)
- "[#12507](https://github.com/leanprover/lean4/pull/12507) fixes … equational theorem generation fails for structurally recursive definitions using a Box-like wrapper around nested inductives." — B (`Node` with `List Node`)
- "[#12413](https://github.com/leanprover/lean4/pull/12413) ports the IR borrow pass to LCNF."
- String search with verified KMP [#12424]; list/array/vector sum lemmas [#11994].
- "[#12351](https://github.com/leanprover/lean4/pull/12351) extends the `@[csimp]` attribute to be correctly tracked by `lake shake`"

## v4.30.0 (2026-05-26)

- **User borrow annotations.** "[#12830](https://github.com/leanprover/lean4/pull/12830) enables support for respecting user provided borrow annotations. … mark arguments … with `(x : @&Ty)` … Note that in some cases this might not be possible. For example, the compiler prioritizes preserving tail calls over preserving borrow annotations. … `trace.Compiler.inferBorrow`." — C, B, E
- **Export + borrow is an error.** "[#13017](https://github.com/leanprover/lean4/pull/13017) ensures that when a declaration is marked with `@[export]`, the compiler throws an error if any of its arguments are marked as borrowed." Also "[#12952](https://github.com/leanprover/lean4/pull/12952) ensures that when a function is marked `export` its borrow annotations (if present) are always ignored." and "[#12930](https://github.com/leanprover/lean4/pull/12930) … `export` forces all arguments to be passed as owned while `extern` respects borrow annotations." — G (confirms spike finding)
- **LCNF backend complete.** "[#12781](https://github.com/leanprover/lean4/pull/12781) ports the C emission pass from IR to LCNF…"; "[#12665](https://github.com/leanprover/lean4/pull/12665) ports the expand reset/reuse pass from IR to LCNF. In addition it prevents exponential code generation unlike the old one. This results in a ~15% decrease in binary size and slight speedups across the board." — C
- Borrow inference: "[#13064](https://github.com/leanprover/lean4/pull/13064) informs the borrow inference that if an `Array` is borrowed and we index into it, the value we obtain is effectively a borrowed value as well. This helps improve the ABI of operations that recurse on linked structures containing arrays…" — B (tree walks)
- "[#13270](https://github.com/leanprover/lean4/pull/13270) adds `Runtime.hold`, which ensures its argument remains alive until the callsite … useful for unsafe code (such as an FFI)…" — G
- **Stack size.** "[#12971](https://github.com/leanprover/lean4/pull/12971) increases Lean's default stack size to 1GB (pages are allocated dynamically…). The stack size can be customized via `LEAN_STACK_SIZE_KB`." — G: applies to threads Lean creates; a Swift-created "Lean thread" gets whatever stack Swift gives it (`Thread.stackSize`), so deep non-tail recursion over `Node` must be sized there.
- Static literals: "[#12724]/[#12727] extract ground array and boxed scalar literals into statically initialized data."; "[#12715](https://github.com/leanprover/lean4/pull/12715) ensures the compiler extracts `Array`/`ByteArray`/`FloatArray` literals as one big closed term…" — E
- **`cbv` tactic** stable with `cbv_simproc` [#12597], step limits [#12788] (alternative to `decide` for concrete evaluation). — tests, `#guard`-style examples
- "[#13117](https://github.com/leanprover/lean4/pull/13117) re-enables `#print axioms` under the module system by computing axiom dependencies at olean serialization time." — all (if we adopt `module`)
- "[#12430](https://github.com/leanprover/lean4/pull/12430) provides `WellFounded.partialExtrinsicFix` for implementing and verifying partially terminating functions."
- "[#12385](https://github.com/leanprover/lean4/pull/12385) adds `Array.mergeSort`…" (z-order sort, if needed)
- "[#12678](https://github.com/leanprover/lean4/pull/12678) marks `List.flatten`, `List.flatMap`, `List.intercalate` as noncomputable to ensure that their `csimp` variants are used everywhere."
- "[#13005]: Metaprograms that call `compileDecl` directly may now need to call `markMeta` first…" — A

## v4.31.0 (2026-06-13)

- **Verifiable loops.** "`repeat`/`while` loops also became *verifiable* ([#13209](https://github.com/leanprover/lean4/pull/13209)). … `whileM`, a counterpart to `Lean.Loop.forIn` that admits a one-step unfolding lemma `whileM_eq` (impossible to prove for the original `partial def`)." — C, D
- `mvcgen'` on `SymM` [#13644] (precursor of `vcgen`).
- Transparency: "`rfl` checks defeq at `.default` transparency … but `with_reducible` (where `simp`/`dsimp` run) won't unfold it … The usual fix is … marking it `@[reducible]`." — all proofs
- Perf: "[#13796](https://github.com/leanprover/lean4/pull/13796) reduces `String.compare` to a single `memcmp`, and [#13235](https://github.com/leanprover/lean4/pull/13235) uses `memcmp` for `ByteArray` equality."; "[#13788](https://github.com/leanprover/lean4/pull/13788) generates specialized `dec` code for values of known shape"; LLVM 22 [#13545]. — C, E
- "[#13357](https://github.com/leanprover/lean4/pull/13357) … applies specialize annotations on higher order operations that lack them or borrow annotations on parameters that should morally be borrowed (e.g. the container when iterating over it)."
- "More `ByteArray` `push`/`set!` lemmas ([#13457](https://github.com/leanprover/lean4/pull/13457))" — "adds the missing `ByteArray` push and `set!` lemmas that are still carried locally in `ZipForStd.ByteArray` downstream." — E
- "Verification of `String.dropWhile`/`String.takeWhile` …([#13155])" — D
- Deprecation tooling (`deprecated_module`, `deprecated_syntax`, deprecated options) [#13002], [#13108], [#13195] — A (retiring claims has a precedent API)

## v4.32.0 (2026-07-13)

- **New `do` elaborator is default** ([#13305]); "`do` notation now requires a `Pure` instance … The arms of `do match` are non-dependent by default" — all `Id.run do` code.
- "[#13912](https://github.com/leanprover/lean4/pull/13912) … `return e` inside `(← do …)` … now early-returns from the _enclosing_ `do` block" (breaking).
- `mvcgen' until`, `sym => mvcgen'` [#13983], [#13925].
- Perf: "[#13938](https://github.com/leanprover/lean4/pull/13938) adds tail-recursive `@[csimp]` runtime replacements for bounded-quantifier `Decidable` instances…"; "[#3727](https://github.com/leanprover/lean4/pull/3727) adds `BitVec.flattenList` … with a `@[csimp]`-driven divide-and-conquer implementation that's ~900× faster than a naive left fold." (precedent for spec + `@[csimp]` fast impl)
- "[#13123](https://github.com/leanprover/lean4/pull/13123) makes the task thread pool reclaim idle worker threads after 5 seconds of inactivity, reducing memory waste from the 1GB default stack size per thread." — G
- "[#13891](https://github.com/leanprover/lean4/pull/13891) adds opt-in support for serializing closures to `.olean` files via `CompactedRegion.save (allowClosures := true)`."
- Module linters [#13917] ("run once at the end of elaborating a module … receives the full array of top-level command syntaxes") — A (per-module claim checks)
- "[#13908](https://github.com/leanprover/lean4/pull/13908) deprecates `Lean.RBMap` and `Lean.RBTree` in favour of `Std.TreeMap` and `Std.TreeSet`." — A (registry type)

## v4.33.0 (2026-08-10)

- **Kernel soundness fixes**, several concerning **nested inductives**: "[#14577] typechecks arguments to phantom parameters of nesting inductives. Soundness bug, affecting users of `comparator`."; "[#14616] rejects names using `_nested` in the names…"; "[#14621] … makes the kernel recheck the declarations it adds to the environment after eliminating a nested inductive type." (All need crafted input/metaprogramming; ordinary `Node` definitions unaffected.)
- `lia` gets its own E-matching set: "[#14098](https://github.com/leanprover/lean4/pull/14098) adds a builtin `@[lia]` attribute … Previously `lia` (the `cutsat`-only `grind` configuration) ran with E-matching disabled…"; "[#14107] tags `Nat.min_def`, `Nat.max_def`, `Int.min_def`, and `Int.max_def` with the `@[lia]` attribute … addresses the most common case where `omega` could previously be replaced by `lia`…" — B
- `grind` BitVec literal fixes: "bitvector literals that were not normalized … could be treated as two distinct values, in one case yielding a proof the kernel rejects ([#14371]…)" (kernel caught it — automation bugs are completeness bugs, not soundness bugs).
- "[#14241](https://github.com/leanprover/lean4/pull/14241) makes `bv_decide` use `ext_iff` lemmas for structure equality … structures may need `@[ext]`…"
- **FFI**: "[#14372](https://github.com/leanprover/lean4/pull/14372) moves `Lean.initializing`, `enableInitializersExecution`, and `isInitializerExecutionEnabled` from `IO` to `BaseIO`. `lean_enable_initializer_execution` now returns a scalar, so C FFI callers must stop handling its result with the `lean_io_result_*` functions or `lean_dec_ref`; failing to adapt is likely to segfault."; "[#13679](https://github.com/leanprover/lean4/pull/13679) stops code generation from inspecting the private constructor of a public type. In rare cases this changes a structure's FFI representation…" — G
- "[#14231](https://github.com/leanprover/lean4/pull/14231) marks `Array.back`… `@[expose]`, so that in a downstream module their bodies are available for definitional reduction."; "[#14267](https://github.com/leanprover/lean4/pull/14267) makes `Fin.foldl` reduce in the kernel…"
- "[#13956](https://github.com/leanprover/lean4/pull/13956) bounds kernel type checking by `maxRecDepth` rather than the physical stack…" (deep `decide` on big trees may need `maxRecDepth`)
- `Float` gets a model (`Float.Model`) [#14079]; `DecidableEq Float` compares bit patterns [#14180] — reinforces "no `Float` in theorems".
- `markLinear` precursor: `dbgTraceIfShared` takes message borrowed [#14272].

## v4.34.0 (2026-09-14)

- Kernel soundness: "[#14838](https://github.com/leanprover/lean4/pull/14838) freezes objects whose 32-bit reference count overflows, following the sticky-counter approach used by Koka." (runtime RC detail) — C
- **FFI initialization.** "[#14505](https://github.com/leanprover/lean4/pull/14505) … ensuring the necessary call to `lean_initialize` happens in each module's initializer when necessary. As a follow-up clean up, the call to `lean_initialize_runtime_module` is made implicit as well, meaning users of Lean as an FFI library do not need to call these functions themselves anymore." — G (matches spike note)
- **`bv_decide` inside `grind`/`sym`** [#14672], [#14713]; `types [...]` clause [#14681]; preprocessor on `SymM` up to 6x [#14215] (`@[bv_normalize]` now a `Sym.simp` set). — E (but axiom cost, see 4.29)
- **Intrinsic verification syntax.** "[#14389](https://github.com/leanprover/lean4/pull/14389) adds intrinsic verification syntax for `Std.Internal.Do` do-notation: loop invariants and function contracts that `vcgen` discharges automatically."; `requires` [#14589], `ensures` [#14701], `spec` section in `where … finally` [#14579]. — B, D, E (experimental)
- Stateful linters [#14357]; linters with code actions [#14402]. — A
- "[#14788](https://github.com/leanprover/lean4/pull/14788) redefines `Bool.and`, `Bool.or`, and `Bool.not` directly in terms of `Bool.rec`, which the kernel reduces much faster…"
- "[#14294](https://github.com/leanprover/lean4/pull/14294) drops `@[implicit_reducible]` from `String.toList`, making it semireducible…" — D: proofs must rewrite with `String.toList` lemmas, not rely on unfolding.
- `ite`/`dite` lemma renames: "`if_pos` and `if_neg` are now `ite_eq_left` and `ite_eq_right`" (deprecated aliases remain) [#14501].
- "[#14520](https://github.com/leanprover/lean4/pull/14520) fixes an exponential blowup in `instantiateMVars` on proof terms that repeatedly reference hypotheses introduced by … `simp at h`…"
- "[#14723](https://github.com/leanprover/lean4/pull/14723) makes `MACOSX_DEPLOYMENT_TARGET` configurable through the Lake API…" — G

## v4.35.0 (2026-10-12) — our pin

- **`ofReduceBool` gone.** "[#14953](https://github.com/leanprover/lean4/pull/14953) removes `Lean.reduceBool`, `Lean.reduceNat`, `Lean.ofReduceBool`, `Lean.ofReduceNat` and `Lean.trustCompiler`. *Migration:* use `native_decide`, or `Lean.Meta.nativeEqTrue` in metaprograms." — **all**: on 4.35 a `native_decide`/`bv_decide` proof shows a generated `…._native.…` axiom, not `Lean.ofReduceBool`.
- **`lake check`.** "[#14990](https://github.com/leanprover/lean4/pull/14990) adds `lake check`, which builds the default targets of the current project, exports them, replays the export through the kernel, and fails if anything uses an axiom other than the standard ones." Plus `--paranoid` running "`lean4lean` ([#15048]), `nanoda` ([#15099]), `con-leche` ([#15130]) and `con-ron` ([#15153])"; sandbox "currently only available on Linux". — all: candidate replacement/complement for `lake exe audit`.
- **`vcgen`** replaces `mvcgen` ("deprecates `mvcgen` and `mvcgen?` in favor of `vcgen`" [#14874]); "`vcgen` needs 0.32 s where `mvcgen` needs 66 s, and the kernel checks the resulting proof in 0.53 s instead of 246 s"; "still marked experimental: `set_option experimental.vcgen true`". Contracts: `given` [#14825], loop `invariant`/`decreasing` [#14703], clauses elaborate like `fun` [#14858]. — B, C, D, E
- **`grind` homomorphisms.** "[#14727](https://github.com/leanprover/lean4/pull/14727) completes support for homomorphisms in `grind` … translations for types including `Fin`, `BitVec`, and the fixed-width integer types `UInt8`–`UInt64`, `USize`, `Int8`–`Int64` and `ISize`, which are mapped to `Nat` and `Int` arithmetic." Breaking: "removes the `Lean.Grind.ToInt` type class hierarchy … removes many `BitVec` and `UIntN` E-matching lemmas from the default `grind` set". — E (UInt8/UInt32 encoders)
- **`Decidable` is now `Bool`-based.** "[#8309](https://github.com/leanprover/lean4/pull/8309) changes the definition of `Decidable`: … now a structure that stores a `Bool` together with a proof … many equations hold by `rfl` … The recommended way to write such instances is now with `decidable_of_bool` or `decidable_of_iff`. `Decidable.isTrue` and `Decidable.isFalse` still exist and can still be used as patterns in `match`." — all `decide` users; hand-written instances.
- **Kernel-reducible containers.** "[#14270](https://github.com/leanprover/lean4/pull/14270) lets `decide` and `rfl` reduce nonempty `Array` equality in the kernel across module boundaries."; "[#14989] … `Array.ofFn` …"; "[#14996] … `Array.map` …" — tests/examples via `decide`.
- **`markLinear`.** "[#15052](https://github.com/leanprover/lean4/pull/15052) introduces dynamic tracking primitives to detect non-linearity issues. Users can call `markLinear` on `String`,`ByteArray`, `FloatArray`, and `Array` … if they are not already unique they will be forcibly copied … every further write access to them must occur linearly. If the access does not occur linearly and the environment variable `LEAN_ABORT_ON_NONLINEAR` is set, the program aborts. Users can attach a breakpoint on `lean_internal_panic`…" (+ vectors/hash maps [#15069], [#15049]) — C, E, bench
- `csimp` × `macro_inline`: "[#15429](https://github.com/leanprover/lean4/pull/15429) introduces support for mutual recursion between the `macro_inline` and `csimp` features … The compiler does *not* check that this process terminates…"; "[#14791] makes the compiler `macro_inline` results of `csimp` lemmas." (4.34)
- `@&` on scalars: "[#14749](https://github.com/leanprover/lean4/pull/14749) corrects a memory leak … when interpreted code calls a compiled function with a scalar parameter that is marked `@&`."; "[#14773] … A borrow annotation on a scalar parameter carries no information, and `Lean.IR.ToIR.lowerParam` now drops it." — C
- RC hardening: "[#15241] and [#15289] close two more ways in which an extremely large input could cause a use-after-free in the official kernel, and [#15288] fixes a related problem with objects shared between threads…"
- `rwa` redesigned [#14937]; `constructor` warns on ambiguity [#14854]; `lia`/`grobner` take fact lists [#15116]; `monotonicity_by` and `strong_induct`/`strong_coinduct` for (co)inductive predicates [#14861], [#14855].
- "[#15019](https://github.com/leanprover/lean4/pull/15019) removes the `withPosition` marker from the bodies of `macro` and `elab` declarations…" — A (custom command syntax)

---

## For Cairn

- **all / `make check`:** The audit must treat *any* axiom outside `propext`, `Classical.choice`,
  `Quot.sound` as a failure. On 4.35, `native_decide` and `bv_decide` no longer mention
  `Lean.ofReduceBool` (removed, #14953); each proof gets its own generated `._native.` axiom
  (#12217). Consider `lake check` (#14990) as a second, kernel-replay audit; `--paranoid` adds
  independent kernels but its sandbox is Linux-only.
- **B, C, D, E:** `grind` (4.22+) is the default closer for arithmetic + congruence goals; `lia`
  replaces `omega` for linear integer goals and knows `min`/`max` (4.33). Tag Cairn lemmas with a
  private `register_grind_attr` set (#11765) and run `#grind_lint` (#11157) on them.
- **B, D:** WF-recursive defs don't reduce (#10714) unless the measure is `Nat` (#7965). Prefer
  structural recursion; when WF, use a `Nat` measure. Use `fun_induction` with `induct_unfolding`
  (#8088, #8104). Derived `LawfulBEq` does not support nested inductives (#10351): `Node` needs
  `DecidableEq` or hand proofs.
- **D:** `String` is now `{b : ByteArray // b.IsValidUtf8}` with dependently typed `String.Pos`
  and `String.Slice` (#10304, #10457, #11240). `String.toList` no longer unfolds at implicit
  transparency (#14294). The text model should keep its own `Array Char` (scalar indices, matching
  `FieldView`) and convert at the boundary, or commit to `String.Pos`; don't mix.
- **C, E:** `vcgen` + `def` contracts (4.34–4.35) can prove `Id.run do` loops, but is experimental
  (`set_option experimental.vcgen true`); keep proofs of core invariants on plain recursive
  definitions and use `vcgen` where a loop is the implementation.
- **C, E, bench:** Use `markLinear` + `LEAN_ABORT_ON_NONLINEAR=1` (#15052) in bench/test builds
  to prove that frame `ByteArray`s and state `Array`s are updated in place.
- **G (host):** `@[export]` with `@&` is an error (#13017); initializers no longer take a world and
  call `lean_initialize*` themselves (#10625, #14505); `lean_enable_initializer_execution`
  returns a scalar (#14372). Lean's 1 GB default stack (#12971) only applies to threads Lean
  creates — size the Swift-created Lean thread's stack explicitly.

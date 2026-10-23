---
title: Lean in production verification (Cedar, SampCert, LNSym, Strata)
urls:
  - https://arxiv.org/abs/2407.01688
  - https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development/
  - https://www.amazon.science/blog/how-we-built-cedar-with-automated-reasoning-and-differential-testing
  - https://cedar-policy.github.io/rfcs/0032-port-formalization-to-lean.html
  - https://bhaktishh.github.io/papers/popl-24-src-abs.pdf
  - https://github.com/cedar-policy/cedar-spec
  - https://github.com/leanprover/SampCert
  - https://arxiv.org/abs/2412.01671
  - https://github.com/leanprover/LNSym
  - https://www.amazon.science/blog/how-the-lean-language-brings-math-to-coding-and-coding-to-math
  - https://github.com/strata-org/Strata
date: 2026-10-23
relevance: 5
---

# Lean in production verification

The largest body of production Lean that is not mathematics belongs to AWS: **Cedar** (an
authorization language), **SampCert** (differential-privacy samplers in AWS Clean Rooms),
**LNSym** (an Armv8 symbolic simulator for crypto code) and, newer, **Strata** (a framework for
language semantics). Cedar is the closest analogue to Cairn: a small, readable, executable Lean
model of something a person cares about, proved, and connected to production by tests at a byte
boundary. It also runs on **Lean v4.35.0 with no Mathlib**, exactly our toolchain, so its code is
directly reusable as precedent.

Verbatim excerpts with sources are archived in
[raw/production-verification-excerpts.md](raw/production-verification-excerpts.md). Repository
facts below are from clones taken on 2026-10-23 (cedar-spec HEAD `c9a0340`, 2026-10-22;
SampCert on `v4.34.1`; LNSym last commit 2024-12-09).

## 1. Cedar: verification-guided development (VGD)

### Shape: model in Lean, product in Rust, tests in between

> (1) We write a readable, executable model of Cedar in Lean and prove that the model satisfies
> key correctness and security properties. [...] (2) We use differential random testing (DRT) to
> check that the Cedar production code, written in Rust, matches the model, and use property-based
> testing (PBT) to test properties against the production code for which there is no analogue in
> the model (or no proof, yet).
> — Disselkoen et al., FSE Companion '24, §6

They rejected shipping Lean-compiled code, for reasons that are mostly about *operating* it
(debugging generated C, a small developer pool, "a bug in the Lean compiler could lead to
security issues") and rejected verifying Rust directly ("teams would likely need to wrangle code
into less idiomatic forms with each release just to enable proofs"), §1.

**Cairn differs on purpose:** our compiled Lean *is* the product (update, view, layout, hit test,
encode). Cedar's two-artefact split is not open to us for the core, so their main argument
against shipping Lean (compiler is trusted, generated C is hard to debug) lands on us in full.
It must be in `docs/trusted.md`, and the conformance driver (GOAL item 5) plays the role DRT
plays for Cedar, checking compiled behaviour against the kernel-checked definitions.

### Model requirements

> First, the models should be human readable, and thus favor simplicity and understandability
> [...] Second, they should be as feature complete as possible, so that proofs about them apply
> to the production code [...] Third, [they] can be used as oracles for differential testing. (§3)

The authorizer is eight lines (`isAuthorized` in `cedar-lean/Cedar/Spec/Authorizer.lean`); the
whole model is 1,673 LOC against 15,693 LOC of Rust (Table 1).

### Numbers

| | Value | Source |
|---|---|---|
| Lean model / Lean proofs / Rust prod | 1,673 / 5,714 / 15,693 LOC | paper Table 1 |
| Proof-to-model ratio | "roughly 3.4 : 1" | paper §3.2 |
| Validator soundness proof | 4,686 LOC, "18 person-days" | paper Table 1; AWS blog 2024-04-08 |
| Proof check + model compile | "about 3 minutes" / "185 seconds" (Rust: 45 s compile+test) | paper §3.2; AWS blog |
| Model speed | median 6 µs Lean vs 10 µs Rust per authorization; blog: 5 µs vs 7 µs | paper §3.2; AWS blog |
| DRT | 6 h nightly per target on 4 vCPU / 8 GB, "millions of inputs"; Dafny era: "on the order of 100 million total tests" | paper §4.3; Hicks 2023 |
| Bugs | 4 found by proofs (incl. a non-termination bug), 21 by DRT/PBT | paper §1 |
| Today (cedar-spec HEAD) | 125,621 lines of `.lean` total; `Cedar/Thm` alone 96,228; `Cedar/Spec` 2,192 | `wc -l` on the clone |

The proof corpus grew about 17x since the paper while the spec stayed around 2k lines: proofs,
not definitions, are where the volume goes.

The 6 µs vs 10 µs comparison is *not* "Lean beats Rust": the Rust includes diagnostics and
unmodelled features (§3.1). It does show that a straightforward Lean model over lists, compiled,
is in the microsecond range for tree-shaped inputs of realistic size.

### Why Lean over Dafny

Cedar started in Dafny (Hicks, Amazon Science, 2023-05-10) and moved in RFC 0032
(accepted 2023-10-24; Dafny deprecated in cedar-spec v3.1.0, 2024-03-08):

> proving Cedar's meta-theoretic properties (such as validator soundness) is less suited for
> Dafny's automation [...] For these proofs to be robust in terms of performance and maintenance,
> they need to be highly detailed, favoring the use of an interactive theorem prover.

Shah's port measured it (POPL '24 SRC): Lean spec smaller than Dafny's in every category except
the 738 lines of generic datatypes Dafny got for free; verification 61.79 s (Lean) vs 115.12 s
(Dafny). Counter-evidence from the same source: "Lean proofs were often longer than Dafny proofs,
that could be empty."

### Nested recursive data: what they did instead of `Std` containers

This is the finding most relevant to our `Node` (children `List Node`) and any future
map-valued state.

> While Rust lets us represent Cedar values as a recursive datatype over built-in sets and maps,
> Lean prohibits doing so for its standard set and map datatypes because their invariants
> introduce circular (not well-founded) reasoning. We worked around this by developing custom set
> and map datatypes that replace embedded invariants with separate theorems. (§3.1)

The current `Cedar/Data/Set.lean` doc: "backed by a sorted duplicate-free list. Functions on sets
assume but don't require their inputs to be well-formed [...] Separate theorems show that these
functions produce well-formed outputs when given well-formed inputs." The type is just
`inductive Set (α) | mk (l : List α)`, and `Value` nests it: `| set (s : Set Value) | record (m :
Map Attr Value)`.

Recursion over nested lists uses `attach` wrappers, with no `termination_by` on `evaluate`:

```lean
  | .set xs          => do
    let vs ← xs.mapM₁ (fun ⟨x₁, _⟩ => evaluate x₁ req es)
```

where `mapM₁ xs f := xs.attach.mapM f` (`Cedar/Data/List.lean:107`), and a rewrite lemma
`mapM₁_eq_mapM` (`Cedar/Thm/Data/List/Lemmas.lean:588`) erases the `attach` again inside proofs.
For `List (α × β)` fields they define `attach₂` carrying `sizeOf x.snd < 1 + sizeOf xs`.
Repository counts: 104 `termination_by`, 68 `decreasing_by`, 60 `.attach`.

Termination proofs paid for themselves: building them "helped us uncover and fix a
non-termination bug in our definition of the Cedar validator", which DRT never found
("Triggering input is too hard to generate", Table 4).

### Proof style for surviving upgrades

`cedar-lean/GUIDE.md`, "Proof stability":

> - Use `simp only` instead of `simp`. It's okay to use `simp` to close a goal.
> - Use `have` to deconstruct values. Use `rcases` only to split disjunctions.
> - Use `exact` instead of `apply` whenever possible.
> - Fully spell out types in function and theorem declarations.

In the repository: 8,970 `simp only` lines out of 14,098 `simp` lines; 472 `omega`; 304
`decide`; 34 `grind` (all in the newest TPE files, e.g. `Cedar/Thm/TPE.lean:165`); 0 `bv_decide`.
`grind` is arriving in new code, not replacing old proofs.

### Upgrade cadence and cost (measured from GitHub)

cedar-spec moved its `lean-toolchain` 33 times between 2023-10-26 and 2026-10-20, roughly monthly
since early 2025, tracking each stable release. PR sizes (files, +/−): 4.22 `86, +584 −644`;
4.23 `13, +225 −225` ("Invalid dotted identifier notation" fixes); 4.26 `17, +116 −91`; 4.31
`29, +58 −70` (RBMap deprecated → `Std.TreeMap`); 4.35 `6, +18 −81` ("a pretty straightforward
upgrade. The only code changes were resolving warnings"). A diff histogram of the 4.22 upgrade is
almost entirely `simp`/`simp only` lemma lists changing.

**Counter-evidence that matters for a per-frame runtime:** the 4.25 bump was reverted the next
day: "DRT encountered OOM after the update" (PR #792). A toolchain upgrade can regress *compiled
code's* memory behaviour while every proof still checks. They also dropped Mathlib for std4 in
Dec 2023 (PR #177: "a small footprint, fewer goals, and faster from-scratch build times"),
matching our no-Mathlib rule.

### What DRT taught them about generators

- Type-directed generation found bugs much faster than naive generation; random requests rarely
  mention the entities random policies mention (Hicks 2023).
- Coverage is not enough: 35.5% of generated `when` conditions were boolean literals; a new
  generator brought that to 9.7% (§4.3).
- DRT caught spec ambiguity, not just bugs: string length differed by "bytes vs. codepoints vs.
  graphemes" between model and Rust, and the feature was dropped (§4.3).
- Missed: malformed inputs ("DRT does not methodically generate malformed policies"), untested
  APIs, and the non-termination bug (Table 4).
- Round-trip properties (parse ∘ print) found 8 of the 21 bugs (Table 2).

### FFI precedent on 4.35

Cedar calls its Lean model from Rust (`cedar-lean-ffi`). The boundary is bytes in, string out:
`@[export isAuthorized] unsafe def isAuthorizedFFI (req: ByteArray) : String` decodes protobuf
(`CedarFFI/Main.lean:85`). Initialization (`cedar-lean-ffi/src/lean_ffi.rs:588`): a `call_once`
runs `lean_initialize_runtime_module_locked`, the module initializer, then
`lean_io_mark_end_initialization` and **`lean_set_exit_on_panic(true)`** ("If we don't explicitly
set this, Lean does not abort after hitting a panic"); each handle calls `lean_initialize_thread`
and its `Drop` calls `lean_finalize_thread`. The comment "WARNING: we can only have one Lean
thread" sits on the constructor. Note their Rust still declares
`initialize_Cedar_CedarFFI(builtin: u8, ob: *mut lean_object)`, i.e. with the world argument
that `docs/spike-boundary.md` says 4.35 no longer takes; C calling conventions tolerate the
extra argument, so this is not evidence either way.

## 2. SampCert: spec definitions with `@[extern]` implementations

SampCert's samplers are written in `SLang`, a shallow monadic embedding whose `bind` is a
mathematical sum, and the executable meaning is swapped in by `@[extern]`:

```lean
@[extern "prob_Bind"]
def probBind (p : SLang T) (f : T → SLang U) : SLang U :=
  fun b => ∑' a, p a * f a b
```

(`SampCert/SLang.lean:71`; also `prob_Pure`, `prob_UniformByte`, `prob_While`, implemented in
57 lines of C++ in `ffi.cpp`.) Proofs reason about the `def` body; the compiled code runs the C.
Nothing in Lean relates them; the paper calls these 57 lines the trusted computing base, and the
samplers are also checked statistically (Kolmogorov–Smirnov tests in `Tests/`). The repository
also carries `@[extern "dirty_io_get"] opaque DirtyIOGet(x : IO ℤ) : UInt32` under the comment
"The following is unsound and should NOT be part of the code". The deployed AWS path translates
SLang to Dafny and then Python (`FastExtract.lean`, `#print_dafny_exports`). Over 12,000 lines of
proof, heavy Mathlib.

**Checked on 4.35 (`/tmp/p4/c.lean`):** a wrong `@[implemented_by]` or `@[extern]` is invisible to
`#print axioms`:

```lean
def fastLen (xs : List Nat) : Nat := xs.length + 1   -- deliberately wrong
@[implemented_by fastLen] def specLen (xs : List Nat) : Nat := xs.length
theorem specLen_nil : specLen [] = 0 := rfl
#print axioms specLen_nil   -- 'specLen_nil' does not depend on any axioms
#eval specLen []            -- 1
```

The same holds for `@[extern "c_len"] def externLen ...`. Our axiom audit cannot see this class
of trust; only `@[csimp]` (which demands a proof of equality) closes the gap.

## 3. LNSym: the cost of bit-blasting and big symbolic proofs

LNSym models Armv8 instructions in Lean and checks the model against hardware by co-simulation
(`make cosim`: random instruction tests, run only on AArch64). Its proofs lean on
`bv_decide`/`native_decide` (67 and 157 occurrences) and its own `simp_mem`, `bv_omega` tactics,
and they accept `Lean.ofReduceBool`:

> info: 'SHA512.sha512_block_armv8_prelude' depends on axioms: [propext, Classical.choice,
> Lean.ofReduceBool, Quot.sound] (`Proofs/SHA512/SHA512Prelude.lean:239`)

Its benchmark harness (`Benchmarks/Command.lean`, a custom `benchmark` command reporting
heartbeats and ms) measures proof time against program length (SHA512 at 50–400 instructions),
with `_noKernel` variants under `set_option debug.skipKernelTC true`: kernel checking of large
symbolic-simulation terms was a cost worth isolating. The repository is pinned to
`nightly-2024-10-07` and has had no commits since 2024-12-09. A downstream project (eth-act/clifv
PR #255) later re-proved eight LNSym `bv_decide` lemmas in the kernel to remove the axiom.

## 4. Strata and the rest

Strata (github.com/strata-org/Strata, Apache-2.0, active as of 2026-10-22) is an AWS Lean
framework for "formalizing language syntax and semantics, and implementing automated reasoning
applications", with dialects (Laurel, Boole). Leo de Moura's Amazon Science overview
(2024-08-16) is qualitative only ("fast runtime enables efficient differential testing of Cedar
models"; no benchmarks). Neither adds a technique Cedar doesn't already show; Strata's
dialect-definition machinery may be worth a look for workstream A later.

## 5. A hole in "check the axioms" (observed, 4.35)

`debug.skipKernelTC` (registered at `src/lean/Lean/Environment.lean:76`, honoured in
`Lean/AddDecl.lean:25`) lets a metaprogram add a false theorem that `#print axioms` reports clean
(`/tmp/p4/b.lean`):

```lean
set_option debug.skipKernelTC true in
run_meta do
  let ty ← mkEq (mkNatLit 4) (mkNatLit 5)
  let v := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Nat) (mkNatLit 4)
  addDecl (.thmDecl { name := `four_eq_five, levelParams := [], type := ty, value := v })
#print axioms four_eq_five    -- 'four_eq_five' does not depend on any axioms
example : False := by have := four_eq_five; omega   -- accepted
```

`lean/Audit.lean` loads `.olean`s with `importModules` and calls `collectAxioms`, which does not
re-run the kernel, so it would pass this. The 4.35 toolchain ships independent re-checkers in
`bin/`: `leanchecker` (source `src/lean/LeanChecker.lean`, replays a module's constants through
the kernel), `leanchecker-paranoid`, `lean4lean` and `nanoda_bin`. Compiling that file to `B.olean` and running
`LEAN_PATH=… leanchecker B` catches it:

```
uncaught exception: while replaying declaration 'four_eq_five':
(kernel) declaration type mismatch, 'four_eq_five' has type
  Eq 4 4
but it is expected to have type
  Eq 4 5
```

(CPU cost was under 0.5 s user for a module importing `Lean`; wall-clock on this machine was
dominated by I/O, so measure in CI before assuming it is free.)

## Counter-evidence and limits

- Cedar's evidence is about a *model* that is not the shipped artefact; their speed numbers are
  for tests, not a latency-critical product. Nothing here shows Lean-compiled code under a
  per-frame budget; our spike's numbers are still the only ones that count for that.
- Cedar's proofs are long and hand-guided (`simp only` everywhere). Ratio 3.4:1 at the paper,
  much higher now; budget proof effort accordingly, and expect most churn in proofs.
- Cedar still uses `native_decide` in `Cedar/Thm` and `Cedar/Data/Int64.lean` (26 uses, e.g.
  `(0 : Int64).toInt = 0`). On 4.35 plain `decide` proves `(86400000 : Int64).toInt = 86400000`
  (checked, no axioms), so those uses look like legacy from older toolchains rather than a need.
- LNSym shows proof automation that is fast enough often relies on `ofReduceBool`, and a project
  with that trust choice can still stall on an old nightly.

## For Cairn

- **All (process).** Adopt Cedar's `GUIDE.md` proof-stability rules: `simp only` except for
  terminal `simp`; `exact` over `apply`; full type signatures. Upgrade the toolchain one stable
  release at a time in its own PR, and gate it on `bench/` numbers as well as `make check`
  (Cedar's 4.25 OOM revert). Write the stable-only rule into AGENTS.md.
- **All (trust).** Extend `make check`: (1) run the toolchain's `leanchecker` over `Cairn` and
  `Examples` modules so the kernel re-checks every declaration; (2) fail on any
  `debug.skipKernelTC` in the source; (3) list every `@[implemented_by]`, `@[extern]` and
  `unsafe` in `Cairn.*` into `docs/trusted.md` automatically, and require `@[csimp]` (a proved
  equation) whenever a fast version replaces a spec definition. `#print axioms` alone does not
  see these.
- **A (claims DSL).** Cedar keeps unit tests out of Lean ("we can instead prove properties"),
  but keeps generated corpora as regression tests. Mirror that: the ledger and claim registry get
  proofs, and the conformance corpus becomes a checked-in regression set.
- **B (layout) and D (text).** Follow Cedar for nested data: keep `children : List Node` as a
  plain inductive; recurse with `xs.attach.map` (or a `map₁` helper) and prove a
  `map₁_eq_map`-style lemma once so proofs never see `attach`. If any state needs a set or map
  inside a recursive type, use a list-backed type with well-formedness as separate theorems, not
  `Std.HashMap`/`TreeMap` with embedded invariants. Treat termination proofs as bug finders.
- **C (runtime).** Copy Cedar's host lifecycle: one-time runtime + module init, then
  `lean_io_mark_end_initialization`, and set `lean_set_exit_on_panic(true)` in debug builds so a
  Lean `panic!` crashes loudly instead of returning `default` into the frame.
- **D (text).** Decide "length" once (Cairn says Unicode scalars) and test it differentially
  against Core Text: Cedar's string-size disagreement (bytes vs codepoints vs graphemes) is the
  exact bug class waiting for us.
- **E (encoding).** Round-trip properties found the most bugs in Cedar (8 of 21). Our round-trip
  is proved in Lean, but the Swift decoder is not: generate corpora type-directed from the Lean
  types, add deliberately malformed frames (Cedar's main blind spot), and run the Swift decoder
  against them in CI.
- **J (conformance).** VGD is the template: kernel-checked model, compiled artefact, differential
  testing between them with type-directed generators and a measured literal/trivial-input rate.

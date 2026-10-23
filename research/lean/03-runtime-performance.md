---
title: "Lean runtime performance: reference counting, in-place updates, boxing, stacks"
urls:
  - https://arxiv.org/abs/1908.05647
  - https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse/
  - https://lean-lang.org/doc/reference/latest/Run-Time-Code/
  - https://github.com/leanprover/lean4/pull/15052
date: 2026-10-23
relevance: 5
---

# Lean runtime performance for a per-frame hot path

Experiments are archived in [raw/runtime-experiments/](raw/runtime-experiments/) (`Bench.lean`,
`IR.lean`, `Deep.lean` + `host.c`). Header paths are under
`~/.elan/toolchains/leanprover--lean4---v4.35.0/include/`, Lean source under `src/lean/`.

## The model: exact reference counts, destructive update when unique

- Ullrich & de Moura, *Counting Immutable Beans* (IFL 2019, arXiv 1908.05647): "We propose a new
  mechanism for efficiently reclaiming memory used by nonshared values" (reset/reuse), plus
  borrowed parameters to cut RC traffic and a heuristic to infer them.
- Reinking, Xie, de Moura, Leijen, *Perceus* (PLDI 2021): reuse analysis "allows for guaranteed
  in-place updates at runtime ... a novel programming paradigm that we call functional but
  in-place (FBIP)". (Koka's implementation; Lean's is the IFL 2019 design.)
- In 4.35 the pass lives in the new compiler: `Lean/Compiler/LCNF/ResetReuse.lean:12-17`
  ("implements the insertion of reset-reuse instructions into lambda pure as described in
  "Counting Immutable Beans""), alongside `InferBorrow.lean`, `ExplicitRC.lean`,
  `ExplicitBoxing.lean`, `CoalesceRC.lean`.

**What "unique" means at runtime** (`lean/lean.h:759-765`):

```c
static inline bool lean_is_exclusive(lean_object * o) {
    if (LEAN_LIKELY(lean_is_st(o))) { return lean_internal_get_rc(o) == 1; }
    else { return false; }
}
```

and `lean.h:133-134`: "`m_rc` ... encodes whether the object is single threaded (> 0), multi
threaded (< 0), or reference counting is not needed (== 0)". So **an object marked
multi-threaded, or a persistent one (created during module initialisation, rc 0), is never
"exclusive"**, and every `Array.set`/`push` on it copies (`lean_ensure_exclusive_array`,
`lean.h:1125-1128`: `if (lean_is_exclusive(a)) return a; return lean_copy_expand_array_nonlinear(a, false);`).
A copy produces a fresh single-threaded array, so a persistent initial state costs one copy, but
state that has been marked MT (shared with a `Task`, or passed through `lean_mark_mt`) costs a
copy *on every update*.

## What the compiler actually emits (observed IR, `IR.lean`)

`set_option trace.compiler.ir.result true` on a structural tree map `bump` (`.node w cs =>
.node (w+1) (go cs)`):

```
let x_13 : u8 := isShared x_1;
case x_13 : u8 of
Bool.false → jmp block_4 x_1 x_13          -- reuse the cell
Bool.true  → inc x_3; inc x_2; dec x_1; jmp block_4 ◾ x_13
...
Bool.false → set x_5[1] := x_9; set x_5[0] := x_8;   -- in place
Bool.true  → let x_12 : obj := ctor_0[T.node] x_8 x_9;
```

So a structural `Node → Node` rewrite is in place when the input tree is not shared.

`Array.modify` on `Array P` with `structure P where (x y : UInt64)`: the element is swapped out
(`Array.set … PUnit.unit`) so it becomes unique, updated with `sset x_16[0, 0] : u64`, and put
back. Scalar fields of a structure are stored unboxed in the constructor (`ctor_0.0.16[P.mk]`).

`Array UInt64` fold: `let x_6 := Array.ugetBorrowed …; let x_7 : u64 := unbox x_6` — **every
element of an `Array UInt64` is a separate heap box** (`lean_box_uint64` allocates a ctor,
`lean.h:3117-3121`; `UInt32` and smaller are boxed as tagged scalars on 64-bit,
`lean.h:3095-3106`). For bulk numeric data use `ByteArray`/`FloatArray` or pack into structures.

## Numbers (M4 Max, compiled `-O3` via Lake; machine load 18–30 from other agents, so treat as upper bounds)

| Case | Time |
|---|---:|
| `Array.set!` over 1e6 elements, unique | 3.2 ms |
| same, with an alias of the original kept alive (one copy, then unique) | 4.7 ms |
| same loop over 2e4 elements, keeping every intermediate version (copy per step, O(n²)) | 1,102 ms |
| `ByteArray.push` ×4 per u32, 1e6 u32s, preallocated | 6.0 ms |
| `List.range n |>.map` 1e6 | 13.4 ms |
| `Array.range n |>.map` 1e6 | 7.6 ms |
| sum over a ~270k-node tree (structural pair) | 1.2 ms |
| structural map over the same tree while the original is still alive (no reuse) | 8.4 ms |

The 2e4 "keep all" case is the shape of the bug to fear: it is 1/50th the size of the unique
loop and 340× slower.

## Catching accidental copies: `markLinear` (new in 4.35, #15052)

`Init/Data/Array/Basic.lean:214-224`: "Marks an array as linear, which is a no-op logically. At
runtime the array is first made unique, copying it if the reference is not already unique, and
then marked. If the environment variable `LEAN_ABORT_ON_NONLINEAR` is set, every non-linear use
from that point on causes a panic instead of a silent copy. To debug where the non-linearity is
coming from you can set a breakpoint on `lean_internal_panic`." Also on `ByteArray`
(`Init/Data/ByteArray/Basic.lean:119-125`), `String`, `FloatArray`, `Vector`.
`@[simp, grind =] theorem markLinear_eq : xs.markLinear = xs := rfl`, so proofs don't see it.
Observed: a marked array written while still referenced exits with status 1 under
`LEAN_ABORT_ON_NONLINEAR=1` (no message printed; use the breakpoint) and silently copies
without it.

## Stack depth: a hazard specific to embedding

Structural recursion over `List Node` children is *not* tail-recursive (`bump.go` above calls
itself after `bump c`). A Lean executable runs `main` through `lean_run_main` (generated
`main` in the C output), on a thread Lean creates with a large stack (the digest notes the 1 GB
default, 4.30 #12971, "only applies to threads Lean creates"). An embedded Lean called from a
host-created thread gets that thread's stack. Observed with `host.c` (pthread, then
`lean_initialize_thread`, then a structural map over one box with *n* leaf children):

| Thread stack | n = 10,000 | 30,000 | 100,000 | 300,000 | 1,000,000 |
|---|---|---|---|---|---|
| 512 KB (the macOS secondary-thread default) | ok | **crash (SIGILL, exit 132)** | crash | | |
| 8 MB | ok | ok | ok | **crash** | crash |
| 64 MB | ok | ok | ok | ok | ok |

The same code in a Lean `main` handled 10,000,000 children.

## What to avoid in a per-frame hot path

- Keeping old versions of the state or frame alive across an update (undo stacks that alias the
  live array, debug snapshots, a `Frame` cached by the host while Lean writes the next one into
  the same buffer). Each alias turns the next write into a full copy.
- Letting the state become multi-threaded: never hand the live `State` to a `Task` or mark it MT.
- `Array UInt64`/`Array Float` for bulk data (boxed per element); `List` for anything indexed.
- `String` concatenation to build output; build `ByteArray` with preallocated capacity.
- Closures in data (`Node` holding functions): each is an allocation and blocks `DecidableEq`.
- Deep non-tail recursion when the host owns the thread; give the Lean thread a big stack.

## Counter-evidence

- Uniqueness is invisible in the types. Nothing stops a refactor from adding an alias; the only
  guards are `markLinear` + `LEAN_ABORT_ON_NONLINEAR` in tests and benchmarks.
- `Array.set!`/`modify` in place needs the *array* unique *and* the compiler to see the old
  value dead; `let old := a[i]!` before the write keeps the element shared (cheap for scalars,
  not for subtrees).
- The spike measured 0.38 µs/node for layout + encode with no optimisation (`docs/spike-boundary.md`),
  so RC overhead is not the bottleneck at M1 scale; copies from aliasing are.

## For Cairn

- **C (runtime) / G (host):** create the Lean thread with an explicit stack of at least 64 MB
  (`Thread.stackSize` in Swift, `pthread_attr_setstacksize` in C). Never mark the state MT.
  Record the stack size in `docs/trusted.md`.
- **E (encoding):** encode into a `ByteArray.emptyWithCapacity` sized from the frame, `push`
  only; call `markLinear` on it in `bench/` and run benchmarks with `LEAN_ABORT_ON_NONLINEAR=1`.
- **B (layout):** structural `Node → Laid` is reuse-friendly; keep `Laid` construction a single
  pass and don't hold the previous `Laid` while building the next unless it's needed (hit testing
  should use the current one).
- **D (text):** undo history must not share the live buffer array with the current state if the
  buffer is mutated in place; store edits (ops) rather than snapshots, or accept the copy knowingly.
- **All:** run `bench/` under `LEAN_ABORT_ON_NONLINEAR=1` with `markLinear` on the state's big
  arrays; a regression shows up as an abort, not a slow graph.

# AGENTS

Cairn is research into UIs where every action is a claim with a durable id and machine-checked
evidence. Read [GOAL.md](GOAL.md) for what we are building now (M2; M1 is in docs/goals/) and
[docs/architecture.md](docs/architecture.md) for how it fits together.

## Layout

- `lean/`: the Lake package. `Cairn/` is the framework (claims, UI core, text, frame encoding),
  and proofs live next to the code they are about. The example apps (Counter, Basics, Todo,
  Clock, Tray, Gallery) live in iamnbutler/cairn_examples (scope `cairn_examples`).
- `host/`: the Swift package. The AppKit host, the Metal renderer, text, the accessibility mirror
  and the debug socket. No application logic.
- `docs/`: design docs, the frame format (`frame.md`) and the trusted base (`trusted.md`).
- `research/`: sourced notes on prior art, one folder per source.
- `tools/`: the conformance driver, the app capture, audits, and the `cairn` CLI (`tools/cairn`).
- `test/fixture/`: Cairn's own app, a package of its own (scope `fixture`, its own claims.lock).
  The framework's checks run on it with the `cairn` CLI.
- `claims.lock`: every `cairn^N` claim id ever issued. Tools write it; never edit it by hand.
- `Package.swift` (root) and `bin/cairn-link`: Cairn as a package for apps in their own repos
  (docs/package.md). The root manifest is library-only with no `unsafeFlags`; it declares
  host/'s library targets again, so keep it in step with `host/Package.swift`. Yap lives in
  iamnbutler/yap-cairn and depends on a tag; a change to anything it uses needs a new tag.

## Rules

- **No `sorry`, no new axioms.** `make check` audits every theorem's axioms; only `propext`,
  `Classical.choice` and `Quot.sound` are allowed. `native_decide` adds a compiler axiom, so
  don't use it in proofs that count toward GOAL.md; note any exception in `docs/trusted.md`.
- **Ids are the contract.** Never renumber, reuse or delete a claim id. Retire it instead.
  Changing what a claim means needs a new id.
- **Pure Lean core.** `update`, `view`, `layout`, `hitTest` and encoding are total, pure functions.
  Effects are data the host runs. No `IO` below the app boundary.
- **Integers for geometry.** Layout uses integer logical pixels. No `Float` in anything a theorem
  talks about.
- **The host stays thin.** If Swift has to decide something about application behaviour, it
  belongs in Lean. Every assumption the host makes goes in `docs/trusted.md`.
- **Lean dependencies:** none beyond core and Std for now (no Mathlib), to keep builds fast.
- **Measure, don't guess.** Performance claims come with numbers in `bench/`.

## Writing Lean

From [research/lean/](research/lean/), measured on our toolchain:

- **Banned:** `implemented_by` (runs unchecked code), `debug.skipKernelTC`, `native_decide`,
  `bv_decide` (each adds its own axiom) and `axiom`. `make lint` greps for them. `make kernel`
  replays every declaration through the kernel, because the axiom audit can't see a skipped
  kernel check.
- **Spec and fast code:** pair them with `@[csimp]` and a proof. `partial def` is opaque to proofs.
- **Recursion over `Node` and `Laid`:** `children.map f` silently becomes well-founded and
  irreducible, so `rfl`, `decide` and `#guard` stop working. Write a structural pair (`f` with
  `where go : List Node → _`, or `mutual`) and prove with mutual theorems or `f.induct`.
  `deriving DecidableEq` doesn't work on nested inductives; hand-write it.
- **Bytes:** write encoding specs arithmetically (`toNat`, `/`, `%`, `*`) over `List UInt8`,
  close round trips with `omega`, and bridge to `ByteArray` and shift-based fast paths once.
- **No `import Lean` in anything the host links.** It makes a small app about 100 MB. Commands
  and elaborators live in modules that apps use only at compile time.
- **Tactics:** `omega` for integer geometry; `simp only [...]` and `grind only [...]` in committed
  proofs; `decide +kernel` for bounded enumerations; `decidable_of_iff` for instances.
- **Performance:** don't alias arrays you update (old frames, undo snapshots), and don't share
  live state with a `Task`; either one copies on every write. Run benches with
  `LEAN_ABORT_ON_NONLINEAR=1` to catch it. The host's Lean thread needs a large stack (64 MB).
- Only `ByteArray`s cross to Swift, never Lean structures: Lean reorders their scalar fields.

## Toolchain

- Lean via elan, pinned in `lean/lean-toolchain`. `export PATH=$HOME/.elan/bin:$PATH` if `lake`
  is missing.
- Swift 6 and the Metal toolchain from Xcode.
- `make build`, `make check` (lint, Lean build, axiom audit, kernel replay, Swift build and tests,
  and the per-app checks on test/fixture).

## Workflow: lane

Every change happens in a lane, never in the main checkout and never with a bare
`git worktree add`.

1. `lane new <name>` from an up-to-date main, then work in the printed tree.
2. `lane why <path>` before editing a file.
3. Commit as you go. Add a `Why: <path> | <note>` trailer only for a non-obvious constraint.
4. `lane check`; confirm, replace or retire stale notes.
5. `make check` passes.
6. `lane push`, then `gh pr create`. Check `git log --oneline -2` after pushing: the lane must sit
   on current `origin/main`.
7. Squash-merge (`gh pr merge --squash`, no `--delete-branch`), `git pull --ff-only` in the main
   checkout, `lane prune --dry-run`, then `lane rm <name>` for merged lanes prune misses.

Each lane has its own `.lake/` and `.build/`; the first build in a fresh lane is slow.

<!-- lane:protocol -->
## Context memory

- Before editing a file, read `.lane/memory/<path>/` if it exists, or run `lane why <path>`.
- Record non-obvious findings with `lane note add <path> -a <anchor> "..."`.
- Do not edit `.lane/` by hand; landing manages it.
- Land with `lane merge`, or `lane push` where trunk is protected, then `lane prune` once it merges.
- Detailed workflow lives in `.agents/skills/lane/SKILL.md`; run `lane install skill` if it is absent.
<!-- /lane:protocol -->

# AGENTS

Warrant is research into UIs where every action is a claim with a durable id and machine-checked
evidence. Read [GOAL.md](GOAL.md) for what we are building now and
[docs/architecture.md](docs/architecture.md) for how it fits together.

## Layout

- `lean/`: the Lake package. `Warrant/` is the framework (claims, UI core, text, frame encoding),
  `Examples/` holds apps built on it, and proofs live next to the code they are about.
- `host/`: the Swift package. The AppKit host, the Metal renderer, text, the accessibility mirror
  and the debug socket. No application logic.
- `docs/`: design docs, the frame format (`frame.md`) and the trusted base (`trusted.md`).
- `research/`: sourced notes on prior art, one folder per source.
- `tools/`: the conformance driver, map generation, audits.
- `claims.lock`: every claim id ever issued. Tools write it; never edit it by hand.

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

## Toolchain

- Lean via elan, pinned in `lean/lean-toolchain`. `export PATH=$HOME/.elan/bin:$PATH` if `lake`
  is missing.
- Swift 6 and the Metal toolchain from Xcode.
- `make build`, `make check` (Lean build, axiom audit, ledger check, Swift build and tests),
  `make demo`.

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

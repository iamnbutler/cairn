---
title: "Metaprogramming for the claims DSL: commands, environment extensions, the module system"
urls:
  - https://lean-lang.org/doc/reference/latest/Notations-and-Macros/
  - https://lean-lang.org/doc/reference/latest/Source-Files-and-Modules/
  - https://leanprover-community.github.io/lean4-metaprogramming-book/
  - https://github.com/leanprover/lean4/pull/8666
  - https://github.com/leanprover/lean4/pull/11637
date: 2026-10-23
relevance: 5
---

# Metaprogramming for a `move 12 "title" where …` command

Two working scratch packages are archived in
[raw/claims-dsl-experiment/](raw/claims-dsl-experiment/): `nonmodule/` (classic files) and
`module/` (the 4.27+ module system). Source paths are under the toolchain's `src/lean/`.

## The pieces

**A persistent registry is an environment extension.** `Lean/EnvExtension.lean:23-31`:

```lean
structure SimplePersistentEnvExtensionDescr (α σ : Type) where
  name          : Name := by exact decl_name%
  addEntryFn    : σ → α → σ
  addImportedFn : Array (Array α) → σ
  ...
```

Each module's entries are written into its `.olean`; on import, `addImportedFn` receives one
array per imported module (`Lean/Environment.lean:1711-1719`, where the core version runs in
`ImportM := ReaderT Lean.ImportM.Context IO`, `:1555`, so it *can* throw, aborting the import).
Register with `initialize claimExt : SimplePersistentEnvExtension … ← registerSimplePersistentEnvExtension {…}`.

**A command is `syntax` + `@[command_elab]`.** The elaborator reads the id and title, checks
the registry, emits ordinary declarations with `elabCommand (← `(def …))`, and records the
entry with `modifyEnv fun env => claimExt.addEntry env {…}`.

## What I observed

Package: `Ext.lean` (extension), `Cmd.lean` (`move` and `#check_claims`), `App/A.lean`
(`move 12`, `move 13`), `App/B.lean` (`move 12`), `App/Same.lean` (imports A, `move 13`),
`App/C.lean` (imports A and B, `#check_claims`).

1. **Duplicate against an import, or in the same file:** a clean error at the id:
   `Cl/App/Same.lean:2:5: error: claim ^13 already issued to claim_13 in Cl.App.A`.
2. **Duplicate between two sibling modules** (A and B never import each other): nothing can
   see it until some module imports both. Two ways it then surfaces:
   - if the generated declaration name is derived from the id alone (`claim_12`), the *import*
     fails: `C.lean:1:0: import Cl.App.B failed, environment already contains 'claim_12' from
     Cl.App.A`. A uniqueness check for free, but reported at the import line.
   - if declaration names are per-module, `addImportedFn` records the duplicate in the state and
     `#check_claims` reports it: `C.lean:3:0: claim ^12 issued twice: Cl.App.A and Cl.App.B`.
3. **`initialize` can't be used in the module that declares it.** Using the extension in the same
   file (`run_cmd modifyEnv fun env => myExt.addEntry env 1`) crashed the `lean` process:
   `libc++abi: terminating due to uncaught exception of type lean::exception: cannot evaluate
   `[init]` declaration 'myExt' in the same module`. The extension must live in its own module,
   imported by the command module.
4. **Importing `Lean` drags the whole compiler into the app binary.** The `Main` that imports a
   module defining `move` (which imports `Lean`) linked to a **101 MB** executable (startup
   ~35 ms); the same toolchain's plain executable is 2.4 MB (~5 ms). Lake's link line always has
   `-lLean`; it is dead-stripped unless something calls `initialize_Lean`, which any transitive
   `import Lean` does. For us this would also break the spike's static-library recipe ("No
   `libLean` (the compiler) needed", `docs/spike-boundary.md`).
5. **The module system fixes (4).** With `module` files, `public meta import Lean` in the
   command module and `meta import Cm.Cmd` in the app module, the app linked to **1.1 MB**, ran,
   and printed the generated claim's value. Release notes: since 4.23 "compiled code for
   non-`meta` definitions isn't imported" (#8666); the module system is stable since 4.27
   (#11637). Gotchas hit on the way:
   - `@[command_elab]` on a private `meta def` fails: "Cannot add attribute … Declaration
     `_private.Cm.Cmd.0.elabMove` must be public". Write `public meta def`.
   - `public syntax (name := moveCmd) …` is a parse error ("unexpected token '('; expected
     identifier"); plain `syntax (name := …)` works and is visible through `meta import`.
   - Generated declarations must be `public def` or they are private to the app module.
   - (From the release notes, not tested here.) In a `module`, definition bodies are hidden from
     importers unless `@[expose]`, so
     a theorem in module B can't unfold a `def` from module A. For proofs across modules, mark
     the specs `@[expose]` (or `public section` with expose); check `#print axioms` still works
     (fixed in 4.30, #13117 per the digest).

## Design patterns that follow

- **Split three ways:** `Cairn/Claims/Ext.lean` (types + `initialize`), `Cairn/Claims/Command.lean`
  (syntax + elaborators, `meta`), and the runtime vocabulary (`Cairn/Claim.lean`, no `Lean`
  import). App modules `meta import` the command module.
- **Make the id the declaration name** (e.g. `Cairn.Claims.c12`, or `«^12»`) to get a
  kernel-level duplicate check whenever two modules meet, *and* record per-module entries so a
  `#check_claims` (or `lake exe ledger`) can explain it. Neither catches modules that are never
  imported together; a root module that imports every app module (and runs `#check_claims`) has
  to exist, and the ledger (`claims.lock`) catches retired/reused ids across history.
- **Don't throw from `addImportedFn`.** It runs at import; an exception there makes every
  downstream file fail at line 1 with an unhelpful location. Record and report from a command.
- **Elaborate to plain declarations** (`def claim_12_apply`, `theorem claim_12_post`) so the
  axiom audit, `#print axioms`, `lake check` and proofs see ordinary constants. The
  extension stores names, not terms.
- **Proof obligations:** have `move … where post := …` elaborate the theorem statement and
  leave its proof to a `by` block written by the author; elaborators shouldn't call `grind`
  silently (it hides what proved the claim and slows every build).
- **JSON for the map:** the extension's state is readable from a `lake exe` that imports the
  root module and calls `claimExt.getState env` via `importModules`, as `Audit.lean` already does
  for axioms.

## Counter-evidence and caveats

- Elaboration of `import Lean` files is slow to start (here 20–100 s per file under heavy machine
  load; not measured on an idle machine). Keep the command module small and stable so it rarely rebuilds.
- Mixing `module` and non-`module` files has rules (a `module` can only import modules); moving
  `Cairn` to the module system is a repo-wide change, so it needs its own PR.
- Not tested: `replay?`/async elaboration modes (`asyncMode := .mainOnly` default) and
  extension behaviour under `lake check`'s re-export.

## For Cairn

- **A (claims DSL):** adopt the module system for `Cairn/Claims/` and anything that
  `meta import`s it, or keep the command in a separate library the app never links. Without one
  of these, the first `import Lean` in an app module makes the host link libLean (101 MB) or fail
  to link with the current `libtool` recipe. Put `initialize` in its own file. Report duplicates
  from a command, not from `addImportedFn`. Name generated declarations after the id.
- **I (TodoMVC):** one root module that imports every claim-bearing module and runs the check.
- **All:** generated declarations are normal Lean, so the axiom audit and `lake check` cover them
  with no special casing.

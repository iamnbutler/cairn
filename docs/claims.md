# Claims

Every thing a person can do in a Cairn app is a **move**: a claim with a durable id (`^N`) and
a proof that what happens meets what the claim says. Flows, invariants, assumptions and places
are claims too. Claims are a language feature: an app module imports the runtime vocabulary and
`meta import`s the commands (see "Linking"), then declares claims with the commands below. An app's `update` is built from its moves and nothing else, so "every behaviour
is a claim" holds by construction, and theorems say so.

Code: `lean/Cairn/Claims/`. Example: `lean/Examples/Counter.lean`. Tests, including one failing
declaration per check: `lean/Cairn/Claims/Tests.lean`.

## Syntax

The command keywords (`move`, `flow`, `invariant`, `assume`, `place`, `retire`) are not reserved
words, so they stay usable as identifiers elsewhere. Clauses are indented under `where`, one per
line; prose is a string, formal parts are `name binders := term`.

### `move`

```lean
move ^2 reset (s : State) "Reset" in ^3 where
  does "Press Reset."
  sees "The count is zero, and Reset disappears."
  enabled := resetEnabled s
  on press
    apply := { s with count := 0 }
    post s' := s'.count = 0 ∧ resetEnabled s' = false
    sound := by intro s _; exact ⟨rfl, rfl⟩
```

- Header: id, Lean name, the state binder `(s : State)`, optionally a key binder `(k : Nat)`
  for keyed controls (one control per item: `^5#12` is the control with key 12), the title, and
  optionally `in ^P`, the place it appears in.
- `does` and `sees` (required): what the person does and what follows.
- `enabled := b` (optional, default always): when the move is available; `s` (and `k`) in scope.
  A `Prop` is decided. This is what presence theorems talk about ("^2's control is on screen
  iff `reset.enabled s`").
- One `on <trigger>` block per kind of action the move answers: `press`, `doublePress`,
  `submit`, `cancel`, `blur`, or `edit (op : TextOp)`, which binds the text operation. A text
  field's claim typically has `on edit` and `on submit`.
- In each block: `apply := newState`, or `emit := (newState, effects)` when it asks the host to
  do something (clipboard, beep); `post s' := P`, the formal statement relating the state before
  (`s`), the key and op if any, and the state after (`s'`); and `sound := proof`.

It generates, in the current namespace:

| Declaration | What it is |
|---|---|
| `reset.enabled : State → Bool` | `enabled` (`State → Nat → Bool` if keyed) |
| `reset.press.apply`, `reset.press.emit` | what the handler does |
| `reset.press.post : State → State → Prop` | the formal statement |
| `reset.press.sound : ∀ s, reset.enabled s = true → reset.press.post s (reset.press.apply s)` | the evidence |
| `reset.info : ClaimInfo` | the human half |
| `reset : Move State` | the move, as `dispatch` uses it |
| `reset.preserves` | turns "every handler keeps `P`", in the move's own terms, into `Move.Preserves reset P` (for invariants) |
| `Cairn.Claims.Issued.«^2»` | a declaration named after the id (see below) |

The `sound` goal is exactly the statement above (with `k` and `op` added for keyed and edit
handlers, and without the `enabled` hypothesis when there is no `enabled`). Inside the proof the
move's namespace is open, so `post`, `apply` and `enabled` refer to this move's.

### `machine`, `moves%`, `claims%`

```lean
def machine : Machine State := { init := {}, moves := moves% }
def claimInfos : List ClaimInfo := claims%
def app : App State := machine.toApp view claimInfos
```

`moves%` is every (non-retired) move declared in the current namespace (or `moves% Some.Ns`);
`claims%` is every claim's `ClaimInfo`, retired ones included, ordered by id. After `moves%`, a
`move` in that namespace is an error (it would never be dispatched); after `claims%`, any claim
is (it would be missing from `App.claims`).

### `flow`

```lean
flow ^5 startOver "Start over" for machine where
  does "Count up, then press Reset."
  sees "The count is back to zero and Reset is gone."
  goal s := s.count = 0 ∧ resetEnabled s = false
  witness press ^1, press ^1, press ^2
```

`witness` is a sequence of actions: `press ^1`, `press ^5#12`, `doublePress ^5#12`,
`edit ^3 (.insert "milk")`, `submit ^3`, `cancel ^…`, `blur ^…`. Each must name a move that
exists and has a handler for that trigger. Generates `startOver.goal`, `startOver.witness`,
`startOver.live : machine.live machine.init witness = true` (every step is answered by an
enabled move, so the path is real and not a run of no-ops), and
`startOver.reaches : goal (machine.run machine.init witness)`. Both default to `by decide`; give
`reaches := proof` to prove it another way.

### `invariant`

```lean
invariant ^6 noPressLeft "Moves never leave a press in progress" for machine where
  does "No move touches the press the spike is tracking."
  holds s := s.pressed = none
  init := rfl
  step := machine.preserves <|
    Move.all_cons (increment.preserves _ fun _ h => h)
      (Move.all_cons (reset.preserves _ fun _ _ h => h) Move.all_nil)
```

`init : holds machine.init`, `step : ∀ s a, holds s → holds (machine.update s a).1`. The pattern
above proves `step` one move at a time: `Machine.preserves` reduces it to `Move.Preserves` for
each move, and each move's generated `preserves` lemma reduces that to one obligation per
handler, stated over its own `apply`. Also generates
`noPressLeft.reachable : ∀ s, machine.Reachable s → holds s`.

### `assume`

```lean
assume ^7 hostClicks "The host reports clicks where they happen" where
  does "The spike host sends a pointer down and up at the logical point the person clicked."
  statement := ∀ m : TextMetrics, m.Valid   -- optional
```

Recorded, never proved: `hostClicks.statement : Prop` is a definition, not an axiom. Theorems
that rely on it take it as a hypothesis, so every use is visible in their statements and the
axiom audit stays clean.

### `place`

```lean
place ^3 window "Counter window" where
  does "The spike's window."
```

A region of the view where moves appear; `in ^P` on moves, flows and places refers to one.

### `retire`

```lean
retire ^9 move "Toggle all (old)" because "Split into ^14 and ^15."
```

The claim is gone; its id stays issued. A tombstone needs the kind, the old title and a reason.

## What each check guarantees

At compile time (in the commands):

| Check | Error |
|---|---|
| An id is issued once in the imported environment | `claim id ^N is already issued: …` |
| Two sibling modules issue the same id | importing both fails: `Cairn.Claims.Issued.^N` is declared twice; `ledger check` also reports it |
| A move says what the person does and what follows | `missing does "…"` / `missing sees "…"` |
| Every claim has a one-line title and a `does` | |
| `in ^P` names an existing, unretired place | `unknown place ^P` / `^P is not a place` |
| A move has at least one handler, at most one per trigger, each with `apply` or `emit`, `post` and `sound` | `missing sound` and so on; a move with no proof does not compile |
| `on edit` binds its text operation; other triggers have none | |
| A keyed move's key binder is a `Nat` | |
| A flow's witness names moves with a handler for the step's trigger | `a witness step names a move, and ^P is not one` |
| A flow's witness is live and reaches its goal | the `decide` (or your proof) fails |
| A retired claim says why | `a retired claim says why it was retired` |
| No move after `moves%`, no claim after `claims%`, in the same namespace | |

Proved about dispatch (`Cairn/Claims/Move.lean`, `Machine.lean`, `Deliver.lean`):

| Theorem | Statement |
|---|---|
| `dispatch_eq` | if the move owning the action's claim has a handler for its trigger and is enabled for its key, `dispatch` is that handler's `apply` |
| `dispatch_post` | …and the new state meets that handler's `post` |
| `dispatch_disabled`, `dispatch_unhandled` | a disabled move, or one without a handler for the trigger, changes nothing and emits nothing |
| `dispatch_unclaimed`, `Machine.update_unclaimed` | **no behaviour without a claim**: if no move owns the action's claim id, the state is unchanged and no effects are emitted |
| `dispatch_effect`, `Machine.update_effect` | **every effect comes from a move**: each emitted effect was emitted by an enabled handler of a move owning the action's claim |
| `dispatch_cases` | dispatch is either the identity with no effects, or exactly one enabled handler |
| `dispatch_preserves`, `dispatch_preserves_moves`, `Machine.preserves` | invariants one move at a time |
| `Invariant.reachable` | an invariant holds in every state reachable from `init` |
| `deliver_effect`, `deliver_unclaimed` | the same two guarantees for a batch of actions through `Runtime.deliver`, so they compose with `Runtime.step_delivers` |

## The ledger

`claims.lock` at the repo root, written by `lake exe ledger update`, never by hand:

```
# id	kind	status	statement	title
2	move	active	5ace86b109a74bf5	Reset
3	place	active	-	Counter window
```

One tab-separated line per id ever issued: kind, `active` or `retired`, a 64-bit FNV-1a hash of
the claim's formal statement (`-` when it has none), and the title.

**The statement hash** covers the claim's kind, a move's triggers and keyedness, and the
definitions that make up its formal statement: a move's `enabled` and each `post`; a flow's
`goal` and `witness`; an invariant's `holds`; an assumption's `statement`. Constants from
Cairn's own modules are followed into their definitions (theorems by statement only, inductive
types by name), so changing a helper a `post` uses changes the hash. Binder names, `apply`, and
proofs don't count, and neither do machines or other claims (each has its own hash), so
changing a move flags that move and not every flow over the machine.

`lake exe ledger check` (in `make check`):

- **fails** when a locked id is gone from the code and the lock doesn't say it's retired; when an
  id is reused for a different kind; when a retired id comes back as a live claim; when the code
  issues an id twice; when a claim has no `does`; and when the code has an id the lock doesn't
  (run `lake exe ledger update` and commit `claims.lock`);
- **warns** when a claim's statement hash or title changed: "meaning changed: give it a new id
  or `lake exe ledger update --accept`".

`lake exe ledger update [--accept]` appends new ids, marks ids retired in the code as retired,
and with `--accept` records changed hashes and titles. It never removes a line and refuses to
write while `check` has errors other than new ids. Both take `--lock PATH` and `--root MODULE`
(default roots `Cairn` and `Examples`: a claim in a module neither imports is invisible to the
ledger, so every app module must be reachable from `Examples.lean`).

## Export for the map

`lake exe claims Examples.Counter` (any modules; submodules included) prints JSON:

```json
{"modules": ["Examples.Counter"],
 "claims": [{"id": 2, "ref": "^2", "kind": "move", "title": "Reset",
   "does": "Press Reset.", "sees": "The count is zero, and Reset disappears.",
   "place": 3, "retired": null, "module": "Examples.Counter", "decl": "Examples.Counter.reset",
   "statement": "5ace86b109a74bf5",
   "statementDecls": ["Examples.Counter.reset.enabled", "Examples.Counter.reset.press.post"],
   "triggers": ["press"], "keyed": false, "passes": [], "machine": null,
   "evidence": [{"role": "sound press", "theorem": "Examples.Counter.reset.press.sound",
                 "proved": true, "extraAxioms": []}]}]}
```

`passes` is a flow's path through move ids; `machine` is the machine a flow or invariant is
stated against. Evidence roles: `sound <trigger>` (moves), `live` and `reaches` (flows),
`init`, `step` and `reachable` (invariants). `proved` is true when the theorem depends on no
axioms beyond `propext`, `Classical.choice` and `Quot.sound`.

## Linking: the commands stay out of the host

The commands are elaborators, so `Cairn.Claims.Elab` (and `Registry`) import `Lean`. Linking
`Lean` into the host would make it about 100 MB (research/lean/05), and with the host's link
recipe (`libInit` and `libleanrt`, no `libLean`) it doesn't link at all. A plain `import` of the
commands also leaks in subtler ways: the importing module's initializer calls `lean_initialize`,
and the compiler reuses specializations compiled inside `Lean` (Counter's `Option` `==` became
a call into `Lean.Meta.Sym.Simp`).

So apps use the module system. An app file is a `module` that imports the runtime vocabulary
and only `meta`-imports the commands:

```lean
module

public import Cairn.Claims.Core     -- Move, Machine, Flow, …: pure, core-only
meta import Cairn.Claims.Elab       -- the commands, at compile time only
public import Cairn.Spike.Frame

@[expose] public section            -- importers' proofs can unfold the app's definitions
```

With that, the app's compiled code and its `runtime_initialize_*` never touch `Lean` or the
commands; the host calls `runtime_initialize_cairn_Examples` (host/Sources/CLean). The
generated declarations are `public` and, in a module, `@[expose]`, so other modules' proofs
can unfold them. `Cairn.Claims` is an umbrella (`Core` plus `meta import Elab`) for non-module
files such as the tests.

One wrinkle remains. Each app object file also contains its full `initialize_*` and
`meta_initialize_*`, which call the commands' initializers, and the linker resolves every
symbol in an object it links. `lean/c/claims_meta.c` (in the `Examples` library's
`moreLinkObjs`) defines those two initializers **weakly**; they return an error if called, and
the host never calls them. Lake executables that link the real module (`ledger`, `claims`,
`bench`) get its strong definitions. A new app library needs the same `moreLinkObjs`.

Consequences of the module system for the modules an app imports: every one of them is a
`module` (a module can only import modules), so `Cairn.Claim`, `Input`, `Geometry`,
`Text.Metrics`, `UI.Node`, `App`, `Spike.Bytes`, `Spike.Frame` and `Claims.Move`/`Machine`/`Core`
are modules with `@[expose] public section`. Non-module files (`Cairn.Runtime`, `Cairn.Layout`,
…) import them unchanged and see everything. `#guard` does not work in a module without
`meta`-importing what it evaluates, so checks there are `example … := by decide`.

Measured (`make check`, Debug): `libcairn_Examples.a` 48 KB, `libcairn_lean.a` 18.5 MB (of
which `libInit` is 15 MB); the `CairnCounter` binary contains no symbols from `libLean`.

## What is not enforced, and why

- **Ids are global only as far as imports reach.** Two modules that are never imported together
  can issue the same id; the ledger catches it because it imports everything reachable from
  `Cairn` and `Examples`, and the `Issued.«^N»` declarations make importing both fail.
- **"Meaning changed" is a warning, not an error.** The hash can't tell a refactor from a change
  of meaning; a person decides, and `--accept` records the decision in the diff.
- **Prose isn't checked against the formal statement.** `does`/`sees` are for reviewers; nothing
  proves that `post` says what `sees` says.
- **`post` constrains the state, not the effects.** Effects come only from moves (proved), but a
  move's `post` says nothing about which effects it emits.
- **Presence and pressability are not generated.** They depend on the view and layout; apps
  prove them per move (`Examples.Counter.reset_present_iff_enabled`).
- **`claims%` is per namespace.** An app spread over several namespaces collects each and
  concatenates.
- **Unkeyed moves ignore the key.** `^1#7` reaches an unkeyed `^1` as if it were `^1`; the view
  never produces such a control, but dispatch doesn't reject it.
- **The ledger reads built `.olean` files**, so `make ledger` builds first; `claims.lock` is only
  as current as the last `ledger update`.

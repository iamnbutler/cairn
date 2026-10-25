---
title: Claims
nav: Claims
eyebrow: Reference
lede: Every claim kind, its clauses, what it generates, and what the build checks.
---

A claim is a statement about the app with a durable id, written `^N`. Claims are a language
feature: the commands below are Lean commands, and an app's `update` is built from its moves and
nothing else. For an introduction, read [Moves and flows](/docs/guide/moves-and-flows/).

## Using the commands

The commands need Lean's compiler, which an app must not link (it would make the app about 100 MB).
So an app file is a Lean `module` that imports the runtime and only `meta import`s the commands,
which makes them available at compile time and absent from the binary:

- `public import Cairn.Claims.Core`, the claim types;
- `meta import Cairn.Claims.Elab`, the commands;
- `public import Cairn.App`, and whatever else the app uses;
- `@[expose] public section`, so other modules' proofs can unfold the app's definitions.

The keywords (`move`, `flow`, `invariant`, `assume`, `place`, `retire`) aren't reserved words, so
they stay usable as names elsewhere. Clauses are indented under `where`, one per line.

## `move`

One thing a person can do.

<bongo:include src="lean/Examples/Counter.lean#counter-reset" />

- **Header:** the id, a Lean name, the state binder `(s : State)`, optionally a key binder
  `(k : Nat)` for a keyed move (one control per item: `^5#12` is the control with key 12), the
  title, and optionally `in ^P`, the place it appears in.
- **`does`, `sees`** (required): what the person does, and what follows.
- **`enabled := b`** (optional; always, by default): when the move is available. A `Prop` is
  decided. Presence theorems are stated against it.
- **`on <trigger>`**, one block per trigger the move answers: `press`, `doublePress`, `submit`,
  `cancel`, `blur`, or `edit (op : TextOp)`, which binds the text operation.
- In each block: **`apply := s'`**, or **`emit := (s', effects)`** when it asks the host to do
  something; **`post s' := P`**, relating the state before (`s`), the key and operation if any,
  and the state after (`s'`); and **`sound := proof`**.

The `sound` goal is `∀ s, enabled s = true → post s (apply s)`, with the key and operation added
for keyed and edit handlers, and without the `enabled` hypothesis when there's no `enabled`.

For a move named `reset`, the command generates `reset.enabled`, `reset.press.apply` (and `emit`),
`reset.press.post`, `reset.press.sound`, `reset.info` (the human half), `reset : Move State`, and
`reset.preserves`, which turns "every handler keeps `P`" into what an invariant's proof needs.

A keyed move, and a field's move with `edit` and `submit`:

<bongo:include src="lean/Examples/Basics.lean#basics-toggle" />

<bongo:include src="lean/Examples/Basics.lean#basics-type-item" />

## `machine`, `moves%`, `claims%`

`moves%` is every move declared in the current namespace, and `claims%` every claim's `ClaimInfo`,
retired ones included, in id order. A move declared after `moves%`, or a claim after `claims%`, in
the same namespace is an error, because it would be silently left out.

<bongo:include src="lean/Examples/Counter.lean#counter-machine" />

<bongo:include src="lean/Examples/Counter.lean#counter-claims" />

`machine.toApp surfaces claims` makes the app; an optional last argument names the control
focused at launch. A machine can also have a `receive`, for messages from the outside world
([effects](/docs/guide/effects/)).

## `flow`

A goal reachable through moves, with a checked path.

<bongo:include src="lean/Examples/Counter.lean#counter-flows" />

`witness` is a sequence of actions, each naming a move with a handler for that trigger:
`press ^1`, `press ^5#12`, `doublePress ^5#12`, `edit ^3 (.insert "milk")`, `edit ^3 .selectAll`,
`submit ^3`, `cancel ^3`, `blur ^3`. The command generates `live` (every step is answered by an
enabled move) and `reaches` (the end state meets `goal`). Both are proved by `decide` unless you
give `reaches := proof`.

## `invariant`

A property that holds in every reachable state.

<bongo:include src="lean/Examples/Basics.lean#basics-invariant" />

- **`holds s := P`**: the property.
- **`init`**: a proof that it holds for the machine's starting state.
- **`step`**: a proof that every action keeps it. `machine.preserves` with `Move.all_cons` splits
  it one move at a time.
- **`receive`**: for a machine that hears the outside world, a proof that every message keeps it
  too. Optional, and proved for you, when the machine ignores the world.

Generates `reachable` and `reachableAll` (it holds in every state reachable by actions, and by
actions and messages), and, when the property is decidable, `check`, a runnable version the fuzzer
calls after every step.

## `assume`

Something the proofs rely on but can't prove.

<bongo:include src="lean/Examples/Counter.lean#counter-assume" />

Optional clauses: `statement := P`, a formal statement (a definition, never an axiom: theorems
that rely on it take it as a hypothesis), and `check "name"`, naming the fuzz check that gathers
evidence for it. See [the trusted base](/docs/internals/trusted-base/).

## `place`

A region of the view where moves appear: a window, a menu, a panel. Moves, flows and other places
refer to it with `in ^P`.

<bongo:include src="lean/Examples/Counter.lean#counter-place" />

## `retire`

A tombstone. The claim is gone; its id stays issued. It needs the old kind, the old title, and a
reason.

Retiring a released claim is a breaking change. A claim the last release had active can be
retired only in a new major version, or a new minor version while at 0.x: Cairn at 0.1.2 can
retire one in 0.2.0, not in 0.1.3. `lake exe ledger check` finds the last release from the git
tags and fails otherwise. A claim added since then can go in any version.

<bongo:include src="lean/Examples/Counter.lean#counter-retire" />

## What the build checks

At compile time, in the commands:

| Check | Error |
|---|---|
| an id is issued once among everything imported | `claim id cairn^N is already issued: …` |
| a move says what the person does and what follows | `missing does "…"`, `missing sees "…"` |
| `in ^P` names a place that exists and isn't retired | `unknown place ^P`, `^P is not a place` |
| a move has at least one handler, at most one per trigger, each with `apply` or `emit`, `post` and `sound` | `missing sound`, and so on |
| a flow's witness names moves with a handler for each step's trigger | `a witness step names a move, and ^P is not one` |
| a flow's witness is live and reaches its goal | the `decide`, or your proof, fails |
| a retired claim says why | `a retired claim says why it was retired` |

Proved once, in the framework, for every app:

- **No behaviour without a claim.** An action whose control no move owns changes nothing and
  emits nothing (`update_unclaimed`).
- **Every effect comes from a move**: each effect was emitted by an enabled handler of the move
  that owns the action (`update_effect`).
- A disabled move, or one without a handler for the trigger, changes nothing.
- An invariant holds in every state the running app reaches, whatever events arrive
  (`steps_reachableAll`).

## Scopes

Claim ids are scoped by package. Cairn's own are `cairn^N`. An app in its own repository sets
its scope once, in its lakefile's `cairn.claims.scope` option (`cairn new` does it for you), and
its `^311` is then `yap^311`. In code, a bare `^N` always means the module's own scope: `in ^P`
and a flow's `witness` find only claims of that scope. Messages name claims in full, and each
package keeps its own `claims.lock`. Frames and the running app still carry bare numbers, since
an app's controls are always its own moves.

The scope defaults to `cairn`, so an app that forgets to set it collides with Cairn's ids at
compile time instead of shipping with them. When claims move with an app to its own package,
the lock they left marks them `moved:<scope>` (Yap's are `moved:yap`), so the ids stay issued
there and can't come back.

## The ledger

`claims.lock`, at the root of the package, has one line per id ever issued: its kind, its status
(`active`, `retired`, or `moved:<scope>` for an id that left with an app), a hash of its formal
statement, and its title. Tools write it; never edit it by
hand. `lake exe ledger check` runs in `make check`:

- it **fails** when an id in the lock is gone from the code without being retired, an id is
  reused for another kind, a retired id comes back, the code issues an id twice, a claim has no
  `does`, or the code has an id the lock doesn't;
- it **warns** when a claim's statement or title changed. A new meaning needs a new id; to keep
  the id, run `lake exe ledger update --accept`, and the change shows in review.

`lake exe ledger update` appends new ids and marks retired ones. It never removes a line.

The hash covers the claim's formal statement and the definitions it uses, followed into Cairn's
own modules. Names of bound variables, `apply` and proofs don't count, so refactoring a handler
doesn't flag the claim, and changing what it promises does.

## What isn't checked

- **Prose.** Nothing proves that `sees` says what `post` says. That is what review is for.
- **Effects in `post`.** A move's `post` constrains the state, not which effects it emits.
- **Presence and pressability** aren't generated: they depend on the view, and each app proves
  them ([Proving a claim](/docs/guide/proving/)).
- **Ids are unique only as far as imports reach.** Each package's ledger imports everything in
  that package, which is how it catches two of its apps using the same id. Two packages may both
  issue `^301`, because their scopes differ.

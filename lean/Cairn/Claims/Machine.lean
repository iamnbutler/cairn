module

public import Cairn.Claims.Move
public import Cairn.App

/-! A machine is an initial state and the moves that act on it. Its `update` is derived from the
moves by `dispatch`, so it inherits every guarantee in `Cairn.Claims.Move`. Flows and invariants
are stated against a machine.

A machine may also hear the outside world (docs/effects.md): `receive` takes the clock, timers,
replies and subscription events. An invariant must be kept by `receive` as well as by every
move, so it holds over any interleaving of a person's actions and the host's messages
(`Invariant.reachableAll`), and through the runtime (`Cairn.Claims.steps_reachableAll`).

Pure, and linked into the host, like `Cairn.Claims.Move`. -/

@[expose] public section


namespace Cairn.Claims

structure Machine (S : Type) where
  init : S
  moves : List (Move S)
  /-- What the outside world does to the state (`App.receive`); by default nothing. -/
  receive : S → Msg → S × List Effect := fun s _ => (s, [])

namespace Machine
variable {S : Type} (M : Machine S)

/-- The update an app gets from its moves. -/
def update (s : S) (a : Action) : S × List Effect := dispatch M.moves s a

/-- The state after a sequence of actions. -/
def run (s : S) (as : List Action) : S := as.foldl (fun s a => (M.update s a).1) s

/-- Every action in the sequence is answered by an enabled move, in turn. -/
def live : S → List Action → Bool
  | _, [] => true
  | s, a :: as => accepts M.moves s a && live (M.update s a).1 as

/-- States reachable from `init`. -/
def Reachable (s : S) : Prop := ∃ as, s = M.run M.init as

/-- One input: a person's action (`update`) or a message from the world (`receive`). -/
def feed (s : S) : Action ⊕ Msg → S
  | .inl a => (M.update s a).1
  | .inr m => (M.receive s m).1

/-- The state after a sequence of actions and messages. -/
def runAll (s : S) (xs : List (Action ⊕ Msg)) : S := xs.foldl M.feed s

/-- States reachable from `init` by actions and messages. -/
def ReachableAll (s : S) : Prop := ∃ xs, s = M.runAll M.init xs

theorem Reachable.all {s : S} (h : M.Reachable s) : M.ReachableAll s := by
  obtain ⟨as, rfl⟩ := h
  refine ⟨as.map .inl, ?_⟩
  unfold run runAll
  generalize M.init = s0
  induction as generalizing s0 with
  | nil => rfl
  | cons a as ih => exact ih _

/-- An app whose update is this machine's. -/
def toApp (view : S → UI → Node) (claims : List ClaimInfo)
    (initFocus : Option ControlRef := none) : App S where
  init := M.init
  view := view
  update := M.update
  receive := M.receive
  claims := claims
  initFocus := initFocus

@[simp] theorem run_nil (s : S) : M.run s [] = s := rfl

@[simp] theorem run_cons (s : S) (a : Action) (as : List Action) :
    M.run s (a :: as) = M.run (M.update s a).1 as := rfl

theorem run_append (s : S) (as bs : List Action) :
    M.run s (as ++ bs) = M.run (M.run s as) bs := by
  simp [run, List.foldl_append]

/-- **No behaviour without a claim**, for a machine. -/
theorem update_unclaimed {s : S} {a : Action} (h : ∀ m ∈ M.moves, m.id ≠ a.claim) :
    M.update s a = (s, []) := dispatch_unclaimed h

/-- **Every effect comes from a move**, for a machine. -/
theorem update_effect {s : S} {a : Action} {e : Effect} (he : e ∈ (M.update s a).2) :
    ∃ m ∈ M.moves, ∃ h ∈ m.handlers, m.id = a.claim ∧ h.trigger = a.trigger ∧
      m.enabled s a.key = true ∧ e ∈ (h.apply s a).2 := dispatch_effect he

/-- **Invariants one move at a time**, for a machine: if every move keeps `P`, so does every
update. Pair with the `name.preserves` lemma each `move` generates. -/
theorem preserves {P : S → Prop} (hm : ∀ m ∈ M.moves, m.Preserves P) :
    ∀ s a, P s → P (M.update s a).1 :=
  fun s a hs => dispatch_preserves_moves hm s a hs

/-- A property true at `s` and preserved by every update holds after any sequence. -/
theorem run_preserves (P : S → Prop) (step : ∀ s a, P s → P (M.update s a).1) :
    ∀ (as : List Action) (s : S), P s → P (M.run s as)
  | [], _, h => h
  | a :: as, s, h => run_preserves P step as _ (step s a h)

/-- A property true at `s` and kept by every update and every message holds after any sequence
of both. -/
theorem runAll_preserves (P : S → Prop) (step : ∀ s a, P s → P (M.update s a).1)
    (recv : ∀ s m, P s → P (M.receive s m).1) :
    ∀ (xs : List (Action ⊕ Msg)) (s : S), P s → P (M.runAll s xs)
  | [], _, h => h
  | .inl a :: xs, s, h => runAll_preserves P step recv xs _ (step s a h)
  | .inr m :: xs, s, h => runAll_preserves P step recv xs _ (recv s m h)

end Machine

/-! ### Claims other than moves

Each structure pairs the claim's human half (`ClaimInfo`) with its formal half. The commands in
`Cairn.Claims` build them; the evidence is in the fields' proofs. -/

/-- A goal reachable from the machine's initial state, with a witness: a sequence of actions,
each answered by an enabled move, after which the goal holds. -/
structure Flow {S : Type} (M : Machine S) where
  info : ClaimInfo
  goal : S → Prop
  witness : List Action
  live : M.live M.init witness = true
  reaches : goal (M.run M.init witness)

/-- A property of every reachable state: true initially, preserved by every update (so by
every move, see `Machine.update`) and by every message from the world (`Machine.receive`; for a
machine that ignores the world this is immediate). -/
structure Invariant {S : Type} (M : Machine S) where
  info : ClaimInfo
  holds : S → Prop
  init : holds M.init
  step : ∀ s a, holds s → holds (M.update s a).1
  recv : ∀ s m, holds s → holds (M.receive s m).1

theorem Invariant.reachable {S : Type} {M : Machine S} (i : Invariant M) {s : S}
    (h : M.Reachable s) : i.holds s := by
  obtain ⟨as, rfl⟩ := h
  exact M.run_preserves i.holds i.step as M.init i.init

theorem Invariant.reachableAll {S : Type} {M : Machine S} (i : Invariant M) {s : S}
    (h : M.ReachableAll s) : i.holds s := by
  obtain ⟨xs, rfl⟩ := h
  exact M.runAll_preserves i.holds i.step i.recv xs M.init i.init

/-- Something taken as given about the world. `statement` is recorded, never proved: theorems
that rely on it take it as a hypothesis, so it never becomes an axiom. -/
structure Assumption where
  info : ClaimInfo
  statement : Prop

/-- A region of the view where moves appear. -/
structure Place where
  info : ClaimInfo

/-! ### Checks on small values -/

section Examples

private def tick : Move Nat where
  info := { id := 1, kind := .move, title := "Tick" }
  enabled _ _ := true
  handlers := [Handler.simple .press (fun n _ => (n + 1, [])) (fun n _ n' => n' = n + 1)
    (fun _ _ _ => rfl)]

private def m : Machine Nat := { init := 0, moves := [tick] }

example : (m.update 4 (.press { claim := 1 })).1 = 5 := by decide
example : (m.update 4 (.press { claim := 2 })).1 = 4 := by decide
example : (m.update 4 (.doublePress { claim := 1 })).1 = 4 := by decide
example : m.run 0 [.press { claim := 1 }, .press { claim := 1 }] = 2 := by decide
example : (m.live 0 [.press { claim := 1 }] && !m.live 0 [.press { claim := 2 }]) = true := by
  decide

example : (m.update 4 (.submit { claim := 9 })) = (4, []) :=
  m.update_unclaimed (by simp [m, tick, Move.id, Action.claim, Action.control])

end Examples

end Cairn.Claims

namespace Cairn.Claims

/-- The state type of a machine. The flow and invariant commands use it to type the bodies they
are given without asking for the state type again. -/
abbrev StateOf {S : Type} (_ : Machine S) : Type := S

end Cairn.Claims

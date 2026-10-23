import Cairn.Claims.Machine
import Cairn.Runtime.Step
import Cairn.Runtime.Proofs

/-! The claim guarantees, carried through the runtime.

`Cairn.Runtime.step_delivers` says a runtime step passes `App.update` exactly the routed
actions, via `Runtime.deliver`. For an app whose update is a machine's, the lemmas here say what
that means for a whole batch of actions: every effect came from an enabled move handler answering
one of the actions, and a batch that names no move's claim changes nothing. -/

namespace Cairn.Claims
open Cairn.Runtime

variable {S : Type} (M : Machine S)

private theorem deliver_go_effect (acts : List Action) :
    ∀ (st : S) (effs : List Effect) (e : Effect),
      e ∈ (acts.foldl (fun (p : S × List Effect) a =>
        let (st', e) := M.update p.1 a; (st', p.2 ++ e)) (st, effs)).2 →
      e ∈ effs ∨ ∃ a ∈ acts, ∃ s, ∃ m ∈ M.moves, ∃ h ∈ m.handlers, m.id = a.claim ∧
        h.trigger = a.trigger ∧ m.enabled s a.key = true ∧ e ∈ (h.apply s a).2 := by
  induction acts with
  | nil => intro st effs e he; exact Or.inl he
  | cons a as ih =>
    intro st effs e he
    simp only [List.foldl_cons] at he
    rcases ih _ _ e he with h | ⟨b, hb, s, m, hm, h, hh, rest⟩
    · rcases List.mem_append.mp h with h | h
      · exact Or.inl h
      · obtain ⟨m, hm, h, hh, r⟩ := M.update_effect h
        exact Or.inr ⟨a, List.mem_cons_self .., st, m, hm, h, hh, r⟩
    · exact Or.inr ⟨b, List.mem_cons_of_mem _ hb, s, m, hm, h, hh, rest⟩

/-- **Every effect the runtime runs comes from a move.** Each effect of delivering a batch of
actions to a machine was emitted by an enabled handler of one of its moves, answering one of
the actions (and owning its claim). -/
theorem deliver_effect {st : S} {acts : List Action} {e : Effect}
    (he : e ∈ (deliver M.update st acts).2) :
    ∃ a ∈ acts, ∃ s, ∃ m ∈ M.moves, ∃ h ∈ m.handlers, m.id = a.claim ∧
      h.trigger = a.trigger ∧ m.enabled s a.key = true ∧ e ∈ (h.apply s a).2 := by
  rcases deliver_go_effect M acts st [] e he with h | h
  · simp at h
  · exact h

private theorem deliver_go_unclaimed (acts : List Action)
    (h : ∀ a ∈ acts, ∀ m ∈ M.moves, m.id ≠ a.claim) :
    ∀ (st : S) (effs : List Effect),
      acts.foldl (fun (p : S × List Effect) a =>
        let (st', e) := M.update p.1 a; (st', p.2 ++ e)) (st, effs) = (st, effs) := by
  induction acts with
  | nil => intro st effs; rfl
  | cons a as ih =>
    intro st effs
    simp only [List.foldl_cons]
    rw [M.update_unclaimed (h a (List.mem_cons_self ..))]
    simp only [List.append_nil]
    exact ih (fun b hb => h b (List.mem_cons_of_mem _ hb)) st effs

/-- **No behaviour without a claim**, through the runtime: a batch of actions none of which
names a move's claim leaves the app state alone and runs no effects. -/
theorem deliver_unclaimed {st : S} {acts : List Action}
    (h : ∀ a ∈ acts, ∀ m ∈ M.moves, m.id ≠ a.claim) : deliver M.update st acts = (st, []) :=
  deliver_go_unclaimed M acts h st []

private theorem deliver_go_run (acts : List Action) :
    ∀ (st : S) (effs : List Effect),
      (acts.foldl (fun (p : S × List Effect) a =>
        let (st', e) := M.update p.1 a; (st', p.2 ++ e)) (st, effs)).1 = M.run st acts := by
  induction acts with
  | nil => intro st effs; rfl
  | cons a as ih => intro st effs; simp only [List.foldl_cons]; exact ih _ _

/-- Delivering a batch of actions to a machine runs them in order. -/
theorem deliver_run (st : S) (acts : List Action) : (deliver M.update st acts).1 = M.run st acts :=
  deliver_go_run M acts st []

/-- **Invariants hold on screen.** In an app whose update is a machine's, the app state of every
runtime state reached from `start` by events is reachable in the machine, so every invariant
(`Invariant.reachable`) holds in it. -/
theorem steps_reachable (view : S → UI → Node) (claims : List ClaimInfo) (cfg : Config)
    (size : Size) (scale : Nat) (es : List Event) (initFocus : Option ControlRef := none) :
    M.Reachable (steps (M.toApp view claims initFocus) cfg
      (start (M.toApp view claims initFocus) cfg size scale) es).1.app := by
  unfold steps
  suffices ∀ (es : List Event) (acc : State S × List Effect), M.Reachable acc.1.app →
      M.Reachable (es.foldl (fun (s, effs) e =>
        let (s', e') := step (M.toApp view claims initFocus) cfg s e; (s', effs ++ e')) acc).1.app from
    this es _ ⟨[], rfl⟩
  intro es
  induction es with
  | nil => intro acc h; exact h
  | cons e es ih =>
    intro acc h
    apply ih
    obtain ⟨as, has⟩ := h
    have hd := congrArg Prod.fst (step_delivers (M.toApp view claims initFocus) cfg acc.1 e)
    refine ⟨as ++ (route cfg.metrics acc.1 e).2, ?_⟩
    simp only at hd ⊢
    rw [hd, M.run_append, ← has]
    exact deliver_run M _ _

end Cairn.Claims

module

public import Cairn.Input
public import Cairn.Claim

/-! Moves and the update they induce.

A **move** is one thing a person can do. It owns a claim id and answers the actions that name a
control of that claim (`^5`, or `^5#12` for the control with key 12). For each kind of action it
answers (`press`, `edit`, …) it has a **handler**: what happens (`apply`), what must follow
(`post`, a formal statement relating the state before and after), and a proof that the first
meets the second whenever the move is enabled.

`dispatch` is the only way a list of moves becomes an `update`, so an app cannot react to input
except through a move. The theorems at the end say so formally.

This module is pure and imports nothing from `Lean`: it is linked into the host. The commands
that build moves live in `Cairn.Claims` (compile time only). -/

@[expose] public section


namespace Cairn

/-- The kind of an action, without its payload. -/
inductive Trigger where
  | press | doublePress | edit | submit | cancel | blur | appear
deriving Repr, DecidableEq, Inhabited

def Trigger.name : Trigger → String
  | .press => "press" | .doublePress => "doublePress" | .edit => "edit"
  | .submit => "submit" | .cancel => "cancel" | .blur => "blur" | .appear => "appear"

def Action.trigger : Action → Trigger
  | .press _ => .press | .doublePress _ => .doublePress | .edit _ _ => .edit
  | .submit _ => .submit | .cancel _ => .cancel | .blur _ => .blur | .appear _ => .appear

/-- The claim an action names. -/
def Action.claim (a : Action) : ClaimId := a.control.claim

/-- The key of the control an action names (`12` in `^5#12`, `0` when there is one control). -/
def Action.key (a : Action) : Nat := a.control.key

/-- The text operation an `edit` carries. -/
def Action.op? : Action → Option TextOp
  | .edit _ op => some op
  | _ => none

namespace Claims

/-- How a move answers one kind of action. `post` relates the state before, the action, and the
state after; `sound` is the proof that `apply` meets `post` whenever the move is enabled for the
action's key. Built from the per-trigger forms below, so `apply` and `post` only ever look at the
key (and the text op for `edit`). -/
structure Handler (S : Type) (enabled : S → Nat → Bool) where
  trigger : Trigger
  apply : S → Action → S × List Effect
  post : S → Action → S → Prop
  sound : ∀ s a, a.trigger = trigger → enabled s a.key = true → post s a (apply s a).1

/-- A handler for an action that carries only its control (`press`, `doublePress`, `submit`,
`cancel`, `blur`, `appear`). -/
def Handler.simple {S : Type} {enabled : S → Nat → Bool} (t : Trigger)
    (apply : S → Nat → S × List Effect) (post : S → Nat → S → Prop)
    (sound : ∀ s k, enabled s k = true → post s k (apply s k).1) : Handler S enabled where
  trigger := t
  apply s a := apply s a.key
  post s a s' := post s a.key s'
  sound s a _ h := sound s a.key h

/-- A handler for `edit`: `apply` and `post` also see the text operation. -/
def Handler.edit {S : Type} {enabled : S → Nat → Bool}
    (apply : S → Nat → TextOp → S × List Effect) (post : S → Nat → TextOp → S → Prop)
    (sound : ∀ s k op, enabled s k = true → post s k op (apply s k op).1) :
    Handler S enabled where
  trigger := .edit
  apply s a := match a with
    | .edit c op => apply s c.key op
    | _ => (s, [])
  post s a s' := match a with
    | .edit c op => post s c.key op s'
    | _ => True
  sound s a ht h := by
    cases a with
    | edit c op => exact sound s c.key op h
    | _ => simp [Action.trigger] at ht

/-- One thing a person can do: a claim, when it is available (`enabled`, per control key), and a
handler for each kind of action it answers. -/
structure Move (S : Type) where
  info : ClaimInfo
  enabled : S → Nat → Bool
  handlers : List (Handler S enabled)

def Move.id {S : Type} (m : Move S) : ClaimId := m.info.id

/-- The triggers a move answers. -/
def Move.triggers {S : Type} (m : Move S) : List Trigger := m.handlers.map (·.trigger)

/-- The handler a move has for a trigger (the first, though the `move` command allows only one
per trigger). -/
def Move.handler? {S : Type} (m : Move S) (t : Trigger) : Option (Handler S m.enabled) :=
  m.handlers.find? (·.trigger == t)

/-- The move a list of moves has for a claim id. -/
def find? {S : Type} (moves : List (Move S)) (id : ClaimId) : Option (Move S) :=
  moves.find? (·.id == id)

/-- Answer an action with the move that owns its claim, if that move has a handler for it and is
enabled for the action's key. Anything else leaves the state alone and emits nothing. -/
def dispatch {S : Type} (moves : List (Move S)) (s : S) (a : Action) : S × List Effect :=
  match find? moves a.claim with
  | none => (s, [])
  | some m =>
    match m.handler? a.trigger with
    | none => (s, [])
    | some h => if m.enabled s a.key then h.apply s a else (s, [])

/-- Whether some move answers the action: it owns the claim, has a handler for the trigger, and
is enabled. Flows use this to check every step of a witness does something. -/
def accepts {S : Type} (moves : List (Move S)) (s : S) (a : Action) : Bool :=
  match find? moves a.claim with
  | none => false
  | some m => (m.handler? a.trigger).isSome && m.enabled s a.key

/-! ### What dispatch guarantees -/

section
variable {S : Type}

theorem find?_some {moves : List (Move S)} {id : ClaimId} {m : Move S}
    (h : find? moves id = some m) : m ∈ moves ∧ m.id = id := by
  unfold find? at h
  have hm := List.mem_of_find?_eq_some h
  have hp := List.find?_some h
  exact ⟨hm, by simpa using hp⟩

theorem find?_none {moves : List (Move S)} {id : ClaimId} :
    find? moves id = none ↔ ∀ m ∈ moves, m.id ≠ id := by
  unfold find?
  simp [List.find?_eq_none]

theorem handler?_some {m : Move S} {t : Trigger} {h : Handler S m.enabled}
    (e : m.handler? t = some h) : h ∈ m.handlers ∧ h.trigger = t := by
  unfold Move.handler? at e
  exact ⟨List.mem_of_find?_eq_some e, by simpa using List.find?_some e⟩

/-- **Dispatch.** When the move found for the action's claim has a handler for its trigger and
is enabled, `dispatch` is that handler's `apply`. -/
theorem dispatch_eq {moves : List (Move S)} {s : S} {a : Action} {m : Move S}
    {h : Handler S m.enabled} (hm : find? moves a.claim = some m)
    (hh : m.handler? a.trigger = some h) (he : m.enabled s a.key = true) :
    dispatch moves s a = h.apply s a := by
  simp [dispatch, hm, hh, he]

/-- A disabled move leaves the state unchanged and emits nothing. -/
theorem dispatch_disabled {moves : List (Move S)} {s : S} {a : Action} {m : Move S}
    (hm : find? moves a.claim = some m) (he : m.enabled s a.key = false) :
    dispatch moves s a = (s, []) := by
  unfold dispatch
  rw [hm]
  simp only
  split <;> simp [he]

/-- A move with no handler for the action's trigger leaves the state unchanged. -/
theorem dispatch_unhandled {moves : List (Move S)} {s : S} {a : Action} {m : Move S}
    (hm : find? moves a.claim = some m) (hh : m.handler? a.trigger = none) :
    dispatch moves s a = (s, []) := by
  simp [dispatch, hm, hh]

/-- **No behaviour without a claim.** If no move owns the action's claim id, the state is
unchanged and no effects are emitted. -/
theorem dispatch_unclaimed {moves : List (Move S)} {s : S} {a : Action}
    (h : ∀ m ∈ moves, m.id ≠ a.claim) : dispatch moves s a = (s, []) := by
  have : find? moves a.claim = none := find?_none.mpr h
  simp [dispatch, this]

/-- Dispatch either leaves the state alone and emits nothing, or it is exactly one enabled
handler of one move in the list that owns the action's claim and answers its trigger. -/
theorem dispatch_cases (moves : List (Move S)) (s : S) (a : Action) :
    dispatch moves s a = (s, []) ∨
    ∃ m ∈ moves, ∃ h ∈ m.handlers, m.id = a.claim ∧ h.trigger = a.trigger ∧
      m.enabled s a.key = true ∧ dispatch moves s a = h.apply s a := by
  unfold dispatch
  split
  · exact Or.inl rfl
  · rename_i m hm
    split
    · exact Or.inl rfl
    · rename_i h hh
      by_cases he : m.enabled s a.key = true
      · obtain ⟨mm, mi⟩ := find?_some hm
        obtain ⟨hmem, ht⟩ := handler?_some hh
        exact Or.inr ⟨m, mm, h, hmem, mi, ht, he, by simp [he]⟩
      · exact Or.inl (by simp [he])

/-- **Every effect comes from a move.** Each effect `dispatch` emits was emitted by the `apply`
of an enabled handler of a move in the list that owns the action's claim. -/
theorem dispatch_effect {moves : List (Move S)} {s : S} {a : Action} {e : Effect}
    (he : e ∈ (dispatch moves s a).2) :
    ∃ m ∈ moves, ∃ h ∈ m.handlers, m.id = a.claim ∧ h.trigger = a.trigger ∧
      m.enabled s a.key = true ∧ e ∈ (h.apply s a).2 := by
  rcases dispatch_cases moves s a with h0 | ⟨m, mm, h, hm, mi, ht, en, eq⟩
  · rw [h0] at he; simp at he
  · exact ⟨m, mm, h, hm, mi, ht, en, eq ▸ he⟩

/-- **Moves keep their promises.** When dispatch runs an enabled handler, the new state meets
that handler's `post`. -/
theorem dispatch_post {moves : List (Move S)} {s : S} {a : Action} {m : Move S}
    {h : Handler S m.enabled} (hm : find? moves a.claim = some m)
    (hh : m.handler? a.trigger = some h) (he : m.enabled s a.key = true) :
    h.post s a (dispatch moves s a).1 := by
  rw [dispatch_eq hm hh he]
  exact h.sound s a (handler?_some hh).2.symm he

/-- `accepts` is exactly "dispatch runs a handler". -/
theorem accepts_iff {moves : List (Move S)} {s : S} {a : Action} :
    accepts moves s a = true ↔ ∃ m h, find? moves a.claim = some m ∧
      m.handler? a.trigger = some h ∧ m.enabled s a.key = true := by
  unfold accepts
  split
  · simp_all
  · rename_i m hm
    cases hh : m.handler? a.trigger <;> simp [hm, hh]

/-- A property every enabled handler preserves is preserved by dispatch. This is how an
invariant is proved one move at a time. -/
theorem dispatch_preserves {moves : List (Move S)} (P : S → Prop)
    (hP : ∀ m ∈ moves, ∀ h ∈ m.handlers, ∀ s a, h.trigger = a.trigger → m.id = a.claim →
      m.enabled s a.key = true → P s → P (h.apply s a).1)
    (s : S) (a : Action) (hs : P s) : P (dispatch moves s a).1 := by
  rcases dispatch_cases moves s a with h0 | ⟨m, mm, h, hm, mi, ht, en, eq⟩
  · rw [h0]; exact hs
  · rw [eq]; exact hP m mm h hm s a ht mi en hs

/-! ### Preservation, one handler at a time

An invariant is preserved by `dispatch` when every handler of every move preserves it. The
`move` command generates `name.preserves`, which turns obligations stated in the move's own
terms (its `apply`, its binders) into `Move.Preserves`. -/

/-- The handler keeps `P` whenever it runs. -/
def Handler.Preserves {en : S → Nat → Bool} (h : Handler S en) (P : S → Prop) : Prop :=
  ∀ s a, a.trigger = h.trigger → en s a.key = true → P s → P (h.apply s a).1

/-- Every handler of the move keeps `P`. -/
def Move.Preserves (m : Move S) (P : S → Prop) : Prop := ∀ h ∈ m.handlers, h.Preserves P

theorem Handler.all_nil {en : S → Nat → Bool} {P : S → Prop} :
    ∀ h ∈ ([] : List (Handler S en)), h.Preserves P := by simp

theorem Handler.all_cons {en : S → Nat → Bool} {P : S → Prop} {h : Handler S en}
    {hs : List (Handler S en)} (p : h.Preserves P) (ps : ∀ h ∈ hs, h.Preserves P) :
    ∀ x ∈ h :: hs, x.Preserves P := by
  intro x hx
  rcases List.mem_cons.mp hx with rfl | hx
  · exact p
  · exact ps x hx

theorem Handler.simple_preserves {en : S → Nat → Bool} {P : S → Prop} {t : Trigger}
    {ap : S → Nat → S × List Effect} {po : S → Nat → S → Prop}
    {so : ∀ s k, en s k = true → po s k (ap s k).1}
    (hp : ∀ s k, en s k = true → P s → P (ap s k).1) :
    (Handler.simple t ap po so).Preserves P :=
  fun s a _ he hs => hp s a.key he hs

theorem Handler.edit_preserves {en : S → Nat → Bool} {P : S → Prop}
    {ap : S → Nat → TextOp → S × List Effect} {po : S → Nat → TextOp → S → Prop}
    {so : ∀ s k op, en s k = true → po s k op (ap s k op).1}
    (hp : ∀ s k op, en s k = true → P s → P (ap s k op).1) :
    (Handler.edit ap po so).Preserves P := by
  intro s a ht he hs
  cases a with
  | edit c op => exact hp s c.key op he hs
  | _ => simp [Action.trigger, Handler.edit] at ht

theorem Move.all_nil {P : S → Prop} : ∀ m ∈ ([] : List (Move S)), m.Preserves P := by simp

theorem Move.all_cons {P : S → Prop} {m : Move S} {ms : List (Move S)}
    (p : m.Preserves P) (ps : ∀ m ∈ ms, m.Preserves P) : ∀ x ∈ m :: ms, x.Preserves P := by
  intro x hx
  rcases List.mem_cons.mp hx with rfl | hx
  · exact p
  · exact ps x hx

/-- **Invariants one move at a time.** If every move keeps `P`, dispatch keeps `P`. -/
theorem dispatch_preserves_moves {moves : List (Move S)} {P : S → Prop}
    (hm : ∀ m ∈ moves, m.Preserves P) (s : S) (a : Action) (hs : P s) :
    P (dispatch moves s a).1 :=
  dispatch_preserves P (fun m mm h hh s a ht _ he hs => hm m mm h hh s a ht.symm he hs) s a hs

@[simp] theorem Handler.simple_apply {en : S → Nat → Bool} {t : Trigger}
    {ap : S → Nat → S × List Effect} {po : S → Nat → S → Prop}
    {so : ∀ s k, en s k = true → po s k (ap s k).1} (s : S) (a : Action) :
    (Handler.simple t ap po so).apply s a = ap s a.key := rfl

end

end Claims
end Cairn

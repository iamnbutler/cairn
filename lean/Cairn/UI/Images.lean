module

public import Cairn.UI.Node
public import Cairn.Input

/-! # Images: what an app knows of the images it shows

An app keeps one `Images` in its state. `load` asks the host for a source (`Request.loadImage`)
and remembers which request id is the source's latest; `receive` takes the reply to that id and
records the size or the failure. A reply to an earlier load of the same source, or to an id this
table never issued, changes nothing (`receive_stale`, `load_supersedes`), so a slow first load
can't overwrite a reload that answered first.

The view reads `state` for each source and builds `Node.image` with it: the node's size is the
app's choice and the same in every state (`Layout.measure_image`). -/

@[expose] public section

namespace Cairn

structure Images where
  /-- What is known of each source; a source not listed is `loading`. -/
  known : List (String × ImageState) := []
  /-- Each source's latest load: request id and source. -/
  pending : List (Nat × String) := []
deriving Repr, Inhabited

namespace Images

/-- `xs` with `k`'s entry replaced by `v` (or `(k, v)` appended). -/
def setAt {α : Type} : List (String × α) → String → α → List (String × α)
  | [], k, v => [(k, v)]
  | (k', v') :: xs, k, v => if k' = k then (k, v) :: xs else (k', v') :: setAt xs k v

theorem lookup_setAt {α : Type} (xs : List (String × α)) (k : String) (v : α) :
    (setAt xs k v).lookup k = some v := by
  induction xs with
  | nil => simp only [setAt, List.lookup, beq_self_eq_true]
  | cons p xs ih =>
    obtain ⟨k', v'⟩ := p
    unfold setAt
    by_cases h : k' = k
    · subst h; simp only [↓reduceIte, List.lookup, beq_self_eq_true]
    · simp only [h, ↓reduceIte, List.lookup]
      have : (k == k') = false := by simp only [beq_eq_false_iff_ne, ne_eq]; exact fun e => h e.symm
      simp only [this]; exact ih

theorem lookup_setAt_ne {α : Type} (xs : List (String × α)) (k k2 : String) (v : α) (h : k ≠ k2) :
    (setAt xs k v).lookup k2 = xs.lookup k2 := by
  induction xs with
  | nil =>
    have : (k2 == k) = false := by simp only [beq_eq_false_iff_ne, ne_eq]; exact fun e => h e.symm
    simp only [setAt, List.lookup, this]
  | cons p xs ih =>
    obtain ⟨k', v'⟩ := p
    unfold setAt
    by_cases hk : k' = k
    · subst hk
      have : (k2 == k') = false := by simp only [beq_eq_false_iff_ne, ne_eq]; exact fun e => h e.symm
      simp only [↓reduceIte, List.lookup, this]
    · simp only [hk, ↓reduceIte, List.lookup]
      split <;> simp_all only

/-- What is known of `source`. -/
def state (t : Images) (source : String) : ImageState := (t.known.lookup source).getD .loading

/-- Load `source` under request id `id` (fresh: the app's next request id). The source shows as
loading until the reply; any earlier load of it is forgotten. `reload` reads it again rather than
answering from the host's cache. -/
def load (t : Images) (id : Nat) (source : String) (reload : Bool := false) : Images × Effect :=
  ({ known := setAt t.known source .loading,
     pending := (id, source) :: t.pending.filter (·.2 != source) },
   .request id (.loadImage source reload))

/-- What a reply says about an image. -/
def ofReply : Reply → ImageState
  | .image w h => .ready w h
  | .failed f m => .failed f m
  | _ => .failed .other "unexpected reply"

/-- A reply: if `id` is a source's latest load, record what it says and stop waiting for it;
otherwise nothing changes. -/
def receive (t : Images) (id : Nat) (r : Reply) : Images :=
  match t.pending.lookup id with
  | some source => { known := setAt t.known source (ofReply r), pending := t.pending.filter (·.1 != id) }
  | none => t

/-- Whether the table is waiting for a reply to `id`. -/
def waiting (t : Images) (id : Nat) : Bool := (t.pending.lookup id).isSome

theorem state_load (t : Images) (id : Nat) (source : String) (reload : Bool) :
    (t.load id source reload).1.state source = .loading := by
  simp only [load, state, lookup_setAt, Option.getD_some]

theorem receive_stale (t : Images) (id : Nat) (r : Reply) (h : t.pending.lookup id = none) :
    t.receive id r = t := by
  simp only [receive, h]

theorem state_receive (t : Images) (id : Nat) (source : String) (r : Reply)
    (h : t.pending.lookup id = some source) :
    (t.receive id r).state source = ofReply r := by
  simp only [receive, h, state, lookup_setAt, Option.getD_some]

/-- After a load of `source`, the table waits for no other id for it. -/
theorem load_supersedes (t : Images) (id old : Nat) (source : String) (reload : Bool)
    (hne : old ≠ id) : ((t.load id source reload).1.pending.lookup old) ≠ some source := by
  simp only [load, List.lookup]
  have : (old == id) = false := by simp only [beq_eq_false_iff_ne, ne_eq]; exact hne
  simp only [this]
  exact lookup_filter_ne t.pending old source
where
  /-- Looking up in a list without `v`'s entries never finds `v`. -/
  lookup_filter_ne (xs : List (Nat × String)) (k : Nat) (v : String) :
      (xs.filter (·.2 != v)).lookup k ≠ some v := by
    induction xs with
    | nil => simp only [List.filter, List.lookup, ne_eq, reduceCtorEq, not_false_eq_true]
    | cons p xs ih =>
      obtain ⟨k', v'⟩ := p
      by_cases hv : v' = v
      · subst hv; simp only [List.filter, bne_self_eq_false]; exact ih
      · have : (v' != v) = true := by simp only [bne_iff_ne, ne_eq]; exact hv
        simp only [List.filter, this, List.lookup]
        split
        · intro e; exact hv (Option.some.inj e)
        · exact ih

/-- **A reply to a superseded load changes nothing**: once `source` was loaded again under
`id`, the reply to any earlier id for it leaves what the table knows of `source` alone. -/
theorem superseded_reply (t : Images) (id old : Nat) (source : String) (reload : Bool) (r : Reply)
    (hne : old ≠ id) :
    (((t.load id source reload).1.receive old r).state source) = .loading := by
  have hs := load_supersedes t id old source reload hne
  unfold receive
  split
  · next src hl =>
    have hsrc : src ≠ source := fun e => hs (e ▸ hl)
    simp only [state]
    rw [lookup_setAt_ne _ _ _ _ hsrc]
    exact state_load t id source reload
  · exact state_load t id source reload

/-! ## Loading several sources -/

/-- Load each of `sources` in order, under ids `id`, `id + 1`, …: the table and the requests. -/
def loadAll (t : Images) (id : Nat) (reload : Bool) : List String → Images × List Effect
  | [] => (t, [])
  | src :: rest =>
    let (t1, e) := t.load id src reload
    let (t2, es) := t1.loadAll (id + 1) reload rest
    (t2, e :: es)

theorem state_load_ne (t : Images) (id : Nat) (src other : String) (reload : Bool) (h : src ≠ other) :
    (t.load id src reload).1.state other = t.state other := by
  simp only [load, state, lookup_setAt_ne _ _ _ _ h]

theorem state_loadAll_notin (t : Images) (id : Nat) (reload : Bool) (src : String) :
    ∀ (srcs : List String), src ∉ srcs → (t.loadAll id reload srcs).1.state src = t.state src := by
  intro srcs
  induction srcs generalizing t id with
  | nil => intro _; rfl
  | cons s rest ih =>
    intro h
    have hs : s ≠ src := fun e => h (e ▸ List.mem_cons_self ..)
    have hr : src ∉ rest := fun m => h (List.mem_cons_of_mem _ m)
    show ((t.load id s reload).1.loadAll (id + 1) reload rest).1.state src = _
    rw [ih _ _ hr, state_load_ne _ _ _ _ _ hs]

/-- **After loading a list, each of its sources shows as loading** until its reply. -/
theorem state_loadAll (t : Images) (id : Nat) (reload : Bool) (src : String) :
    ∀ (srcs : List String), src ∈ srcs → (t.loadAll id reload srcs).1.state src = .loading := by
  intro srcs
  induction srcs generalizing t id with
  | nil => intro h; cases h
  | cons s rest ih =>
    intro h
    show ((t.load id s reload).1.loadAll (id + 1) reload rest).1.state src = _
    by_cases hr : src ∈ rest
    · exact ih _ _ hr
    · have hs : s = src := by
        rcases List.mem_cons.mp h with e | e
        · exact e.symm
        · exact absurd e hr
      subst hs
      rw [state_loadAll_notin _ _ _ _ _ hr]
      exact state_load t id s reload

/-! ## Pending ids -/

theorem pending_load (t : Images) (id : Nat) (src : String) (reload : Bool) (p : Nat × String)
    (h : p ∈ (t.load id src reload).1.pending) : p.1 = id ∨ p ∈ t.pending := by
  simp only [load, List.mem_cons, List.mem_filter] at h
  rcases h with h | h
  · exact Or.inl (by rw [h])
  · exact Or.inr h.1

theorem pending_loadAll (t : Images) (reload : Bool) :
    ∀ (srcs : List String) (id : Nat) (p : Nat × String), p ∈ (t.loadAll id reload srcs).1.pending →
      (id ≤ p.1 ∧ p.1 < id + srcs.length) ∨ p ∈ t.pending := by
  intro srcs
  induction srcs generalizing t with
  | nil => intro _ p h; exact Or.inr h
  | cons s rest ih =>
    intro id p h
    have h' : p ∈ ((t.load id s reload).1.loadAll (id + 1) reload rest).1.pending := h
    rcases ih _ (id + 1) p h' with ⟨h1, h2⟩ | h
    · left; simp only [List.length_cons]; omega
    · rcases pending_load t id s reload p h with e | e
      · left; simp only [List.length_cons]; omega
      · exact Or.inr e

theorem pending_receive (t : Images) (id : Nat) (r : Reply) (p : Nat × String)
    (h : p ∈ (t.receive id r).pending) : p ∈ t.pending := by
  unfold receive at h
  split at h
  · exact (List.mem_filter.mp h).1
  · exact h

theorem loadAll_length (t : Images) (id : Nat) (reload : Bool) :
    ∀ (srcs : List String), (t.loadAll id reload srcs).2.length = srcs.length := by
  intro srcs
  induction srcs generalizing t id with
  | nil => rfl
  | cons s rest ih =>
    show (((t.load id s reload).1.loadAll (id + 1) reload rest).2.length + 1) = rest.length + 1
    rw [ih]

/-! ## Cancelling

A load still in flight holds one of the runtime's request slots (`App.maxInFlight`) until the
host answers it. `cancel` and `cancelAll` stop waiting and ask the runtime to cancel: a queued
request is never sent, a sent one is cancelled at the host, and its reply reaches no app
(`Book.cancel_blocks`). A cancelled source keeps what was known of it (`loading` if it never
answered) until it is loaded again. -/

/-- Stop waiting for `source`'s latest load and cancel it. -/
def cancel (t : Images) (source : String) : Images × List Effect :=
  ({ t with pending := t.pending.filter (·.2 != source) },
   (t.pending.filter (·.2 == source)).map fun p => .cancelRequest p.1)

/-- Stop waiting for every load and cancel each one. -/
def cancelAll (t : Images) : Images × List Effect :=
  ({ t with pending := [] }, t.pending.map fun p => .cancelRequest p.1)

/-- **After `cancelAll`, no reply changes the table.** -/
theorem receive_cancelAll (t : Images) (id : Nat) (r : Reply) :
    t.cancelAll.1.receive id r = t.cancelAll.1 :=
  receive_stale _ _ _ (by simp only [cancelAll, List.lookup])

/-- `cancelAll` cancels exactly the ids the table was waiting for. -/
theorem cancelAll_effects (t : Images) :
    t.cancelAll.2 = t.pending.map fun p => .cancelRequest p.1 := rfl

/-- After `cancel source`, a reply to any id leaves what is known of `source` alone. -/
theorem receive_cancel (t : Images) (source : String) (id : Nat) (r : Reply) :
    ((t.cancel source).1.receive id r).state source = (t.cancel source).1.state source := by
  unfold receive
  split
  · next src hl =>
    have hsrc : src ≠ source := fun e =>
      Images.load_supersedes.lookup_filter_ne t.pending id source (e ▸ hl)
    simp only [state, cancel]
    rw [lookup_setAt_ne _ _ _ _ hsrc]
  · rfl

end Images

end Cairn

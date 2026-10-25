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
where
  lookup_setAt_ne {α : Type} (xs : List (String × α)) (k k2 : String) (v : α) (h : k ≠ k2) :
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

end Images

end Cairn

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

theorem pending_load_src (t : Images) (id : Nat) (src : String) (reload : Bool) (p : Nat × String)
    (h : p ∈ (t.load id src reload).1.pending) : p.2 = src ∨ p ∈ t.pending := by
  simp only [load, List.mem_cons, List.mem_filter] at h
  rcases h with h | h
  · exact Or.inl (by rw [h])
  · exact Or.inr h.1

theorem pending_loadAll_src (t : Images) (reload : Bool) :
    ∀ (srcs : List String) (id : Nat) (p : Nat × String), p ∈ (t.loadAll id reload srcs).1.pending →
      p.2 ∈ srcs ∨ p ∈ t.pending := by
  intro srcs
  induction srcs generalizing t with
  | nil => intro _ p h; exact Or.inr h
  | cons s rest ih =>
    intro id p h
    have h' : p ∈ ((t.load id s reload).1.loadAll (id + 1) reload rest).1.pending := h
    rcases ih _ (id + 1) p h' with h | h
    · exact Or.inl (List.mem_cons_of_mem _ h)
    · rcases pending_load_src t id s reload p h with e | e
      · exact Or.inl (e ▸ List.mem_cons_self ..)
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

/-- Stop waiting for the loads of every source `p` picks, and cancel each one. -/
def cancelWhere (t : Images) (p : String → Bool) : Images × List Effect :=
  ({ t with pending := t.pending.filter fun q => !p q.2 },
   (t.pending.filter fun q => p q.2).map fun q => .cancelRequest q.1)

theorem pending_cancelWhere (t : Images) (p : String → Bool) (q : Nat × String)
    (h : q ∈ (t.cancelWhere p).1.pending) : q ∈ t.pending ∧ p q.2 = false := by
  simp only [cancelWhere, List.mem_filter, Bool.not_eq_true'] at h
  exact h

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

/-! ## Evicted images

With `Sub.imageCache` the host keeps its decoded images within a byte budget: past it, it drops
the images used least recently that the latest frame doesn't draw, and says so with
`SubEvent.evicted` once the pixels are gone. `evicted` forgets such an image: a ready one goes
back to `loading`, and the table stops waiting for (and cancels) any load of it still in flight,
because that load's reply may say ready for pixels dropped since. The app loads it again when it
wants to show it. -/

/-- Whether the table takes `source` for ready. -/
def isReady (t : Images) (source : String) : Bool :=
  match t.state source with
  | .ready .. => true
  | _ => false

/-- The host dropped `source`'s pixels (`SubEvent.evicted`): forget that it is ready, stop waiting
for its loads and cancel them. -/
def evicted (t : Images) (source : String) : Images × List Effect :=
  let (t1, cs) := t.cancel source
  ({ t1 with known := if t.isReady source then setAt t.known source .loading else t.known }, cs)

/-- **After `evicted`, the source is not ready.** -/
theorem state_evicted (t : Images) (source : String) (w h : Nat) :
    (t.evicted source).1.state source ≠ .ready w h := by
  intro e
  by_cases hr : t.isReady source = true
  · simp only [evicted, cancel, hr, ↓reduceIte, state, lookup_setAt, Option.getD_some] at e
    cases e
  · have hs : t.state source = .ready w h := by
      simp only [evicted, cancel, hr, Bool.false_eq_true, ↓reduceIte] at e
      exact e
    simp only [isReady, hs, not_true_eq_false] at hr

theorem state_evicted_ne (t : Images) (source other : String) (h : source ≠ other) :
    (t.evicted source).1.state other = t.state other := by
  unfold evicted cancel
  by_cases hr : t.isReady source = true
  · simp only [hr, ↓reduceIte, state, lookup_setAt_ne _ _ _ _ h]
  · simp only [hr, Bool.false_eq_true, ↓reduceIte, state]

theorem pending_evicted (t : Images) (source : String) (p : Nat × String)
    (h : p ∈ (t.evicted source).1.pending) : p ∈ t.pending ∧ p.2 ≠ source := by
  simp only [evicted, cancel, List.mem_filter, bne_iff_ne, ne_eq] at h
  exact h

/-- After `evicted`, no reply makes the source ready: the table waits for no load of it. -/
theorem receive_evicted (t : Images) (source : String) (id : Nat) (r : Reply) :
    ((t.evicted source).1.receive id r).state source = (t.evicted source).1.state source := by
  unfold receive
  split
  · next src hl =>
    have hsrc : src ≠ source := fun e => by
      have := (pending_evicted t source _ (mem_lookup _ _ _ hl)).2
      exact this e
    simp only [state]
    rw [lookup_setAt_ne _ _ _ _ hsrc]
  · rfl
where
  /-- A lookup finds an entry of the list. -/
  mem_lookup : ∀ (xs : List (Nat × String)) (k : Nat) (v : String), xs.lookup k = some v → (k, v) ∈ xs
    | [], _, _, h => by simp only [List.lookup, reduceCtorEq] at h
    | (k', v') :: xs, k, v, h => by
      simp only [List.lookup] at h
      split at h
      · next he =>
        have hk : k = k' := by simpa only [beq_iff_eq] using he
        cases h; subst hk; exact List.mem_cons_self ..
      · exact List.mem_cons_of_mem _ (mem_lookup xs k v h)

/-- A reply leaves alone the state of a source the table waits for no load of. -/
theorem state_receive_waiting (t : Images) (id : Nat) (r : Reply) (source : String)
    (h : ∀ p ∈ t.pending, p.2 ≠ source) : (t.receive id r).state source = t.state source := by
  unfold receive
  split
  · next src hl =>
    have hsrc : src ≠ source := h _ (receive_evicted.mem_lookup _ _ _ hl)
    simp only [state]
    rw [lookup_setAt_ne _ _ _ _ hsrc]
  · rfl

/-! ## The cache, modelled

`Cache` puts the table together with the host: whether it holds each source's pixels, the
messages on their way to the app (replies and `evicted` notices, in the order the app hears
them), and the loads the host has found pixels for. The host's moves are what ^1011 says of it:
it answers a load ready only after it held the pixels for it (`find`, then `ready`), and every
time it drops a source's pixels it says so afterwards (`evict`). The app's are loads, cancels
and hearing each message in turn with `receive` and `evicted`; the runtime may swallow a reply
(`drop`). In every state reached, an image the table takes for ready has its pixels with the
host, or an `evicted` notice for it is still on its way (`ready_held`); so once the app has heard
everything, ready means the pixels are there (`ready_held_quiet`). -/

namespace Cache

/-- A message to the app. -/
inductive Note where
  | reply (id : Nat) (r : Reply)
  | evicted (source : String)

structure Sys where
  t : Images
  /-- Whether the host holds pixels for each source. -/
  has : String → Bool
  /-- Messages to the app, the next one first. -/
  q : List Note
  /-- Loads the host has held pixels for, which it may answer ready. -/
  found : List (Nat × String)
  /-- Every load the app made: id and source. -/
  asked : List (Nat × String)
  /-- The id the app's next load gets. -/
  next : Nat

/-- `has` with `src` set to `b`. -/
def setHas (has : String → Bool) (src : String) (b : Bool) : String → Bool :=
  fun s => if s = src then b else has s

/-- The app's table before anything was asked. -/
def init (has : String → Bool) : Sys := ⟨{}, has, [], [], [], 0⟩

inductive Step : Sys → Sys → Prop
  /-- The app loads `src` under its next id. -/
  | load (s : Sys) (src : String) (reload : Bool) :
      Step s { s with t := (s.t.load s.next src reload).1, asked := (s.next, src) :: s.asked,
                      next := s.next + 1 }
  /-- The app stops waiting for some loads (`cancel`, `cancelWhere`, `cancelAll`). -/
  | cancel (s : Sys) (t : Images) (hk : t.known = s.t.known) (hp : ∀ p ∈ t.pending, p ∈ s.t.pending) :
      Step s { s with t := t }
  /-- The host holds pixels for a load the app made (read and decoded, or already kept). -/
  | find (s : Sys) (id : Nat) (src : String) (h : (id, src) ∈ s.asked) :
      Step s { s with has := setHas s.has src true, found := (id, src) :: s.found }
  /-- The host answers ready a load it held the pixels for. -/
  | ready (s : Sys) (id : Nat) (src : String) (w h : Nat) (hf : (id, src) ∈ s.found) :
      Step s { s with q := s.q ++ [.reply id (.image w h)] }
  /-- Any other answer, to any id. -/
  | other (s : Sys) (id : Nat) (r : Reply) (hr : ∀ w h, r ≠ .image w h) :
      Step s { s with q := s.q ++ [.reply id r] }
  /-- The host drops `src`'s pixels, then says so. -/
  | evict (s : Sys) (src : String) :
      Step s { s with has := setHas s.has src false, q := s.q ++ [.evicted src] }
  /-- The app hears a reply. -/
  | hearReply (s : Sys) (id : Nat) (r : Reply) (rest : List Note) (hq : s.q = .reply id r :: rest) :
      Step s { s with t := s.t.receive id r, q := rest }
  /-- The runtime swallows a reply (to a cancelled request). -/
  | drop (s : Sys) (id : Nat) (r : Reply) (rest : List Note) (hq : s.q = .reply id r :: rest) :
      Step s { s with q := rest }
  /-- The app hears that `src` was evicted. -/
  | hearEvicted (s : Sys) (src : String) (rest : List Note) (hq : s.q = .evicted src :: rest) :
      Step s { s with t := (s.t.evicted src).1, q := rest }

inductive Reach : Sys → Prop
  | init (has : String → Bool) : Reach (init has)
  | step {s s' : Sys} : Reach s → Step s s' → Reach s'

/-- What every reachable state keeps. -/
structure Inv (s : Sys) : Prop where
  fresh : ∀ p ∈ s.asked, p.1 < s.next
  unique : ∀ id a b, (id, a) ∈ s.asked → (id, b) ∈ s.asked → a = b
  pendingAsked : ∀ p ∈ s.t.pending, p ∈ s.asked
  foundAsked : ∀ p ∈ s.found, p ∈ s.asked
  readyFound : ∀ id w h, Note.reply id (.image w h) ∈ s.q → ∃ src, (id, src) ∈ s.found
  /-- An image the table takes for ready is held, or its eviction is on its way. -/
  held : ∀ src w h, s.t.state src = .ready w h → s.has src = true ∨ Note.evicted src ∈ s.q
  /-- So is one whose pending load the host answered or may answer ready. -/
  heldPending : ∀ id src, (id, src) ∈ s.t.pending →
    ((∃ w h, Note.reply id (.image w h) ∈ s.q) ∨ (id, src) ∈ s.found) →
    s.has src = true ∨ Note.evicted src ∈ s.q

theorem ofReply_ready {r : Reply} {w h : Nat} (e : ofReply r = .ready w h) : r = .image w h := by
  cases r <;> simp_all only [ofReply, reduceCtorEq, ImageState.ready.injEq]

theorem inv_init (has : String → Bool) : Inv (init has) where
  fresh := fun _ h => nomatch h
  unique := fun _ _ _ h => nomatch h
  pendingAsked := fun _ h => nomatch h
  foundAsked := fun _ h => nomatch h
  readyFound := fun _ _ _ h => nomatch h
  held := fun src w h e => by
    simp only [init, state, List.lookup, Option.getD_none, reduceCtorEq] at e
  heldPending := fun _ _ h => nomatch h

/-- An `evicted` notice behind a reply is still there once the reply is heard. -/
theorem evicted_tail {src : String} {n : Note} {rest : List Note} (hn : ∀ s, n ≠ .evicted s)
    (h : Note.evicted src ∈ n :: rest) : Note.evicted src ∈ rest := by
  rcases List.mem_cons.mp h with e | e
  · exact absurd e.symm (hn src)
  · exact e

theorem inv_step {s s' : Sys} (hi : Inv s) (hs : Step s s') : Inv s' := by
  cases hs with
  | load src reload =>
    have hmem : ∀ p, p ∈ (s.t.load s.next src reload).1.pending → p = (s.next, src) ∨ p ∈ s.t.pending := by
      intro p hp
      simp only [load, List.mem_cons, List.mem_filter] at hp
      rcases hp with e | e
      · exact Or.inl e
      · exact Or.inr e.1
    have hnew : ∀ id', (s.next, id') ∉ s.asked := fun _ h => Nat.lt_irrefl _ (hi.fresh _ h)
    refine ⟨?_, ?_, ?_, ?_, hi.readyFound, ?_, ?_⟩
    · intro p hp
      rcases List.mem_cons.mp hp with e | e
      · subst e; exact Nat.lt_succ_self _
      · exact Nat.lt_succ_of_lt (hi.fresh p e)
    · intro id a b ha hb
      rcases List.mem_cons.mp ha with ea | ea <;> rcases List.mem_cons.mp hb with eb | eb
      · simp only [Prod.mk.injEq] at ea eb; rw [ea.2, eb.2]
      · simp only [Prod.mk.injEq] at ea; rw [ea.1] at eb; exact absurd eb (hnew b)
      · simp only [Prod.mk.injEq] at eb; rw [eb.1] at ea; exact absurd ea (hnew a)
      · exact hi.unique id a b ea eb
    · intro p hp
      rcases hmem p hp with e | e
      · rw [e]; exact List.mem_cons_self ..
      · exact List.mem_cons_of_mem _ (hi.pendingAsked p e)
    · intro p hp; exact List.mem_cons_of_mem _ (hi.foundAsked p hp)
    · intro o w h e
      by_cases ho : src = o
      · subst ho; rw [state_load] at e; cases e
      · rw [state_load_ne _ _ _ _ _ ho] at e; exact hi.held o w h e
    · intro id o hp hc
      rcases hmem _ hp with e | e
      · simp only [Prod.mk.injEq] at e
        obtain ⟨rfl, rfl⟩ := e
        exfalso
        rcases hc with ⟨w, h, hq⟩ | hf
        · obtain ⟨src', hf⟩ := hi.readyFound _ w h hq
          exact hnew src' (hi.foundAsked _ hf)
        · exact hnew o (hi.foundAsked _ hf)
      · exact hi.heldPending id o e hc
  | cancel t hk hp =>
    have hst : ∀ o, t.state o = s.t.state o := fun o => by simp only [state, hk]
    refine ⟨hi.fresh, hi.unique, fun p h => hi.pendingAsked p (hp p h), hi.foundAsked,
      hi.readyFound, fun o w h e => hi.held o w h (by rw [← hst]; exact e),
      fun id o h hc => hi.heldPending id o (hp _ h) hc⟩
  | find id src hmem =>
    have hmono : ∀ o, s.has o = true → setHas s.has src true o = true := fun o h => by
      simp only [setHas]; split <;> simp_all only
    have hsrc : setHas s.has src true src = true := by simp only [setHas, ↓reduceIte]
    refine ⟨hi.fresh, hi.unique, hi.pendingAsked, ?_, ?_, ?_, ?_⟩
    · intro p hp
      rcases List.mem_cons.mp hp with e | e
      · rw [e]; exact hmem
      · exact hi.foundAsked p e
    · intro i w h hq
      obtain ⟨o, ho⟩ := hi.readyFound i w h hq
      exact ⟨o, List.mem_cons_of_mem _ ho⟩
    · intro o w h e
      rcases hi.held o w h e with e' | e'
      · exact Or.inl (hmono o e')
      · exact Or.inr e'
    · intro i o hp hc
      by_cases hio : (i, o) = (id, src)
      · simp only [Prod.mk.injEq] at hio; obtain ⟨rfl, rfl⟩ := hio; exact Or.inl hsrc
      · have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
          rcases hc with hc | hc
          · exact Or.inl hc
          · rcases List.mem_cons.mp hc with e | e
            · exact absurd e hio
            · exact Or.inr e
        rcases hi.heldPending i o hp hc' with e' | e'
        · exact Or.inl (hmono o e')
        · exact Or.inr e'
  | ready id src w h hf =>
    have hq : ∀ i w' h', Note.reply i (.image w' h') ∈ s.q ++ [Note.reply id (.image w h)] →
        Note.reply i (.image w' h') ∈ s.q ∨ i = id := by
      intro i w' h' m
      rcases List.mem_append.mp m with m | m
      · exact Or.inl m
      · simp only [List.mem_singleton, Note.reply.injEq] at m; exact Or.inr m.1
    refine ⟨hi.fresh, hi.unique, hi.pendingAsked, hi.foundAsked, ?_, ?_, ?_⟩
    · intro i w' h' m
      rcases hq i w' h' m with m | rfl
      · exact hi.readyFound i w' h' m
      · exact ⟨src, hf⟩
    · intro o w' h' e
      rcases hi.held o w' h' e with e' | e'
      · exact Or.inl e'
      · exact Or.inr (List.mem_append_left _ e')
    · intro i o hp hc
      have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
        rcases hc with ⟨w', h', m⟩ | hc
        · rcases hq i w' h' m with m | rfl
          · exact Or.inl ⟨w', h', m⟩
          · have := hi.unique i o src (hi.pendingAsked _ hp) (hi.foundAsked _ hf)
            subst this; exact Or.inr hf
        · exact Or.inr hc
      rcases hi.heldPending i o hp hc' with e' | e'
      · exact Or.inl e'
      · exact Or.inr (List.mem_append_left _ e')
  | other id r hr =>
    have hq : ∀ i w' h', Note.reply i (.image w' h') ∈ s.q ++ [Note.reply id r] →
        Note.reply i (.image w' h') ∈ s.q := by
      intro i w' h' m
      rcases List.mem_append.mp m with m | m
      · exact m
      · simp only [List.mem_singleton, Note.reply.injEq] at m
        exact absurd m.2.symm (hr w' h')
    refine ⟨hi.fresh, hi.unique, hi.pendingAsked, hi.foundAsked,
      fun i w' h' m => hi.readyFound i w' h' (hq i w' h' m), ?_, ?_⟩
    · intro o w' h' e
      rcases hi.held o w' h' e with e' | e'
      · exact Or.inl e'
      · exact Or.inr (List.mem_append_left _ e')
    · intro i o hp hc
      have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
        rcases hc with ⟨w', h', m⟩ | hc
        · exact Or.inl ⟨w', h', hq i w' h' m⟩
        · exact Or.inr hc
      rcases hi.heldPending i o hp hc' with e' | e'
      · exact Or.inl e'
      · exact Or.inr (List.mem_append_left _ e')
  | evict src =>
    have hq : ∀ i w' h', Note.reply i (.image w' h') ∈ s.q ++ [Note.evicted src] →
        Note.reply i (.image w' h') ∈ s.q := by
      intro i w' h' m
      rcases List.mem_append.mp m with m | m
      · exact m
      · simp only [List.mem_singleton, reduceCtorEq] at m
    have hkeep : ∀ o, (s.has o = true ∨ Note.evicted o ∈ s.q) →
        setHas s.has src false o = true ∨ Note.evicted o ∈ s.q ++ [Note.evicted src] := by
      intro o h
      by_cases ho : o = src
      · subst ho; exact Or.inr (List.mem_append_right _ (List.mem_singleton_self _))
      · rcases h with h | h
        · left; simp only [setHas, ho, ↓reduceIte]; exact h
        · exact Or.inr (List.mem_append_left _ h)
    refine ⟨hi.fresh, hi.unique, hi.pendingAsked, hi.foundAsked,
      fun i w' h' m => hi.readyFound i w' h' (hq i w' h' m),
      fun o w' h' e => hkeep o (hi.held o w' h' e), ?_⟩
    intro i o hp hc
    have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
      rcases hc with ⟨w', h', m⟩ | hc
      · exact Or.inl ⟨w', h', hq i w' h' m⟩
      · exact Or.inr hc
    exact hkeep o (hi.heldPending i o hp hc')
  | hearReply id r rest hq =>
    have hn : ∀ x, Note.reply id r ≠ .evicted x := fun _ e => Note.noConfusion e
    have hin : ∀ n, n ∈ rest → n ∈ s.q := fun n m => by rw [hq]; exact List.mem_cons_of_mem _ m
    have hkeep : ∀ o, (s.has o = true ∨ Note.evicted o ∈ s.q) → s.has o = true ∨ Note.evicted o ∈ rest := by
      intro o h
      rcases h with h | h
      · exact Or.inl h
      · rw [hq] at h; exact Or.inr (evicted_tail hn h)
    refine ⟨hi.fresh, hi.unique, fun p h => hi.pendingAsked p (pending_receive _ _ _ _ h),
      hi.foundAsked, fun i w h m => hi.readyFound i w h (hin _ m), ?_, ?_⟩
    · intro o w h e
      show s.has o = true ∨ _
      unfold receive at e
      split at e
      · next src hl =>
        by_cases ho : src = o
        · subst ho
          simp only [state, lookup_setAt, Option.getD_some] at e
          have hr := ofReply_ready e
          subst hr
          have hp := receive_evicted.mem_lookup _ _ _ hl
          exact hkeep src (hi.heldPending id src hp (Or.inl ⟨w, h, by rw [hq]; exact List.mem_cons_self ..⟩))
        · simp only [state, lookup_setAt_ne _ _ _ _ ho] at e
          exact hkeep o (hi.held o w h e)
      · exact hkeep o (hi.held o w h e)
    · intro i o hp hc
      have hp' := pending_receive _ _ _ _ hp
      have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
        rcases hc with ⟨w', h', m⟩ | hc
        · exact Or.inl ⟨w', h', hin _ m⟩
        · exact Or.inr hc
      exact hkeep o (hi.heldPending i o hp' hc')
  | drop id r rest hq =>
    have hn : ∀ x, Note.reply id r ≠ .evicted x := fun _ e => Note.noConfusion e
    have hin : ∀ n, n ∈ rest → n ∈ s.q := fun n m => by rw [hq]; exact List.mem_cons_of_mem _ m
    have hkeep : ∀ o, (s.has o = true ∨ Note.evicted o ∈ s.q) → s.has o = true ∨ Note.evicted o ∈ rest := by
      intro o h
      rcases h with h | h
      · exact Or.inl h
      · rw [hq] at h; exact Or.inr (evicted_tail hn h)
    refine ⟨hi.fresh, hi.unique, hi.pendingAsked, hi.foundAsked,
      fun i w h m => hi.readyFound i w h (hin _ m), fun o w h e => hkeep o (hi.held o w h e), ?_⟩
    intro i o hp hc
    have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
      rcases hc with ⟨w', h', m⟩ | hc
      · exact Or.inl ⟨w', h', hin _ m⟩
      · exact Or.inr hc
    exact hkeep o (hi.heldPending i o hp hc')
  | hearEvicted src rest hq =>
    have hin : ∀ n, n ∈ rest → n ∈ s.q := fun n m => by rw [hq]; exact List.mem_cons_of_mem _ m
    have hkeep : ∀ o, o ≠ src → (s.has o = true ∨ Note.evicted o ∈ s.q) →
        s.has o = true ∨ Note.evicted o ∈ rest := by
      intro o ho h
      rcases h with h | h
      · exact Or.inl h
      · rw [hq] at h
        rcases List.mem_cons.mp h with e | e
        · simp only [Note.evicted.injEq] at e; exact absurd e ho
        · exact Or.inr e
    refine ⟨hi.fresh, hi.unique, fun p h => hi.pendingAsked p (pending_evicted _ _ _ h).1,
      hi.foundAsked, fun i w h m => hi.readyFound i w h (hin _ m), ?_, ?_⟩
    · intro o w h e
      by_cases ho : src = o
      · subst ho; exact absurd e (state_evicted _ _ w h)
      · rw [state_evicted_ne _ _ _ ho] at e
        exact hkeep o (Ne.symm ho) (hi.held o w h e)
    · intro i o hp hc
      have hp' := pending_evicted _ _ _ hp
      have hc' : (∃ w h, Note.reply i (.image w h) ∈ s.q) ∨ (i, o) ∈ s.found := by
        rcases hc with ⟨w', h', m⟩ | hc
        · exact Or.inl ⟨w', h', hin _ m⟩
        · exact Or.inr hc
      exact hkeep o hp'.2 (hi.heldPending i o hp'.1 hc')

theorem inv_reach {s : Sys} (h : Reach s) : Inv s := by
  induction h with
  | init has => exact inv_init has
  | step _ hs ih => exact inv_step ih hs

/-- **Ready is never stale for long**: in every state reached, an image the app's table takes for
ready has its pixels with the host, or an `evicted` notice for it is on its way to the app. -/
theorem ready_held {s : Sys} (h : Reach s) (src : String) (w hh : Nat)
    (e : s.t.state src = .ready w hh) : s.has src = true ∨ Note.evicted src ∈ s.q :=
  (inv_reach h).held src w hh e

/-- **Once the app has heard everything, ready means the host holds the pixels.** -/
theorem ready_held_quiet {s : Sys} (h : Reach s) (hq : s.q = []) (src : String) (w hh : Nat)
    (e : s.t.state src = .ready w hh) : s.has src = true := by
  rcases ready_held h src w hh e with e' | e'
  · exact e'
  · rw [hq] at e'; nomatch e'

end Cache

end Images

end Cairn

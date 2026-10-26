import Cairn.Runtime.Proofs

/-! What the runtime guarantees about the outside world (docs/effects.md, "Semantics").

* The clock never goes back (`step_clock`).
* A timer reaches `receive` only while it is set: a cancelled timer never fires, and a timer
  fires once per setting (`steps_book`, read with `Book.run`).
* A reply reaches `receive` only for a pending request, with the id it was sent under, in the
  shape that answers its kind, and once (`steps_book`, `step_reply`, `step_reply_ignored`).
* Subscription diffs start exactly the wanted subscriptions that are not running, stop exactly
  the running ones no longer wanted, and the active set becomes what the app wants
  (`diffSubs_stop`, `diffSubs_start`, `diffSubs_active`).

The timer and reply statements are about a recording wrapper, `logged app`, whose state carries
the list of everything delivered to `receive` and `update`, with the effects each returned.
`Book.run` is the specification such a log must meet: it replays the log against a book of
armed timers and pending requests and fails at the first delivery the book does not allow. -/

namespace Cairn.Runtime

variable {S : Type}

/-! ## Lookup tables -/

theorem lookup_append {β : Type} (l m : List (Nat × β)) (x : Nat) :
    (l ++ m).lookup x = (l.lookup x).or (m.lookup x) := by
  induction l with
  | nil => rfl
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.cons_append, List.lookup]
    cases x == a <;> simp only [ih, Option.some_or]

theorem lookup_filter {β : Type} (l : List (Nat × β)) (id x : Nat) :
    (l.filter (fun p => p.1 != id)).lookup x = if x = id then none else l.lookup x := by
  induction l with
  | nil => simp only [List.filter_nil, List.lookup, ite_self]
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.filter_cons]
    by_cases ha : a = id
    · subst ha
      simp only [bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, ih]
      by_cases hx : x = a
      · simp only [hx, ↓reduceIte]
      · simp only [hx, ↓reduceIte, List.lookup, beq_eq_false_iff_ne.mpr hx]
    · simp only [bne_iff_ne.mpr ha, ↓reduceIte, List.lookup, ih]
      by_cases hx : x = id
      · subst hx
        simp only [beq_eq_false_iff_ne.mpr (Ne.symm ha), ↓reduceIte]
      · simp only [hx, ↓reduceIte]

theorem any_eq_lookup {β : Type} (l : List (Nat × β)) (id : Nat) :
    l.any (fun p => p.1 == id) = (l.lookup id).isSome := by
  induction l with
  | nil => rfl
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.any_cons, List.lookup, ih]
    by_cases h : a = id
    · subst h; simp only [beq_self_eq_true, Bool.true_or, Option.isSome_some]
    · simp only [beq_eq_false_iff_ne.mpr h, beq_eq_false_iff_ne.mpr (Ne.symm h), Bool.false_or]

/-! ## The world's other fields stay put -/

/-- Absorbing effects touches only timers and requests. -/
def Same (w w' : World) : Prop :=
  w'.clock = w.clock ∧ w'.heard = w.heard ∧ w'.booted = w.booted ∧ w'.subs = w.subs ∧
    w'.nextSub = w.nextSub ∧ w'.cap = w.cap

theorem Same.trans {a b c : World} (h1 : Same a b) (h2 : Same b c) : Same a c := by
  obtain ⟨a1, a2, a3, a4, a5, a6⟩ := h1
  obtain ⟨b1, b2, b3, b4, b5, b6⟩ := h2
  exact ⟨b1.trans a1, b2.trans a2, b3.trans a3, b4.trans a4, b5.trans a5, b6.trans a6⟩

theorem cancel_same (w : World) (id : Nat) : Same w (w.cancel id).1 := by
  unfold World.cancel; split
  · exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
  · split <;> exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem absorb1_same (w : World) (e : Effect) : Same w (w.absorb1 e).1 := by
  cases e <;> simp only [World.absorb1] <;> (try split) <;> (try split) <;>
    first | exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩ | exact cancel_same _ _

theorem absorb_cons (w : World) (e : Effect) (es : List Effect) :
    (w.absorb (e :: es)).1 = ((w.absorb1 e).1.absorb es).1 := rfl

theorem absorb_same (es : List Effect) : ∀ (w : World), Same w (w.absorb es).1 := by
  induction es with
  | nil => intro w; exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
  | cons e es ih => intro w; rw [absorb_cons]; exact (absorb1_same w e).trans (ih _)

/-! ## Books -/

/-- What a delivery log records: a message to `receive` or an action to `update`, with the
effects it returned. -/
inductive Entry where
  | recv (m : Msg) (es : List Effect)
  | upd (a : Action) (es : List Effect)

/-- The specification's state: which timers are armed and which requests are pending. -/
structure Book where
  armed : String → Bool := fun _ => false
  pending : Nat → Option Request.Kind := fun _ => none

namespace Book

def arm (b : Book) (n : String) (on : Bool) : Book :=
  { b with armed := fun x => if x = n then on else b.armed x }

def drop (b : Book) (id : Nat) : Book :=
  { b with pending := fun x => if x = id then none else b.pending x }

/-- One effect: `setTimer` arms, `cancelTimer` disarms, a request with a fresh id becomes
pending (one whose id is pending is refused), `cancelRequest` withdraws a pending request. Whether
a request is sent at once or waits for a slot is the runtime's business, not the book's: the
book's pending requests are the ones the app may still hear about. -/
def take (b : Book) : Effect → Book
  | .setTimer n _ => b.arm n true
  | .cancelTimer n => b.arm n false
  | .request id r =>
    match b.pending id with
    | some _ => b
    | none => { b with pending := fun x => if x = id then some r.kind else b.pending x }
  | .cancelRequest id => b.drop id
  | _ => b

def takeAll (b : Book) (es : List Effect) : Book := es.foldl take b

/-- Which messages may be delivered: a timer only while armed, a reply only to a pending
request and in the shape that answers it. -/
def admits (b : Book) : Msg → Bool
  | .timer n => b.armed n
  | .reply id r =>
    match b.pending id with
    | some k => r.answers k
    | none => false
  | _ => true

/-- Delivering a message uses it up: a fired timer is disarmed, an answered request is no
longer pending. -/
def pre (b : Book) : Msg → Book
  | .timer n => b.arm n false
  | .reply id _ => b.drop id
  | _ => b

/-- Replay a log; `none` at the first delivery the book does not allow. -/
def run (b : Book) : List Entry → Option Book
  | [] => some b
  | .recv m es :: rest => if b.admits m then ((b.pre m).takeAll es).run rest else none
  | .upd _ es :: rest => (b.takeAll es).run rest

theorem run_append (xs ys : List Entry) : ∀ (b : Book), b.run (xs ++ ys) = (b.run xs).bind (·.run ys) := by
  induction xs with
  | nil => intro b; rfl
  | cons x xs ih =>
    intro b
    cases x with
    | recv m es =>
      simp only [List.cons_append, run]
      split
      · exact ih _
      · rfl
    | upd a es => exact ih _

theorem takeAll_append (b : Book) (xs ys : List Effect) :
    b.takeAll (xs ++ ys) = (b.takeAll xs).takeAll ys := List.foldl_append

/-- A timer whose last word in a delivery's effects was `cancelTimer` is not armed after it. -/
theorem cancel_disarms (b : Book) (n : String) (es rest : List Effect)
    (h : ∀ ms, Effect.setTimer n ms ∉ rest) :
    (b.takeAll (es ++ .cancelTimer n :: rest)).armed n = false := by
  rw [takeAll_append]
  generalize b.takeAll es = b
  simp only [takeAll, List.foldl_cons]
  have : (b.take (.cancelTimer n)).armed n = false := by simp only [take, arm, ↓reduceIte]
  revert this h
  generalize b.take (.cancelTimer n) = b
  induction rest generalizing b with
  | nil => intro _ hb; exact hb
  | cons e rest ih =>
    intro h hb
    simp only [List.foldl_cons]
    apply ih
    · intro ms hm; exact h ms (List.mem_cons_of_mem _ hm)
    · cases e <;> simp only [take] <;> (try split) <;> (try exact hb)
      case setTimer m ms =>
        have hm : m ≠ n := fun he => h ms (he ▸ List.mem_cons_self)
        simp only [arm, (Ne.symm hm), ↓reduceIte, hb]
      case cancelTimer m => simp only [arm]; split <;> simp_all

/-- **A cancelled request is never answered**: once `cancelRequest id` is the last word on `id`
in a delivery's effects (no request under `id` after it), no reply to `id` is admitted. -/
theorem cancel_blocks (b : Book) (id : Nat) (es rest : List Effect) (r : Reply)
    (h : ∀ q, Effect.request id q ∉ rest) :
    (b.takeAll (es ++ .cancelRequest id :: rest)).admits (.reply id r) = false := by
  rw [takeAll_append]
  generalize b.takeAll es = b
  simp only [takeAll, List.foldl_cons]
  have : (b.take (.cancelRequest id)).pending id = none := by simp only [take, drop, ↓reduceIte]
  suffices hp : (rest.foldl take (b.take (.cancelRequest id))).pending id = none by
    simp only [admits, hp]
  revert this h
  generalize b.take (.cancelRequest id) = b
  induction rest generalizing b with
  | nil => intro _ hb; exact hb
  | cons e rest ih =>
    intro h hb
    simp only [List.foldl_cons]
    apply ih
    · intro q hq; exact h q (List.mem_cons_of_mem _ hq)
    · cases e <;> simp only [take] <;> (try exact hb)
      case request j q =>
        have hj : j ≠ id := fun he => h q (he ▸ List.mem_cons_self)
        split
        · exact hb
        · simp only [hj.symm, ↓reduceIte, hb]
      case cancelRequest j => simp only [drop]; split <;> simp_all

/-- A reply uses up its request: right after delivery a second reply to the same id is not
admitted. -/
theorem reply_once (b : Book) (id : Nat) (r r' : Reply) :
    (b.pre (.reply id r)).admits (.reply id r') = false := by
  simp only [pre, drop, admits, ↓reduceIte]

end Book

/-! ## Keyed lists

The runtime's request tables are lists keyed by id. While no id appears twice (`Keys`), a lookup
is a membership test. -/

theorem lookup_some_mem {β : Type} {l : List (Nat × β)} {x : Nat} {v : β}
    (h : l.lookup x = some v) : (x, v) ∈ l := by
  induction l with
  | nil => simp only [List.lookup, reduceCtorEq] at h
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.lookup] at h
    split at h
    · rename_i he
      have hx : x = a := by simpa only [beq_iff_eq] using he
      cases h; subst hx; exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (ih h)

theorem lookup_none_of {β : Type} {l : List (Nat × β)} {x : Nat} (h : x ∉ l.map (·.1)) :
    l.lookup x = none := by
  induction l with
  | nil => rfl
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.map_cons, List.mem_cons, not_or] at h
    simp only [List.lookup, beq_eq_false_iff_ne.mpr h.1]
    exact ih h.2

theorem lookup_isSome_iff {β : Type} (l : List (Nat × β)) (x : Nat) :
    (l.lookup x).isSome = true ↔ x ∈ l.map (·.1) := by
  constructor
  · intro h
    obtain ⟨v, hv⟩ := Option.isSome_iff_exists.mp h
    exact List.mem_map.mpr ⟨(x, v), lookup_some_mem hv, rfl⟩
  · intro h
    induction l with
    | nil => cases h
    | cons p l ih =>
      obtain ⟨a, b⟩ := p
      simp only [List.lookup]
      by_cases hx : x = a
      · subst hx; simp only [beq_self_eq_true, Option.isSome_some]
      · simp only [beq_eq_false_iff_ne.mpr hx]
        simp only [List.map_cons, List.mem_cons] at h
        exact ih (h.resolve_left hx)

theorem lookup_of_mem {β : Type} {l : List (Nat × β)} {x : Nat} {v : β}
    (hn : (l.map (·.1)).Nodup) (h : (x, v) ∈ l) : l.lookup x = some v := by
  induction l with
  | nil => cases h
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.map_cons, List.nodup_cons] at hn
    rcases List.mem_cons.mp h with he | he
    · cases he; simp only [List.lookup, beq_self_eq_true]
    · have hx : x ≠ a := fun e => hn.1 (e ▸ List.mem_map_of_mem he)
      simp only [List.lookup, beq_eq_false_iff_ne.mpr hx]
      exact ih hn.2 he

/-- Two keyed lists with the same members and no repeated key look up alike. -/
theorem lookup_congr {β : Type} {l l' : List (Nat × β)} (hm : ∀ p, p ∈ l ↔ p ∈ l')
    (hn : (l.map (·.1)).Nodup) (hn' : (l'.map (·.1)).Nodup) (x : Nat) : l.lookup x = l'.lookup x := by
  cases h : l.lookup x with
  | some v => exact (lookup_of_mem hn' ((hm _).mp (lookup_some_mem h))).symm
  | none =>
    cases h' : l'.lookup x with
    | none => rfl
    | some v =>
      have := (hm _).mpr (lookup_some_mem h')
      rw [lookup_of_mem hn this] at h; cases h

theorem nodup_middle {α : Type} {a c : List α} {x : α} (h : (a ++ c).Nodup) (hx : x ∉ a ++ c) :
    (a ++ [x] ++ c).Nodup := by
  have hp : (a ++ [x] ++ c).Perm (x :: (a ++ c)) := by
    rw [List.append_assoc, List.singleton_append]; exact List.perm_middle
  exact hp.nodup_iff.mpr (List.nodup_cons.mpr ⟨hx, h⟩)

theorem nodup_snoc {α : Type} {a : List α} {x : α} (h : a.Nodup) (hx : x ∉ a) : (a ++ [x]).Nodup :=
  List.nodup_append.mpr ⟨h, List.nodup_cons.mpr ⟨List.not_mem_nil, List.nodup_nil⟩,
    fun _ ha _ hb he => by rw [List.mem_singleton] at hb; subst hb; subst he; exact hx ha⟩

/-! ## The runtime's requests against the book -/

namespace World

/-- No id is both pending and queued, or twice in either. -/
def Keys (w : World) : Prop := (w.entries.map (·.1)).Nodup

/-- How a queued request shows in `entries`. -/
def wkind (p : Nat × Request) : Nat × Request.Kind := (p.1, p.2.kind)

theorem entries_eq (w : World) : w.entries = w.pending ++ w.waiting.map wkind := rfl

theorem map_wkind_keys (l : List (Nat × Request)) : (l.map wkind).map (·.1) = l.map (·.1) := by
  simp only [List.map_map]; rfl

theorem live_none {w : World} {id : Nat} (h : w.live id = none) :
    w.pending.lookup id = none ∧ (w.waiting.map wkind).lookup id = none := by
  simp only [live, entries_eq, lookup_append, Option.or_eq_none_iff] at h
  exact h

theorem waiting_any {w : World} {id : Nat} :
    w.waiting.any (·.1 == id) = true ↔ id ∈ w.waiting.map (·.1) := by
  simp only [List.any_eq_true, beq_iff_eq, List.mem_map]

/-- An id both pending and queued contradicts `Keys`. -/
theorem keys_disjoint {w : World} (hk : w.Keys) {id : Nat} (hp : id ∈ w.pending.map (·.1))
    (hq : id ∈ w.waiting.map (·.1)) : False := by
  unfold Keys at hk
  rw [entries_eq, List.map_append, map_wkind_keys] at hk
  exact (List.nodup_append.mp hk).2.2 id hp id hq rfl

theorem waiting_filter (w : World) (id : Nat) :
    (w.queued.filter (·.2.1 != id)).map (·.2) = w.waiting.filter (·.1 != id) := by
  simp only [waiting, List.filter_map]; rfl

theorem map_wkind_filter (l : List (Nat × Request)) (id : Nat) :
    (l.filter (·.1 != id)).map wkind = (l.map wkind).filter (·.1 != id) := by
  simp only [List.filter_map]; rfl

end World

/-- The runtime's tables and a book agree: the same timers armed, and the requests the app may
still hear about (pending or queued) the same, each id once. -/
def Agrees (w : World) (b : Book) : Prop :=
  (∀ n, n ∈ w.timerNames ↔ b.armed n = true) ∧ (∀ id, w.live id = b.pending id) ∧ w.Keys

theorem mem_setTimer (w : World) (n x : String) (ms : Nat) :
    x ∈ (w.setTimer n ms).timerNames ↔ x = n ∨ x ∈ w.timerNames := by
  simp only [World.timerNames, World.setTimer, List.map_append, List.mem_append, List.mem_map,
    List.mem_filter, List.map_cons, List.map_nil, List.mem_cons, List.not_mem_nil, or_false]
  constructor
  · rintro (⟨p, ⟨hp, -⟩, rfl⟩ | h)
    · exact Or.inr ⟨p, hp, rfl⟩
    · exact Or.inl h
  · rintro (h | ⟨p, hp, rfl⟩)
    · exact Or.inr h
    · by_cases he : p.1 = n
      · exact Or.inr he
      · exact Or.inl ⟨p, ⟨hp, bne_iff_ne.mpr he⟩, rfl⟩

theorem mem_cancelTimer (w : World) (n x : String) :
    x ∈ (w.cancelTimer n).timerNames ↔ x ≠ n ∧ x ∈ w.timerNames := by
  simp only [World.timerNames, World.cancelTimer, List.mem_map, List.mem_filter, bne_iff_ne,
    ne_eq]
  constructor
  · rintro ⟨p, ⟨hp, hn⟩, rfl⟩; exact ⟨hn, p, hp, rfl⟩
  · rintro ⟨hn, p, hp, rfl⟩; exact ⟨p, ⟨hp, hn⟩, rfl⟩

/-- Sending a request with a fresh id. -/
theorem send_agrees {w : World} {b : Book} (h : Agrees w b) {id : Nat} (k : Request.Kind)
    (hb : b.pending id = none) :
    Agrees (w.send id k) { b with pending := fun x => if x = id then some k else b.pending x } := by
  obtain ⟨ht, hp, hk⟩ := h
  have hl : w.live id = none := (hp id).trans hb
  obtain ⟨h1, h2⟩ := World.live_none hl
  have hnot : id ∉ w.entries.map (·.1) := fun m =>
    by rw [← lookup_isSome_iff] at m; simp only [World.live] at hl; rw [hl] at m; cases m
  refine ⟨ht, fun x => ?_, ?_⟩
  · show (w.pending ++ [(id, k)] ++ w.waiting.map World.wkind).lookup x = _
    rw [lookup_append, lookup_append]
    by_cases hx : x = id
    · subst hx; simp only [h1, List.lookup, beq_self_eq_true, Option.none_or, Option.some_or, ↓reduceIte]
    · simp only [List.lookup, beq_eq_false_iff_ne.mpr hx, Option.or_none, hx, ↓reduceIte]
      rw [← hp x, World.live, World.entries_eq, lookup_append]
  · show ((w.pending ++ [(id, k)] ++ w.waiting.map World.wkind).map (·.1)).Nodup
    simp only [List.map_append, List.map_cons, List.map_nil]
    have := hk; unfold World.Keys at this; rw [World.entries_eq, List.map_append] at this hnot
    exact nodup_middle this hnot

/-- Queueing a request with a fresh id. -/
theorem enqueue_agrees {w : World} {b : Book} (h : Agrees w b) {id : Nat} (r : Request)
    (hb : b.pending id = none) :
    Agrees (w.enqueue id r) { b with pending := fun x => if x = id then some r.kind else b.pending x } := by
  obtain ⟨ht, hp, hk⟩ := h
  have hl : w.live id = none := (hp id).trans hb
  have hnot : id ∉ w.entries.map (·.1) := fun m =>
    by rw [← lookup_isSome_iff] at m; simp only [World.live] at hl; rw [hl] at m; cases m
  have he : (w.enqueue id r).entries = w.entries ++ [(id, r.kind)] := by
    simp only [World.entries, World.enqueue, World.waiting, List.map_append, List.map_cons,
      List.map_nil, List.append_assoc]
  refine ⟨ht, fun x => ?_, ?_⟩
  · show (w.enqueue id r).entries.lookup x = _
    rw [he, lookup_append]
    by_cases hx : x = id
    · subst hx; simp only [World.live] at hl
      simp only [hl, List.lookup, beq_self_eq_true, Option.none_or, ↓reduceIte]
    · simp only [List.lookup, beq_eq_false_iff_ne.mpr hx, Option.or_none, hx, ↓reduceIte]
      exact hp x
  · show ((w.enqueue id r).entries.map (·.1)).Nodup
    rw [he, List.map_append]
    exact nodup_snoc hk hnot

theorem cancel_agrees {w : World} {b : Book} (h : Agrees w b) (id : Nat) :
    Agrees (w.cancel id).1 (b.drop id) := by
  obtain ⟨ht, hp, hk⟩ := h
  unfold World.cancel
  split
  · rename_i hq
    have hq := World.waiting_any.mp hq
    have hpn : w.pending.lookup id = none :=
      lookup_none_of fun m => World.keys_disjoint hk m hq
    refine ⟨ht, fun x => ?_, ?_⟩
    · show (w.pending ++ ((w.queued.filter (·.2.1 != id)).map (·.2)).map World.wkind).lookup x = _
      rw [World.waiting_filter, World.map_wkind_filter, lookup_append, lookup_filter]
      by_cases hx : x = id
      · subst hx; simp only [hpn, ↓reduceIte, Option.or_none, Book.drop]
      · simp only [hx, ↓reduceIte, Book.drop]; rw [← hp x, World.live, World.entries_eq, lookup_append]
    · show ((w.pending ++ ((w.queued.filter (·.2.1 != id)).map (·.2)).map World.wkind).map (·.1)).Nodup
      rw [World.waiting_filter, World.map_wkind_filter]
      exact List.Nodup.sublist ((List.Sublist.append (List.Sublist.refl _) List.filter_sublist).map _) hk
  · rename_i hq
    have hq : id ∉ w.waiting.map (·.1) := fun m => hq (World.waiting_any.mpr m)
    have hwn : (w.waiting.map World.wkind).lookup id = none := by
      apply lookup_none_of; rw [World.map_wkind_keys]; exact hq
    split
    · refine ⟨ht, fun x => ?_, ?_⟩
      · show (w.pending.filter (·.1 != id) ++ w.waiting.map World.wkind).lookup x = _
        rw [lookup_append, lookup_filter]
        by_cases hx : x = id
        · subst hx; simp only [hwn, ↓reduceIte, Option.none_or, Book.drop]
        · simp only [hx, ↓reduceIte, Book.drop]; rw [← hp x, World.live, World.entries_eq, lookup_append]
      · show ((w.pending.filter (·.1 != id) ++ w.waiting.map World.wkind).map (·.1)).Nodup
        exact List.Nodup.sublist ((List.Sublist.append List.filter_sublist (List.Sublist.refl _)).map _) hk
    · rename_i hpn
      refine ⟨ht, fun x => ?_, hk⟩
      simp only [Book.drop]
      by_cases hx : x = id
      · subst hx; simp only [↓reduceIte, World.live, World.entries_eq, lookup_append, hpn, hwn,
          Option.or_none]
      · simp only [hx, ↓reduceIte]; exact hp x

theorem absorb1_agrees {w : World} {b : Book} (h : Agrees w b) (e : Effect) :
    Agrees (w.absorb1 e).1 (b.take e) := by
  have h0 := h
  obtain ⟨ht, hp, hk⟩ := h
  cases e
  case setTimer n ms =>
    refine ⟨fun x => ?_, hp, hk⟩
    show x ∈ (w.setTimer n ms).timerNames ↔ (if x = n then true else b.armed x) = true
    rw [mem_setTimer, ht]
    by_cases hx : x = n <;> simp only [hx, ↓reduceIte, true_or, false_or]
  case cancelTimer n =>
    refine ⟨fun x => ?_, hp, hk⟩
    show x ∈ (w.cancelTimer n).timerNames ↔ (if x = n then false else b.armed x) = true
    rw [mem_cancelTimer, ht]
    by_cases hx : x = n <;> simp only [hx, ↓reduceIte, ne_eq, not_true_eq_false, false_and,
      Bool.false_eq_true, not_false_eq_true, true_and]
  case request id r =>
    have hli : w.isLive id = (b.pending id).isSome := by rw [World.isLive, hp]
    cases hb : b.pending id with
    | some k =>
      simp only [World.absorb1, Book.take, hli, hb, Option.isSome_some, ↓reduceIte]
      exact h0
    | none =>
      simp only [World.absorb1, Book.take, hli, hb, Option.isSome_none, Bool.false_eq_true,
        ↓reduceIte]
      split
      · exact send_agrees h0 _ hb
      · exact enqueue_agrees h0 _ hb
  case cancelRequest id => exact cancel_agrees h0 id
  all_goals exact h0

theorem absorb_agrees (es : List Effect) :
    ∀ {w : World} {b : Book}, Agrees w b → Agrees (w.absorb es).1 (b.takeAll es) := by
  induction es with
  | nil => intro w b h; exact h
  | cons e es ih => intro w b h; rw [absorb_cons]; exact ih (absorb1_agrees h e)

theorem takeReply_some {w w' : World} {id : Nat} {r : Reply} (h : w.takeReply id r = some w') :
    ∃ k, w.pending.lookup id = some k ∧ r.answers k = true ∧
      w' = { w with pending := w.pending.filter (fun p => p.1 != id) } := by
  unfold World.takeReply at h
  split at h
  · rename_i k hk
    split at h
    · exact ⟨k, hk, by assumption, (Option.some.inj h).symm⟩
    · cases h
  · cases h

/-! ## Taking replies and sending from the queue keep the book -/

/-- How a queued request shows in `entries`. -/
def qkind (q : Nat × Nat × Request) : Nat × Request.Kind := (q.2.1, q.2.2.kind)

theorem entries_queued (w : World) : w.entries = w.pending ++ w.queued.map qkind := by
  simp only [World.entries, World.waiting, List.map_map]; rfl

/-- `promoteGo` moves the requests it is given into `pending` or the queue, touching nothing
else. -/
theorem promoteGo_spec (rest : List (Nat × Nat × Request)) : ∀ (w : World),
    (∃ p q, (World.promoteGo w rest).1 = { w with pending := p, queued := q }) ∧
      ((World.promoteGo w rest).1.entries).Perm (w.entries ++ rest.map qkind) := by
  induction rest with
  | nil => intro w; exact ⟨⟨w.pending, w.queued, rfl⟩, by simp only [World.promoteGo, List.map_nil, List.append_nil]; exact List.Perm.refl _⟩
  | cons q rest ih =>
    intro w
    simp only [World.promoteGo]
    split
    · obtain ⟨⟨p, q', he⟩, hp⟩ := ih (w.send q.2.1 q.2.2.kind)
      refine ⟨⟨p, q', by rw [he]; rfl⟩, hp.trans ?_⟩
      simp only [entries_queued, World.send, List.map_cons, List.append_assoc, List.singleton_append]
      exact List.Perm.append_left _ List.perm_middle.symm
    · obtain ⟨⟨p, q', he⟩, hp⟩ := ih { w with queued := w.queued ++ [q] }
      refine ⟨⟨p, q', by rw [he]⟩, hp.trans ?_⟩
      simp only [entries_queued, List.map_append, List.map_cons, List.map_nil, List.append_assoc,
        List.singleton_append]
      exact List.Perm.refl _

theorem promote_spec (w : World) :
    (∃ p q, w.promote.1 = { w with pending := p, queued := q }) ∧ (w.promote.1.entries).Perm w.entries := by
  obtain ⟨⟨p, q, he⟩, hp⟩ := promoteGo_spec w.queued { w with queued := [] }
  refine ⟨⟨p, q, by unfold World.promote; rw [he]⟩, ?_⟩
  unfold World.promote
  refine hp.trans ?_
  simp only [entries_queued, List.map_nil, List.append_nil]
  exact List.Perm.refl _

theorem agrees_entries {w w' : World} {b : Book} (ht : w'.timers = w.timers)
    (hp : w'.entries.Perm w.entries) (h : Agrees w b) : Agrees w' b := by
  obtain ⟨h1, h2, h3⟩ := h
  have hk' : w'.Keys := (hp.map (fun p : Nat × Request.Kind => p.1)).nodup_iff.mpr h3
  refine ⟨fun n => by unfold World.timerNames; rw [ht]; exact h1 n, fun x => ?_, hk'⟩
  rw [← h2 x]
  exact lookup_congr (fun _ => hp.mem_iff) hk' h3 x

theorem promote_agrees {w : World} {b : Book} (h : Agrees w b) : Agrees w.promote.1 b := by
  obtain ⟨⟨p, q, he⟩, hp⟩ := promote_spec w
  exact agrees_entries (by rw [he]) hp h

theorem takeStop_some {w w' : World} {id : Nat} (h : w.takeStop id = some w') :
    w.isStopping id = true ∧ w' = { w with stopping := w.stopping.filter (·.1 != id) } := by
  unfold World.takeStop at h
  split at h
  · exact ⟨by assumption, (Option.some.inj h).symm⟩
  · cases h

theorem takeStop_agrees {w w' : World} {b : Book} {id : Nat} (h : Agrees w b)
    (hw : w.takeStop id = some w') : Agrees w' b := by
  obtain ⟨-, rfl⟩ := takeStop_some hw
  exact agrees_entries rfl (List.Perm.refl _) h

theorem takeReply_agrees {w w' : World} {b : Book} {id : Nat} {r : Reply} (h : Agrees w b)
    (hw : w.takeReply id r = some w') : Agrees w' (b.drop id) := by
  obtain ⟨k, hk, -, rfl⟩ := takeReply_some hw
  obtain ⟨ht, hp, hkeys⟩ := h
  have hin : id ∈ w.pending.map (·.1) := List.mem_map.mpr ⟨(id, k), lookup_some_mem hk, rfl⟩
  have hwn : (w.waiting.map World.wkind).lookup id = none := by
    apply lookup_none_of; rw [World.map_wkind_keys]; exact fun m => World.keys_disjoint hkeys hin m
  refine ⟨ht, fun x => ?_, ?_⟩
  · show (w.pending.filter (·.1 != id) ++ w.waiting.map World.wkind).lookup x = _
    rw [lookup_append, lookup_filter]
    by_cases hx : x = id
    · subst hx; simp only [hwn, ↓reduceIte, Option.none_or, Book.drop]
    · simp only [hx, ↓reduceIte, Book.drop]; rw [← hp x, World.live, World.entries_eq, lookup_append]
  · show ((w.pending.filter (·.1 != id) ++ w.waiting.map World.wkind).map (·.1)).Nodup
    exact List.Nodup.sublist ((List.Sublist.append List.filter_sublist (List.Sublist.refl _)).map _) hkeys

/-- A pending request is live, with its kind. -/
theorem live_of_pending {w : World} {id : Nat} {k : Request.Kind} (h : w.pending.lookup id = some k) :
    w.live id = some k := by
  simp only [World.live, World.entries_eq, lookup_append, h, Option.some_or]

/-! ## The recording wrapper -/

def logUpdate (app : App S) (st : S × List Entry) (a : Action) : (S × List Entry) × List Effect :=
  let r := app.update st.1 a
  ((r.1, st.2 ++ [.upd a r.2]), r.2)

def logReceive (app : App S) (st : S × List Entry) (m : Msg) : (S × List Entry) × List Effect :=
  let r := app.receive st.1 m
  ((r.1, st.2 ++ [.recv m r.2]), r.2)

/-- `app`, with a log of every delivery in its state. It behaves as `app` does: every field
reads only the first component. -/
def logged (app : App S) : App (S × List Entry) where
  init := (app.init, [])
  surfaces := app.surfaces.map (Surface.comap Prod.fst)
  update := logUpdate app
  receive := logReceive app
  subscriptions st := app.subscriptions st.1
  initEffects := app.initEffects
  claims := app.claims
  initFocus := app.initFocus
  keepScroll st := app.keepScroll st.1

theorem deliver_acc (u : S → Action → S × List Effect) (acts : List Action) :
    ∀ (st : S) (effs : List Effect),
      acts.foldl (fun (st, effs) a => let (st', e) := u st a; (st', effs ++ e)) (st, effs) =
        ((deliver u st acts).1, effs ++ (deliver u st acts).2) := by
  induction acts with
  | nil => intro st effs; simp only [List.foldl_nil, deliver, List.append_nil]
  | cons a acts ih =>
    intro st effs
    simp only [deliver, List.foldl_cons]
    rw [ih, ih (u st a).1 ([] ++ (u st a).2)]
    simp only [List.nil_append, List.append_assoc]

theorem deliver_cons (u : S → Action → S × List Effect) (st : S) (a : Action) (acts : List Action) :
    deliver u st (a :: acts) =
      ((deliver u (u st a).1 acts).1, (u st a).2 ++ (deliver u (u st a).1 acts).2) := by
  simp only [deliver, List.foldl_cons]
  rw [deliver_acc]
  simp only [List.nil_append]
  rfl

theorem deliver_logged (app : App S) (acts : List Action) :
    ∀ (st : S × List Entry), ∃ ups, (deliver (logUpdate app) st acts).1.2 = st.2 ++ ups ∧
      ∀ b : Book, b.run ups = some (b.takeAll (deliver (logUpdate app) st acts).2) := by
  induction acts with
  | nil => intro st; exact ⟨[], by simp only [deliver, List.foldl_nil, List.append_nil],
      fun b => rfl⟩
  | cons a acts ih =>
    intro st
    obtain ⟨ups, h1, h2⟩ := ih (logUpdate app st a).1
    refine ⟨.upd a (app.update st.1 a).2 :: ups, ?_, fun b => ?_⟩
    · rw [deliver_cons, h1]; simp only [logUpdate, List.append_assoc, List.singleton_append]
    · rw [deliver_cons, Book.takeAll_append]
      exact h2 _

/-! ## Each part of a step keeps the book -/

/-- A context whose log extends `log0` by entries the book `b0` allows, ending at a book that
agrees with the context's world. -/
def Inv (log0 : List Entry) (b0 : Book) (c : Ctx (S × List Entry)) : Prop :=
  ∃ new b, c.app.2 = log0 ++ new ∧ b0.run new = some b ∧ Agrees c.world b

theorem give_inv (app : App S) {log0 : List Entry} {b0 b : Book} {c : Ctx (S × List Entry)}
    {new : List Entry} {m : Msg} (hl : c.app.2 = log0 ++ new) (hr : b0.run new = some b)
    (ha : b.admits m = true) (hw : Agrees c.world (b.pre m)) :
    Inv log0 b0 (give (logged app) c m) := by
  refine ⟨new ++ [.recv m (app.receive c.app.1 m).2],
    (b.pre m).takeAll (app.receive c.app.1 m).2, ?_, ?_, ?_⟩
  · simp only [give, logged, logReceive, hl, List.append_assoc]
  · rw [Book.run_append, hr]; simp only [Option.bind_some, Book.run, ha, ↓reduceIte]
  · exact absorb_agrees _ hw

theorem hear_inv (app : App S) {log0 : List Entry} {b0 : Book} {c : Ctx (S × List Entry)}
    (h : Inv log0 b0 c) : Inv log0 b0 (hear (logged app) c) := by
  unfold hear; split
  · exact h
  · obtain ⟨new, b, hl, hr, ha⟩ := h
    exact give_inv app hl hr rfl ha

theorem fire_inv (app : App S) {log0 : List Entry} {b0 : Book} {c : Ctx (S × List Entry)}
    (n : String) (h : Inv log0 b0 c) : Inv log0 b0 (fire (logged app) c n) := by
  unfold fire; split
  · rename_i hd
    obtain ⟨new, b, hl, hr, ha⟩ := h
    have hn : n ∈ c.world.timerNames := by
      simp only [World.dueNow, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at hd
      obtain ⟨p, hp, he, -⟩ := hd
      exact List.mem_map.mpr ⟨p, hp, he⟩
    exact give_inv app hl hr ((ha.1 n).mp hn) (absorb1_agrees ha (.cancelTimer n))
  · exact h

theorem foldl_fire_inv (app : App S) {log0 : List Entry} {b0 : Book} (ns : List String) :
    ∀ {c : Ctx (S × List Entry)}, Inv log0 b0 c → Inv log0 b0 (ns.foldl (fire (logged app)) c) := by
  induction ns with
  | nil => intro c h; exact h
  | cons n ns ih => intro c h; exact ih (fire_inv app n h)

theorem boot_booted (app : App S) (c : Ctx S) (h : c.world.booted = true) : boot app c = c := by
  simp only [boot, h, ↓reduceIte]

theorem ack_inv {log0 : List Entry} {b0 : Book} {c : Ctx (S × List Entry)}
    (h : Inv log0 b0 c) (id : Nat) : Inv log0 b0 (ack c id) := by
  unfold ack; split
  · rename_i w hw
    obtain ⟨new, b, hl, hr, hag⟩ := h
    exact ⟨new, b, hl, hr, promote_agrees (takeStop_agrees hag hw)⟩
  · exact h

theorem admit_inv (app : App S) (s : State (S × List Entry)) (e : Event)
    (hb : s.world.booted = true) {b0 : Book} (ha : Agrees s.world b0) :
    Inv s.app.2 b0 (admit (logged app) s e) := by
  have base : Inv s.app.2 b0 ({ app := s.app, world := s.world } : Ctx (S × List Entry)) :=
    ⟨[], b0, (List.append_nil _).symm, rfl, ha⟩
  cases e <;> simp only [admit] <;> (try exact base)
  case clock t =>
    rw [boot_booted _ _ hb]
    have bt : Inv s.app.2 b0 ({ app := s.app, world := s.world.tick t } : Ctx (S × List Entry)) :=
      ⟨[], b0, (List.append_nil _).symm, rfl, ha⟩
    split
    · exact bt
    · exact foldl_fire_inv app _ (hear_inv app bt)
  case reply id r =>
    split
    · have hh := hear_inv app base
      split
      · rename_i w hw
        obtain ⟨new, b, hl, hr, hag⟩ := hh
        obtain ⟨k, hk, hans, -⟩ := takeReply_some hw
        have hbk : b.pending id = some k := (hag.2.1 id).symm.trans (live_of_pending hk)
        refine give_inv app hl hr ?_ (promote_agrees (takeReply_agrees hag hw))
        simp only [Book.admits, hbk, hans]
      · exact ack_inv hh id
    · exact ack_inv base id
  case subEvent id ev =>
    split
    · obtain ⟨new, b, hl, hr, hag⟩ := hear_inv app base
      exact give_inv app hl hr rfl hag
    · exact base

theorem act_inv (app : App S) {log0 : List Entry} {b0 : Book} {c : Ctx (S × List Entry)}
    (acts : List Action) (h : Inv log0 b0 c) : Inv log0 b0 (act (logged app) c acts) := by
  unfold act; split
  · exact h
  · obtain ⟨new, b, hl, hr, ha⟩ := hear_inv app h
    generalize hear (logged app) c = c' at hl hr ha
    obtain ⟨ups, h1, h2⟩ := deliver_logged app acts c'.app
    refine ⟨new ++ ups, b.takeAll (deliver (logUpdate app) c'.app acts).2, ?_, ?_, ?_⟩
    · show (deliver (logUpdate app) c'.app acts).1.2 = _
      rw [h1, hl, List.append_assoc]
    · rw [Book.run_append, hr]; exact h2 b
    · exact absorb_agrees _ ha

/-! ## Steps -/

theorem act_nil (app : App S) (c : Ctx S) : act app c [] = c := by
  simp only [act, List.isEmpty_nil, ↓reduceIte]


/-- What a step leaves in the world, and the app, is what `act` leaves after `admit`; the step
only adds the subscription diff. -/
theorem step_ctx (app : App S) (cfg : Config) (s : State S) (e : Event) :
    let c := act app (admit app s e) (route cfg.metrics s e).2
    (step app cfg s e).1.app = c.app ∧
      ∃ subs next, (step app cfg s e).1.world = { c.world with subs, nextSub := next } := by
  refine ⟨step_app app cfg s e, ?_⟩
  unfold step
  generalize route cfg.metrics s e = r
  obtain ⟨s1, acts⟩ := r
  dsimp only
  split
  · rename_i hc
    simp only [Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true, List.isEmpty_iff] at hc
    obtain ⟨⟨ha, -⟩, -⟩ := hc
    subst ha
    rw [act_nil]
    exact ⟨_, _, rfl⟩
  · exact ⟨_, _, rfl⟩

/-- One step of the recording app: the log grows by entries the book allows, and the runtime's
tables agree with the book afterwards. -/
theorem step_book (app : App S) (cfg : Config) (s : State (S × List Entry)) (e : Event)
    (hb : s.world.booted = true) {b0 : Book} (ha : Agrees s.world b0) :
    ∃ new b, (step (logged app) cfg s e).1.app.2 = s.app.2 ++ new ∧ b0.run new = some b ∧
      Agrees (step (logged app) cfg s e).1.world b := by
  obtain ⟨h1, subs, next, hw⟩ := step_ctx (logged app) cfg s e
  obtain ⟨new, b, hl, hr, hag⟩ := act_inv app (route cfg.metrics s e).2 (admit_inv app s e hb ha)
  exact ⟨new, b, h1 ▸ hl, hr, by rw [hw]; exact agrees_entries rfl (List.Perm.refl _) hag⟩

/-! ## The clock -/

/-- The clock does not go back and a booted world stays booted. -/
def Grows (w w' : World) : Prop :=
  w.clock.mono ≤ w'.clock.mono ∧ (w.booted = true → w'.booted = true)

theorem Grows.refl (w : World) : Grows w w := ⟨Nat.le_refl _, id⟩

theorem Grows.trans {a b c : World} (h1 : Grows a b) (h2 : Grows b c) : Grows a c :=
  ⟨Nat.le_trans h1.1 h2.1, fun h => h2.2 (h1.2 h)⟩

theorem Same.grows {w w' : World} (h : Same w w') : Grows w w' :=
  ⟨by rw [h.1]; exact Nat.le_refl _, fun hb => h.2.2.1.trans hb⟩

theorem give_grows (app : App S) (c : Ctx S) (m : Msg) : Grows c.world (give app c m).world :=
  (absorb_same _ _).grows

theorem give_grows' (app : App S) {w : World} {c : Ctx S} {m : Msg} (h : Grows w c.world) :
    Grows w (give app c m).world :=
  h.trans (give_grows app c m)

theorem hear_grows (app : App S) (c : Ctx S) : Grows c.world (hear app c).world := by
  unfold hear; split
  · exact Grows.refl _
  · exact give_grows' app ⟨Nat.le_refl _, fun h => h⟩

theorem fire_grows (app : App S) (c : Ctx S) (n : String) : Grows c.world (fire app c n).world := by
  unfold fire; split
  · exact give_grows' app ⟨Nat.le_refl _, fun h => h⟩
  · exact Grows.refl _

theorem foldl_fire_grows (app : App S) (ns : List String) :
    ∀ (c : Ctx S), Grows c.world (ns.foldl (fire app) c).world := by
  induction ns with
  | nil => intro c; exact Grows.refl _
  | cons n ns ih => intro c; exact (fire_grows app c n).trans (ih _)

theorem boot_grows (app : App S) (c : Ctx S) : Grows c.world (boot app c).world := by
  unfold boot; split
  · exact Grows.refl _
  · have h0 : Grows c.world { c.world with booted := true } := ⟨Nat.le_refl _, fun _ => rfl⟩
    have h1 := hear_grows app { c with world := { c.world with booted := true } }
    exact (h0.trans h1).trans (absorb_same _ _).grows

theorem tick_mono (w : World) (t : Time) : w.clock.mono ≤ (w.tick t).clock.mono :=
  Nat.le_max_left _ _

theorem tick_reaches (w : World) (t : Time) : t.mono ≤ (w.tick t).clock.mono :=
  Nat.le_max_right _ _

theorem admit_clock_grows (app : App S) (s : State S) (t : Time) :
    Grows (s.world.tick t) (admit app s (.clock t)).world := by
  have h1 := boot_grows app { app := s.app, world := s.world.tick t }
  simp only [admit]
  split
  · exact h1
  · exact h1.trans ((hear_grows app _).trans (foldl_fire_grows app _ _))

theorem promoteGo_same (rest : List (Nat × Nat × Request)) (w : World) :
    Same w (World.promoteGo w rest).1 := by
  obtain ⟨⟨p, q, he⟩, -⟩ := promoteGo_spec rest w
  rw [he]; exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem promote_same (w : World) : Same w w.promote.1 := by
  obtain ⟨⟨p, q, he⟩, -⟩ := promote_spec w
  rw [he]; exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem release_grows (c : Ctx S) (w : World) (h : Same c.world w) :
    Grows c.world (release c w).world :=
  (h.trans (promote_same w)).grows

theorem ack_grows (c : Ctx S) (id : Nat) : Grows c.world (ack c id).world := by
  unfold ack; split
  · rename_i w hw
    obtain ⟨-, rfl⟩ := takeStop_some hw
    exact release_grows c _ ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
  · exact Grows.refl _

theorem admit_grows (app : App S) (s : State S) (e : Event) :
    Grows s.world (admit app s e).world := by
  cases e
  case clock t => exact (show Grows s.world (s.world.tick t) from ⟨tick_mono _ _, id⟩).trans
                    (admit_clock_grows app s t)
  case reply id r =>
    simp only [admit]
    split
    · have hh := hear_grows app ({ app := s.app, world := s.world } : Ctx S)
      split
      · rename_i w hw
        obtain ⟨k, -, -, rfl⟩ := takeReply_some hw
        exact give_grows' app (hh.trans (release_grows _ _ ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩))
      · exact hh.trans (ack_grows _ _)
    · exact ack_grows ({ app := s.app, world := s.world } : Ctx S) id
  case subEvent id ev =>
    simp only [admit]
    split
    · exact (hear_grows app { app := s.app, world := s.world }).trans (give_grows app _ _)
    · exact Grows.refl _
  all_goals exact Grows.refl _

theorem act_grows (app : App S) (c : Ctx S) (acts : List Action) :
    Grows c.world (act app c acts).world := by
  unfold act; split
  · exact Grows.refl _
  · exact (hear_grows app c).trans (absorb_same _ _).grows

/-- A step never moves the clock back, and once the first clock has booted the app it stays
booted. -/
theorem step_clock (app : App S) (cfg : Config) (s : State S) (e : Event) :
    Grows s.world (step app cfg s e).1.world := by
  obtain ⟨-, subs, next, hw⟩ := step_ctx app cfg s e
  have h := (admit_grows app s e).trans (act_grows app _ (route cfg.metrics s e).2)
  rw [hw]; exact h

/-- A clock event brings the runtime's clock at least to the host's time. -/
theorem step_clock_reaches (app : App S) (cfg : Config) (s : State S) (t : Time) :
    t.mono ≤ (step app cfg s (.clock t)).1.world.clock.mono := by
  obtain ⟨-, subs, next, hw⟩ := step_ctx app cfg s (.clock t)
  have h := (admit_clock_grows app s t).trans (act_grows app _ (route cfg.metrics s (.clock t)).2)
  rw [hw]
  exact Nat.le_trans (tick_reaches _ _) h.1

/-! ## Batches -/

theorem steps_go (app : App S) (cfg : Config) (P : State S → Prop)
    (hstep : ∀ s e, P s → P (step app cfg s e).1) (es : List Event) :
    ∀ (s : State S) (effs : List Effect), P s →
      P (es.foldl (fun (s, effs) e => let (s', e') := step app cfg s e; (s', effs ++ e'))
        (s, effs)).1 := by
  induction es with
  | nil => intro s effs h; exact h
  | cons e es ih => intro s effs h; exact ih _ _ (hstep s e h)

/-- A batch never moves the clock back. -/
theorem steps_clock (app : App S) (cfg : Config) (s : State S) (es : List Event) :
    s.world.clock.mono ≤ (steps app cfg s es).1.world.clock.mono ∧
      (s.world.booted = true → (steps app cfg s es).1.world.booted = true) :=
  steps_go app cfg (fun s' => Grows s.world s'.world)
    (fun s' e h => h.trans (step_clock app cfg s' e)) (es ++ frameEvents) s [] (Grows.refl _)

/-- **Timers and replies.** Over any batch of events after the first clock, everything
delivered to the app is allowed by the book: a timer reaches `receive` only while it is set
(never after `cancelTimer`, and once per `setTimer`), and a reply only to a pending request of
the kind it answers, once. And the runtime's tables still agree with the book at the end. -/
theorem steps_book (app : App S) (cfg : Config) (s : State (S × List Entry)) (es : List Event)
    (hb : s.world.booted = true) {b0 : Book} (ha : Agrees s.world b0) :
    ∃ new b, (steps (logged app) cfg s es).1.app.2 = s.app.2 ++ new ∧ b0.run new = some b ∧
      Agrees (steps (logged app) cfg s es).1.world b := by
  have := steps_go (logged app) cfg
    (fun s' => s'.world.booted = true ∧ ∃ new b, s'.app.2 = s.app.2 ++ new ∧ b0.run new = some b ∧
      Agrees s'.world b)
    (fun s' e ⟨hb', new, b, hl, hr, hag⟩ => by
      obtain ⟨new', b', hl', hr', hag'⟩ := step_book app cfg s' e hb' hag
      refine ⟨(step_clock (logged app) cfg s' e).2 hb', new ++ new', b', ?_, ?_, hag'⟩
      · rw [hl', hl, List.append_assoc]
      · rw [Book.run_append, hr]; exact hr')
    (es ++ frameEvents) s [] ⟨hb, [], b0, (List.append_nil _).symm, rfl, ha⟩
  exact this.2

/-! ## Replies and subscription events -/

theorem absorb1_pending (w : World) (e : Effect) {id : Nat} {k : Request.Kind}
    (he : e ≠ .cancelRequest id) (h : w.pending.lookup id = some k) :
    (w.absorb1 e).1.pending.lookup id = some k := by
  cases e <;> simp only [World.absorb1] <;> (try exact h)
  case request id' r =>
    split
    · exact h
    · split
      · simp only [World.send, lookup_append, h, Option.some_or]
      · exact h
  case cancelRequest j =>
    have hj : j ≠ id := fun e => he (e ▸ rfl)
    unfold World.cancel; split
    · exact h
    · split
      · show (w.pending.filter (·.1 != j)).lookup id = _
        rw [lookup_filter]; simp only [hj.symm, ↓reduceIte, h]
      · exact h

theorem absorb_pending (es : List Effect) :
    ∀ (w : World) {id : Nat} {k : Request.Kind}, Effect.cancelRequest id ∉ es →
      w.pending.lookup id = some k → (w.absorb es).1.pending.lookup id = some k := by
  induction es with
  | nil => intro w id k _ h; exact h
  | cons e es ih =>
    intro w id k hn h
    rw [absorb_cons]
    exact ih _ (fun m => hn (List.mem_cons_of_mem _ m))
      (absorb1_pending w e (fun he => hn (he ▸ List.mem_cons_self)) h)

/-- The app does not withdraw request `id` when it hears the time. -/
def KeepsOnClock (app : App S) (id : Nat) : Prop :=
  ∀ st t, Effect.cancelRequest id ∉ (app.receive st (.clock t)).2

theorem hear_pending (app : App S) (c : Ctx S) {id : Nat} {k : Request.Kind}
    (hq : KeepsOnClock app id)
    (h : c.world.pending.lookup id = some k) : (hear app c).world.pending.lookup id = some k := by
  unfold hear; split
  · exact h
  · exact absorb_pending _ _ (hq _ _) h

theorem route_reply (m : TextMetrics) (s : State S) (id : Nat) (r : Reply) :
    (route m s (.reply id r)).2 = [] := rfl

theorem route_subEvent (m : TextMetrics) (s : State S) (id : Nat) (ev : SubEvent) :
    (route m s (.subEvent id ev)).2 = [] := rfl

/-- A reply to a pending request, in the shape that answers it, is delivered to `receive`
with the id it was requested under: it is the last thing the app hears in that step. (Unless the
app withdrew the request on hearing the time just before: then it is swallowed,
`step_reply_cancelled`.) -/
theorem step_reply (app : App S) (cfg : Config) (s : State (S × List Entry)) {id : Nat}
    {r : Reply} {k : Request.Kind} (hk : s.world.pending.lookup id = some k)
    (ha : r.answers k = true) (hq : KeepsOnClock app id) :
    ∃ es, (step (logged app) cfg s (.reply id r)).1.app.2.getLast? = some (.recv (.reply id r) es) := by
  rw [(step_ctx (logged app) cfg s (.reply id r)).1, route_reply, act_nil]
  have ht : ∀ w : World, w.pending.lookup id = some k →
      w.takeReply id r = some { w with pending := w.pending.filter (fun p => p.1 != id) } := by
    intro w hw; simp only [World.takeReply, hw, ha, ↓reduceIte]
  simp only [admit, ht s.world hk, Option.isSome_some, ↓reduceIte]
  have hh := hear_pending (logged app) ({ app := s.app, world := s.world } : Ctx _) (fun st t => hq st.1 t) hk
  generalize hear (logged app) { app := s.app, world := s.world } = c at hh
  simp only [ht c.world hh, give, release_app, logged, logReceive, List.getLast?_append,
    List.getLast?_singleton, Option.some_or]
  exact ⟨_, rfl⟩

/-- A reply to an id that is not pending, or in the wrong shape, reaches no one. -/
theorem step_reply_ignored (app : App S) (cfg : Config) (s : State S) {id : Nat} {r : Reply}
    (h : s.world.takeReply id r = none) : (step app cfg s (.reply id r)).1.app = s.app := by
  rw [step_app, route_reply, act_nil]
  simp only [admit, h, Option.isSome_none, Bool.false_eq_true, ↓reduceIte, ack_app]

/-- An event from an active subscription is delivered as that subscription's message. -/
theorem step_sub (app : App S) (cfg : Config) (s : State (S × List Entry)) {id : Nat}
    {sub : Sub} (ev : SubEvent) (h : s.world.subOf id = some sub) :
    ∃ es, (step (logged app) cfg s (.subEvent id ev)).1.app.2.getLast? =
      some (.recv (.sub sub ev) es) := by
  rw [(step_ctx (logged app) cfg s (.subEvent id ev)).1, route_subEvent, act_nil]
  simp only [admit, h, give, logged, logReceive, List.getLast?_append, List.getLast?_singleton,
    Option.some_or]
  exact ⟨_, rfl⟩

/-- An event for a subscription that is not active (stopped, or never started) reaches no
one. -/
theorem step_sub_ignored (app : App S) (cfg : Config) (s : State S) {id : Nat} (ev : SubEvent)
    (h : s.world.subOf id = none) : (step app cfg s (.subEvent id ev)).1.app = s.app := by
  rw [step_app, route_subEvent, act_nil]
  simp only [admit, h]

/-! ## Subscription diffs -/

theorem mem_freshSubs (want : List Sub) :
    ∀ (seen : List Sub) (x : Sub), x ∈ freshSubs seen want ↔ x ∈ want ∧ x ∉ seen := by
  induction want with
  | nil => intro seen x; simp only [freshSubs, List.not_mem_nil, false_and]
  | cons a want ih =>
    intro seen x
    simp only [freshSubs]
    split
    · rename_i ha
      rw [ih, List.mem_cons]
      have ha : a ∈ seen := by simpa using ha
      constructor
      · rintro ⟨h1, h2⟩; exact ⟨Or.inr h1, h2⟩
      · rintro ⟨h1 | h1, h2⟩
        · subst h1; exact absurd ha h2
        · exact ⟨h1, h2⟩
    · rename_i ha
      have ha : a ∉ seen := by simpa using ha
      rw [List.mem_cons, ih, List.mem_cons, List.mem_cons]
      constructor
      · rintro (rfl | ⟨h1, h2⟩)
        · exact ⟨Or.inl rfl, ha⟩
        · exact ⟨Or.inr h1, fun h => h2 (Or.inr h)⟩
      · rintro ⟨h1, h2⟩
        by_cases hx : x = a
        · exact Or.inl hx
        · exact Or.inr ⟨h1.resolve_left hx, fun h => h.elim hx h2⟩

theorem mem_number (l : List Sub) :
    ∀ (n id : Nat) (x : Sub), (id, x) ∈ number n l → x ∈ l ∧ n ≤ id ∧ id < n + l.length := by
  induction l with
  | nil => intro n id x h; simp only [number, List.not_mem_nil] at h
  | cons a l ih =>
    intro n id x h
    simp only [number, List.mem_cons, Prod.mk.injEq] at h
    rcases h with ⟨rfl, rfl⟩ | h
    · exact ⟨List.mem_cons_self, Nat.le_refl _, by simp only [List.length_cons]; omega⟩
    · obtain ⟨h1, h2, h3⟩ := ih (n + 1) id x h
      exact ⟨List.mem_cons_of_mem _ h1, by omega, by simp only [List.length_cons]; omega⟩

theorem number_mem (l : List Sub) : ∀ (n : Nat) (x : Sub), x ∈ l → ∃ id, (id, x) ∈ number n l := by
  induction l with
  | nil => intro n x h; simp only [List.not_mem_nil] at h
  | cons a l ih =>
    intro n x h
    rcases List.mem_cons.mp h with rfl | h
    · exact ⟨n, by simp only [number, List.mem_cons, true_or]⟩
    · obtain ⟨id, hid⟩ := ih (n + 1) x h
      exact ⟨id, by simp only [number, List.mem_cons, hid, or_true]⟩

theorem contains_false {l : List Sub} {x : Sub} : (!l.contains x) = true ↔ x ∉ l := by
  rw [Bool.not_eq_true', ← Bool.not_eq_true, List.contains_iff_mem]

/-- The diff stops exactly the running subscriptions the app no longer wants. -/
theorem diffSubs_stop (active : List (Nat × Sub)) (want : List Sub) (next id : Nat) :
    SubCmd.stop id ∈ (diffSubs active want next).2.1 ↔ ∃ sub, (id, sub) ∈ active ∧ sub ∉ want := by
  simp only [diffSubs, List.mem_append, List.mem_map, List.mem_filter, contains_false]
  constructor
  · rintro (⟨⟨i, sub⟩, ⟨hp, hw⟩, he⟩ | ⟨p, -, he⟩)
    · cases he; exact ⟨sub, hp, hw⟩
    · cases he
  · rintro ⟨sub, hp, hw⟩
    exact Or.inl ⟨(id, sub), ⟨hp, hw⟩, rfl⟩

/-- The new subscriptions the diff starts, under the ids it gives them. -/
theorem diffSubs_start (active : List (Nat × Sub)) (want : List Sub) (next id : Nat) (sub : Sub) :
    SubCmd.start id sub ∈ (diffSubs active want next).2.1 ↔
      (id, sub) ∈ number next (freshSubs ((active.filter fun p => want.contains p.2).map (·.2)) want) := by
  simp only [diffSubs, List.mem_append, List.mem_map]
  constructor
  · rintro (⟨p, -, he⟩ | ⟨⟨i, x⟩, hp, he⟩)
    · cases he
    · cases he; exact hp
  · intro h; exact Or.inr ⟨(id, sub), h, rfl⟩

theorem fresh_iff (active : List (Nat × Sub)) (want : List Sub) (sub : Sub) :
    sub ∈ freshSubs ((active.filter fun p => want.contains p.2).map (·.2)) want ↔
      sub ∈ want ∧ ∀ id, (id, sub) ∉ active := by
  rw [mem_freshSubs]
  simp only [List.mem_map, List.mem_filter, List.contains_iff_mem, not_exists, not_and]
  constructor
  · rintro ⟨hw, hn⟩
    exact ⟨hw, fun id hp => hn (id, sub) ⟨hp, hw⟩ rfl⟩
  · rintro ⟨hw, hn⟩
    exact ⟨hw, fun ⟨i, x⟩ ⟨hp, _⟩ he => by cases he; exact hn i hp⟩

/-- The diff starts exactly the wanted subscriptions that are not running, each once. -/
theorem diffSubs_starts (active : List (Nat × Sub)) (want : List Sub) (next : Nat) (sub : Sub) :
    (∃ id, SubCmd.start id sub ∈ (diffSubs active want next).2.1) ↔
      sub ∈ want ∧ ∀ id, (id, sub) ∉ active := by
  simp only [diffSubs_start]
  constructor
  · rintro ⟨id, h⟩; exact (fresh_iff active want sub).mp (mem_number _ _ _ _ h).1
  · intro h; exact number_mem _ _ _ ((fresh_iff active want sub).mpr h)

/-- Started subscriptions get fresh ids: at least `next` and below the new `next`. -/
theorem diffSubs_fresh (active : List (Nat × Sub)) (want : List Sub) (next id : Nat) (sub : Sub)
    (h : SubCmd.start id sub ∈ (diffSubs active want next).2.1) :
    next ≤ id ∧ id < (diffSubs active want next).2.2 := by
  rw [diffSubs_start] at h
  obtain ⟨-, h1, h2⟩ := mem_number _ _ _ _ h
  refine ⟨h1, ?_⟩
  simp only [diffSubs]
  have : ∀ (l : List Sub) n, (number n l).length = l.length := by
    intro l; induction l with
    | nil => intro n; rfl
    | cons a l ih => intro n; simp only [number, List.length_cons, ih]
  rw [this]; exact h2

/-- After the diff, the running subscriptions are exactly the ones the app wants. -/
theorem diffSubs_active (active : List (Nat × Sub)) (want : List Sub) (next : Nat) (sub : Sub) :
    sub ∈ (diffSubs active want next).1.map (·.2) ↔ sub ∈ want := by
  simp only [diffSubs, List.map_append, List.mem_append]
  constructor
  · rintro (h | h)
    · simp only [List.mem_map, List.mem_filter, List.contains_iff_mem] at h
      obtain ⟨p, ⟨-, hw⟩, rfl⟩ := h
      exact hw
    · obtain ⟨⟨i, x⟩, hp, rfl⟩ := List.mem_map.mp h
      exact ((mem_freshSubs _ _ _).mp (mem_number _ _ _ _ hp).1).1
  · intro hw
    by_cases hk : sub ∈ (active.filter fun p => want.contains p.2).map (·.2)
    · exact Or.inl hk
    · obtain ⟨id, hid⟩ := number_mem _ next sub ((mem_freshSubs _ _ _).mpr ⟨hw, hk⟩)
      exact Or.inr (List.mem_map.mpr ⟨(id, sub), hid, rfl⟩)

theorem lookup_eq_none {β : Type} (l : List (Nat × β)) (id : Nat) (h : ∀ x, (id, x) ∉ l) :
    l.lookup id = none := by
  induction l with
  | nil => rfl
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    have ha : a ≠ id := fun he => h b (he ▸ List.mem_cons_self)
    simp only [List.lookup, beq_eq_false_iff_ne.mpr (Ne.symm ha)]
    exact ih fun x hx => h x (List.mem_cons_of_mem _ hx)

/-- A stopped subscription is gone from the active set (when ids are below `next` and name one
subscription each, as `diffSubs` keeps them), so its late events reach no one
(`step_sub_ignored`). -/
theorem diffSubs_stopped (active : List (Nat × Sub)) (want : List Sub) (next id : Nat)
    (hlt : ∀ p ∈ active, p.1 < next) (hu : ∀ a b, (id, a) ∈ active → (id, b) ∈ active → a = b)
    (h : SubCmd.stop id ∈ (diffSubs active want next).2.1) :
    (diffSubs active want next).1.lookup id = none := by
  obtain ⟨sub, hs, hw⟩ := (diffSubs_stop active want next id).mp h
  apply lookup_eq_none
  intro x hx
  simp only [diffSubs, List.mem_append, List.mem_filter, List.contains_iff_mem] at hx
  rcases hx with ⟨hx, hxw⟩ | hx
  · exact hw (hu x sub hx hs ▸ hxw)
  · have := (mem_number _ _ _ _ hx).2.1
    have := hlt _ hs
    omega

end Cairn.Runtime

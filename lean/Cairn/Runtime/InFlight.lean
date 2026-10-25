import Cairn.Runtime.WorldProofs

/-! Requests in flight (docs/effects.md, "Requests in flight"): what the runtime guarantees
about the cap, the queue and cancelled requests.

* **The cap is never exceeded**: the capped requests with the host (sent and not answered, or
  cancelled and not yet answered) never number more than `App.maxInFlight`, and the cap never
  changes (`step_cap`, `steps_cap`).
* **Nothing waits that could go**: after every event, every queued request is held either by
  the cap or by its id's cancelled request still being with the host (`step_settled`,
  `queued_blocked`).
* **Every queued request is eventually sent or cancelled**: a queued request always has a
  blocker, a request with the host, and the host's reply to a blocker either takes the request
  out of the queue or shrinks a count of what is ahead of it (`step_drains`). Nothing else ever
  grows that count (`step_wait_le`), so after finitely many replies the request has left the
  queue: sent (`promote`) or cancelled (`World.cancel`).
* **A cancelled id never delivers**: the host's reply to a request cancelled after it was sent
  reaches no app, and frees its slot (`step_reply_cancelled`); on the book's side, no reply to a
  cancelled id is admitted until it is requested again (`Book.cancel_blocks`, read with
  `steps_book`).

The statements are about a world that is `Fine` (`step_fine`, from `start_fine`). -/

namespace Cairn.Runtime

variable {S : Type}

namespace World

/-- The request tables, the cap and the next ticket are the same. -/
def Reqs (w w' : World) : Prop :=
  w'.pending = w.pending ∧ w'.queued = w.queued ∧ w'.stopping = w.stopping ∧ w'.cap = w.cap ∧
    w'.nextTicket = w.nextTicket

theorem Reqs.refl (w : World) : w.Reqs w := ⟨rfl, rfl, rfl, rfl, rfl⟩

end World

/-! ## Keeping a property through a step

The runtime changes the request tables in five ways only: absorbing an effect, taking a reply
or a cancelled request's reply (each followed by `promote`), and updates that leave the tables
alone (the clock, timers, subscriptions). A property of worlds `I`, with a relation `R` between
a world and a later one, that each of these keeps is kept by a whole step. -/

/-- `I` is kept and `R` holds across absorbing an effect and updates that leave the tables
alone. -/
structure Through (I : World → Prop) (R : World → World → Prop) : Prop where
  trans : ∀ {a b c : World}, R a b → R b c → R a c
  reqs : ∀ {w w' : World}, w.Reqs w' → I w → I w' ∧ R w w'
  absorb1 : ∀ (w : World) (e : Effect), I w → I (w.absorb1 e).1 ∧ R w (w.absorb1 e).1

/-- …and across taking a reply, or a cancelled request's reply, then sending from the queue. -/
structure Carries (I : World → Prop) (R : World → World → Prop) : Prop extends Through I R where
  reply : ∀ (w w' : World) (id : Nat) (r : Reply), I w → w.takeReply id r = some w' →
    I w'.promote.1 ∧ R w w'.promote.1
  stop : ∀ (w w' : World) (id : Nat), I w → w.takeStop id = some w' →
    I w'.promote.1 ∧ R w w'.promote.1

namespace Through

variable {I : World → Prop} {R : World → World → Prop}

theorem refl (K : Through I R) {w : World} (h : I w) : I w ∧ R w w := K.reqs (World.Reqs.refl w) h

theorem next (K : Through I R) {a b c : World} (h1 : I b ∧ R a b) (h2 : I b → I c ∧ R b c) :
    I c ∧ R a c :=
  let h := h2 h1.1
  ⟨h.1, K.trans h1.2 h.2⟩

theorem absorb (K : Through I R) (es : List Effect) :
    ∀ (w : World), I w → I (w.absorb es).1 ∧ R w (w.absorb es).1 := by
  induction es with
  | nil => intro w h; exact K.refl h
  | cons e es ih =>
    intro w h; rw [absorb_cons]
    exact K.next (K.absorb1 w e h) (ih _)

theorem give (K : Through I R) (app : App S) (c : Ctx S) (m : Msg) (h : I c.world) :
    I (give app c m).world ∧ R c.world (give app c m).world :=
  K.absorb _ _ h

theorem hear (K : Through I R) (app : App S) (c : Ctx S) (h : I c.world) :
    I (hear app c).world ∧ R c.world (hear app c).world := by
  unfold Runtime.hear; split
  · exact K.refl h
  · exact K.next (by exact K.reqs ⟨rfl, rfl, rfl, rfl, rfl⟩ h) (K.give app _ _)

theorem fire (K : Through I R) (app : App S) (c : Ctx S) (n : String) (h : I c.world) :
    I (fire app c n).world ∧ R c.world (fire app c n).world := by
  unfold Runtime.fire; split
  · exact K.next (by exact K.reqs ⟨rfl, rfl, rfl, rfl, rfl⟩ h) (K.give app _ _)
  · exact K.refl h

theorem foldl_fire (K : Through I R) (app : App S) (ns : List String) :
    ∀ (c : Ctx S), I c.world →
      I (ns.foldl (Runtime.fire app) c).world ∧ R c.world (ns.foldl (Runtime.fire app) c).world := by
  induction ns with
  | nil => intro c h; exact K.refl h
  | cons n ns ih => intro c h; exact K.next (K.fire app c n h) (ih _)

theorem boot (K : Through I R) (app : App S) (c : Ctx S) (h : I c.world) :
    I (boot app c).world ∧ R c.world (boot app c).world := by
  unfold Runtime.boot; split
  · exact K.refl h
  · exact K.next (K.next (by exact K.reqs ⟨rfl, rfl, rfl, rfl, rfl⟩ h) (K.hear app _)) (K.absorb _ _)

theorem act (K : Through I R) (app : App S) (c : Ctx S) (acts : List Action) (h : I c.world) :
    I (act app c acts).world ∧ R c.world (act app c acts).world := by
  unfold Runtime.act; split
  · exact K.refl h
  · exact K.next (K.hear app c h) (K.absorb _ _)

end Through

namespace Carries

variable {I : World → Prop} {R : World → World → Prop}

theorem ack (K : Carries I R) (c : Ctx S) (id : Nat) (h : I c.world) :
    I (ack c id).world ∧ R c.world (ack c id).world := by
  unfold Runtime.ack; split
  · rename_i w hw; exact K.stop _ _ _ h hw
  · exact K.toThrough.refl h

theorem admit (K : Carries I R) (app : App S) (s : State S) (e : Event) (h : I s.world) :
    I (admit app s e).world ∧ R s.world (admit app s e).world := by
  have K' := K.toThrough
  cases e <;> simp only [Runtime.admit] <;> (try exact K'.refl h)
  case clock t =>
    have h0 : I (s.world.tick t) ∧ R s.world (s.world.tick t) := K'.reqs ⟨rfl, rfl, rfl, rfl, rfl⟩ h
    have h1 := K'.next h0 (K'.boot app { app := s.app, world := s.world.tick t })
    split
    · exact h1
    · exact K'.next (K'.next h1 (K'.hear app _)) (K'.foldl_fire app _ _)
  case reply id r =>
    split
    · have hh := K'.hear app ({ app := s.app, world := s.world } : Ctx S) h
      split
      · rename_i w hw
        exact K'.next (K'.next hh (fun h' => K.reply _ _ _ _ h' hw)) (K'.give app (release _ w) _)
      · exact K'.next hh (K.ack _ id)
    · exact K.ack ({ app := s.app, world := s.world } : Ctx S) id h
  case subEvent id ev =>
    split
    · exact K'.next (K'.hear app ({ app := s.app, world := s.world } : Ctx S) h) (K'.give app _ _)
    · exact K'.refl h

/-- **A kept property is kept by a step.** -/
theorem step (K : Carries I R) (app : App S) (cfg : Config) (s : State S) (e : Event) (h : I s.world) :
    I (step app cfg s e).1.world ∧ R s.world (step app cfg s e).1.world := by
  obtain ⟨-, subs, next, hw⟩ := step_ctx app cfg s e
  rw [hw]
  exact K.toThrough.next (K.toThrough.next (K.admit app s e h) (K.toThrough.act app _ _))
    (K.toThrough.reqs ⟨rfl, rfl, rfl, rfl, rfl⟩)

/-- …and by a batch of steps. -/
theorem steps (K : Carries I R) (app : App S) (cfg : Config) (s : State S) (es : List Event)
    (h : I s.world) :
    I (steps app cfg s es).1.world ∧ R s.world (steps app cfg s es).1.world :=
  steps_go app cfg (fun s' => I s'.world ∧ R s.world s'.world)
    (fun s' e h' => K.toThrough.next h' (K.step app cfg s' e)) (es ++ frameEvents) s [] (K.toThrough.refl h)

end Carries

/-! ## The cap -/

namespace World

theorem countP_filter_le {α : Type} (p q : α → Bool) (l : List α) :
    (l.filter q).countP p ≤ l.countP p :=
  List.filter_sublist.countP_le

theorem countP_filter_ne {β : Type} (p : Nat × β → Bool) {x : Nat} {v : β} :
    ∀ (l : List (Nat × β)), (x, v) ∈ l →
      (l.filter (·.1 != x)).countP p + (if p (x, v) then 1 else 0) ≤ l.countP p := by
  intro l
  induction l with
  | nil => intro h; cases h
  | cons a l ih =>
    intro h
    have hf : (l.filter (·.1 != x)).countP p ≤ l.countP p := countP_filter_le _ _ _
    rcases List.mem_cons.mp h with e | e
    · subst e
      simp only [List.filter_cons, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte,
        List.countP_cons]
      omega
    · have ih' := ih e
      by_cases ha : a.1 = x
      · have : (a.1 != x) = false := by simp only [ha, bne_self_eq_false]
        simp only [List.filter_cons, this, Bool.false_eq_true, ↓reduceIte, List.countP_cons]
        omega
      · have : (a.1 != x) = true := by simp only [bne_iff_ne, ne_eq]; exact ha
        simp only [List.filter_cons, this, ↓reduceIte, List.countP_cons]
        omega

theorem send_inFlight (w : World) (id : Nat) (k : Request.Kind) :
    (w.send id k).inFlight = w.inFlight + (if k.capped then 1 else 0) := by
  simp only [inFlight, send, List.countP_append, List.countP_cons, List.countP_nil]
  omega

theorem canSend_capped {w : World} {id : Nat} {k : Request.Kind} (h : w.canSend id k = true)
    (hk : k.capped = true) : w.inFlight < w.cap := by
  simp only [canSend, hk, Bool.not_true, Bool.false_or, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

theorem canSend_stop {w : World} {id : Nat} {k : Request.Kind} (h : w.canSend id k = true) :
    w.isStopping id = false := by
  simp only [canSend, Bool.and_eq_true, Bool.not_eq_true'] at h
  exact h.1

/-- Sending under `canSend` keeps the cap. -/
theorem send_cap {w : World} {id : Nat} {k : Request.Kind} (hc : w.inFlight ≤ w.cap)
    (h : w.canSend id k = true) : (w.send id k).inFlight ≤ (w.send id k).cap := by
  show (w.send id k).inFlight ≤ w.cap
  rw [send_inFlight]
  cases hk : k.capped
  · simp only [Bool.false_eq_true, ↓reduceIte, Nat.add_zero]; exact hc
  · have := canSend_capped h hk; simp only [↓reduceIte]; omega

theorem cancel_inFlight (w : World) (id : Nat) : (w.cancel id).1.inFlight ≤ w.inFlight := by
  unfold cancel; split
  · exact Nat.le_refl _
  · split
    · rename_i k hk
      have := countP_filter_ne (fun p : Nat × Request.Kind => p.2.capped) w.pending
        (lookup_some_mem hk)
      simp only [inFlight, List.countP_append, List.countP_cons, List.countP_nil] at this ⊢
      omega
    · exact Nat.le_refl _

theorem absorb1_cap (w : World) (e : Effect) (h : w.inFlight ≤ w.cap) :
    (w.absorb1 e).1.inFlight ≤ (w.absorb1 e).1.cap := by
  cases e <;> simp only [absorb1] <;> (try exact h)
  case request id r =>
    split
    · exact h
    · split
      · rename_i hs; exact send_cap h hs
      · exact h
  case cancelRequest id =>
    have := cancel_inFlight w id
    rw [(cancel_same w id).2.2.2.2.2]; omega

theorem promoteGo_cap (rest : List (Nat × Nat × Request)) :
    ∀ (w : World), w.inFlight ≤ w.cap →
      (promoteGo w rest).1.inFlight ≤ (promoteGo w rest).1.cap := by
  induction rest with
  | nil => intro w h; exact h
  | cons q rest ih =>
    intro w h
    simp only [promoteGo]
    split
    · rename_i hs; exact ih _ (send_cap h hs)
    · exact ih _ h

theorem promote_cap (w : World) (h : w.inFlight ≤ w.cap) : w.promote.1.inFlight ≤ w.promote.1.cap :=
  promoteGo_cap _ _ h

theorem takeReply_inFlight {w w' : World} {id : Nat} {r : Reply} (h : w.takeReply id r = some w') :
    w'.inFlight ≤ w.inFlight ∧ w'.cap = w.cap := by
  obtain ⟨k, -, -, rfl⟩ := takeReply_some h
  refine ⟨?_, rfl⟩
  have := countP_filter_le (fun p : Nat × Request.Kind => p.2.capped)
    (fun p : Nat × Request.Kind => p.1 != id) w.pending
  simp only [inFlight] at this ⊢; omega

theorem takeStop_inFlight {w w' : World} {id : Nat} (h : w.takeStop id = some w') :
    w'.inFlight ≤ w.inFlight ∧ w'.cap = w.cap := by
  obtain ⟨-, rfl⟩ := takeStop_some h
  refine ⟨?_, rfl⟩
  have := countP_filter_le (fun p : Nat × Request.Kind => p.2.capped)
    (fun p : Nat × Request.Kind => p.1 != id) w.stopping
  simp only [inFlight] at this ⊢; omega

end World

/-- The cap holds, and the cap itself never changes. -/
theorem carries_cap : Carries (fun w => w.inFlight ≤ w.cap) (fun w w' => w'.cap = w.cap) where
  trans h1 h2 := h2.trans h1
  reqs := by
    rintro w w' ⟨h1, -, h3, h4, -⟩ h
    refine ⟨?_, h4⟩
    simp only [World.inFlight, h1, h3, h4]; exact h
  absorb1 w e h := ⟨World.absorb1_cap w e h, (absorb1_same w e).2.2.2.2.2⟩
  reply w w' id r h hw := by
    obtain ⟨h1, h2⟩ := World.takeReply_inFlight hw
    refine ⟨World.promote_cap _ (by omega), ?_⟩
    rw [(promote_same w').2.2.2.2.2, h2]
  stop w w' id h hw := by
    obtain ⟨h1, h2⟩ := World.takeStop_inFlight hw
    refine ⟨World.promote_cap _ (by omega), ?_⟩
    rw [(promote_same w').2.2.2.2.2, h2]

/-- **The cap is never exceeded.** After any event, the capped requests with the host (sent
and not answered, or cancelled and not yet answered) number at most the cap, and the cap is
unchanged. -/
theorem step_cap (app : App S) (cfg : Config) (s : State S) (e : Event)
    (h : s.world.inFlight ≤ s.world.cap) :
    (step app cfg s e).1.world.inFlight ≤ (step app cfg s e).1.world.cap ∧
      (step app cfg s e).1.world.cap = s.world.cap :=
  carries_cap.step app cfg s e h

theorem start_cap (app : App S) (cfg : Config) (size : Size) (scale : Nat) :
    (start app cfg size scale).world.inFlight = 0 ∧
      (start app cfg size scale).world.cap = max 1 app.maxInFlight := ⟨rfl, rfl⟩

/-- **From launch, the cap is `App.maxInFlight` (at least one) and never exceeded.** -/
theorem steps_cap (app : App S) (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    let w := (steps app cfg (start app cfg size scale) es).1.world
    w.inFlight ≤ w.cap ∧ w.cap = max 1 app.maxInFlight := by
  have h := carries_cap.steps app cfg (start app cfg size scale) es
    (by rw [(start_cap app cfg size scale).1]; exact Nat.zero_le _)
  exact ⟨h.1, h.2⟩

/-! ## Fine worlds: the tables' own invariants -/

namespace World

/-- The request tables are well formed: no id is pending or queued twice (`Keys`), no pending
id is also stopping, the cap holds and is at least one, and the queue is in ticket order with
every ticket issued. -/
structure Fine (w : World) : Prop where
  keys : w.Keys
  apart : ∀ p ∈ w.pending, w.isStopping p.1 = false
  cap : w.inFlight ≤ w.cap
  pos : 0 < w.cap
  sorted : w.queued.Pairwise (fun a b => a.1 < b.1)
  fresh : ∀ q ∈ w.queued, q.1 < w.nextTicket

/-- **Nothing waits that could go**: no queued request could be sent now. -/
def Settled (w : World) : Prop := ∀ q ∈ w.queued, w.canSend q.2.1 q.2.2.kind = false

theorem canSend_false {w : World} {id : Nat} {k : Request.Kind} :
    w.canSend id k = false ↔ w.isStopping id = true ∨ (k.capped = true ∧ w.cap ≤ w.inFlight) := by
  simp only [canSend]
  cases w.isStopping id <;> cases k.capped <;>
    simp only [Bool.not_false, Bool.not_true, Bool.true_and, Bool.false_and, Bool.true_or,
      Bool.false_or, decide_eq_false_iff_not, Nat.not_lt, true_or, false_or, true_and, false_and,
      Bool.false_eq_true, Bool.true_eq_false]

/-- A queued request that can't go stays unable to while nothing is freed: no fewer requests in
flight, no fewer ids stopping, the same cap. -/
theorem Settled.mono {w w' : World} (h : w.Settled) (hq : ∀ q ∈ w'.queued, q ∈ w.queued)
    (hs : ∀ id, w.isStopping id = true → w'.isStopping id = true) (hi : w.inFlight ≤ w'.inFlight)
    (hc : w'.cap = w.cap) : w'.Settled := by
  intro q hq'
  rcases canSend_false.mp (h q (hq q hq')) with e | ⟨e1, e2⟩
  · exact canSend_false.mpr (Or.inl (hs _ e))
  · exact canSend_false.mpr (Or.inr ⟨e1, by omega⟩)

/-- The canonical book of a world: its timers and its live requests. -/
def bookOf (w : World) : Book := { armed := fun n => decide (n ∈ w.timerNames), pending := w.live }

theorem agrees_bookOf {w : World} (h : w.Keys) : Agrees w (bookOf w) :=
  ⟨fun n => by simp only [bookOf, decide_eq_true_eq], fun _ => rfl, h⟩

theorem isStopping_iff (w : World) (id : Nat) :
    w.isStopping id = true ↔ ∃ k, (id, k) ∈ w.stopping := by
  simp only [isStopping, List.any_eq_true, beq_iff_eq]
  constructor
  · rintro ⟨⟨a, k⟩, hm, rfl⟩; exact ⟨k, hm⟩
  · rintro ⟨k, hm⟩; exact ⟨(id, k), hm, rfl⟩

/-- With no id twice, `filter` takes out exactly one entry. -/
theorem countP_filter_one {β : Type} (p : Nat × β → Bool) {x : Nat} {v : β} :
    ∀ (l : List (Nat × β)), (l.map (·.1)).Nodup → (x, v) ∈ l →
      (l.filter (·.1 != x)).countP p + (if p (x, v) then 1 else 0) = l.countP p := by
  intro l
  induction l with
  | nil => intro _ h; cases h
  | cons a l ih =>
    intro hn h
    simp only [List.map_cons, List.nodup_cons] at hn
    rcases List.mem_cons.mp h with e | e
    · subst e
      have hl : l.filter (·.1 != x) = l := by
        apply List.filter_eq_self.mpr
        intro b hb
        simp only [bne_iff_ne, ne_eq]
        intro he; exact hn.1 (List.mem_map.mpr ⟨b, hb, he⟩)
      simp only [List.filter_cons, bne_self_eq_false, Bool.false_eq_true, ↓reduceIte, hl,
        List.countP_cons]
    · have ha : a.1 ≠ x := fun he => hn.1 (List.mem_map.mpr ⟨(x, v), e, he.symm⟩)
      have : (a.1 != x) = true := by simp only [bne_iff_ne, ne_eq]; exact ha
      have ih' := ih hn.2 e
      simp only [List.filter_cons, this, ↓reduceIte, List.countP_cons]
      omega

theorem pending_nodup {w : World} (h : w.Keys) : (w.pending.map (·.1)).Nodup := by
  unfold Keys at h; rw [entries_eq, List.map_append] at h
  exact (List.nodup_append.mp h).1

/-- What `absorb1` does to the request tables. -/
theorem absorb1_cases (w : World) (e : Effect) :
    w.Reqs (w.absorb1 e).1 ∨
    (∃ id k, w.canSend id k = true ∧ (w.absorb1 e).1 = { w.send id k with timers := (w.absorb1 e).1.timers }) ∨
    (∃ id r, w.canSend id r.kind = false ∧
      (w.absorb1 e).1 = { w.enqueue id r with timers := (w.absorb1 e).1.timers }) ∨
    (∃ id, (w.absorb1 e).1 = (w.cancel id).1) := by
  cases e <;> simp only [absorb1]
  case setTimer n ms => exact Or.inl ⟨rfl, rfl, rfl, rfl, rfl⟩
  case cancelTimer n => exact Or.inl ⟨rfl, rfl, rfl, rfl, rfl⟩
  case request id r =>
    split
    · exact Or.inl (Reqs.refl w)
    · split
      · rename_i hs; exact Or.inr (Or.inl ⟨id, r.kind, hs, rfl⟩)
      · rename_i hs
        exact Or.inr (Or.inr (Or.inl ⟨id, r, by simpa only [Bool.not_eq_true] using hs, rfl⟩))
  case cancelRequest id => exact Or.inr (Or.inr (Or.inr ⟨id, rfl⟩))
  all_goals exact Or.inl (Reqs.refl w)

/-- `id`'s pending request, of kind `k`, moved to `stopping`. -/
def stopOne (w : World) (id : Nat) (k : Request.Kind) : World :=
  { w with pending := w.pending.filter (·.1 != id), stopping := w.stopping ++ [(id, k)] }

theorem cancel_cases (w : World) (id : Nat) :
    (w.cancel id).1 = { w with queued := w.queued.filter (·.2.1 != id) } ∨
    (∃ k, w.pending.lookup id = some k ∧ (w.cancel id).1 = w.stopOne id k) ∨
    (w.cancel id).1 = w := by
  unfold cancel; split
  · exact Or.inl rfl
  · split
    · rename_i k hk; exact Or.inr (Or.inl ⟨k, hk, rfl⟩)
    · exact Or.inr (Or.inr rfl)

theorem fine_reqs {w w' : World} (hr : w.Reqs w') (h : w.Fine) : w'.Fine := by
  obtain ⟨h1, h2, h3, h4, h5⟩ := hr
  obtain ⟨k, a, c, p, so, f⟩ := h
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · simp only [Keys, entries, waiting, h1, h2]; exact k
  · simp only [isStopping, h1, h3]; exact a
  · simp only [inFlight, h1, h3, h4]; exact c
  · rw [h4]; exact p
  · rw [h2]; exact so
  · rw [h2, h5]; exact f

theorem settled_reqs {w w' : World} (hr : w.Reqs w') (h : w.Settled) : w'.Settled := by
  obtain ⟨h1, h2, h3, h4, h5⟩ := hr
  simp only [Settled, canSend, isStopping, inFlight, h1, h2, h3, h4]; exact h

theorem cancel_fine {w : World} (h : w.Fine) (id : Nat) : (w.cancel id).1.Fine ∧
    (w.Settled → (w.cancel id).1.Settled) := by
  have hk : (w.cancel id).1.Keys := (cancel_agrees (agrees_bookOf h.keys) id).2.2
  rcases cancel_cases w id with e | ⟨k, hl, e⟩ | e
  · rw [e] at hk ⊢
    refine ⟨⟨hk, h.apart, h.cap, h.pos, h.sorted.sublist List.filter_sublist,
      fun q hq => h.fresh q (List.mem_filter.mp hq).1⟩, fun hs => ?_⟩
    exact hs.mono (fun q hq => (List.mem_filter.mp hq).1) (fun _ x => x) (Nat.le_refl _) rfl
  · rw [e] at hk ⊢
    have hm : (id, k) ∈ w.pending := lookup_some_mem hl
    have hc := countP_filter_one (fun p : Nat × Request.Kind => p.2.capped) w.pending
      (pending_nodup h.keys) hm
    have hfl : (w.stopOne id k).inFlight = w.inFlight := by
      simp only [stopOne, inFlight, List.countP_append, List.countP_cons, List.countP_nil]
      simp only at hc
      omega
    have hst : ∀ x, w.isStopping x = true → (w.stopOne id k).isStopping x = true := by
      intro x hx
      simp only [isStopping] at hx
      simp only [stopOne, isStopping, List.any_append, hx, Bool.true_or]
    refine ⟨⟨hk, ?_, by rw [hfl]; exact h.cap, h.pos, h.sorted, h.fresh⟩, fun hs => ?_⟩
    · intro p hp
      obtain ⟨hp1, hp2⟩ := List.mem_filter.mp hp
      simp only [bne_iff_ne, ne_eq] at hp2
      have := h.apart p hp1
      simp only [isStopping] at this
      simp only [stopOne, isStopping, List.any_append, List.any_cons, List.any_nil, Bool.or_false]
      rw [this]
      simp only [Bool.false_or, beq_eq_false_iff_ne]
      exact fun e => hp2 e.symm
    · exact hs.mono (fun q hq => hq) hst (by rw [hfl]; exact Nat.le_refl _) rfl
  · rw [e]; exact ⟨h, fun x => x⟩

theorem absorb1_fine {w : World} (h : w.Fine) (e : Effect) : (w.absorb1 e).1.Fine ∧
    (w.Settled → (w.absorb1 e).1.Settled) := by
  rcases absorb1_cases w e with hr | ⟨id, k, hs, he⟩ | ⟨id, r, hs, he⟩ | ⟨id, he⟩
  · exact ⟨fine_reqs hr h, settled_reqs hr⟩
  · have hk : (w.absorb1 e).1.Keys := (absorb1_agrees (agrees_bookOf h.keys) e).2.2
    rw [he] at hk ⊢
    have hc : (w.send id k).inFlight ≤ (w.send id k).cap := send_cap h.cap hs
    refine ⟨⟨hk, ?_, hc, h.pos, h.sorted, h.fresh⟩, fun hset => ?_⟩
    · intro p hp
      rcases List.mem_append.mp hp with hp | hp
      · exact h.apart p hp
      · rw [List.mem_singleton] at hp; subst hp; exact (canSend_stop hs : w.isStopping id = false)
    · refine hset.mono (fun q hq => hq) (fun _ x => x) ?_ rfl
      show w.inFlight ≤ (w.send id k).inFlight
      rw [send_inFlight]; exact Nat.le_add_right _ _
  · have hk : (w.absorb1 e).1.Keys := (absorb1_agrees (agrees_bookOf h.keys) e).2.2
    rw [he] at hk ⊢
    refine ⟨⟨hk, h.apart, h.cap, h.pos, ?_, ?_⟩, fun hset => ?_⟩
    · show (w.queued ++ [(w.nextTicket, id, r)]).Pairwise _
      refine List.pairwise_append.mpr ⟨h.sorted, List.pairwise_singleton _ _, ?_⟩
      intro a ha b hb; rw [List.mem_singleton] at hb; subst hb; exact h.fresh a ha
    · intro q hq
      rcases List.mem_append.mp hq with hq | hq
      · exact Nat.lt_succ_of_lt (h.fresh q hq)
      · rw [List.mem_singleton] at hq; subst hq; exact Nat.lt_succ_self _
    · intro q hq
      rcases List.mem_append.mp hq with hq | hq
      · exact hset q hq
      · rw [List.mem_singleton] at hq; subst hq; exact hs
  · rw [he]; exact cancel_fine h id

/-- How `promoteGo` leaves the tables: some of the requests it was given sent, the rest
appended to the queue in order. -/
theorem promoteGo_parts (rest : List (Nat × Nat × Request)) : ∀ (w : World),
    ∃ sent l, (promoteGo w rest).1 = { w with pending := w.pending ++ sent, queued := w.queued ++ l } ∧
      l.Sublist rest ∧ (∀ p ∈ sent, w.isStopping p.1 = false) := by
  induction rest with
  | nil => intro w; exact ⟨[], [], by simp only [promoteGo, List.append_nil], List.Sublist.slnil,
      fun _ h => nomatch h⟩
  | cons q rest ih =>
    intro w
    simp only [promoteGo]
    split
    · rename_i hs
      obtain ⟨sent, l, he, hl, hp⟩ := ih (w.send q.2.1 q.2.2.kind)
      refine ⟨(q.2.1, q.2.2.kind) :: sent, l, ?_, hl.cons _, ?_⟩
      · rw [he]; simp only [send, List.append_assoc, List.singleton_append]
      · intro p hm
        rcases List.mem_cons.mp hm with e | e
        · subst e; exact canSend_stop hs
        · exact hp p e
    · rename_i hs
      obtain ⟨sent, l, he, hl, hp⟩ := ih { w with queued := w.queued ++ [q] }
      refine ⟨sent, q :: l, ?_, hl.cons_cons _, hp⟩
      rw [he]; simp only [List.append_assoc, List.singleton_append]

theorem promoteGo_settled (rest : List (Nat × Nat × Request)) :
    ∀ (w : World), w.Settled → (promoteGo w rest).1.Settled := by
  induction rest with
  | nil => intro w h; exact h
  | cons q rest ih =>
    intro w h
    simp only [promoteGo]
    split
    · apply ih
      refine h.mono (fun q hq => hq) (fun _ x => x) ?_ rfl
      show w.inFlight ≤ (w.send q.2.1 q.2.2.kind).inFlight
      rw [send_inFlight]; exact Nat.le_add_right _ _
    · rename_i hs
      apply ih
      intro q' hq'
      rcases List.mem_append.mp hq' with hq' | hq'
      · exact h q' hq'
      · rw [List.mem_singleton] at hq'; subst hq'
        exact (show w.canSend _ _ = false by simpa only [Bool.not_eq_true] using hs)

/-- **After `promote`, nothing waits that could go.** -/
theorem promote_settled (w : World) : w.promote.1.Settled :=
  promoteGo_settled _ _ (fun _ h => nomatch h)

theorem promote_fine {w : World} (h : w.Fine) : w.promote.1.Fine := by
  have hk : w.promote.1.Keys := (promote_agrees (agrees_bookOf h.keys)).2.2
  have hc := promote_cap w h.cap
  obtain ⟨sent, l, he, hl, hp⟩ := promoteGo_parts w.queued { w with queued := [] }
  have he' : w.promote.1 = { w with pending := w.pending ++ sent, queued := l } := by
    unfold promote; rw [he]; simp only [List.nil_append]
  rw [he'] at hk hc ⊢
  refine ⟨hk, ?_, hc, h.pos, h.sorted.sublist hl, fun q hq => h.fresh q (hl.subset hq)⟩
  intro p hm
  rcases List.mem_append.mp hm with hm | hm
  · exact h.apart p hm
  · exact hp p hm

theorem takeReply_fine {w w' : World} {id : Nat} {r : Reply} (h : w.Fine)
    (hw : w.takeReply id r = some w') : w'.Fine := by
  have hk : w'.Keys := (takeReply_agrees (agrees_bookOf h.keys) hw).2.2
  have hc := takeReply_inFlight hw
  obtain ⟨k, -, -, rfl⟩ := takeReply_some hw
  exact ⟨hk, fun p hp => h.apart p (List.mem_filter.mp hp).1, by rw [hc.2]; exact Nat.le_trans hc.1 h.cap,
    h.pos, h.sorted, h.fresh⟩

theorem takeStop_fine {w w' : World} {id : Nat} (h : w.Fine) (hw : w.takeStop id = some w') :
    w'.Fine := by
  have hk : w'.Keys := (takeStop_agrees (agrees_bookOf h.keys) hw).2.2
  have hc := takeStop_inFlight hw
  obtain ⟨-, rfl⟩ := takeStop_some hw
  refine ⟨hk, fun p hp => ?_, by rw [hc.2]; exact Nat.le_trans hc.1 h.cap, h.pos, h.sorted, h.fresh⟩
  have := h.apart p hp
  simp only [isStopping, List.any_filter] at this ⊢
  simp only [List.any_eq_false, Bool.and_eq_true, not_and] at this ⊢
  intro x hx _; exact this x hx

end World

/-- Fine and settled worlds stay fine and settled. -/
theorem carries_fine : Carries (fun w => w.Fine ∧ w.Settled) (fun _ _ => True) where
  trans _ _ := trivial
  reqs hr h := ⟨⟨World.fine_reqs hr h.1, World.settled_reqs hr h.2⟩, trivial⟩
  absorb1 _ e h := let f := World.absorb1_fine h.1 e; ⟨⟨f.1, f.2 h.2⟩, trivial⟩
  reply _ _ _ _ h hw := ⟨⟨World.promote_fine (World.takeReply_fine h.1 hw), World.promote_settled _⟩, trivial⟩
  stop _ _ _ h hw := ⟨⟨World.promote_fine (World.takeStop_fine h.1 hw), World.promote_settled _⟩, trivial⟩

/-- **Every step keeps the tables fine and settled**: after any event, nothing waits in the
queue that could be sent. -/
theorem step_settled (app : App S) (cfg : Config) (s : State S) (e : Event)
    (h : s.world.Fine ∧ s.world.Settled) :
    (step app cfg s e).1.world.Fine ∧ (step app cfg s e).1.world.Settled :=
  (carries_fine.step app cfg s e h).1

theorem start_fine (app : App S) (cfg : Config) (size : Size) (scale : Nat) :
    (start app cfg size scale).world.Fine ∧ (start app cfg size scale).world.Settled :=
  And.intro
    (World.Fine.mk List.nodup_nil (fun _ h => nomatch h) (Nat.zero_le _)
      (Nat.lt_of_lt_of_le Nat.zero_lt_one (Nat.le_max_left _ _)) List.Pairwise.nil
      (fun _ h => nomatch h))
    (fun _ h => nomatch h)

theorem steps_fine (app : App S) (cfg : Config) (size : Size) (scale : Nat) (es : List Event) :
    (steps app cfg (start app cfg size scale) es).1.world.Fine ∧
      (steps app cfg (start app cfg size scale) es).1.world.Settled :=
  (carries_fine.steps app cfg _ es (start_fine app cfg size scale)).1

/-! ## A cancelled request's reply -/

theorem stopping_not_pending {w : World} (h : w.Fine) {id : Nat} (hs : w.isStopping id = true) :
    w.pending.lookup id = none := by
  cases hl : w.pending.lookup id with
  | none => rfl
  | some k =>
    have := h.apart _ (lookup_some_mem hl)
    simp only at this
    rw [hs] at this; cases this

theorem takeReply_stopping {w : World} (h : w.Fine) {id : Nat} (hs : w.isStopping id = true)
    (r : Reply) : w.takeReply id r = none := by
  simp only [World.takeReply, stopping_not_pending h hs]

theorem promote_stopping (w : World) : w.promote.1.stopping = w.stopping := by
  obtain ⟨⟨p, q, he⟩, -⟩ := promote_spec w
  rw [he]

/-- **A cancelled id never delivers.** The host's one reply to a request cancelled after it was
sent reaches no app, whatever it says, and the id stops being held: its slot is free and a
request under it can be sent. -/
theorem step_reply_cancelled (app : App S) (cfg : Config) (s : State S) {id : Nat} (r : Reply)
    (h : s.world.Fine) (hs : s.world.isStopping id = true) :
    (step app cfg s (.reply id r)).1.app = s.app ∧
      (step app cfg s (.reply id r)).1.world.stopping = s.world.stopping.filter (·.1 != id) := by
  have hn := takeReply_stopping h hs r
  refine ⟨step_reply_ignored app cfg s hn, ?_⟩
  obtain ⟨-, subs, next, hw⟩ := step_ctx app cfg s (.reply id r)
  rw [hw, route_reply, act_nil]
  simp only [admit, hn, Option.isSome_none, Bool.false_eq_true, ↓reduceIte, ack, World.takeStop, hs,
    release]
  exact promote_stopping _

/-! ## Every queued request is eventually sent or cancelled

Fix a queued request `q` with ticket `t`. `ahead w t` counts what holds the requests up to `t`:
the capped ones among them (each needs a slot) and those whose id is still stopping (each needs
that reply). Nothing the runtime does makes it grow (`step_wait_le`), and the reply to whatever
blocks `q` either takes `q` out of the queue or makes it shrink (`step_drains`). -/

namespace World

def capAhead (w : World) (t : Nat) : Nat :=
  w.queued.countP fun q => decide (q.1 ≤ t) && q.2.2.kind.capped

def stopAhead (w : World) (t : Nat) : Nat :=
  w.queued.countP fun q => decide (q.1 ≤ t) && w.isStopping q.2.1

/-- What holds up the queued requests with tickets up to `t`. -/
def ahead (w : World) (t : Nat) : Nat := w.capAhead t + w.stopAhead t

/-- From `w` to `w'`, nothing ahead grew and no queued request up to `t` appeared, or saw its id
start stopping. -/
def Drains (t : Nat) (w w' : World) : Prop :=
  w'.ahead t ≤ w.ahead t ∧ ∀ q, q.1 ≤ t → q ∈ w'.queued →
    q ∈ w.queued ∧ (w'.isStopping q.2.1 = true → w.isStopping q.2.1 = true)

theorem Drains.trans {t : Nat} {a b c : World} (h1 : Drains t a b) (h2 : Drains t b c) :
    Drains t a c :=
  ⟨Nat.le_trans h2.1 h1.1, fun q hq m =>
    let x := h2.2 q hq m
    let y := h1.2 q hq x.1
    ⟨y.1, fun e => y.2 (x.2 e)⟩⟩

theorem drains_same {t : Nat} {w w' : World} (hq : w'.queued = w.queued) (hs : w'.stopping = w.stopping) :
    Drains t w w' := by
  have hi : ∀ id, w'.isStopping id = w.isStopping id := by intro id; simp only [isStopping, hs]
  refine ⟨?_, fun q _ m => ⟨hq ▸ m, fun e => (hi _) ▸ e⟩⟩
  simp only [ahead, capAhead, stopAhead, hq, hi, Nat.le_refl]

theorem drains_sub {t : Nat} {w w' : World} (hq : w'.queued.Sublist w.queued)
    (hs : ∀ id, w'.isStopping id = true → w.isStopping id = true) : Drains t w w' := by
  refine ⟨?_, fun q _ m => ⟨hq.subset m, hs _⟩⟩
  have h1 : w'.capAhead t ≤ w.capAhead t := hq.countP_le
  have h2 : w'.stopAhead t ≤ w.stopAhead t := by
    unfold stopAhead
    refine Nat.le_trans (List.countP_mono_left ?_) hq.countP_le
    intro q _ e
    simp only [Bool.and_eq_true, decide_eq_true_eq] at e ⊢
    exact ⟨e.1, hs _ e.2⟩
  unfold ahead; omega

theorem live_apart {w : World} (h : w.Keys) {id : Nat} {k : Request.Kind}
    (hl : w.pending.lookup id = some k) : ∀ q ∈ w.queued, q.2.1 ≠ id := by
  intro q hq he
  have hp : id ∈ w.pending.map (·.1) := List.mem_map.mpr ⟨(id, k), lookup_some_mem hl, rfl⟩
  have hw : id ∈ w.waiting.map (·.1) := by
    simp only [waiting, List.map_map]
    exact List.mem_map.mpr ⟨q, hq, he⟩
  exact keys_disjoint h hp hw

theorem stopOne_drains {t : Nat} {w : World} (h : w.Keys) {id : Nat} {k : Request.Kind}
    (hl : w.pending.lookup id = some k) : Drains t w (w.stopOne id k) := by
  have ha := live_apart h hl
  have hi : ∀ q ∈ w.queued, (w.stopOne id k).isStopping q.2.1 = w.isStopping q.2.1 := by
    intro q hq
    simp only [stopOne, isStopping, List.any_append, List.any_cons, List.any_nil, Bool.or_false]
    have : (id == q.2.1) = false := by
      simp only [beq_eq_false_iff_ne, ne_eq]; exact fun e => ha q hq e.symm
    rw [this, Bool.or_false]
  refine ⟨?_, fun q _ m => ⟨m, fun e => (hi q m) ▸ e⟩⟩
  have : (w.stopOne id k).stopAhead t = w.stopAhead t := by
    unfold stopAhead
    exact List.countP_congr fun q hq => by rw [hi q hq]
  unfold ahead capAhead; rw [this]; exact Nat.le_refl _

theorem absorb1_drains {t : Nat} {w : World} (h : w.Fine) (ht : t < w.nextTicket) (e : Effect) :
    t < (w.absorb1 e).1.nextTicket ∧ Drains t w (w.absorb1 e).1 := by
  rcases absorb1_cases w e with hr | ⟨id, k, hs, he⟩ | ⟨id, r, hs, he⟩ | ⟨id, he⟩
  · obtain ⟨h1, h2, h3, h4, h5⟩ := hr
    exact ⟨h5 ▸ ht, drains_same h2 h3⟩
  · rw [he]; exact ⟨ht, drains_same rfl rfl⟩
  · rw [he]
    refine ⟨Nat.lt_succ_of_lt ht, ?_, ?_⟩
    · have hn : decide (w.nextTicket ≤ t) = false := by
        simp only [decide_eq_false_iff_not, Nat.not_le]; exact ht
      simp only [ahead, capAhead, stopAhead, enqueue, List.countP_append, List.countP_cons,
        List.countP_nil, hn, Bool.false_and, Bool.false_eq_true, ↓reduceIte, Nat.add_zero]
      simp only [isStopping, Nat.le_refl]
    · intro q hq m
      rcases List.mem_append.mp m with m | m
      · exact ⟨m, fun e => e⟩
      · rw [List.mem_singleton] at m; subst m
        simp only at hq; omega
  · rw [he]
    rcases cancel_cases w id with e | ⟨k, hl, e⟩ | e
    · rw [e]
      exact ⟨ht, drains_sub List.filter_sublist (fun _ x => x)⟩
    · rw [e]; exact ⟨ht, stopOne_drains h.keys hl⟩
    · rw [e]; exact ⟨ht, drains_same rfl rfl⟩

theorem takeStop_isStopping {w w' : World} {id : Nat} (hw : w.takeStop id = some w') (x : Nat) :
    w'.isStopping x = true → w.isStopping x = true := by
  obtain ⟨-, rfl⟩ := takeStop_some hw
  simp only [isStopping, List.any_filter, List.any_eq_true, Bool.and_eq_true]
  rintro ⟨y, hy, -, e⟩; exact ⟨y, hy, e⟩

theorem promote_queued (w : World) : w.promote.1.queued.Sublist w.queued ∧
    w.promote.1.stopping = w.stopping ∧ w.promote.1.nextTicket = w.nextTicket := by
  obtain ⟨sent, l, he, hl, -⟩ := promoteGo_parts w.queued { w with queued := [] }
  have he' : w.promote.1 = { w with pending := w.pending ++ sent, queued := l } := by
    unfold promote; rw [he]; simp only [List.nil_append]
  rw [he']; exact ⟨hl, rfl, rfl⟩

theorem promote_drains' {t : Nat} (w : World) : Drains t w w.promote.1 := by
  obtain ⟨h1, h2, -⟩ := promote_queued w
  exact drains_sub h1 (fun x e => by simp only [isStopping, h2] at e ⊢; exact e)

end World

/-- Fine worlds stay fine, the ticket bound holds, and nothing ahead of a ticket grows. -/
theorem carries_drains (t : Nat) :
    Carries (fun w => w.Fine ∧ t < w.nextTicket) (World.Drains t) where
  trans := World.Drains.trans
  reqs hr h := by
    obtain ⟨h1, h2, h3, h4, h5⟩ := hr
    exact ⟨⟨World.fine_reqs ⟨h1, h2, h3, h4, h5⟩ h.1, h5 ▸ h.2⟩, World.drains_same h2 h3⟩
  absorb1 _ e h :=
    let d := World.absorb1_drains h.1 h.2 e
    ⟨⟨(World.absorb1_fine h.1 e).1, d.1⟩, d.2⟩
  reply w w' _ _ h hw := by
    have hn := (World.promote_queued w').2.2
    have hn' : w'.nextTicket = w.nextTicket := by obtain ⟨k, -, -, rfl⟩ := takeReply_some hw; rfl
    have hd : World.Drains t w w' := by
      obtain ⟨k, -, -, rfl⟩ := takeReply_some hw; exact World.drains_same rfl rfl
    exact ⟨⟨World.promote_fine (World.takeReply_fine h.1 hw), by rw [hn, hn']; exact h.2⟩,
      hd.trans (World.promote_drains' _)⟩
  stop w w' _ h hw := by
    have hn := (World.promote_queued w').2.2
    have hn' : w'.nextTicket = w.nextTicket := by obtain ⟨-, rfl⟩ := takeStop_some hw; rfl
    have hq : w'.queued = w.queued := by obtain ⟨-, rfl⟩ := takeStop_some hw; rfl
    have hd : World.Drains t w w' :=
      World.drains_sub (hq ▸ List.Sublist.refl _) (World.takeStop_isStopping hw)
    exact ⟨⟨World.promote_fine (World.takeStop_fine h.1 hw), by rw [hn, hn']; exact h.2⟩,
      hd.trans (World.promote_drains' _)⟩

/-- **Nothing ahead grows.** Over any event, the count of what holds up the queued requests with
tickets up to `t` does not grow, and no request up to `t` joins the queue (every ticket issued is
below `nextTicket`). -/
theorem step_wait_le (app : App S) (cfg : Config) (s : State S) (e : Event) {t : Nat}
    (h : s.world.Fine) (ht : t < s.world.nextTicket) :
    World.Drains t s.world (step app cfg s e).1.world :=
  ((carries_drains t).step app cfg s e ⟨h, ht⟩).2

namespace World

theorem countP_lt {α : Type} {p p' : α → Bool} {a : α} :
    ∀ (l : List α), (∀ y ∈ l, p' y = true → p y = true) → a ∈ l → p a = true → p' a = false →
      l.countP p' < l.countP p := by
  intro l
  induction l with
  | nil => intro _ h; cases h
  | cons b l ih =>
    intro hm ha hp hp'
    have hle : l.countP p' ≤ l.countP p :=
      List.countP_mono_left fun y hy e => hm y (List.mem_cons_of_mem _ hy) e
    simp only [List.countP_cons]
    rcases List.mem_cons.mp ha with e | e
    · subst e; simp only [hp, hp', ↓reduceIte, Bool.false_eq_true]; omega
    · have := ih (fun y hy e => hm y (List.mem_cons_of_mem _ hy) e) e hp hp'
      cases hb : p' b
      · simp only [Bool.false_eq_true, ↓reduceIte]; split <;> omega
      · simp only [hm b List.mem_cons_self hb, ↓reduceIte]; omega

/-- The capped requests with tickets up to `t` in a list. -/
def capIn (t : Nat) (l : List (Nat × Nat × Request)) : Nat :=
  l.countP fun q => decide (q.1 ≤ t) && q.2.2.kind.capped

/-- With a slot free, `promoteGo` reaching a capped request `q` whose id is not stopping sends a
capped request with ticket up to `t`: `q`, or one before it. -/
theorem promoteGo_strict {t : Nat} {q : Nat × Nat × Request} (hq1 : q.1 ≤ t)
    (hqc : q.2.2.kind.capped = true) (post : List (Nat × Nat × Request)) :
    ∀ (pre : List (Nat × Nat × Request)) (w : World), (∀ p ∈ pre, p.1 ≤ t) →
      w.isStopping q.2.1 = false → w.inFlight < w.cap →
      ∃ l, (promoteGo w (pre ++ q :: post)).1.queued = w.queued ++ l ∧
        l.Sublist (pre ++ q :: post) ∧ capIn t l < capIn t (pre ++ q :: post) := by
  intro pre
  induction pre with
  | nil =>
    intro w _ hs hc
    have hcs : w.canSend q.2.1 q.2.2.kind = true := by
      simp only [canSend, hs, hqc, Bool.not_false, Bool.not_true, Bool.true_and, Bool.false_or,
        decide_eq_true_eq]; exact hc
    obtain ⟨sent, l, he, hl, -⟩ := promoteGo_parts post (w.send q.2.1 q.2.2.kind)
    refine ⟨l, ?_, hl.cons _, ?_⟩
    · simp only [List.nil_append, promoteGo, hcs, ↓reduceIte]; rw [he]; rfl
    · have : capIn t l ≤ capIn t post := hl.countP_le
      simp only [capIn, List.nil_append, List.countP_cons, hqc, Bool.and_true, decide_eq_true_eq] at this ⊢
      simp only [hq1, ↓reduceIte]; omega
  | cons p pre ih =>
    intro w hp hs hc
    have hp1 : p.1 ≤ t := hp p List.mem_cons_self
    have hpre : ∀ y ∈ pre, y.1 ≤ t := fun y hy => hp y (List.mem_cons_of_mem _ hy)
    simp only [List.cons_append, promoteGo]
    split
    · rename_i hcs
      cases hpc : p.2.2.kind.capped
      · obtain ⟨l, he, hl, hlt⟩ := ih (w.send p.2.1 p.2.2.kind) hpre hs (by
          rw [send_inFlight]; simp only [hpc, Bool.false_eq_true, ↓reduceIte, Nat.add_zero]; exact hc)
        refine ⟨l, by rw [he]; rfl, hl.cons _, ?_⟩
        simp only [capIn, List.countP_cons, hpc, Bool.and_false, Bool.false_eq_true, ↓reduceIte,
          Nat.add_zero] at hlt ⊢
        exact hlt
      · obtain ⟨sent, l, he, hl, -⟩ := promoteGo_parts (pre ++ q :: post) (w.send p.2.1 p.2.2.kind)
        refine ⟨l, by rw [he]; rfl, hl.cons _, ?_⟩
        have : capIn t l ≤ capIn t (pre ++ q :: post) := hl.countP_le
        simp only [capIn, List.countP_cons, hpc, Bool.and_true, decide_eq_true_eq, hp1,
          ↓reduceIte] at this ⊢
        omega
    · obtain ⟨l, he, hl, hlt⟩ := ih { w with queued := w.queued ++ [p] } hpre hs hc
      refine ⟨p :: l, by rw [he]; simp only [List.append_assoc, List.singleton_append], hl.cons_cons _, ?_⟩
      simp only [capIn, List.countP_cons] at hlt ⊢
      split <;> omega

/-- With a slot free and a capped queued request whose id is not stopping, `promote` makes the
count ahead of it shrink. -/
theorem promote_strict {w : World} (h : w.Fine) {q : Nat × Nat × Request} (hq : q ∈ w.queued)
    (hqc : q.2.2.kind.capped = true) (hs : w.isStopping q.2.1 = false) (hc : w.inFlight < w.cap) :
    w.promote.1.ahead q.1 < w.ahead q.1 := by
  obtain ⟨pre, post, hsplit⟩ := List.append_of_mem hq
  have hpre : ∀ p ∈ pre, p.1 ≤ q.1 := by
    have := h.sorted; rw [hsplit] at this
    intro p hp
    exact Nat.le_of_lt ((List.pairwise_append.mp this).2.2 p hp q List.mem_cons_self)
  obtain ⟨l, he, hl, hlt⟩ := promoteGo_strict (Nat.le_refl q.1) hqc post pre { w with queued := [] }
    hpre hs hc
  have hpq : w.promote.1.queued = l := by
    unfold promote; rw [hsplit, he]; rfl
  obtain ⟨-, hst, -⟩ := promote_queued w
  have hi : ∀ x, w.promote.1.isStopping x = w.isStopping x := by
    intro x; simp only [isStopping, hst]
  have h2 : w.promote.1.stopAhead q.1 ≤ w.stopAhead q.1 := by
    unfold stopAhead
    simp only [hi]
    exact (promote_queued w).1.countP_le
  have h1 : w.promote.1.capAhead q.1 < w.capAhead q.1 := by
    unfold capAhead; rw [hpq, hsplit]; exact hlt
  unfold ahead; omega

/-- What `q` waits for, by id: the host's reply to its id's cancelled request, or (for a capped
request whose id is free) the reply to any capped request with the host. -/
def Blocks (w : World) (q : Nat × Nat × Request) (x : Nat) : Prop :=
  (w.isStopping q.2.1 = true ∧ x = q.2.1) ∨
  (q.2.2.kind.capped = true ∧ w.isStopping q.2.1 = false ∧
    ∃ k, k.capped = true ∧ ((x, k) ∈ w.pending ∨ (x, k) ∈ w.stopping))

/-- **Every queued request has a blocker**: in a fine, settled world a queued request waits for
a request that is with the host. -/
theorem queued_blocked {w : World} (h : w.Fine) (hs : w.Settled) {q : Nat × Nat × Request}
    (hq : q ∈ w.queued) : ∃ x, w.Blocks q x := by
  rcases canSend_false.mp (hs q hq) with e | ⟨hc, hle⟩
  · exact ⟨q.2.1, Or.inl ⟨e, rfl⟩⟩
  · cases hst : w.isStopping q.2.1
    · have hpos : 0 < w.inFlight := Nat.lt_of_lt_of_le h.pos hle
      unfold inFlight at hpos
      by_cases hp : 0 < w.pending.countP (·.2.capped)
      · obtain ⟨a, ha, hac⟩ := List.countP_pos_iff.mp hp
        exact ⟨a.1, Or.inr ⟨hc, hst, a.2, hac, Or.inl ha⟩⟩
      · have hp2 : 0 < w.stopping.countP (·.2.capped) := by omega
        obtain ⟨a, ha, hac⟩ := List.countP_pos_iff.mp hp2
        exact ⟨a.1, Or.inr ⟨hc, hst, a.2, hac, Or.inr ha⟩⟩
    · exact ⟨q.2.1, Or.inl ⟨hst, rfl⟩⟩

/-- Taking a capped request out of the tables frees a slot; then `promote` shrinks the count
ahead of a capped queued request whose id is free. -/
theorem freed_strict {w w2 : World} (h2 : w2.Fine) {q : Nat × Nat × Request} (hq : q ∈ w2.queued)
    (hqc : q.2.2.kind.capped = true) (hs : w2.isStopping q.2.1 = false)
    (hc : w2.inFlight < w2.cap) (hd : w2.ahead q.1 ≤ w.ahead q.1) :
    w2.promote.1.ahead q.1 < w.ahead q.1 :=
  Nat.lt_of_lt_of_le (promote_strict h2 hq hqc hs hc) hd

theorem takeReply_frees {w w2 : World} (h : w.Fine) {x : Nat} {k : Request.Kind} {r : Reply}
    (hm : (x, k) ∈ w.pending) (hk : k.capped = true) (hw : w.takeReply x r = some w2) :
    w2.inFlight < w2.cap := by
  obtain ⟨k0, -, -, rfl⟩ := takeReply_some hw
  have := countP_filter_ne (fun p : Nat × Request.Kind => p.2.capped) w.pending hm
  have hc := h.cap
  simp only [hk, ↓reduceIte, inFlight] at this hc ⊢
  omega

theorem takeStop_frees {w w2 : World} (h : w.Fine) {x : Nat} {k : Request.Kind}
    (hm : (x, k) ∈ w.stopping) (hk : k.capped = true) (hw : w.takeStop x = some w2) :
    w2.inFlight < w2.cap := by
  obtain ⟨-, rfl⟩ := takeStop_some hw
  have := countP_filter_ne (fun p : Nat × Request.Kind => p.2.capped) w.stopping hm
  have hc := h.cap
  simp only [hk, ↓reduceIte, inFlight] at this hc ⊢
  omega

theorem takeStop_some_of {w : World} {x : Nat} {k : Request.Kind} (hm : (x, k) ∈ w.stopping) :
    ∃ w2, w.takeStop x = some w2 := by
  have : w.isStopping x = true := (isStopping_iff w x).mpr ⟨k, hm⟩
  exact ⟨{ w with stopping := w.stopping.filter (·.1 != x) }, by simp only [takeStop, this, ↓reduceIte]⟩

/-- How a request with the host fares: still pending with its kind, or moved to `stopping`. -/
def Track (x : Nat) (k : Request.Kind) (w w' : World) : Prop :=
  ((x, k) ∈ w.pending → (x, k) ∈ w'.pending ∨ (x, k) ∈ w'.stopping) ∧
    ((x, k) ∈ w.stopping → (x, k) ∈ w'.stopping)

theorem Track.trans {x : Nat} {k : Request.Kind} {a b c : World} (h1 : Track x k a b)
    (h2 : Track x k b c) : Track x k a c :=
  ⟨fun m => (h1.1 m).elim h2.1 (fun e => Or.inr (h2.2 e)), fun m => h2.2 (h1.2 m)⟩

theorem absorb1_track {w : World} (h : w.Fine) (e : Effect) (x : Nat) (k : Request.Kind) :
    Track x k w (w.absorb1 e).1 := by
  rcases absorb1_cases w e with hr | ⟨id, k0, hs, he⟩ | ⟨id, r, hs, he⟩ | ⟨id, he⟩
  · obtain ⟨h1, -, h3, -, -⟩ := hr
    exact ⟨fun m => Or.inl (h1 ▸ m), fun m => h3 ▸ m⟩
  · rw [he]; exact ⟨fun m => Or.inl (List.mem_append_left _ m), fun m => m⟩
  · rw [he]; exact ⟨fun m => Or.inl m, fun m => m⟩
  · rw [he]
    rcases cancel_cases w id with e | ⟨k0, hl, e⟩ | e
    · rw [e]; exact ⟨fun m => Or.inl m, fun m => m⟩
    · rw [e]
      refine ⟨fun m => ?_, fun m => List.mem_append_left _ m⟩
      by_cases hx : x = id
      · subst hx
        have : w.pending.lookup x = some k := lookup_of_mem (pending_nodup h.keys) m
        rw [hl] at this; cases this
        exact Or.inr (List.mem_append_right _ List.mem_cons_self)
      · refine Or.inl (List.mem_filter.mpr ⟨m, ?_⟩)
        simp only [bne_iff_ne, ne_eq]; exact hx
    · rw [e]; exact ⟨fun m => Or.inl m, fun m => m⟩

end World

/-- Absorbing effects keeps the drain and tracks a request with the host. -/
theorem through_track (t x : Nat) (k : Request.Kind) :
    Through (fun w => w.Fine ∧ t < w.nextTicket) (fun w w' => World.Drains t w w' ∧ World.Track x k w w') where
  trans h1 h2 := ⟨h1.1.trans h2.1, h1.2.trans h2.2⟩
  reqs hr h := by
    have d := (carries_drains t).reqs hr h
    obtain ⟨h1, -, h3, -, -⟩ := hr
    exact ⟨d.1, d.2, fun m => Or.inl (h1 ▸ m), fun m => h3 ▸ m⟩
  absorb1 w e h :=
    let d := (carries_drains t).absorb1 w e h
    ⟨d.1, d.2, World.absorb1_track h.1 e x k⟩

/-- **The reply to a blocker drains the queue.** If `x` blocks a queued request `q` and the host
answers `x` (in the shape that answers its kind, if it is pending), then afterwards `q` has left
the queue (sent or cancelled), or the count ahead of it is smaller. With `step_wait_le` and
`queued_blocked`, `q` leaves the queue after at most `ahead q.1` replies to its blockers. -/
theorem step_drains (app : App S) (cfg : Config) (s : State S) {q : Nat × Nat × Request}
    {x : Nat} {r : Reply} (h : s.world.Fine) (hq : q ∈ s.world.queued) (hb : s.world.Blocks q x)
    (hr : ∀ k, s.world.pending.lookup x = some k → r.answers k = true) :
    q ∉ (step app cfg s (.reply x r)).1.world.queued ∨
      (step app cfg s (.reply x r)).1.world.ahead q.1 < s.world.ahead q.1 := by
  obtain ⟨-, subs, next, hw⟩ := step_ctx app cfg s (.reply x r)
  rw [hw, route_reply, act_nil]
  have ht : q.1 < s.world.nextTicket := h.fresh q hq
  -- What follows the point where a reply is taken keeps the drain.
  have after : ∀ (W w1 : World), World.Drains q.1 s.world w1 → World.Drains q.1 w1 W →
      (q ∈ w1.queued → W.ahead q.1 < s.world.ahead q.1) →
      q ∉ ({ W with subs, nextSub := next } : World).queued ∨
        ({ W with subs, nextSub := next } : World).ahead q.1 < s.world.ahead q.1 := by
    intro W w1 _ hd2 hs
    by_cases hq1 : q ∈ w1.queued
    · exact Or.inr (hs hq1)
    · exact Or.inl fun m => hq1 (hd2.2 q (Nat.le_refl _) m).1
  have hnp : ∀ k, (x, k) ∈ s.world.pending → (s.world.takeReply x r).isSome = true := by
    intro k m
    have hl := lookup_of_mem (World.pending_nodup h.keys) m
    simp only [World.takeReply, hl, hr k hl, ↓reduceIte, Option.isSome_some]
  simp only [admit]
  split
  · rename_i hsome
    -- `x` is pending, so it blocks `q` as a capped request with the host.
    obtain ⟨k0, hl0, -⟩ : ∃ k0, s.world.pending.lookup x = some k0 ∧ True := by
      cases e : s.world.pending.lookup x with
      | none => simp only [World.takeReply, e, Option.isSome_none, Bool.false_eq_true] at hsome
      | some k0 => exact ⟨k0, rfl, trivial⟩
    have hxs : s.world.isStopping x = false := h.apart _ (lookup_some_mem hl0)
    obtain ⟨hqc, hqs, k, hkc, hm⟩ : q.2.2.kind.capped = true ∧ s.world.isStopping q.2.1 = false ∧
        ∃ k, k.capped = true ∧ ((x, k) ∈ s.world.pending ∨ (x, k) ∈ s.world.stopping) := by
      rcases hb with ⟨hst, rfl⟩ | hb
      · rw [hst] at hxs; cases hxs
      · exact hb
    have hmp : (x, k) ∈ s.world.pending := by
      rcases hm with m | m
      · exact m
      · have := (World.isStopping_iff _ _).mpr ⟨k, m⟩; rw [this] at hxs; cases hxs
    have c0 := (through_track q.1 x k).hear app ({ app := s.app, world := s.world } : Ctx S) ⟨h, ht⟩
    generalize hc1 : hear app ({ app := s.app, world := s.world } : Ctx S) = c1 at c0
    obtain ⟨⟨hf1, ht1⟩, hd1, htr⟩ := c0
    have hq1s : q ∈ c1.world.queued → c1.world.isStopping q.2.1 = false := by
      intro m
      cases e : c1.world.isStopping q.2.1
      · rfl
      · have := (hd1.2 q (Nat.le_refl _) m).2 e; rw [hqs] at this; cases this
    split
    · rename_i w2 hw2
      have hI2 : w2.promote.1.Fine ∧ q.1 < w2.promote.1.nextTicket :=
        ((carries_drains q.1).reply _ _ _ _ ⟨hf1, ht1⟩ hw2).1
      have hd2 := ((carries_drains q.1).reply _ _ _ _ ⟨hf1, ht1⟩ hw2).2
      have hg := (carries_drains q.1).toThrough.give app (release c1 w2) (.reply x r) hI2
      refine after _ c1.world hd1 (hd2.trans hg.2) fun m => ?_
      obtain ⟨k2, -, -, he2⟩ := takeReply_some hw2
      have hpm : (x, k) ∈ c1.world.pending := by
        rcases htr.1 hmp with m' | m'
        · exact m'
        · have hst : c1.world.isStopping x = true := (World.isStopping_iff _ _).mpr ⟨k, m'⟩
          rw [takeReply_stopping hf1 hst] at hw2; cases hw2
      have hm2 : q ∈ w2.queued := by rw [he2]; exact m
      have hs2 : w2.isStopping q.2.1 = false := by rw [he2]; exact hq1s m
      have hd2' : w2.ahead q.1 ≤ s.world.ahead q.1 := by
        rw [he2]; exact Nat.le_trans (World.drains_same (t := q.1) rfl rfl).1 hd1.1
      exact Nat.lt_of_le_of_lt hg.2.1
        (World.freed_strict (World.takeReply_fine hf1 hw2) hm2 hqc hs2
          (World.takeReply_frees hf1 hpm hkc hw2) hd2')
    · rename_i hnone
      have hsm : (x, k) ∈ c1.world.stopping := by
        rcases htr.1 hmp with m' | m'
        · have hl := lookup_of_mem (World.pending_nodup hf1.keys) m'
          have hl0' := lookup_of_mem (World.pending_nodup h.keys) hmp
          simp only [World.takeReply, hl, hr k hl0', ↓reduceIte] at hnone; cases hnone
        · exact m'
      obtain ⟨w2, hw2⟩ := World.takeStop_some_of hsm
      have hack : (ack c1 x).world = w2.promote.1 := by
        simp only [ack, hw2, release]
      rw [hack]
      have hd2 := ((carries_drains q.1).stop _ _ _ ⟨hf1, ht1⟩ hw2).2
      refine after _ c1.world hd1 hd2 fun m => ?_
      obtain ⟨-, he2⟩ := takeStop_some hw2
      have hm2 : q ∈ w2.queued := by rw [he2]; exact m
      have hs2 : w2.isStopping q.2.1 = false := by
        cases e : w2.isStopping q.2.1
        · rfl
        · have := World.takeStop_isStopping hw2 _ e; rw [hq1s m] at this; cases this
      have hd2' : w2.ahead q.1 ≤ s.world.ahead q.1 :=
        Nat.le_trans (World.drains_sub (t := q.1) (by rw [he2]; exact List.Sublist.refl _)
          (World.takeStop_isStopping hw2)).1 hd1.1
      exact World.freed_strict (World.takeStop_fine hf1 hw2) hm2 hqc hs2
        (World.takeStop_frees hf1 hsm hkc hw2) hd2'
  · rename_i hnot
    have hnp' : ∀ k, (x, k) ∉ s.world.pending := fun k m => hnot (hnp k m)
    rcases hb with ⟨hst, rfl⟩ | ⟨hqc, hqs, k, hkc, hm⟩
    · -- `q`'s own id is stopping: its reply clears it.
      have hst' := hst
      obtain ⟨k, hm⟩ := (World.isStopping_iff _ _).mp hst
      obtain ⟨w2, hw2⟩ := World.takeStop_some_of hm
      have hack : (ack ({ app := s.app, world := s.world } : Ctx S) q.2.1).world = w2.promote.1 := by
        simp only [ack, hw2, release]
      rw [hack]
      have hd2 := ((carries_drains q.1).stop _ _ _ ⟨h, ht⟩ hw2).2
      refine after _ s.world (World.drains_same rfl rfl) hd2 fun _ => ?_
      obtain ⟨-, he2⟩ := takeStop_some hw2
      have hlt : w2.stopAhead q.1 < s.world.stopAhead q.1 := by
        rw [he2]; unfold World.stopAhead
        refine World.countP_lt _ ?_ hq ?_ ?_
        · intro y _ e
          simp only [Bool.and_eq_true, decide_eq_true_eq] at e ⊢
          refine ⟨e.1, ?_⟩
          have := e.2; simp only [World.isStopping, List.any_filter, List.any_eq_true,
            Bool.and_eq_true] at this ⊢
          obtain ⟨z, hz, -, hz2⟩ := this; exact ⟨z, hz, hz2⟩
        · simp only [Nat.le_refl, decide_true, Bool.true_and]; exact hst'
        · simp only [Nat.le_refl, decide_true, Bool.true_and, World.isStopping, List.any_filter,
            List.any_eq_false, Bool.and_eq_true, not_and, bne_iff_ne, ne_eq, beq_iff_eq]
          intro z _ hz e; exact hz e
      have hca : w2.capAhead q.1 = s.world.capAhead q.1 := by rw [he2]; rfl
      have := (World.promote_drains' (t := q.1) w2).1
      unfold World.ahead at this ⊢; omega
    · have hsm : (x, k) ∈ s.world.stopping := hm.resolve_left (hnp' k)
      obtain ⟨w2, hw2⟩ := World.takeStop_some_of hsm
      have hack : (ack ({ app := s.app, world := s.world } : Ctx S) x).world = w2.promote.1 := by
        simp only [ack, hw2, release]
      rw [hack]
      have hd2 := ((carries_drains q.1).stop _ _ _ ⟨h, ht⟩ hw2).2
      refine after _ s.world (World.drains_same rfl rfl) hd2 fun _ => ?_
      obtain ⟨-, he2⟩ := takeStop_some hw2
      have hm2 : q ∈ w2.queued := by rw [he2]; exact hq
      have hs2 : w2.isStopping q.2.1 = false := by
        cases e : w2.isStopping q.2.1
        · rfl
        · have := World.takeStop_isStopping hw2 _ e; rw [hqs] at this; cases this
      exact World.freed_strict (World.takeStop_fine h hw2) hm2 hqc hs2
        (World.takeStop_frees h hsm hkc hw2)
        (World.drains_sub (t := q.1) (by rw [he2]; exact List.Sublist.refl _)
          (World.takeStop_isStopping hw2)).1

end Cairn.Runtime

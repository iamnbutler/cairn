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
    (fun s' e h' => K.toThrough.next h' (K.step app cfg s' e)) es s [] (K.toThrough.refl h)

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

end Cairn.Runtime

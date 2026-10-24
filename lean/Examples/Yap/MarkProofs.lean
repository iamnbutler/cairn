module

public import Examples.Yap.AppProofs

/-! # ^347: a mark waits for the appends

Marking a transcript typed rewrites its day file (`Pend.markRead`, then `Pend.markWrite`). The
host runs requests concurrently and nothing orders their completion (docs/effects.md), so a
line is only known to be in its file once its append is answered. The app keeps the day-file
appends it has sent and not yet heard back from in `Io.appends`; here it is proved that

* every `appendFile` `receive` (or the menu) sends is in `Io.appends` after it, with its line;
* an append leaves `Io.appends` only when a reply with its id arrives;
* a mark starts (a new `markRead` request appears) only when
  `Io.appends` is empty after the message, so when every append sent so far, the clip's own
  included, has been answered, and none goes out in the same frame.

The bookkeeping: `Io.Frame io io'` says `io'` follows `io` without starting a mark (the count is
the same, no `markRead` appears) and without dropping an append. Everything `receive` does is a
`Frame`, except `Io.landed` (drops the append a reply answers) and `nextMark` (may start a mark,
only with no append in flight). -/

@[expose] public section

namespace Examples.Yap
open Cairn

/-! ## Frames -/

/-- `io'` follows `io` without starting a mark (no `markRead` appears), dropping an append in
flight, or saving a line. -/
structure Io.Frame (io io' : Io) : Prop where
  marks : ∀ id c f l, (id, Pend.markRead c f l) ∈ io'.pending → (id, Pend.markRead c f l) ∈ io.pending
  appends : ∀ x ∈ io.appends, x ∈ io'.appends
  saved : ∀ e ∈ io'.saved, e ∈ io.saved

theorem Io.Frame.refl (io : Io) : io.Frame io := ⟨fun _ _ _ _ h => h, fun _ h => h, fun _ h => h⟩

theorem Io.Frame.trans {a b c : Io} (h1 : a.Frame b) (h2 : b.Frame c) : a.Frame c :=
  ⟨fun _ _ _ _ h => h1.marks _ _ _ _ (h2.marks _ _ _ _ h),
    fun _ h => h2.appends _ (h1.appends _ h), fun _ h => h1.saved _ (h2.saved _ h)⟩

theorem Io.Frame.of_eq {io io' : Io}
    (h2 : io'.pending = io.pending) (h3 : io'.appends = io.appends) (h4 : io'.saved = io.saved) :
    io.Frame io' :=
  ⟨fun _ _ _ _ h => h2 ▸ h, fun _ h => h3 ▸ h, fun _ h => h4 ▸ h⟩

/-- Not a mark's read. -/
def Pend.notMark : Pend → Prop
  | .markRead .. => False
  | _ => True

theorem Io.frame_fresh (io : Io) {p : Pend} (hp : p.notMark) : io.Frame (io.fresh p).1 := by
  refine ⟨?_, fun _ h => h, fun _ h => h⟩
  intro id c f l h
  simp only [Io.fresh, List.mem_cons] at h
  rcases h with h | h
  · simp only [Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact hp.elim
  · exact h

theorem Io.frame_ask (io : Io) {p : Pend} (hp : p.notMark) (a : Ask) : io.Frame (io.ask p a).1 :=
  io.frame_fresh hp

theorem Io.frame_ask_of {io io' : Io} (h : io.Frame io') {p : Pend} (hp : p.notMark) (a : Ask) :
    io.Frame (io'.ask p a).1 :=
  h.trans (io'.frame_ask hp a)

theorem Io.frame_take {io io' : Io} {id : Nat} {p : Pend} (h : io.take id = some (p, io')) :
    io.Frame io' := by
  unfold Io.take at h
  cases hl : io.pending.lookup id <;> simp only [hl, Option.map_none, Option.map_some,
    reduceCtorEq, Option.some.injEq, Prod.mk.injEq] at h
  obtain ⟨-, rfl⟩ := h
  exact ⟨fun _ _ _ _ hm => (List.mem_filter.1 hm).1, fun _ hm => hm, fun _ hm => hm⟩

/-! ## The machine's commands -/

theorem frame_deletes (io : Io) (ds : List Nat) : io.Frame (deletes io ds).1 := by
  induction ds generalizing io with
  | nil => exact Io.Frame.refl _
  | cons d ds ih =>
    simp only [deletes]
    exact (io.frame_fresh (p := .ignore) (by trivial)).trans (ih _)

theorem frame_trAsk (io : Io) (c : Cmd) : io.Frame (trAsk io c).1 := by
  cases c <;> simp only [trAsk]
  case «open» o =>
    cases o <;> (refine Io.frame_ask _ ?_ _; trivial)
  case markTyped => exact Io.Frame.of_eq rfl rfl rfl
  case play snd => refine Io.frame_ask _ ?_ _; trivial
  case startRecording c =>
    have h0 : io.Frame { io with held := c :: io.held } := Io.Frame.of_eq rfl rfl rfl
    exact Io.frame_ask_of (Io.frame_ask_of h0 (p := .front c) trivial _) (p := .model) trivial _
  all_goals first
    | exact Io.Frame.refl _
    | (refine Io.frame_ask _ ?_ _; trivial)
    | (apply Io.frame_ask_of; exact Io.Frame.of_eq rfl rfl rfl; trivial)

theorem frame_tr (io : Io) (c : Cmd) : io.Frame (tr io c).1 := by
  cases c <;> simp only [tr]
  case save q t => exact ⟨fun _ _ _ _ h => h, fun _ h => List.mem_cons_of_mem _ h, fun _ h => h⟩
  case deleteDays ds => exact frame_deletes io ds
  case overlay c o => exact Io.Frame.of_eq rfl rfl rfl
  all_goals first
    | exact Io.Frame.refl _
    | exact frame_trAsk io _

theorem frame_trAll (io : Io) (cs : List Cmd) : io.Frame (trAll io cs).1 := by
  induction cs generalizing io with
  | nil => exact Io.Frame.refl _
  | cons c cs ih => exact (frame_tr io c).trans (ih _)

/-- An append to a file. -/
def Ask.isAppend : Ask → Bool
  | .append .. => true
  | _ => false

theorem mem_asks_append {as : List (Nat × Ask)} {id : Nat} {f : String} {d : ByteArray}
    (h : Effect.request id (.appendFile f d) ∈ as.map Ask.effect) :
    ∃ x ∈ as, x.1 = id ∧ ∃ l, x.2 = .append f l ∧ d = l.toUTF8 := by
  obtain ⟨⟨i, a⟩, hx, he⟩ := List.mem_map.1 h
  cases a <;> simp only [Ask.effect, Ask.request, Effect.request.injEq, reduceCtorEq, and_false,
    Request.appendFile.injEq] at he
  obtain ⟨rfl, rfl, rfl⟩ := he
  exact ⟨_, hx, rfl, _, rfl, rfl⟩

theorem trAsk_noAppend (io : Io) (c : Cmd) : ∀ x ∈ (trAsk io c).2, x.2.isAppend = false := by
  cases c <;> simp only [trAsk]
  case «open» o => cases o <;> simp [Io.ask, Io.fresh, Ask.isAppend]
  all_goals simp [Io.ask, Io.fresh, Ask.isAppend]

theorem no_append {as : List (Nat × Ask)} (hn : ∀ x ∈ as, x.2.isAppend = false) {id : Nat}
    {f : String} {d : ByteArray} (h : Effect.request id (.appendFile f d) ∈ as.map Ask.effect) : False := by
  obtain ⟨x, hx, -, l, he, -⟩ := mem_asks_append h
  have := hn x hx
  rw [he] at this
  cases this

/-- Every append a command sends is in flight after it, with its line. -/
theorem tr_append {io : Io} {c : Cmd} {id : Nat} {f : String} {d : ByteArray}
    (h : Effect.request id (.appendFile f d) ∈ (tr io c).2) :
    ∃ k line, (id, k, f, line) ∈ (tr io c).1.appends ∧ d = line.toUTF8 := by
  cases c <;> simp only [tr] at h
  case save q t =>
    simp only [List.mem_singleton, Effect.request.injEq, Request.appendFile.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    exact ⟨_, _, List.mem_cons_self, rfl⟩
  case deleteDays ds =>
    obtain ⟨_, _, -, he⟩ := mem_deletes h
    cases he
  case overlay c o => exact (overlay_apply_ok _ _ _ _ h).elim
  all_goals first
    | (simp [transcription] at h; done)
    | exact (no_append (trAsk_noAppend _ _) h).elim

theorem trAll_append_tracked {io : Io} {cs : List Cmd} {id : Nat} {f : String} {d : ByteArray}
    (h : Effect.request id (.appendFile f d) ∈ (trAll io cs).2) :
    ∃ k line, (id, k, f, line) ∈ (trAll io cs).1.appends ∧ d = line.toUTF8 := by
  induction cs generalizing io with
  | nil => simp [trAll] at h
  | cons c cs ih =>
    simp only [trAll, List.mem_append] at h ⊢
    rcases h with h | h
    · obtain ⟨k, line, hm, hd⟩ := tr_append h
      exact ⟨k, line, (frame_trAll _ cs).appends _ hm, hd⟩
    · exact ih h

/-! ## The app's own requests -/

/-- Asks that append nothing. -/
def NoAppend (as : List (Nat × Ask)) : Prop := ∀ x ∈ as, x.2.isAppend = false

theorem noAppend_nil : NoAppend [] := fun _ h => nomatch h

theorem frame_booted {io io' : Io} (h : io.Frame io') :
    io.Frame (booted io').io ∧ NoAppend (booted io').asks := by
  unfold booted
  split
  · exact ⟨h, noAppend_nil⟩
  · split
    · exact ⟨h.trans (Io.Frame.of_eq rfl rfl rfl), noAppend_nil⟩
    · exact ⟨h, noAppend_nil⟩

theorem frame_nextRecent {io io' : Io} (h : io.Frame io') (n : Nat) (rest : List String)
    (acc : List Transcript) :
    io.Frame (nextRecent io' n rest acc).io ∧ NoAppend (nextRecent io' n rest acc).asks := by
  unfold nextRecent
  split
  · exact ⟨h, noAppend_nil⟩
  · split
    · exact ⟨h, noAppend_nil⟩
    · simp only [Io.ask, Io.fresh]
      refine ⟨h.trans ?_, ?_⟩
      · clear h; refine ⟨?_, ?_, ?_⟩ <;> intros <;> simp_all
      · simp [NoAppend, Ask.isAppend]

theorem frame_ownReply (s : AppState) (p : Pend) (io : Io) (r : Cairn.Reply) :
    io.Frame (ownReply s p io r).io ∧ NoAppend (ownReply s p io r).asks := by
  cases p <;> simp only [ownReply, Io.ask, Io.fresh]
  case bootPrefs | bootModel | bootEnabled | bootSubmits =>
    exact frame_booted (Io.Frame.of_eq rfl rfl rfl)
  case recentList n =>
    split
    · exact frame_nextRecent (Io.Frame.refl _) _ _ _
    · exact ⟨Io.Frame.refl _, noAppend_nil⟩
  case recentFile n rest acc =>
    split <;> exact frame_nextRecent (Io.Frame.refl _) _ _ _
  all_goals (repeat' split) <;> first
    | exact ⟨Io.Frame.refl _, noAppend_nil⟩
    | (refine ⟨⟨?_, ?_, ?_⟩, ?_⟩ <;> (try intros) <;> simp_all [NoAppend, Ask.isAppend, markDone])

theorem frame_checks (io : Io) : io.Frame (checks io).1 ∧ NoAppend (checks io).2 := by
  unfold checks
  split
  · exact ⟨Io.Frame.refl _, noAppend_nil⟩
  · simp only [Io.ask, Io.fresh]
    (refine ⟨⟨?_, ?_, ?_⟩, ?_⟩ <;> (try intros) <;> simp_all [NoAppend, Ask.isAppend])

/-! ## A reply to an append -/

theorem landed_frame (io : Io) (id : Nat) (r : Cairn.Reply) :
    (io.landed id r).pending = io.pending ∧
      (∀ x ∈ io.appends, x ∉ (io.landed id r).appends → x.1 = id) ∧
      (∀ e ∈ (io.landed id r).saved, e ∈ io.saved ∨
        (r.ok = true ∧ (id, some e.1, e.2.1, e.2.2) ∈ io.appends)) := by
  unfold Io.landed
  split
  · exact ⟨rfl, fun _ h hn => (hn h).elim, fun _ h => Or.inl h⟩
  · rename_i k clip file line hf
    refine ⟨rfl, ?_, ?_⟩
    · intro x hx hn
      simp only [List.mem_filter, not_and, bne_iff_ne, ne_eq, Decidable.not_not] at hn
      exact hn hx
    · intro e he
      have hm := List.mem_of_find?_eq_some hf
      have hk := List.find?_some hf
      simp only [beq_iff_eq] at hk
      subst hk
      dsimp only at he
      split at he
      · rcases List.mem_cons.1 (List.mem_of_mem_take he) with rfl | he
        · exact Or.inr ⟨by assumption, hm⟩
        · exact Or.inl he
      · exact Or.inl he

/-! ## What a message is -/

theorem frame_prepMsg (s : AppState) (m : Msg) :
    ∃ io0, (io0 = s.io ∨ ∃ id r, m = .reply id r ∧ io0 = s.io.landed id r) ∧
      io0.Frame (prepMsg s m).io ∧ NoAppend (prepMsg s m).asks := by
  cases m with
  | clock t => exact ⟨s.io, Or.inl rfl, Io.Frame.of_eq rfl rfl rfl, noAppend_nil⟩
  | timer n =>
    refine ⟨s.io, Or.inl rfl, ?_⟩
    simp only [prepMsg]
    split
    · exact ⟨Io.Frame.of_eq rfl rfl rfl, noAppend_nil⟩
    · exact ⟨Io.Frame.refl _, noAppend_nil⟩
  | reply id r =>
    refine ⟨s.io.landed id r, Or.inr ⟨id, r, rfl, rfl⟩, ?_⟩
    simp only [prepMsg]
    split
    · exact ⟨Io.Frame.refl _, noAppend_nil⟩
    · split
      · rename_i p io ht
        obtain ⟨h1, h2⟩ := frame_ownReply s p io r
        exact ⟨(Io.frame_take ht).trans h1, h2⟩
      · exact ⟨Io.Frame.refl _, noAppend_nil⟩
  | sub x e =>
    refine ⟨s.io, Or.inl rfl, ?_⟩
    cases x <;> cases e
    case every.tick =>
      simp only [prepMsg]
      split
      · exact ⟨Io.Frame.refl _, noAppend_nil⟩
      · have h := frame_checks s.io
        rcases hc : checks s.io with ⟨io', as⟩
        rw [hc] at h
        exact h
    all_goals simp only [prepMsg, Io.ask, Io.fresh]
    all_goals (repeat' split) <;> first
      | exact ⟨Io.Frame.refl _, noAppend_nil⟩
      | (refine ⟨⟨?_, ?_, ?_⟩, ?_⟩ <;> (try intros) <;> simp_all [NoAppend, Ask.isAppend])

/-! ## The end of a message: the marks' next requests -/

/-- `io'` follows `io` by starting a mark: no append was in flight before or after, and each new
mark's read is for a line whose append was answered ok (`Io.saved`). -/
structure Io.Started (io io' : Io) : Prop where
  before : io.appends = []
  after : io'.appends = []
  marks : ∀ id c f l, (id, Pend.markRead c f l) ∈ io'.pending →
    (id, Pend.markRead c f l) ∈ io.pending ∨ (c, f, l) ∈ io'.saved
  saved : ∀ e ∈ io'.saved, e ∈ io.saved

/-- What the end of a message does: nothing to the marks, or start one. -/
def Io.Ends (io io' : Io) : Prop := io.Frame io' ∨ io.Started io'

theorem Io.Frame.ends {a b c : Io} (h1 : a.Frame b) (h2 : b.Ends c) : a.Ends c := by
  rcases h2 with h2 | h2
  · exact Or.inl (h1.trans h2)
  · refine Or.inr ⟨?_, h2.after, fun id c f l h => ?_, fun e he => h1.saved _ (h2.saved _ he)⟩
    · cases ha : a.appends with
      | nil => rfl
      | cons x xs =>
        have := h1.appends x (by rw [ha]; exact List.mem_cons_self)
        rw [h2.before] at this; cases this
    · rcases h2.marks id c f l h with h | h
      · exact Or.inl (h1.marks _ _ _ _ h)
      · exact Or.inr h

theorem Io.Ends.saved {a b : Io} (h : a.Ends b) : ∀ e ∈ b.saved, e ∈ a.saved := by
  rcases h with h | h
  · exact h.saved
  · exact h.saved

theorem forgetAll_spec (io : Io) (cs : List Nat) :
    io.Frame (forgetAll io cs).1 ∧ NoAppend (forgetAll io cs).2 := by
  induction cs generalizing io with
  | nil => exact ⟨Io.Frame.refl _, noAppend_nil⟩
  | cons c cs ih =>
    simp only [forgetAll, Io.ask, Io.fresh]
    obtain ⟨h1, h2⟩ := ih { io with nextId := io.nextId + 2, pending := (io.nextId, .ignore) :: io.pending }
    refine ⟨Io.Frame.trans ?_ h1, ?_⟩
    · refine ⟨?_, ?_, ?_⟩ <;> intros <;> simp_all
    · intro x hx
      rcases List.mem_cons.1 hx with rfl | hx
      · rfl
      · exact h2 x hx

theorem reappendAll_spec (io : Io) (ls : List (String × String)) :
    io.Frame (reappendAll io ls).1 ∧ ∀ x ∈ (reappendAll io ls).2, ∀ f l, x.2 = .append f l →
      (x.1, none, f, l) ∈ (reappendAll io ls).1.appends := by
  induction ls generalizing io with
  | nil =>
    simp only [reappendAll]
    exact ⟨Io.Frame.of_eq rfl rfl rfl, by simp⟩
  | cons fl rest ih =>
    obtain ⟨f, l⟩ := fl
    simp only [reappendAll, Io.ask, Io.fresh]
    obtain ⟨h1, h2⟩ := ih { io with nextId := io.nextId + 2, pending := (io.nextId, .ignore) :: io.pending,
                                    appends := (io.nextId, none, f, l) :: io.appends }
    refine ⟨Io.Frame.trans ?_ h1, ?_⟩
    · refine ⟨?_, ?_, ?_⟩ <;> intros <;> simp_all
    · intro x hx f' l' he
      rcases List.mem_cons.1 hx with rfl | hx
      · simp only [Ask.append.injEq] at he
        obtain ⟨rfl, rfl⟩ := he
        exact h1.appends _ List.mem_cons_self
      · exact h2 x hx f' l' he

theorem startMark_spec (io : Io) (cs : List Nat) :
    (io.Frame (startMark io cs).1 ∨
      ((startMark io cs).1.appends = io.appends ∧
        (∀ id c f l, (id, Pend.markRead c f l) ∈ (startMark io cs).1.pending →
          (id, Pend.markRead c f l) ∈ io.pending ∨ (c, f, l) ∈ (startMark io cs).1.saved) ∧
        ∀ e ∈ (startMark io cs).1.saved, e ∈ io.saved)) ∧
    NoAppend (startMark io cs).2 := by
  induction cs with
  | nil => exact ⟨Or.inl (Io.Frame.of_eq rfl rfl rfl), noAppend_nil⟩
  | cons c rest ih =>
    simp only [startMark]
    split
    · rename_i k file line hf
      simp only [Io.ask, Io.fresh]
      refine ⟨Or.inr ⟨?_, ?_, ?_⟩, by simp [NoAppend, Ask.isAppend]⟩
      · trivial
      · intro id c' f l h
        rcases List.mem_cons.1 h with h | h
        · simp only [Prod.mk.injEq, Pend.markRead.injEq] at h
          obtain ⟨-, h1, h2, h3⟩ := h
          subst h1 h2 h3
          have hk := List.find?_some hf
          simp only [beq_iff_eq] at hk
          subst hk
          exact Or.inr (List.mem_of_find?_eq_some hf)
        · exact Or.inl h
      · first | trivial | (intro e he; exact he) | simp
    · exact ih

theorem nextMark_spec (io : Io) : io.Ends (nextMark io).1 ∧ NoAppend (nextMark io).2 := by
  unfold nextMark
  split
  · rename_i he
    have he : io.appends = [] := List.isEmpty_iff.1 he
    split
    · obtain ⟨h1 | ⟨h1, h2, h3⟩, h4⟩ := startMark_spec io io.marks
      · exact ⟨Or.inl h1, h4⟩
      · exact ⟨Or.inr ⟨he, h1.trans he, h2, h3⟩, h4⟩
    · rename_i m
      split
      · split
        · obtain ⟨h1 | ⟨h1, h2, h3⟩, h4⟩ := startMark_spec { io with marking := none } io.marks
          · exact ⟨Or.inl ((Io.Frame.of_eq rfl rfl rfl : io.Frame { io with marking := none }).trans h1), h4⟩
          · exact ⟨Or.inr ⟨he, h1.trans he, h2, h3⟩, h4⟩
        · simp only [Io.ask, Io.fresh]
          refine ⟨Or.inl ?_, by simp [NoAppend, Ask.isAppend]⟩
          refine ⟨?_, ?_, ?_⟩ <;> intros <;> simp_all
      · exact ⟨Or.inl (Io.Frame.refl _), noAppend_nil⟩
  · exact ⟨Or.inl (Io.Frame.refl _), noAppend_nil⟩

/-- Appends among the asks are in flight. -/
def Tracked (io : Io) (as : List (Nat × Ask)) : Prop :=
  ∀ x ∈ as, ∀ f l, x.2 = .append f l → (x.1, none, f, l) ∈ io.appends

theorem pump_spec (io : Io) : io.Ends (pumpMarks io).1 ∧ Tracked (pumpMarks io).1 (pumpMarks io).2 := by
  obtain ⟨h1, h2⟩ := reappendAll_spec io io.reappend
  obtain ⟨h3, h4⟩ := nextMark_spec (reappendAll io io.reappend).1
  refine ⟨h1.ends h3, ?_⟩
  intro x hx f l he
  rcases List.mem_append.1 hx with hx | hx
  · have hm := h2 x hx f l he
    rcases h3 with h3 | h3
    · exact h3.appends _ hm
    · rw [h3.before] at hm; cases hm
  · have := h4 x hx
    rw [he] at this; cases this

theorem collect_spec (io : Io) (s : State) :
    io.Ends (collect io s).1 ∧ Tracked (collect io s).1 (collect io s).2 := by
  obtain ⟨h1, h2⟩ := forgetAll_spec { io with held := io.held.filter (fun c => (needed s).contains c) }
    (io.held.filter (fun c => !(needed s).contains c))
  obtain ⟨h3, h4⟩ := pump_spec (forget io s).1
  refine ⟨((Io.Frame.of_eq rfl rfl rfl :
    io.Frame { io with held := io.held.filter (fun c => (needed s).contains c) }).trans h1).ends h3, ?_⟩
  intro x hx f l he
  rcases List.mem_append.1 hx with hx | hx
  · have := h2 x hx
    rw [he] at this; cases this
  · exact h4 x hx f l he

/-! ## Through `receive` and the menu -/

theorem Io.Ends.appends {a b : Io} (h : a.Ends b) : ∀ x ∈ a.appends, x ∈ b.appends := by
  rcases h with h | h
  · exact h.appends
  · intro x hx; rw [h.before] at hx; cases hx

theorem prep_none {s : AppState} {m : Msg} (h : (prepMsg s m).input = none) :
    (prep s m).io = (pumpMarks (prepMsg s m).io).1 ∧
      (prep s m).asks = (prepMsg s m).asks ++ (pumpMarks (prepMsg s m).io).2 := by
  simp [prep, h]

theorem prep_some {s : AppState} {m : Msg} {i : Input} (h : (prepMsg s m).input = some i) :
    prep s m = prepMsg s m := by
  simp only [prep, h]

theorem receive_spec (s : AppState) (m : Msg) :
    ∃ io0, (io0 = s.io ∨ ∃ id r, m = .reply id r ∧ io0 = s.io.landed id r) ∧
      io0.Ends (receive s m).1.io ∧
      ∀ id f d, Effect.request id (.appendFile f d) ∈ (receive s m).2 →
        ∃ k line, (id, k, f, line) ∈ (receive s m).1.io.appends ∧ d = line.toUTF8 := by
  obtain ⟨io0, h0, hf, hn⟩ := frame_prepMsg s m
  refine ⟨io0, h0, ?_⟩
  cases hi : (prepMsg s m).input with
  | none =>
    have hi' : (prep s m).input = none := by rw [prep_input_eq]; exact hi
    rw [receive_none hi']
    dsimp only
    rw [(prep_none hi).1, (prep_none hi).2]
    obtain ⟨h1, h2⟩ := pump_spec (prepMsg s m).io
    refine ⟨hf.ends h1, ?_⟩
    intro id f d he
    obtain ⟨x, hx, rfl, l, hxa, rfl⟩ := mem_asks_append he
    rcases List.mem_append.1 hx with hx | hx
    · have := hn x hx
      rw [hxa] at this; cases this
    · exact ⟨_, _, h2 x hx f l hxa, rfl⟩
  | some i =>
    have hi' : (prep s m).input = some i := by rw [prep_input_eq]; exact hi
    rw [receive_some hi', prep_some hi]
    simp only [feedCore]
    have ht := frame_trAll (prepMsg s m).io (step (coreAt s (prepMsg s m)) i).2
    obtain ⟨h1, h2⟩ := collect_spec (trAll (prepMsg s m).io (step (coreAt s (prepMsg s m)) i).2).1
      (step (coreAt s (prepMsg s m)) i).1
    refine ⟨(hf.trans ht).ends h1, ?_⟩
    intro id f d he
    simp only [List.mem_append] at he
    rcases he with he | he | he
    · obtain ⟨x, hx, -, l, hxa, -⟩ := mem_asks_append he
      have := hn x hx
      rw [hxa] at this; cases this
    · obtain ⟨k, line, hm, hd⟩ := trAll_append_tracked he
      exact ⟨k, line, h1.appends _ hm, hd⟩
    · obtain ⟨x, hx, rfl, l, hxa, rfl⟩ := mem_asks_append he
      exact ⟨_, _, h2 x hx f l hxa, rfl⟩

/-- **^347, the appends**: every append `receive` sends is in flight after it. -/
theorem receive_tracks (s : AppState) (m : Msg) {id : Nat} {f : String} {d : ByteArray}
    (h : Effect.request id (.appendFile f d) ∈ (receive s m).2) :
    ∃ k line, (id, k, f, line) ∈ (receive s m).1.io.appends ∧ d = line.toUTF8 := by
  obtain ⟨_, _, _, h3⟩ := receive_spec s m
  exact h3 _ _ _ h

/-- **^347, the replies**: an append is in flight until a reply with its id arrives. -/
theorem receive_answers (s : AppState) (m : Msg) {x : Nat × Option Nat × String × String}
    (hx : x ∈ s.io.appends) (hn : x ∉ (receive s m).1.io.appends) : ∃ r, m = .reply x.1 r := by
  obtain ⟨io0, h0 | ⟨id, r, rfl, rfl⟩, h2, -⟩ := receive_spec s m
  · subst h0; exact (hn (h2.appends _ hx)).elim
  · obtain ⟨-, h3, -⟩ := landed_frame s.io id r
    by_cases hl : x ∈ (s.io.landed id r).appends
    · exact (hn (h2.appends _ hl)).elim
    · exact ⟨r, by rw [h3 x hx hl]⟩

/-- **^347, the saved lines**: a line is saved only when the reply to its append says it worked. -/
theorem receive_saves (s : AppState) (m : Msg) {e : Nat × String × String}
    (he : e ∈ (receive s m).1.io.saved) (hn : e ∉ s.io.saved) :
    ∃ id r, m = .reply id r ∧ r.ok = true ∧ (id, some e.1, e.2.1, e.2.2) ∈ s.io.appends := by
  obtain ⟨io0, h0 | ⟨id, r, rfl, rfl⟩, h2, -⟩ := receive_spec s m
  · subst h0; exact (hn (h2.saved _ he)).elim
  · obtain ⟨-, -, h3⟩ := landed_frame s.io id r
    rcases h3 e (h2.saved _ he) with h | ⟨hok, hm⟩
    · exact (hn h).elim
    · exact ⟨id, r, rfl, hok, hm⟩

/-- **^347, the marks**: a mark starts (its read appears) only when no append is in flight after
the message, and only for a saved line. -/
theorem receive_marks (s : AppState) (m : Msg) {id c : Nat} {f l : String}
    (h : (id, Pend.markRead c f l) ∈ (receive s m).1.io.pending)
    (hn : (id, Pend.markRead c f l) ∉ s.io.pending) :
    (receive s m).1.io.appends = [] ∧ (c, f, l) ∈ (receive s m).1.io.saved := by
  obtain ⟨io0, h0, h2, -⟩ := receive_spec s m
  have hp : io0.pending = s.io.pending := by
    rcases h0 with rfl | ⟨id, r, -, rfl⟩
    · rfl
    · exact (landed_frame s.io id r).1
  rcases h2 with h2 | h2
  · exact (hn (hp ▸ h2.marks _ _ _ _ h)).elim
  · rcases h2.marks _ _ _ _ h with h' | h'
    · exact (hn (hp ▸ h')).elim
    · exact ⟨h2.after, h'⟩

/-- **^347, the menu**: it starts no mark, drops no append, and its appends are in flight. -/
theorem menuStep_marks (s : AppState) (a : MenuAction) :
    s.io.Frame (menuStep s a).1.io ∧ ∀ id f d, Effect.request id (.appendFile f d) ∈ (menuStep s a).2 →
      ∃ k line, (id, k, f, line) ∈ (menuStep s a).1.io.appends ∧ d = line.toUTF8 :=
  ⟨frame_trAll _ _, fun _ _ _ h => trAll_append_tracked h⟩

end Examples.Yap

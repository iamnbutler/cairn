module

public import Examples.Yap.MarkProofs

/-! # Yap: nothing shows before the microphone runs

The original Yap's `begin` (App/Yap.swift) starts the microphone first and only then says
"Listening…" and shows the overlay; a microphone that fails to start says so and never shows it.
Here a recording is *starting* until the host reports `micStarted` (the `record` subscription's
`started` event, ^1005), and:

* the overlay shows a recording only once its microphone has started (`receive_ovInv`, ^349);
* while a recording is starting, key events wait: a key event leaves it as it is
  (`app_keys_wait`, ^350);
* the key events that waited are handled once the start is reported, each timed from then, as
  the original's main thread handles them once `engine.start()` returns (`micStarted_replay`,
  ^351). -/

@[expose] public section

namespace Examples.Yap
open Cairn

/-! ## A recording that started stays started -/

/-- Going from `s` to `o`, a recording both have is the same clip, and stays started. -/
def Grows (s : State) (o : State × List Cmd) : Prop :=
  ∀ r r', s.recording = some r → o.1.recording = some r' →
    r'.clip = r.clip ∧ (r.started = true → r'.started = true)

namespace Grows

theorem mod {s : State} {o : State × List Cmd}
    (h : ∀ r r', s.recording = some r → o.1.recording = some r' →
      r'.clip = r.clip ∧ r'.started = r.started) : Grows s o := fun r r' hr hr' => by
  obtain ⟨h1, h2⟩ := h r r' hr hr'
  exact ⟨h1, fun h3 => h2.trans h3⟩

theorem same {s : State} {o : State × List Cmd} (h : o.1.recording = s.recording) : Grows s o :=
  mod fun r r' hr hr' => by rw [h, hr] at hr'; cases hr'; exact ⟨rfl, rfl⟩

theorem none {s : State} {o : State × List Cmd} (h : o.1.recording = none) : Grows s o :=
  fun _ _ _ hr' => by rw [h] at hr'; cases hr'

theorem of_rec {s s' : State} {o : State × List Cmd} (hs : s'.recording = s.recording)
    (h : Grows s' o) : Grows s o := fun r r' hr hr' => h r r' (hs.trans hr) hr'

theorem of_some {s : State} {o : State × List Cmd}
    (h : ∀ r', o.1.recording = some r' → (∃ r, s.recording = some r ∧ r.Same r') ∨ s.recording = .none) :
    Grows s o := mod fun r r' hr hr' => by
  rcases h r' hr' with ⟨r0, h0, hs⟩ | h0
  · rw [hr] at h0; cases h0
    exact ⟨hs.clip, hs.started⟩
  · rw [hr] at h0; cases h0

theorem comp {s : State} {o₁ o₂ : State × List Cmd} (h₁ : Grows s o₁) (h₂ : Grows o₁.1 o₂)
    (hn : o₁.1.recording = .none → o₂.1.recording = .none) (l : List Cmd) : Grows s (o₂.1, l) := by
  intro r r' hr hr'
  cases hm : o₁.1.recording with
  | none => rw [hn hm] at hr'; cases hr'
  | some m =>
    obtain ⟨a1, a2⟩ := h₁ r m hr hm
    obtain ⟨b1, b2⟩ := h₂ m r' hm hr'
    exact ⟨b1.trans a1, fun h => b2 (a2 h)⟩

end Grows

theorem stepKey_grows (s : State) (k : Key) : Grows s (stepKey s k) :=
  Grows.of_some fun _ h => (stepKey_some s k h).imp_right (·.1)

theorem drain_grows (s : State) (ks : List Key) : Grows s (drain s ks) :=
  Grows.of_some fun _ h => (drain_some s ks h).imp_right (·.1)

theorem release_grows (s : State) : Grows s (release s) :=
  Grows.of_some fun _ h => Or.inl (release_some s h)

theorem poll_grows (s : State) (r : Recording) (hr : s.recording = some r) : Grows s (poll s r) := by
  refine Grows.mod fun r0 r' h0 hr' => ?_
  rw [hr] at h0; cases h0
  revert hr'
  unfold poll; dsimp only
  repeat' split
  all_goals intro hr'; simp only [Option.some.injEq] at hr'; subst hr'; exact ⟨rfl, rfl⟩

theorem tickRec_grows (s : State) : Grows s (tickRec s) := by
  unfold tickRec
  split
  · exact Grows.same rfl
  · rename_i r hr
    split
    · split
      · exact Grows.none rfl
      · exact Grows.same rfl
    · split
      · exact Grows.none (send_recording _ _)
      · split
        · exact poll_grows s r hr
        · exact Grows.same rfl

theorem tickRec_none (s : State) (h : s.recording = .none) : (tickRec s).1.recording = .none := by
  unfold tickRec; split
  · exact h
  · rename_i hr; rw [h] at hr; cases hr

theorem tick_grows (s : State) : Grows s (tick s) := by
  unfold tick
  split
  · exact tickRec_grows _
  · exact Grows.comp (Grows.of_rec (s' := { s with keys := [] }) rfl (drain_grows _ _))
      (tickRec_grows _) (tickRec_none _) _

theorem micStarted_grows (s : State) (c : Nat) : Grows s (micStarted s c) := by
  unfold micStarted
  split
  · rename_i r hr
    split
    · intro r0 r' h0 hr'
      rw [hr] at h0; cases h0
      rcases drain_some _ _ hr' with ⟨r1, h1, hs⟩ | ⟨h1, -⟩
      · simp only [Option.some.injEq] at h1; subst h1
        refine ⟨hs.clip, fun _ => ?_⟩
        rw [hs.started]
      · cases h1
    · exact Grows.same rfl
  · exact Grows.same rfl

theorem keyIn_grows (s : State) (k : Key) : Grows s (keyIn s k) := by
  unfold keyIn; split
  · exact Grows.same rfl
  · exact stepKey_grows _ _

theorem audio_grows (s : State) (c : Nat) (a : Audio) : Grows s (audio s c a) := by
  unfold audio
  split
  · rename_i r hr
    split
    · exact Grows.mod fun r0 r' h0 hr' => by
        rw [hr] at h0; cases h0; simp only [Option.some.injEq] at hr'; subst hr'; exact ⟨rfl, rfl⟩
    · exact Grows.same rfl
  · exact Grows.same rfl

theorem micFailed_grows (s : State) (c : Nat) (e : String) : Grows s (micFailed s c e) := by
  unfold micFailed
  split
  · split
    · split <;> exact Grows.none rfl
    · exact Grows.same rfl
  · exact Grows.same rfl

theorem chunkDone_grows (s : State) (c q : Nat) (t : Option String) : Grows s (chunkDone s c q t) := by
  unfold chunkDone
  split
  · rename_i r hr
    split
    · exact Grows.mod fun r0 r' h0 hr' => by
        rw [hr] at h0; cases h0; simp only [Option.some.injEq] at hr'; subst hr'; exact ⟨rfl, rfl⟩
    · exact Grows.same rfl
  · exact Grows.same rfl

theorem reply_grows (s : State) (q : Nat) (x : Reply) : Grows s (reply s q x) := by
  unfold reply
  cases hq : s.reqs.lookup q with
  | none => exact Grows.same rfl
  | some req =>
    dsimp only
    cases req <;> cases x <;> dsimp only
    case clip.ok => exact Grows.same (transcribed_recording _ _ _)
    case chunk.ok =>
      exact Grows.of_rec (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (chunkDone_grows _ _ _ _)
    case chunk.failed =>
      exact Grows.of_rec (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (chunkDone_grows _ _ _ _)
    all_goals exact Grows.same rfl

theorem setKey_grows (s : State) (k : Hotkey) : Grows s (setKey s k) := by
  unfold setKey
  split
  · exact Grows.same rfl
  · dsimp only
    split
    · exact Grows.same rfl
    · split
      · exact Grows.of_rec (s' := { s with keyHeld := false }) rfl (release_grows _)
      · exact Grows.same rfl

theorem applySettings_grows (s : State) (cfg : Settings) : Grows s (applySettings s cfg) := by
  unfold applySettings
  dsimp only
  split
  · exact Grows.same rfl
  · rename_i k _
    have h := Grows.of_rec (s' := { s with settings := cfg }) rfl (setKey_grows _ k)
    exact fun r r' hr hr' => h r r' hr (by revert hr'; split <;> exact id)

theorem configured_grows (s : State) (c : ConfigRead) : Grows s (configured s c) := by
  have : Grows s (readConfig s c) := by
    unfold readConfig
    split
    · exact Grows.same rfl
    · exact applySettings_grows _ _
    · exact applySettings_grows _ _
  exact fun r r' hr hr' => this r r' hr hr'

theorem menu_grows (s : State) (m : MenuAction) : Grows s (menu s m) := by
  rcases menu_recording s m with h | h
  · exact Grows.same h
  · exact Grows.none h

/-- **A recording keeps its clip, and once its microphone has started it stays started.** -/
theorem step_grows (s : State) (i : Input) : Grows s (step s i) := by
  cases i with
  | keyDown t f => exact keyIn_grows _ _
  | keyUp t => exact keyIn_grows _ _
  | otherKey => exact keyIn_grows _ _
  | tick t => exact Grows.of_rec (s' := { s with now := max s.now t }) rfl (tick_grows _)
  | micStarted c t =>
    exact Grows.of_rec (s' := { s with now := max s.now t }) rfl (micStarted_grows _ _)
  | audio c a => exact audio_grows _ _ _
  | micFailed c e => exact micFailed_grows _ _ _
  | reply q x => exact reply_grows _ _ _
  | config c => exact configured_grows _ _
  | menu m => exact menu_grows _ _
  | front c a =>
    refine Grows.mod fun r r' hr hr' => ?_
    simp only [step, setFront, hr, Option.map_some, Option.some.injEq] at hr'
    subst hr'
    split <;> exact ⟨rfl, rfl⟩
  | keyLost =>
    simp only [step, keyLost]
    split
    · exact Grows.none rfl
    · exact Grows.none ‹_›
  | transcriptDays => exact Grows.same rfl
  | _ => exact Grows.same rfl

/-! ## The overlay begins only when the microphone starts -/

theorem micStarted_begin (s : State) (c n : Nat) (h : Cmd.overlay n .begin ∈ (micStarted s c).2) :
    ∃ r, s.recording = some r ∧ r.clip = n ∧
      ∀ r', (micStarted s c).1.recording = some r' → r'.started = true := by
  unfold micStarted at h ⊢
  split at h
  · rename_i r hr
    split at h
    · rename_i hc
      simp only [hr, hc, and_self, ↓reduceIte]
      rcases List.mem_append.1 h with h | h
      · split at h
        · simp only [List.mem_cons, Cmd.overlay.injEq, List.not_mem_nil, or_false,
            reduceCtorEq, and_false] at h
          refine ⟨r, rfl, hc.1.trans h.1.symm, fun r' hr' => ?_⟩
          rcases drain_some _ _ hr' with ⟨r1, h1, hs⟩ | ⟨h1, -⟩
          · simp only [Option.some.injEq] at h1; subst h1
            rw [hs.started]
          · cases h1
        · simp at h
      · exact absurd rfl ((drain_kinds _ _).not_mem (k := .begin) (by simp [drainKinds]) h)
    · simp at h
  · simp at h

/-- **Only the microphone's start shows the overlay**: a step that begins the overlay for clip
`n` is the host reporting that clip's microphone started, and leaves no recording but that one,
started. -/
theorem step_begin (s : State) (i : Input) {n : Nat} (h : Cmd.overlay n .begin ∈ (step s i).2) :
    ∃ r, s.recording = some r ∧ r.clip = n ∧
      ∀ r', (step s i).1.recording = some r' → r'.started = true := by
  have hk := kind_of_step h
  cases i
  case micStarted c t =>
    exact micStarted_begin { s with now := max s.now t } c n h
  all_goals simp [stepKinds, drainKinds, Cmd.kind] at hk

/-! ## The app's overlay -/

/-- What ^349 looks at in the overlay: its clip stays, and it doesn't appear. -/
def OvKeeps (o o' : Overlay) : Prop := o'.clip = o.clip ∧ (o'.shown = true → o.shown = true)

theorem OvKeeps.refl (o : Overlay) : OvKeeps o o := ⟨rfl, id⟩

theorem OvKeeps.trans {a b c : Overlay} (h1 : OvKeeps a b) (h2 : OvKeeps b c) : OvKeeps a c :=
  ⟨h2.1.trans h1.1, fun h => h1.2 (h2.2 h)⟩

theorem OvKeeps.of_eq {a b : Overlay} (h : b = a) : OvKeeps a b := h ▸ OvKeeps.refl _

theorem apply_keeps (o : Overlay) (now c : Nat) (x : OverlayCmd) (hx : x ≠ .begin) :
    OvKeeps o (o.apply now c x).1 := by
  cases x
  case begin => exact absurd rfl hx
  all_goals simp only [Overlay.apply]
  all_goals (repeat' split) <;> first
    | exact OvKeeps.refl _
    | exact ⟨rfl, id⟩
    | exact ⟨rfl, fun h => by simp at h⟩

theorem hear_keeps (o : Overlay) (c now : Nat) (ls : List Level) : OvKeeps o (o.hear c now ls) := by
  unfold Overlay.hear; split
  · exact ⟨rfl, id⟩
  · exact OvKeeps.refl _

theorem take_overlay {io io' : Io} {id : Nat} {p : Pend} (h : io.take id = some (p, io')) :
    io'.overlay = io.overlay := by
  unfold Io.take at h
  cases hl : io.pending.lookup id <;> simp only [hl, Option.map_none, Option.map_some,
    reduceCtorEq, Option.some.injEq, Prod.mk.injEq] at h
  obtain ⟨-, rfl⟩ := h
  rfl

theorem landed_overlay (io : Io) (id : Nat) (r : Cairn.Reply) : (io.landed id r).overlay = io.overlay := by
  unfold Io.landed; split <;> rfl

theorem deletes_overlay (io : Io) (ds : List Nat) : (deletes io ds).1.overlay = io.overlay := by
  induction ds generalizing io with
  | nil => rfl
  | cons d ds ih => simp only [deletes]; exact ih _

theorem trAsk_overlay (io : Io) (c : Cmd) : (trAsk io c).1.overlay = io.overlay := by
  cases c <;> simp only [trAsk]
  case «open» o => cases o <;> rfl
  all_goals rfl

theorem startMark_overlay (io : Io) (cs : List Nat) : (startMark io cs).1.overlay = io.overlay := by
  induction cs generalizing io with
  | nil => rfl
  | cons c cs ih =>
    simp only [startMark]
    split
    · rfl
    · exact ih _

theorem reappendAll_overlay (io : Io) (ls : List (String × String)) :
    (reappendAll io ls).1.overlay = io.overlay := by
  induction ls generalizing io with
  | nil => rfl
  | cons l ls ih => simp only [reappendAll]; exact ih _

theorem nextMark_overlay (io : Io) : (nextMark io).1.overlay = io.overlay := by
  unfold nextMark
  split
  · split
    · exact startMark_overlay _ _
    · split
      · split
        · exact startMark_overlay _ _
        · rfl
      · rfl
  · rfl

theorem pumpMarks_overlay (io : Io) : (pumpMarks io).1.overlay = io.overlay := by
  simp only [pumpMarks]
  rw [nextMark_overlay, reappendAll_overlay]

theorem forgetAll_overlay (io : Io) (cs : List Nat) : (forgetAll io cs).1.overlay = io.overlay := by
  induction cs generalizing io with
  | nil => rfl
  | cons c cs ih => simp only [forgetAll]; exact ih _

theorem collect_overlay (io : Io) (s : State) : (collect io s).1.overlay = io.overlay := by
  simp only [collect, forget]
  rw [pumpMarks_overlay, forgetAll_overlay]

theorem booted_overlay (io : Io) : (booted io).io.overlay = io.overlay := by
  unfold booted
  split
  · rfl
  · split <;> rfl

theorem nextRecent_overlay (io : Io) (n : Nat) (rest : List String) (acc : List Transcript) :
    (nextRecent io n rest acc).io.overlay = io.overlay := by
  unfold nextRecent
  split
  · rfl
  · split <;> rfl

theorem ownReply_overlay (s : AppState) (p : Pend) (io : Io) (r : Cairn.Reply) :
    (ownReply s p io r).io.overlay = io.overlay := by
  cases p <;> simp only [ownReply, Io.ask, Io.fresh]
  case bootPrefs | bootModel | bootEnabled | bootSubmits => exact booted_overlay _
  case recentList n =>
    split
    · exact nextRecent_overlay _ _ _ _
    · rfl
  case recentFile n rest acc =>
    split <;> exact nextRecent_overlay _ _ _ _
  all_goals (repeat' split) <;> rfl

theorem checks_overlay (io : Io) : (checks io).1.overlay = io.overlay := by
  unfold checks; split <;> rfl

theorem prepMsg_overlay (s : AppState) (m : Msg) : OvKeeps s.io.overlay (prepMsg s m).io.overlay := by
  cases m with
  | clock t => exact OvKeeps.refl _
  | timer n =>
    simp only [prepMsg]
    split
    · exact ⟨rfl, fun h => by simp at h⟩
    · exact OvKeeps.refl _
  | reply id r =>
    simp only [prepMsg]
    split
    · exact OvKeeps.of_eq (landed_overlay _ _ _)
    · split
      · rename_i p io ht
        exact OvKeeps.of_eq ((ownReply_overlay s p io r).trans
          ((take_overlay ht).trans (landed_overlay _ _ _)))
      · exact OvKeeps.of_eq (landed_overlay _ _ _)
  | sub x e =>
    cases x <;> cases e
    case every.tick =>
      simp only [prepMsg]
      split
      · exact OvKeeps.refl _
      · exact OvKeeps.of_eq (checks_overlay _)
    case record.audio c frames peak ws => exact hear_keeps _ _ _ _
    case record.failed => simp only [prepMsg]; split <;> exact OvKeeps.refl _
    all_goals simp only [prepMsg, Io.ask, Io.fresh]
    all_goals (repeat' split) <;> exact OvKeeps.refl _

theorem prep_overlay (s : AppState) (m : Msg) : OvKeeps s.io.overlay (prep s m).io.overlay := by
  cases h : (prepMsg s m).input <;> simp only [prep, h]
  · exact (prepMsg_overlay s m).trans (OvKeeps.of_eq (pumpMarks_overlay _))
  · exact prepMsg_overlay s m

theorem tr_keeps (io : Io) (c : Cmd) (hc : c.kind ≠ .begin) : OvKeeps io.overlay (tr io c).1.overlay := by
  cases c <;> simp only [tr]
  case overlay n x =>
    refine apply_keeps _ _ _ _ ?_
    rintro rfl; exact hc rfl
  case deleteDays ds => exact OvKeeps.of_eq (deletes_overlay _ _)
  all_goals first
    | exact OvKeeps.refl _
    | exact OvKeeps.of_eq (trAsk_overlay _ _)

/-- The overlay after a step's commands: as it was (at most hidden), or begun by one of them. -/
theorem trAll_overlay (io : Io) (cs : List Cmd) :
    OvKeeps io.overlay (trAll io cs).1.overlay ∨
      ∃ n, Cmd.overlay n .begin ∈ cs ∧ (trAll io cs).1.overlay.clip = n := by
  induction cs generalizing io with
  | nil => exact Or.inl (OvKeeps.refl _)
  | cons c cs ih =>
    simp only [trAll]
    by_cases hc : c.kind = .begin
    · obtain ⟨n, rfl⟩ : ∃ n, c = .overlay n .begin := by
        cases c <;> simp [Cmd.kind] at hc
        rename_i n x; cases x <;> simp at hc; exact ⟨n, rfl⟩
      right
      rcases ih (tr io (.overlay n .begin)).1 with h | ⟨n', h1, h2⟩
      · exact ⟨n, List.mem_cons_self .., h.1⟩
      · exact ⟨n', List.mem_cons_of_mem _ h1, h2⟩
    · rcases ih (tr io c).1 with h | ⟨n', h1, h2⟩
      · exact Or.inl ((tr_keeps io c hc).trans h)
      · exact Or.inr ⟨n', List.mem_cons_of_mem _ h1, h2⟩

theorem trAll_keeps (io : Io) (cs : List Cmd) (hc : ∀ c ∈ cs, c.kind ≠ .begin) :
    OvKeeps io.overlay (trAll io cs).1.overlay := by
  rcases trAll_overlay io cs with h | ⟨n, h1, -⟩
  · exact h
  · exact absurd rfl (hc _ h1)

/-- **The overlay shows a recording only once its microphone has started** (^349), and every
recording's clip, and the overlay's, is one numbered so far. -/
def OvInv (s : AppState) : Prop :=
  (∀ r, s.core.recording = some r → r.clip < s.core.nextClip) ∧
    s.io.overlay.clip < s.core.nextClip ∧
    ∀ r, s.core.recording = some r → s.io.overlay.shown = true → s.io.overlay.clip = r.clip →
      r.started = true

theorem ovInv_init : OvInv {} := by
  refine ⟨fun r h => ?_, ?_, fun r h => ?_⟩
  · cases h
  · exact Nat.zero_lt_one
  · cases h

/-- `OvInv` through a step of the machine, from overlay `ov` (as the message left it) to `ov'`. -/
theorem ovInv_step (c : State) (i : Input) (ov ov' : Overlay)
    (h1 : ∀ r, c.recording = some r → r.clip < c.nextClip) (h2 : ov.clip < c.nextClip)
    (h3 : ∀ r, c.recording = some r → ov.shown = true → ov.clip = r.clip → r.started = true)
    (ho : OvKeeps ov ov' ∨ ∃ n, Cmd.overlay n .begin ∈ (step c i).2 ∧ ov'.clip = n) :
    (∀ r, (step c i).1.recording = some r → r.clip < (step c i).1.nextClip) ∧
      ov'.clip < (step c i).1.nextClip ∧
      ∀ r, (step c i).1.recording = some r → ov'.shown = true → ov'.clip = r.clip →
        r.started = true := by
  obtain ⟨hle, -⟩ := step_rel c i
  have hg := step_grows c i
  have hrec : ∀ r', (step c i).1.recording = some r' →
      (∃ r, c.recording = some r ∧ r'.clip = r.clip ∧ (r.started = true → r'.started = true)) ∨
        r'.clip = c.nextClip := by
    intro r' hr'
    rcases step_starts c i r' hr' with h | h
    · cases hr : c.recording with
      | none => rw [hr] at h; cases h
      | some r => exact Or.inl ⟨r, rfl, hg r r' hr hr'⟩
    · exact Or.inr (step_start c i h).2.1
  refine ⟨fun r' hr' => ?_, ?_, ?_⟩
  · rcases hrec r' hr' with ⟨r, hr, hc, -⟩ | hc
    · rw [hc]; exact Nat.lt_of_lt_of_le (h1 r hr) hle
    · rcases step_starts c i r' hr' with h | h
      · cases hr : c.recording with
        | none => rw [hr] at h; cases h
        | some r =>
          rw [hr] at h; simp only [Option.map_some, Option.some.injEq] at h
          rw [← h]; exact Nat.lt_of_lt_of_le (h1 r hr) hle
      · obtain ⟨-, h2', h3'⟩ := step_start c i h
        rw [h3']; exact Nat.lt_succ_self _
  · rcases ho with ho | ⟨n, hn, hc⟩
    · obtain ⟨ho1, -⟩ := ho; rw [ho1]; exact Nat.lt_of_lt_of_le h2 hle
    · obtain ⟨r, hr, hrn, -⟩ := step_begin c i hn
      rw [hc, ← hrn]; exact Nat.lt_of_lt_of_le (h1 r hr) hle
  · intro r' hr' hs hc
    rcases ho with ho | ⟨n, hn, -⟩
    · obtain ⟨ho1, ho2⟩ := ho
      rcases hrec r' hr' with ⟨r, hr, hc', hst⟩ | hc'
      · exact hst (h3 r hr (ho2 hs) (by rw [← ho1, hc, hc']))
      · rw [ho1, hc'] at hc; exact absurd hc (Nat.ne_of_lt h2)
    · obtain ⟨-, -, -, h4⟩ := step_begin c i hn
      exact h4 r' hr'

theorem receive_ovInv (s : AppState) (m : Msg) (h : OvInv s) : OvInv (receive s m).1 := by
  obtain ⟨h1, h2, h3⟩ := h
  have hp := prep_overlay s m
  obtain ⟨w, hw⟩ := coreAt_eq s (prep s m)
  cases hi : (prep s m).input with
  | none =>
    rw [receive_none hi, hw]
    exact ⟨h1, by rw [hp.1]; exact h2, fun r hr hs hc => h3 r hr (hp.2 hs) (by rw [← hp.1]; exact hc)⟩
  | some i =>
    rw [receive_some hi, hw]
    simp only [feedCore, OvInv]
    rw [collect_overlay]
    have := ovInv_step { s.core with wall := w } i (prep s m).io.overlay _ h1
      (by rw [hp.1]; exact h2) (fun r hr hs hc => h3 r hr (hp.2 hs) (by rw [← hp.1]; exact hc))
      (trAll_overlay _ _)
    exact this

theorem menuStep_ovInv (s : AppState) (a : MenuAction) (h : OvInv s) : OvInv (menuStep s a).1 := by
  obtain ⟨h1, h2, h3⟩ := h
  have ho := trAll_keeps s.io (menu s.core a).2 fun c hc hb => by
    have := menu_kinds s.core a c hc
    rw [hb] at this; simp at this
  have hle := (menu_rel s.core a).1
  simp only [menuStep]
  refine ⟨fun r hr => ?_, by rw [ho.1]; exact Nat.lt_of_lt_of_le h2 hle, fun r hr hs hc => ?_⟩
  · rcases menu_recording s.core a with he | he <;> rw [he] at hr
    · exact Nat.lt_of_lt_of_le (h1 r hr) hle
    · cases hr
  · rcases menu_recording s.core a with he | he <;> rw [he] at hr
    · exact h3 r hr (ho.2 hs) (by rw [← ho.1]; exact hc)
    · cases hr

/-! ## Key events wait for the microphone -/

/-- **While the microphone is starting, a key event leaves the recording as it is** (^350): it
waits, and is handled once the start is reported (or has failed). -/
theorem app_keys_wait (s : AppState) (r : Recording) (k : Nat) (mo : Option Nat) (e : SubEvent)
    (hr : s.core.recording = some r) (hs : r.started = false) (he : ∀ f m, e ≠ .failed f m) :
    (receive s (.sub (.globalKey k mo) e)).1.core.recording = some r := by
  have hw : waiting s.core = true := by simp [waiting, starting, hr, hs]
  cases e
  case keyDown t => show (keyIn s.core _).1.recording = _; simp [keyIn, hw, hr]
  case keyUp t => show (keyIn s.core _).1.recording = _; simp [keyIn, hw, hr]
  case otherKey t => show (keyIn s.core _).1.recording = _; simp [keyIn, hw, hr]
  case failed f m => exact absurd rfl (he f m)
  all_goals exact hr

/-! ## Timed from the start -/

/-- **Replayed from when the start finished** (^351): a key released while the microphone was
starting is handled once the start is reported at `u`, and timed from then (as in the original,
whose main thread handles it only once `engine.start()` returns): pressed at `pressedAt`, it was
a tap if the start ended within 300 ms of the press, and a hold otherwise. -/
theorem micStarted_replay (s : State) (r : Recording) (c t u : Ms) (hr : s.recording = some r)
    (hc : r.clip = c) (hs : r.started = false) (hq : s.keys = [.up t]) (ht : t ≤ u)
    (hk : s.keyHeld = true) (hch : s.chorded = false) :
    (step s (.micStarted c u)).1.recording =
      if max s.now u - s.pressedAt < tapLimit then
        some { r with started := true, nextPoll := max s.now u + pollMs, latched := true,
                      deadline := max s.now u + latchLimit }
      else none := by
  have hm : max (max s.now u) t = max s.now u := Nat.max_eq_left (Nat.le_trans ht (Nat.le_max_right _ _))
  simp only [step, micStarted, hr, hc, hs, and_self, ↓reduceIte, hq, drain, stepKey, hk, hm,
    release, hch, Bool.not_false, Bool.true_and, Bool.false_eq_true, decide_eq_true_eq]
  split
  · simp
  · simp [send_recording]

end Examples.Yap

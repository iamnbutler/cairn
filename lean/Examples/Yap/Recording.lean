module

public import Examples.Yap.Keys

/-! # Yap: one recording at a time, and every recording ends

`State.recording` is an `Option`, so the model can't hold two; what matters is what the host
is told. The host is asked to start a recording only when none is in progress, and a recording
leaves the model only when the host is told to stop it (or the host said its microphone
failed). And every recording ends once the key is up and ten minutes pass. -/

@[expose] public section

namespace Examples.Yap

/-! ## Starting and stopping -/

/-- **The host is asked to start a recording only when none is in progress**, and it is a new
clip: the next number, never used before. -/
theorem tickRec_nextClip (s : State) : (tickRec s).1.nextClip = s.nextClip := by
  unfold tickRec
  split
  · rfl
  · split
    · split <;> rfl
    · split
      · unfold send; dsimp only; repeat' split
        all_goals rfl
      · split
        · unfold poll; dsimp only; repeat' split
          all_goals rfl
        · rfl

theorem step_start (s : State) (i : Input) {n : Nat} (h : Cmd.startRecording n ∈ (step s i).2) :
    s.recording = none ∧ n = s.nextClip ∧ (step s i).1.nextClip = n + 1 := by
  have hk : ∀ k, Cmd.startRecording n ∈ (keyIn s k).2 →
      s.recording = none ∧ n = s.nextClip ∧ (keyIn s k).1.nextClip = n + 1 := by
    intro k h
    unfold keyIn at h ⊢
    split at h
    · simp at h
    · rename_i hw
      simp only [hw, Bool.false_eq_true, ↓reduceIte]
      obtain ⟨h1, h2, h3, -⟩ := stepKey_start s k h
      exact ⟨h1, h2, h3⟩
  cases i with
  | keyDown t f => exact hk _ h
  | keyUp t => exact hk _ h
  | otherKey => exact hk _ h
  | tick t =>
    simp only [step, tick] at h ⊢
    split at h
    · exact absurd rfl ((tickRec_kinds _).not_mem (k := Kind.start) (by simp) h)
    · rename_i hc
      simp only [hc, Bool.false_eq_true, ↓reduceIte]
      rcases List.mem_append.1 h with h | h
      · obtain ⟨h1, h2, h3⟩ := drain_start _ _ h
        exact ⟨h1, h2, by rw [tickRec_nextClip]; exact h3⟩
      · exact absurd rfl ((tickRec_kinds _).not_mem (k := Kind.start) (by simp) h)
  | micStarted c t =>
    simp only [step, micStarted] at h
    split at h
    · split at h
      · rcases List.mem_append.1 h with h | h
        · split at h <;> simp at h
        · obtain ⟨h1, -⟩ := drain_start _ _ h
          cases h1
      · simp at h
    · simp at h
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, drainKinds, Cmd.kind]) h)

/-- `o` ends `s`'s recording only by telling the host to stop it. -/
def Ends (s : State) (o : State × List Cmd) : Prop :=
  ∀ r, s.recording = some r → o.1.recording.map (·.clip) = some r.clip ∨ Cmd.stopRecording r.clip ∈ o.2

theorem Ends.same {s : State} {o : State × List Cmd} (h : o.1.recording = s.recording) : Ends s o := by
  intro r hr; left; simp [h, hr]

theorem Ends.stops {s : State} {o : State × List Cmd}
    (h : ∀ r, s.recording = some r → Cmd.stopRecording r.clip ∈ o.2) : Ends s o :=
  fun r hr => Or.inr (h r hr)

theorem Ends.of_rec {s s' : State} {o : State × List Cmd} (hs : s'.recording = s.recording)
    (h : Ends s' o) : Ends s o := fun r hr => h r (hs.trans hr)

theorem send_stops (s : State) (r : Recording) : Cmd.stopRecording r.clip ∈ (send s r).2 := by
  unfold send; dsimp only
  repeat' split
  all_goals simp

theorem drop_stops (s : State) (r : Recording) : Cmd.stopRecording r.clip ∈ (drop s r).2 := by
  simp [drop]

theorem release_ends (s : State) : Ends s (release s) := by
  intro r hr
  unfold release
  simp only [hr]
  split
  · split
    · left; simp [hr]
    · right; exact drop_stops _ _
  · split
    · left; simp
    · right; exact send_stops _ _

theorem press_ends (s : State) (f : Option Target) : Ends s (press s f) := by
  intro r hr
  left
  unfold press
  split
  · simp [hr]
  · dsimp only; simp [hr]

theorem poll_ends (s : State) (r : Recording) (hr : s.recording = some r) : Ends s (poll s r) := by
  intro r' hr'
  rw [hr] at hr'; cases hr'
  left
  unfold poll; dsimp only
  repeat' (split <;> try dsimp only) <;> simp

theorem Ends.comp {s : State} {o₁ o₂ : State × List Cmd} (h₁ : Ends s o₁) (h₂ : Ends o₁.1 o₂) :
    Ends s (o₂.1, o₁.2 ++ o₂.2) := by
  intro r hr
  rcases h₁ r hr with h | h
  · cases h' : o₁.1.recording with
    | none => rw [h'] at h; cases h
    | some r₁ =>
      rw [h'] at h
      simp only [Option.map_some, Option.some.injEq] at h
      rcases h₂ r₁ h' with h2 | h2
      · left; rw [← h]; exact h2
      · right; rw [← h]; exact List.mem_append_right _ h2
  · right; exact List.mem_append_left _ h

theorem stepKey_ends (s : State) (k : Key) : Ends s (stepKey s k) := by
  cases k with
  | down t f =>
    simp only [stepKey]
    split
    · exact Ends.same rfl
    · exact Ends.of_rec (s' := { s with now := max s.now t, keyHeld := true }) rfl (press_ends _ _)
  | up t =>
    simp only [stepKey]
    split
    · exact Ends.of_rec (s' := { s with now := max s.now t, keyHeld := false }) rfl (release_ends _)
    · exact Ends.same rfl
  | other => simp only [stepKey]; split <;> exact Ends.same rfl

theorem drain_ends (s : State) (ks : List Key) : Ends s (drain s ks) := by
  induction ks generalizing s with
  | nil => exact Ends.same rfl
  | cons k ks ih =>
    simp only [drain]
    split
    · exact Ends.comp (stepKey_ends s k) (ih _)
    · intro r hr
      rcases stepKey_ends s k r hr with h | h
      · exact Or.inl h
      · exact Or.inr (List.mem_append_left _ h)

theorem tickRec_ends (s : State) : Ends s (tickRec s) := by
  intro r hr
  unfold tickRec
  simp only [hr]
  split
  · split
    · right; exact drop_stops _ _
    · left; simp [hr]
  · split
    · right; exact send_stops _ _
    · split
      · exact poll_ends s r hr r hr
      · left; simp [hr]

theorem tick_ends (s : State) : Ends s (tick s) := by
  unfold tick
  split
  · exact tickRec_ends _
  · exact Ends.comp (Ends.of_rec (s' := { s with keys := [] }) rfl (drain_ends _ _)) (tickRec_ends _)

theorem micStarted_ends (s : State) (c : Nat) : Ends s (micStarted s c) := by
  unfold micStarted
  split
  · rename_i r hr
    split
    · intro r₀ hr₀
      rw [hr] at hr₀; cases hr₀
      rcases drain_ends { s with
          recording := some { r with started := true, latched := false, nextPoll := s.now + pollMs },
          keys := [], detail := "Listening…" } s.keys _ rfl with h | h
      · exact Or.inl h
      · exact Or.inr (List.mem_append_right _ h)
    · exact Ends.same rfl
  · exact Ends.same rfl

theorem audio_ends (s : State) (c : Nat) (a : Audio) : Ends s (audio s c a) := by
  intro r hr; left
  unfold audio; simp only [hr]
  split <;> simp_all

theorem micFailed_ends (s : State) (c : Nat) (e : String) :
    Ends s (micFailed s c e) ∨ ∃ r, s.recording = some r ∧ r.clip = c := by
  unfold micFailed
  split
  · rename_i r hr
    split
    · exact Or.inr ⟨r, hr, by assumption⟩
    · exact Or.inl (Ends.same rfl)
  · exact Or.inl (Ends.same rfl)

theorem keep_recording (s : State) (t : Transcript) : (keep s t).1.recording = s.recording := by
  unfold keep; dsimp only; split <;> rfl

theorem typeIt_recording (s : State) (c : ClipReq) (t : Transcript) :
    (typeIt s c t).1.recording = s.recording := rfl

theorem transcribed_recording (s : State) (c : ClipReq) (raw : String) :
    (transcribed s c raw).1.recording = s.recording := by
  unfold transcribed; dsimp only
  split
  · rfl
  · split
    · rw [typeIt_recording, keep_recording]
    · rw [keep_recording]

theorem chunkDone_ends (s : State) (c q : Nat) (t : Option String) : Ends s (chunkDone s c q t) := by
  intro r hr; left
  unfold chunkDone; simp only [hr]
  split <;> simp_all

theorem reply_ends (s : State) (q : Nat) (x : Reply) : Ends s (reply s q x) := by
  unfold reply
  cases hq : s.reqs.lookup q with
  | none => exact Ends.same rfl
  | some req =>
    dsimp only
    cases req <;> cases x <;> dsimp only
    case clip.ok => exact Ends.same (transcribed_recording _ _ _)
    case chunk.ok clip fixes raw =>
      exact Ends.of_rec (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (chunkDone_ends _ _ _ _)
    case chunk.failed =>
      exact Ends.of_rec (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (chunkDone_ends _ _ _ _)
    all_goals exact Ends.same rfl

theorem cancel_ends (s : State) : Ends s (cancel s) := by
  apply Ends.stops
  intro r hr
  simp [cancel, hr]

theorem setKey_ends (s : State) (k : Hotkey) : Ends s (setKey s k) := by
  unfold setKey
  split
  · exact Ends.same rfl
  · dsimp only
    split
    · exact Ends.same rfl
    · split
      · intro r hr
        rcases release_ends { s with keyHeld := false } r hr with h | h
        · exact Or.inl h
        · exact Or.inr (List.mem_append_left _ h)
      · exact Ends.same rfl

theorem applySettings_ends (s : State) (cfg : Settings) : Ends s (applySettings s cfg) := by
  unfold applySettings
  dsimp only
  split
  · exact Ends.same rfl
  · rename_i k _
    intro r hr
    rcases setKey_ends { s with settings := cfg } k r hr with h | h
    · left; split <;> exact h
    · exact Or.inr h

theorem configured_ends (s : State) (c : ConfigRead) : Ends s (configured s c) := by
  intro r hr
  unfold configured
  dsimp only
  have : Ends s (readConfig s c) := by
    unfold readConfig
    split
    · exact Ends.same rfl
    · exact applySettings_ends _ _
    · exact applySettings_ends _ _
  rcases this r hr with h | h
  · exact Or.inl h
  · exact Or.inr (List.mem_append_left _ h)

theorem menu_ends (s : State) (m : MenuAction) : Ends s (menu s m) := by
  cases m <;> simp only [menu]
  case toggleEnabled =>
    split
    · exact Ends.same rfl
    · intro r hr
      rcases cancel_ends { s with enabled := !s.enabled } r hr with h | h
      · exact Or.inl h
      · exact Or.inr (List.mem_cons_of_mem _ h)
  all_goals first
    | exact Ends.same rfl
    | (split <;> exact Ends.same rfl)

/-- **A recording leaves the model only when the host is told to stop it**, or when the host
reported that its microphone failed. With `step_start`, the host never has two recordings. -/
theorem step_ends (s : State) (i : Input) (r : Recording) (hr : s.recording = some r) :
    (step s i).1.recording.map (·.clip) = some r.clip ∨ Cmd.stopRecording r.clip ∈ (step s i).2 ∨
      ∃ e, i = .micFailed r.clip e := by
  have hk : ∀ k, Ends s (keyIn s k) := by
    intro k
    unfold keyIn
    split
    · exact Ends.same rfl
    · exact stepKey_ends _ _
  cases i with
  | keyDown t f => exact Or.imp_right Or.inl (hk _ r hr)
  | keyUp t => exact Or.imp_right Or.inl (hk _ r hr)
  | otherKey => exact Or.imp_right Or.inl (hk _ r hr)
  | micStarted c t =>
    exact Or.imp_right Or.inl (Ends.of_rec (s' := { s with now := max s.now t }) rfl
      (micStarted_ends _ _) r hr)
  | tick t => exact Or.imp_right Or.inl (tick_ends _ r hr)
  | audio c a => exact Or.imp_right Or.inl (audio_ends s c a r hr)
  | micFailed c e =>
    rcases micFailed_ends s c e with h | ⟨r', hr', rfl⟩
    · exact Or.imp_right Or.inl (h r hr)
    · rw [hr] at hr'; cases hr'
      exact Or.inr (Or.inr ⟨e, rfl⟩)
  | reply q x => exact Or.imp_right Or.inl (reply_ends s q x r hr)
  | config c => exact Or.imp_right Or.inl (configured_ends s c r hr)
  | menu m => exact Or.imp_right Or.inl (menu_ends s m r hr)
  | transcriptDays => left; simp [step, hr]
  | front c a =>
    left; simp only [step, setFront, hr, Option.map_some]
    split <;> rfl
  | keyLost => right; left; simp [step, keyLost, hr, drop]
  | _ => left; simp [step, hr]

/-! ## Every recording ends -/

/-- A recording that isn't hands free has its key down, a hands-free one sends itself within ten
minutes of now, and one still starting isn't hands free; and key events wait only while a
recording is starting, or when there is none. -/
def RecInv (s : State) : Prop :=
  (∀ r, s.recording = some r →
    (r.latched = false → s.keyHeld = true) ∧ (r.latched = true → r.deadline ≤ s.now + latchLimit) ∧
      (r.started = false → r.latched = false)) ∧
  (s.keys ≠ [] → ∀ r, s.recording = some r → r.started = false)

/-- What `RecInv` looks at in a recording. -/
def shape (o : Option Recording) : Option (Bool × Ms × Bool) :=
  o.map fun r => (r.latched, r.deadline, r.started)

/-- `s'` keeps `s`'s recording as it was, or has none. -/
def Calm (s s' : State) : Prop :=
  s'.recording = none ∨
    (shape s'.recording = shape s.recording ∧ s'.keyHeld = s.keyHeld ∧ s.now ≤ s'.now ∧
      s'.keys = s.keys)

theorem Calm.refl (s : State) : Calm s s := Or.inr ⟨rfl, rfl, Nat.le_refl _, rfl⟩

theorem Calm.same {s s' : State} (hr : s'.recording = s.recording) (hk : s'.keyHeld = s.keyHeld)
    (hn : s'.now = s.now) (hq : s'.keys = s.keys) : Calm s s' :=
  Or.inr ⟨by rw [hr], hk, Nat.le_of_eq hn.symm, hq⟩

theorem Calm.none {s s' : State} (h : s'.recording = none) : Calm s s' := Or.inl h

theorem Calm.trans {s₁ s₂ s₃ : State} (a : Calm s₁ s₂) (b : Calm s₂ s₃) : Calm s₁ s₃ := by
  rcases b with b | ⟨hs, hk, hn, hq⟩
  · exact Or.inl b
  · rcases a with a | ⟨hs', hk', hn', hq'⟩
    · left; simpa [shape, a] using hs
    · exact Or.inr ⟨hs.trans hs', hk.trans hk', Nat.le_trans hn' hn, hq.trans hq'⟩

theorem RecInv.calm {s s' : State} (h : RecInv s) (c : Calm s s') : RecInv s' := by
  rcases c with c | ⟨hs, hk, hn, hq⟩
  · exact ⟨fun r hr => by simp [c] at hr, fun _ r hr => by simp [c] at hr⟩
  · refine ⟨fun r' hr' => ?_, fun hne r' hr' => ?_⟩
    · cases hr : s.recording with
      | none => simp [shape, hr, hr'] at hs
      | some r =>
        simp only [shape, hr, hr', Option.map_some, Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨hl, hd, hst⟩ := h.1 r hr
        rw [hs.1, hs.2.1, hs.2.2, hk]
        exact ⟨hl, fun x => Nat.le_trans (hd x) (Nat.add_le_add_right hn _), hst⟩
    · cases hr : s.recording with
      | none => simp [shape, hr, hr'] at hs
      | some r =>
        simp only [shape, hr, hr', Option.map_some, Option.some.injEq, Prod.mk.injEq] at hs
        rw [hs.2.2]; exact h.2 (hq ▸ hne) r hr

theorem send_calm (s : State) (r : Recording) : Calm s (send s r).1 := Calm.none (send_recording s r)

theorem drop_calm (s : State) (r : Recording) : Calm s (drop s r).1 := Calm.none rfl

theorem poll_calm (s : State) (r : Recording) (hr : s.recording = some r) : Calm s (poll s r).1 := by
  unfold poll; dsimp only
  repeat' split
  all_goals exact Or.inr ⟨by simp [shape, hr], rfl, Nat.le_refl _, rfl⟩

theorem tickRec_calm (s : State) : Calm s (tickRec s).1 := by
  unfold tickRec
  split
  · exact Calm.refl _
  · rename_i r hr
    split
    · split
      · exact drop_calm _ _
      · exact Calm.refl _
    · split
      · exact send_calm _ _
      · split
        · exact poll_calm _ _ hr
        · exact Calm.refl _

theorem audio_calm (s : State) (c : Nat) (a : Audio) : Calm s (audio s c a).1 := by
  unfold audio
  split
  · rename_i r hr
    split
    · exact Or.inr ⟨by simp [shape, hr], rfl, Nat.le_refl _, rfl⟩
    · exact Calm.refl _
  · exact Calm.refl _

theorem micFailed_calm (s : State) (c : Nat) (e : String) : Calm s (micFailed s c e).1 := by
  unfold micFailed
  split
  · split
    · split <;> exact Calm.none rfl
    · exact Calm.refl _
  · exact Calm.refl _

theorem keep_calm (s : State) (t : Transcript) : Calm s (keep s t).1 := by
  unfold keep; dsimp only; split <;> exact Calm.same rfl rfl rfl rfl

theorem transcribed_calm (s : State) (c : ClipReq) (raw : String) : Calm s (transcribed s c raw).1 := by
  unfold transcribed; dsimp only
  split
  · exact Calm.same rfl rfl rfl rfl
  · split
    · exact (keep_calm _ _).trans (Calm.same rfl rfl rfl rfl)
    · exact keep_calm _ _

theorem chunkDone_calm (s : State) (c q : Nat) (t : Option String) : Calm s (chunkDone s c q t).1 := by
  unfold chunkDone
  split
  · rename_i r hr
    split
    · exact Or.inr ⟨by simp [shape, hr], rfl, Nat.le_refl _, rfl⟩
    · exact Calm.refl _
  · exact Calm.refl _

theorem Calm.of_eq {s s' s'' : State} (h : s'.recording = s.recording ∧ s'.keyHeld = s.keyHeld ∧
    s'.now = s.now ∧ s'.keys = s.keys) (c : Calm s' s'') : Calm s s'' :=
  (Calm.same h.1 h.2.1 h.2.2.1 h.2.2.2).trans c

theorem reply_calm (s : State) (q : Nat) (x : Reply) : Calm s (reply s q x).1 := by
  unfold reply
  cases hq : s.reqs.lookup q with
  | none => exact Calm.refl _
  | some req =>
    dsimp only
    cases req <;> cases x <;> dsimp only
    case clip.ok =>
      exact Calm.of_eq (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) ⟨rfl, rfl, rfl, rfl⟩
        (transcribed_calm _ _ _)
    case chunk.ok =>
      exact Calm.of_eq (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) ⟨rfl, rfl, rfl, rfl⟩
        (chunkDone_calm _ _ _ _)
    case chunk.failed =>
      exact Calm.of_eq (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) ⟨rfl, rfl, rfl, rfl⟩
        (chunkDone_calm _ _ _ _)
    all_goals exact Calm.same rfl rfl rfl rfl

theorem cancel_calm (s : State) : Calm s (cancel s).1 := Calm.none rfl

theorem menu_calm (s : State) (m : MenuAction) : Calm s (menu s m).1 := by
  cases m <;> simp only [menu]
  case toggleEnabled => split <;> first | exact Calm.same rfl rfl rfl rfl | exact Calm.none rfl
  all_goals first
    | exact Calm.same rfl rfl rfl rfl
    | (split <;> exact Calm.same rfl rfl rfl rfl)

/-- Hands-free recordings send themselves within ten minutes. -/
def Bound (s : State) : Prop :=
  ∀ r, s.recording = some r → r.latched = true → r.deadline ≤ s.now + latchLimit

theorem RecInv.bound {s : State} (h : RecInv s) : Bound s := fun r hr => (h.1 r hr).2.1

/-- While key events wait, the recording, if any, is starting. -/
theorem RecInv.waiting {s : State} (h : RecInv s) (hw : waiting s = true) :
    ∀ r, s.recording = some r → r.started = false := by
  intro r hr
  cases hq : s.keys with
  | cons k ks => exact h.2 (by simp [hq]) r hr
  | nil =>
    simpa [Examples.Yap.waiting, starting, hr, hq] using hw

/-- Key events are handled at once only with none waiting and no microphone starting. -/
theorem not_waiting {s : State} (hw : waiting s = false) :
    s.keys = [] ∧ ∀ r, s.recording = some r → r.started = true := by
  simp only [waiting, Bool.or_eq_false_iff, Bool.not_eq_false', List.isEmpty_iff] at hw
  refine ⟨hw.2, fun r hr => ?_⟩
  have := hw.1
  simp only [starting, hr, Option.any_some, Bool.not_eq_false'] at this
  exact this

theorem release_recInv (s : State) (hb : Bound s) (hs : ∀ r, s.recording = some r → r.started = true)
    (hq : s.keys = []) : RecInv (release s).1 := by
  refine ⟨?_, fun hne => absurd (by rw [(release_frame s).keys, hq]) hne⟩
  unfold release
  split
  · rename_i hr; intro r h; simp [hr] at h
  · rename_i r hr
    split
    · split
      · intro r' h
        rw [hr] at h; cases h
        exact ⟨fun hl => by simp_all, hb _ hr, fun h' => by simp [hs _ hr] at h'⟩
      · intro r' h; simp [drop] at h
    · split
      · intro r' h
        simp only [Option.some.injEq] at h
        subst h
        exact ⟨by simp, fun _ => Nat.le_refl _, fun h' => by simp [hs r hr] at h'⟩
      · intro r' h; simp [send_recording] at h

theorem press_recInv (s : State) (f : Option Target) (hk : s.keyHeld = true) (hb : Bound s)
    (h3 : ∀ r, s.recording = some r → r.started = false → r.latched = false) (hq : s.keys = []) :
    RecInv (press s f).1 := by
  refine ⟨?_, fun hne => absurd (by rw [(press_frame s f).keys, hq]) hne⟩
  unfold press
  split
  · exact fun r hr => ⟨fun _ => hk, hb r hr, h3 r hr⟩
  · dsimp only
    split
    · intro r' h
      exact ⟨fun _ => hk, hb r' h, h3 r' h⟩
    · intro r' h
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨fun _ => hk, by simp, fun _ => rfl⟩

theorem stepKey_recInv (s : State) (k : Key) (h : RecInv s)
    (hs : ∀ r, s.recording = some r → r.started = true) (hq : s.keys = []) :
    RecInv (stepKey s k).1 := by
  cases k with
  | down t f =>
    have h' : RecInv { s with now := max s.now t } :=
      h.calm (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _, rfl⟩)
    simp only [stepKey]
    split
    · exact h'
    · exact press_recInv { s with now := max s.now t, keyHeld := true } f rfl h'.bound
        (fun r hr => (h.1 r hr).2.2) hq
  | up t =>
    have h' : RecInv { s with now := max s.now t } :=
      h.calm (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _, rfl⟩)
    simp only [stepKey]
    split
    · exact release_recInv { s with now := max s.now t, keyHeld := false } h'.bound hs hq
    · exact h'
  | other =>
    simp only [stepKey]
    split
    · exact h.calm (Calm.same rfl rfl rfl rfl)
    · exact h

theorem drain_recInv (s : State) (ks : List Key) (h : RecInv s)
    (hs : ∀ r, s.recording = some r → r.started = true) (hq : s.keys = []) :
    RecInv (drain s ks).1 := by
  induction ks generalizing s with
  | nil => exact h
  | cons k ks ih =>
    simp only [drain]
    have h1 := stepKey_recInv s k h hs hq
    have hq1 : (stepKey s k).1.keys = [] := by rw [(stepKey_frame s k).keys, hq]
    split
    · rename_i he
      refine ih _ h1 ?_ hq1
      intro r' hr'
      rcases stepKey_some s k hr' with ⟨r, hr, hsm⟩ | ⟨h0, -⟩
      · rw [hsm.started]; exact hs r hr
      · rw [h0, hr'] at he; cases he
    · rename_i he
      refine ⟨h1.1, fun _ r' hr' => ?_⟩
      rcases stepKey_some s k hr' with ⟨r, hr, -⟩ | ⟨-, h2, -⟩
      · exfalso; apply he; rw [hr]; exact (by rw [show (stepKey s k).1.recording = some r' from hr']; rfl)
      · exact h2

theorem tick_recInv (s : State) (h : RecInv s) : RecInv (tick s).1 := by
  unfold tick
  split
  · exact h.calm (tickRec_calm _)
  · rename_i hc
    have hne : s.keys ≠ [] := fun he => hc (by simp [he])
    have hst : starting s = false := by
      cases hs : starting s
      · rfl
      · exact absurd (by simp [hs]) hc
    have hn : s.recording = none := by
      cases hr : s.recording with
      | none => rfl
      | some r =>
        have := h.2 hne r hr
        simp [starting, hr, this] at hst
    have hd := drain_recInv { s with keys := [] } s.keys
      ⟨h.1, fun hne' => absurd rfl hne'⟩ (fun r hr => by simp [hn] at hr) rfl
    exact hd.calm (tickRec_calm _)

theorem micStarted_recInv (s : State) (c : Nat) (h : RecInv s) : RecInv (micStarted s c).1 := by
  unfold micStarted
  split
  · rename_i r hr
    split
    · rename_i hc
      obtain ⟨hl, -, hst⟩ := h.1 r hr
      refine drain_recInv _ _ ⟨fun r' hr' => ?_, fun hne => absurd rfl hne⟩ (fun r' hr' => ?_) rfl
      · simp only [Option.some.injEq] at hr'; subst hr'
        exact ⟨fun _ => hl (hst hc.2), fun h' => by simp at h', fun h' => by simp at h'⟩
      · simp only [Option.some.injEq] at hr'; subst hr'; rfl
    · exact h
  · exact h

theorem keyIn_recInv (s : State) (k : Key) (h : RecInv s) : RecInv (keyIn s k).1 := by
  unfold keyIn
  cases hw : waiting s with
  | true => exact ⟨h.1, fun _ r hr => h.waiting hw r hr⟩
  | false =>
    obtain ⟨hq, hs⟩ := not_waiting hw
    exact stepKey_recInv s k h hs hq

theorem setKey_recInv (s : State) (k : Hotkey) (h : RecInv s) : RecInv (setKey s k).1 := by
  unfold setKey
  split
  · exact h
  · dsimp only
    cases hw : waiting s with
    | true => exact ⟨h.1, fun _ r hr => h.waiting hw r hr⟩
    | false =>
      obtain ⟨hq, hs⟩ := not_waiting hw
      simp only [Bool.false_eq_true, ↓reduceIte]
      split
      · exact (release_recInv { s with keyHeld := false } h.bound hs hq).calm
          (Calm.same rfl rfl rfl rfl)
      · exact h.calm (Calm.same rfl rfl rfl rfl)

theorem applySettings_recInv (s : State) (cfg : Settings) (h : RecInv s) :
    RecInv (applySettings s cfg).1 := by
  have h' : RecInv { s with settings := cfg } := h.calm (Calm.same rfl rfl rfl rfl)
  unfold applySettings
  dsimp only
  split
  · exact h'.calm (Calm.same rfl rfl rfl rfl)
  · rename_i k _
    have := setKey_recInv _ k h'
    split
    · exact this.calm (Calm.same rfl rfl rfl rfl)
    · exact this

theorem configured_recInv (s : State) (c : ConfigRead) (h : RecInv s) :
    RecInv (configured s c).1 := by
  have : RecInv (readConfig s c).1 := by
    unfold readConfig
    split
    · exact h.calm (Calm.same rfl rfl rfl rfl)
    · exact applySettings_recInv _ _ h
    · exact applySettings_recInv _ _ h
  exact this.calm (Calm.same rfl rfl rfl rfl)

/-- `RecInv` holds in every reachable state. -/
theorem step_recInv (s : State) (i : Input) (h : RecInv s) : RecInv (step s i).1 := by
  cases i with
  | keyDown t f => exact keyIn_recInv _ _ h
  | keyUp t => exact keyIn_recInv _ _ h
  | otherKey => exact keyIn_recInv _ _ h
  | tick t => exact tick_recInv _ (h.calm (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _, rfl⟩))
  | micStarted c t => exact micStarted_recInv _ _ (h.calm (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _, rfl⟩))
  | audio c a => exact h.calm (audio_calm _ _ _)
  | micFailed c e => exact h.calm (micFailed_calm _ _ _)
  | reply q x => exact h.calm (reply_calm _ _ _)
  | config c => exact configured_recInv _ _ h
  | menu m => exact h.calm (menu_calm _ _)
  | transcriptDays => exact h
  | front c a =>
    refine h.calm (Or.inr ⟨?_, rfl, Nat.le_refl _, rfl⟩)
    simp only [step, setFront, shape, Option.map_map]
    congr 1; funext r; simp only [Function.comp]; split <;> rfl
  | keyLost =>
    simp only [step, keyLost]
    split
    · exact h.calm (Calm.none rfl)
    · rename_i hr; exact h.calm (Calm.none hr)
  | _ => exact h.calm (Calm.same rfl rfl rfl rfl)

theorem recInv_init : RecInv init := ⟨fun r h => by simp [init] at h, fun h => by simp [init] at h⟩

theorem release_keyHeld (s : State) : (release s).1.keyHeld = s.keyHeld := by
  unfold release
  split
  · rfl
  · split
    · split <;> rfl
    · split
      · rfl
      · unfold send; dsimp only; repeat' split
        all_goals rfl

theorem release_now (s : State) : (release s).1.now = s.now := by
  unfold release
  split
  · rfl
  · split
    · split <;> rfl
    · split
      · rfl
      · exact send_now _ _

/-- The clock, with a release last among the key events waiting for a microphone that is
starting (or that has failed), ten minutes after it: no recording. -/
theorem tick_queued_up (s : State) (ks : List Key) (t : Ms) (hk : s.keys = ks ++ [.up t])
    (hn : t + latchLimit ≤ s.now) (hs : ∀ r, s.recording = some r → r.started = false) :
    (tick s).1.recording = none := by
  unfold tick
  have hne : s.keys.isEmpty = false := by rw [hk]; simp
  cases hst : starting s with
  | true =>
    simp only [hne, Bool.or_true, ↓reduceIte]
    cases hr : s.recording with
    | none => simp [starting, hr] at hst
    | some r =>
      have hrs := hs r hr
      have hto : timedOut s = true := by
        simp only [timedOut, List.any_eq_true]
        exact ⟨.up t, by rw [hk]; simp, by simpa using hn⟩
      simp [tickRec, hr, hrs, hto, drop]
  | false =>
    simp only [hne, Bool.or_false, Bool.false_eq_true, ↓reduceIte]
    have hrn : s.recording = none := by
      cases hr : s.recording with
      | none => rfl
      | some r => have := hs r hr; simp [starting, hr, this] at hst
    rw [hk]
    have hnow := (drain_frame { s with keys := [] } (ks ++ [.up t])).2.2.1
    rcases drain_none_up { s with keys := [] } ks t hrn with h1 | ⟨hup, r, hr, hrs⟩
    · simp [tickRec, h1]
    · have hto : timedOut (drain { s with keys := [] } (ks ++ [.up t])).1 = true := by
        simp only [timedOut, List.any_eq_true]
        exact ⟨.up t, hup, by simpa using Nat.le_trans hn hnow⟩
      simp [tickRec, hr, hrs, hto, drop]

/-- The clock with no key events waiting and the recording, if any, hands free past its
deadline: no recording. -/
theorem tick_due (s : State) (hq : s.keys = [])
    (h : ∀ r, s.recording = some r → r.started = true ∧ r.latched = true ∧ r.deadline ≤ s.now) :
    (tick s).1.recording = none := by
  unfold tick
  simp only [hq, List.isEmpty_nil, Bool.true_or, ↓reduceIte]
  unfold tickRec
  split
  · assumption
  · rename_i r hr
    obtain ⟨h1, h2, h3⟩ := h r hr
    simp only [h1, h2, h3, Bool.not_true, Bool.false_eq_true, ↓reduceIte, and_self]
    exact send_recording _ _

/-- **Every recording ends**: once the key's release `t` is heard, the clock ten minutes on
(`u`) finds no recording. A release that comes while the microphone is starting waits for it
(Yap's main thread is in `AudioCapture.start`); a start that never returns is given up ten
minutes after the release. A recording held down has no limit, as in Swift Yap. -/
theorem keyUp_tick_none (s : State) (h : RecInv s) (t : Ms) (ht : s.now ≤ t) (w : Int) (u : Ms)
    (hu : t + latchLimit ≤ u) :
    (step { (step s (.keyUp t)).1 with wall := w } (.tick u)).1.recording = none := by
  simp only [step, keyIn]
  cases hw : waiting s with
  | true =>
    simp only [↓reduceIte]
    exact tick_queued_up _ s.keys t rfl (Nat.le_trans hu (Nat.le_max_right _ _))
      (fun r hr => h.waiting hw r hr)
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte]
    obtain ⟨hq, hs⟩ := not_waiting hw
    have h1 := stepKey_recInv s (.up t) h hs hq
    have hq1 : (stepKey s (.up t)).1.keys = [] := by rw [(stepKey_frame s _).keys, hq]
    have hk : (stepKey s (.up t)).1.keyHeld = false := by
      simp only [stepKey]; split
      · rw [release_keyHeld]
      · rename_i hk; simpa using hk
    have hn : (stepKey s (.up t)).1.now = t := by
      simp only [stepKey]; split
      · rw [release_now]; exact Nat.max_eq_right ht
      · exact Nat.max_eq_right ht
    refine tick_due _ (by exact hq1) ?_
    intro r hr
    replace hr : (stepKey s (.up t)).1.recording = some r := hr
    have hst : r.started = true := by
      rcases stepKey_some s (.up t) hr with ⟨r0, h0, hsm⟩ | ⟨-, -, -, -, h5, -⟩
      · rw [hsm.started]; exact hs r0 h0
      · exact absurd rfl ((stepKey_kinds s (.up t)).not_mem (k := Kind.start) (by simp [keyKinds]) h5)
    obtain ⟨hl, hd, -⟩ := h1.1 r hr
    have hlt : r.latched = true := by
      cases hr' : r.latched
      · have := hl hr'; rw [hk] at this; cases this
      · rfl
    refine ⟨hst, hlt, ?_⟩
    have := hd hlt; rw [hn] at this
    exact Nat.le_trans (Nat.le_trans this hu) (Nat.le_max_right _ _)

theorem recording_ends (s : State) (h : RecInv s) (t : Ms) (ht : s.now ≤ t) :
    (run s [.keyUp t, .tick (t + latchLimit)]).recording = none :=
  keyUp_tick_none s h t ht _ _ (Nat.le_refl _)

end Examples.Yap

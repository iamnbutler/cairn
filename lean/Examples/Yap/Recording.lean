module

public import Examples.Yap.Proofs

/-! # Yap: one recording at a time, and every recording ends

`State.recording` is an `Option`, so the model can't hold two; what matters is what the host
is told. The host is asked to start a recording only when none is in progress, and a recording
leaves the model only when the host is told to stop it (or the host said its microphone
failed). And every recording ends once the key is up and ten minutes pass. -/

@[expose] public section

namespace Examples.Yap

/-! ## Starting and stopping -/

theorem press_start (s : State) (f : Option Target) {n : Nat}
    (h : Cmd.startRecording n ∈ (press s f).2) :
    s.recording = none ∧ n = s.nextClip ∧ (press s f).1.recording.map (·.clip) = some n ∧
      (press s f).1.nextClip = n + 1 := by
  unfold press at h ⊢
  split at h
  · simp at h
  · rename_i he
    simp only [he] at ⊢
    dsimp only at h ⊢
    split at h
    · simp at h
    · rename_i hr
      simp only [List.mem_append, List.mem_cons, Cmd.startRecording.injEq, List.not_mem_nil,
        or_false] at h
      rcases h with rfl | h
      · refine ⟨hr, rfl, ?_, ?_⟩ <;> (split <;> simp_all)
      · split at h <;> simp at h

/-- **The host is asked to start a recording only when none is in progress**, and it is a new
clip: the next number, never used before. -/
theorem step_start (s : State) (i : Input) {n : Nat} (h : Cmd.startRecording n ∈ (step s i).2) :
    s.recording = none ∧ n = s.nextClip ∧ (step s i).1.recording.map (·.clip) = some n ∧
      (step s i).1.nextClip = n + 1 := by
  cases i with
  | keyDown t f =>
    simp only [step] at h ⊢
    split at h
    · simp at h
    · rename_i hk
      simp only [hk, Bool.false_eq_true, ↓reduceIte]
      exact press_start _ _ h
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, Cmd.kind]) h)

/-- `o` ends `s`'s recording only by telling the host to stop it. -/
def Ends (s : State) (o : State × List Cmd) : Prop :=
  ∀ r, s.recording = some r → o.1.recording.map (·.clip) = some r.clip ∨ Cmd.stopRecording r.clip ∈ o.2

theorem Ends.same {s : State} {o : State × List Cmd} (h : o.1.recording = s.recording) : Ends s o := by
  intro r hr; left; simp [h, hr]

theorem Ends.stops {s : State} {o : State × List Cmd}
    (h : ∀ r, s.recording = some r → Cmd.stopRecording r.clip ∈ o.2) : Ends s o :=
  fun r hr => Or.inr (h r hr)

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

theorem tick_ends (s : State) : Ends s (tick s) := by
  intro r hr
  unfold tick
  simp only [hr]
  split
  · right; exact send_stops _ _
  · split
    · exact poll_ends s r hr r hr
    · left; simp [hr]

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

theorem Ends.of_rec {s s' : State} {o : State × List Cmd} (hs : s'.recording = s.recording)
    (h : Ends s' o) : Ends s o := fun r hr => h r (hs.trans hr)

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
  cases i with
  | keyDown t f =>
    simp only [step]
    split
    · left; simp [hr]
    · exact Or.imp_right Or.inl (press_ends _ _ r hr)
  | keyUp t =>
    simp only [step]
    split
    · exact Or.imp_right Or.inl (release_ends _ r hr)
    · left; simp [hr]
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
  | otherKey => simp only [step]; split <;> (left; simp [hr])
  | transcriptDays => left; simp [step, hr]
  | front c a =>
    left; simp only [step, setFront, hr, Option.map_some]
    split <;> rfl
  | keyLost => right; left; simp [step, keyLost, hr, drop]
  | _ => left; simp [step, hr]

/-! ## Every recording ends -/

/-- A recording that isn't hands free has its key down, and a hands-free one sends itself
within ten minutes of now. -/
def RecInv (s : State) : Prop :=
  ∀ r, s.recording = some r →
    (r.latched = false → s.keyHeld = true) ∧ (r.latched = true → r.deadline ≤ s.now + latchLimit)

/-- What `RecInv` looks at in a recording. -/
def shape (o : Option Recording) : Option (Bool × Ms) := o.map fun r => (r.latched, r.deadline)

/-- `s'` keeps `s`'s recording as it was, or has none. -/
def Calm (s s' : State) : Prop :=
  s'.recording = none ∨
    (shape s'.recording = shape s.recording ∧ s'.keyHeld = s.keyHeld ∧ s.now ≤ s'.now)

theorem Calm.refl (s : State) : Calm s s := Or.inr ⟨rfl, rfl, Nat.le_refl _⟩

theorem Calm.same {s s' : State} (hr : s'.recording = s.recording) (hk : s'.keyHeld = s.keyHeld)
    (hn : s'.now = s.now) : Calm s s' := Or.inr ⟨by rw [hr], hk, Nat.le_of_eq hn.symm⟩

theorem Calm.none {s s' : State} (h : s'.recording = none) : Calm s s' := Or.inl h

theorem Calm.trans {s₁ s₂ s₃ : State} (a : Calm s₁ s₂) (b : Calm s₂ s₃) : Calm s₁ s₃ := by
  rcases b with b | ⟨hs, hk, hn⟩
  · exact Or.inl b
  · rcases a with a | ⟨hs', hk', hn'⟩
    · left; simpa [shape, a] using hs
    · exact Or.inr ⟨hs.trans hs', hk.trans hk', Nat.le_trans hn' hn⟩

theorem RecInv.calm {s s' : State} (h : RecInv s) (c : Calm s s') : RecInv s' := by
  intro r' hr'
  rcases c with c | ⟨hs, hk, hn⟩
  · simp [c] at hr'
  · cases hr : s.recording with
    | none => simp [shape, hr, hr'] at hs
    | some r =>
      simp only [shape, hr, hr', Option.map_some, Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨hl, hd⟩ := h r hr
      rw [hs.1, hs.2, hk]
      exact ⟨hl, fun x => Nat.le_trans (hd x) (Nat.add_le_add_right hn _)⟩

theorem send_calm (s : State) (r : Recording) : Calm s (send s r).1 := Calm.none (send_recording s r)

theorem drop_calm (s : State) (r : Recording) : Calm s (drop s r).1 := Calm.none rfl

theorem poll_calm (s : State) (r : Recording) (hr : s.recording = some r) : Calm s (poll s r).1 := by
  unfold poll; dsimp only
  repeat' split
  all_goals exact Or.inr ⟨by simp [shape, hr], rfl, Nat.le_refl _⟩

theorem tick_calm (s : State) : Calm s (tick s).1 := by
  unfold tick
  split
  · exact Calm.refl _
  · rename_i r hr
    split
    · exact send_calm _ _
    · split
      · exact poll_calm _ _ hr
      · exact Calm.refl _

theorem audio_calm (s : State) (c : Nat) (a : Audio) : Calm s (audio s c a).1 := by
  unfold audio
  split
  · rename_i r hr
    split
    · exact Or.inr ⟨by simp [shape, hr], rfl, Nat.le_refl _⟩
    · exact Calm.refl _
  · exact Calm.refl _

theorem micFailed_calm (s : State) (c : Nat) (e : String) : Calm s (micFailed s c e).1 := by
  unfold micFailed
  split
  · split
    · exact Calm.none rfl
    · exact Calm.refl _
  · exact Calm.refl _

theorem keep_calm (s : State) (t : Transcript) : Calm s (keep s t).1 := by
  unfold keep; dsimp only; split <;> exact Calm.same rfl rfl rfl

theorem transcribed_calm (s : State) (c : ClipReq) (raw : String) : Calm s (transcribed s c raw).1 := by
  unfold transcribed; dsimp only
  split
  · exact Calm.same rfl rfl rfl
  · split
    · exact (keep_calm _ _).trans (Calm.same rfl rfl rfl)
    · exact keep_calm _ _

theorem chunkDone_calm (s : State) (c q : Nat) (t : Option String) : Calm s (chunkDone s c q t).1 := by
  unfold chunkDone
  split
  · rename_i r hr
    split
    · exact Or.inr ⟨by simp [shape, hr], rfl, Nat.le_refl _⟩
    · exact Calm.refl _
  · exact Calm.refl _

theorem Calm.of_eq {s s' s'' : State} (h : s'.recording = s.recording ∧ s'.keyHeld = s.keyHeld ∧
    s'.now = s.now) (c : Calm s' s'') : Calm s s'' := (Calm.same h.1 h.2.1 h.2.2).trans c

theorem reply_calm (s : State) (q : Nat) (x : Reply) : Calm s (reply s q x).1 := by
  unfold reply
  cases hq : s.reqs.lookup q with
  | none => exact Calm.refl _
  | some req =>
    dsimp only
    cases req <;> cases x <;> dsimp only
    case clip.ok =>
      exact Calm.of_eq (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) ⟨rfl, rfl, rfl⟩
        (transcribed_calm _ _ _)
    case chunk.ok =>
      exact Calm.of_eq (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) ⟨rfl, rfl, rfl⟩
        (chunkDone_calm _ _ _ _)
    case chunk.failed =>
      exact Calm.of_eq (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) ⟨rfl, rfl, rfl⟩
        (chunkDone_calm _ _ _ _)
    all_goals exact Calm.same rfl rfl rfl

theorem cancel_calm (s : State) : Calm s (cancel s).1 := Calm.none rfl

theorem menu_calm (s : State) (m : MenuAction) : Calm s (menu s m).1 := by
  cases m <;> simp only [menu]
  case toggleEnabled => split <;> first | exact Calm.same rfl rfl rfl | exact Calm.none rfl
  all_goals first
    | exact Calm.same rfl rfl rfl
    | (split <;> exact Calm.same rfl rfl rfl)

/-- Hands-free recordings send themselves within ten minutes. -/
def Bound (s : State) : Prop :=
  ∀ r, s.recording = some r → r.latched = true → r.deadline ≤ s.now + latchLimit

theorem RecInv.bound {s : State} (h : RecInv s) : Bound s := fun r hr => (h r hr).2

theorem release_recInv (s : State) (hb : Bound s) :
    RecInv (release s).1 := by
  unfold release
  split
  · rename_i hr; intro r h; simp [hr] at h
  · rename_i r hr
    split
    · split
      · intro r' h
        rw [hr] at h; cases h
        exact ⟨fun hl => by simp_all, hb r hr⟩
      · intro r' h; simp [drop] at h
    · split
      · intro r' h
        simp only [Option.some.injEq] at h
        subst h
        exact ⟨by simp, fun _ => Nat.le_refl _⟩
      · intro r' h; simp [send_recording] at h

theorem press_recInv (s : State) (f : Option Target) (hk : s.keyHeld = true) (hb : Bound s) :
    RecInv (press s f).1 := by
  unfold press
  split
  · exact fun r hr => ⟨fun _ => hk, hb r hr⟩
  · dsimp only
    split
    · rename_i hr
      intro r' h
      exact ⟨fun _ => hk, hb r' h⟩
    · intro r' h
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨fun _ => hk, by simp⟩

theorem setKey_recInv (s : State) (k : Hotkey) (h : RecInv s) : RecInv (setKey s k).1 := by
  unfold setKey
  split
  · exact h
  · dsimp only
    split
    · exact (release_recInv { s with keyHeld := false } h.bound).calm (Calm.same rfl rfl rfl)
    · exact h.calm (Calm.same rfl rfl rfl)

theorem applySettings_recInv (s : State) (cfg : Settings) (h : RecInv s) :
    RecInv (applySettings s cfg).1 := by
  have h' : RecInv { s with settings := cfg } := h.calm (Calm.same rfl rfl rfl)
  unfold applySettings
  dsimp only
  split
  · exact h'.calm (Calm.same rfl rfl rfl)
  · rename_i k _
    have := setKey_recInv _ k h'
    split
    · exact this.calm (Calm.same rfl rfl rfl)
    · exact this

theorem configured_recInv (s : State) (c : ConfigRead) (h : RecInv s) :
    RecInv (configured s c).1 := by
  have : RecInv (readConfig s c).1 := by
    unfold readConfig
    split
    · exact h.calm (Calm.same rfl rfl rfl)
    · exact applySettings_recInv _ _ h
    · exact applySettings_recInv _ _ h
  exact this.calm (Calm.same rfl rfl rfl)

/-- `RecInv` holds in every reachable state. -/
theorem step_recInv (s : State) (i : Input) (h : RecInv s) : RecInv (step s i).1 := by
  cases i with
  | keyDown t f =>
    have h' : RecInv { s with now := max s.now t } := h.calm (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _⟩)
    simp only [step]
    split
    · exact h'
    · exact press_recInv { s with now := max s.now t, keyHeld := true } f rfl h'.bound
  | keyUp t =>
    have h' : RecInv { s with now := max s.now t } := h.calm (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _⟩)
    simp only [step]
    split
    · exact release_recInv { s with now := max s.now t, keyHeld := false } h'.bound
    · exact h'
  | otherKey =>
    simp only [step]
    split
    · exact h.calm (Calm.same rfl rfl rfl)
    · exact h
  | tick t =>
    exact h.calm (Calm.trans (s₂ := { s with now := max s.now t })
      (Or.inr ⟨rfl, rfl, Nat.le_max_left _ _⟩) (tick_calm _))
  | audio c a => exact h.calm (audio_calm _ _ _)
  | micFailed c e => exact h.calm (micFailed_calm _ _ _)
  | reply q x => exact h.calm (reply_calm _ _ _)
  | config c => exact configured_recInv _ _ h
  | menu m => exact h.calm (menu_calm _ _)
  | transcriptDays => exact h
  | front c a =>
    refine h.calm (Or.inr ⟨?_, rfl, Nat.le_refl _⟩)
    simp only [step, setFront, shape, Option.map_map]
    congr 1; funext r; simp only [Function.comp]; split <;> rfl
  | keyLost =>
    simp only [step, keyLost]
    split
    · exact h.calm (Calm.none rfl)
    · rename_i hr; exact h.calm (Calm.none hr)
  | _ => exact h.calm (Calm.same rfl rfl rfl)

theorem recInv_init : RecInv init := by intro r h; simp [init] at h

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

/-- **Every recording ends**: once the key is up, ten minutes later there is no recording (the
host delivers the tick it was asked for with `wakeAt`). A recording held down has no limit, as
in Swift Yap: it ends when the key comes up. -/
theorem recording_ends (s : State) (h : RecInv s) (t : Ms) (ht : s.now ≤ t) :
    (run s [.keyUp t, .tick (t + latchLimit)]).recording = none := by
  have h1 := step_recInv s (.keyUp t) h
  have hk : (step s (.keyUp t)).1.keyHeld = false := by
    simp only [step]; split
    · rw [release_keyHeld]
    · simpa using ‹¬s.keyHeld = true›
  have hn : (step s (.keyUp t)).1.now = t := by
    simp only [step]; split
    · rw [release_now]; exact Nat.max_eq_right ht
    · exact Nat.max_eq_right ht
  simp only [run, List.foldl_cons, List.foldl_nil]
  generalize (step s (.keyUp t)).1 = s1 at h1 hk hn
  cases hr : s1.recording with
  | none => simp [step, tick, hr]
  | some r =>
    obtain ⟨hl, hd⟩ := h1 r hr
    have hlt : r.latched = true := by
      cases hr' : r.latched
      · simp [hl hr'] at hk
      · rfl
    have hdl : r.deadline ≤ max s1.now (t + latchLimit) := by
      have := hd hlt; rw [hn] at this; exact Nat.le_trans this (Nat.le_max_right _ _)
    simp only [step, tick, hr, hlt, hdl, and_self, ↓reduceIte]
    exact send_recording _ _

end Examples.Yap

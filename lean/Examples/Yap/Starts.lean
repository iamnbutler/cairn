module

public import Examples.Yap.Recording

/-! # Yap: a new recording is started, never conjured

`step_start` says the host is asked to start a recording only when none is in progress, and
always for a new clip. This is the other half: whenever the machine has a recording it didn't
have before (a different clip, or one where there was none), it asked the host to start it in
the same step. So a new recording is always the next clip number, never an old one. The app
(`Examples.Yap.App`) derives its `record` subscription from the recording, so this is what makes
a new subscription a new clip (^313). -/

@[expose] public section

namespace Examples.Yap

/-- Going from `s` to `o`, a recording `o` has is `s`'s clip, or `o` asked for it to start. -/
def Starts (s : State) (o : State × List Cmd) : Prop :=
  ∀ r', o.1.recording = some r' →
    s.recording.map (·.clip) = some r'.clip ∨ Cmd.startRecording r'.clip ∈ o.2

namespace Starts

theorem none {s : State} {o : State × List Cmd} (h : o.1.recording = none) : Starts s o := by
  intro r' hr'; rw [h] at hr'; cases hr'

theorem clip {s : State} {o : State × List Cmd}
    (h : o.1.recording.map (·.clip) = s.recording.map (·.clip)) : Starts s o := by
  intro r' hr'; left; rw [← h, hr']; rfl

theorem same {s : State} {o : State × List Cmd} (h : o.1.recording = s.recording) : Starts s o :=
  clip (by rw [h])

theorem of_rec {s s' : State} {o : State × List Cmd} (hs : s'.recording = s.recording)
    (h : Starts s' o) : Starts s o := fun r' hr' => by rw [← hs]; exact h r' hr'

theorem mono {s : State} {o o' : State × List Cmd} (h : Starts s o) (hr : o'.1.recording = o.1.recording)
    (hc : ∀ c ∈ o.2, c ∈ o'.2) : Starts s o' := fun r' hr' =>
  (h r' (hr ▸ hr')).imp_right (hc _)

end Starts

theorem send_starts (s : State) (r : Recording) : Starts s (send s r) := Starts.none (send_recording s r)

theorem drop_starts (s : State) (r : Recording) : Starts s (drop s r) := Starts.none rfl

theorem release_starts (s : State) : Starts s (release s) := by
  unfold release
  split
  · exact Starts.same rfl
  · rename_i r hr
    split
    · split
      · exact Starts.same rfl
      · exact Starts.of_rec (s' := s) rfl (drop_starts s r)
    · split
      · exact Starts.clip (by simp [hr])
      · exact send_starts _ _

theorem press_starts (s : State) (f : Option Target) : Starts s (press s f) := by
  unfold press
  split
  · exact Starts.same rfl
  · dsimp only
    split
    · exact Starts.same rfl
    · intro r' hr'
      simp only [Option.some.injEq] at hr'
      subst hr'
      right; simp

theorem poll_starts (s : State) (r : Recording) (hr : s.recording = some r) : Starts s (poll s r) := by
  obtain ⟨r', h', hc, -⟩ := poll_recording s r
  exact Starts.clip (by rw [h', hr]; simp [hc])

theorem tick_starts (s : State) : Starts s (tick s) := by
  unfold tick
  split
  · exact Starts.same rfl
  · rename_i r hr
    split
    · exact send_starts _ _
    · split
      · exact poll_starts s r hr
      · exact Starts.same rfl

theorem audio_starts (s : State) (c : Nat) (a : Audio) : Starts s (audio s c a) := by
  unfold audio
  split
  · rename_i r hr
    split
    · exact Starts.clip (by simp [hr])
    · exact Starts.same rfl
  · exact Starts.same rfl

theorem micFailed_starts (s : State) (c : Nat) (e : String) : Starts s (micFailed s c e) := by
  unfold micFailed
  split
  · split
    · exact Starts.none rfl
    · exact Starts.same rfl
  · exact Starts.same rfl

theorem chunkDone_starts (s : State) (c q : Nat) (t : Option String) : Starts s (chunkDone s c q t) := by
  unfold chunkDone
  split
  · rename_i r hr
    split
    · exact Starts.clip (by simp [hr])
    · exact Starts.same rfl
  · exact Starts.same rfl

theorem reply_starts (s : State) (q : Nat) (x : Reply) : Starts s (reply s q x) := by
  unfold reply
  cases hq : s.reqs.lookup q with
  | none => exact Starts.same rfl
  | some req =>
    dsimp only
    cases req <;> cases x <;> dsimp only
    case clip.ok => exact Starts.same (transcribed_recording _ _ _)
    case chunk.ok =>
      exact Starts.of_rec (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (chunkDone_starts _ _ _ _)
    case chunk.failed =>
      exact Starts.of_rec (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (chunkDone_starts _ _ _ _)
    all_goals exact Starts.same rfl

theorem cancel_starts (s : State) : Starts s (cancel s) := Starts.none rfl

theorem setKey_starts (s : State) (k : Hotkey) : Starts s (setKey s k) := by
  unfold setKey
  split
  · exact Starts.same rfl
  · dsimp only
    split
    · exact (Starts.of_rec (s' := { s with keyHeld := false }) rfl (release_starts _)).mono rfl
        (fun c hc => List.mem_append_left _ hc)
    · exact Starts.same rfl

theorem applySettings_starts (s : State) (cfg : Settings) : Starts s (applySettings s cfg) := by
  unfold applySettings
  dsimp only
  split
  · exact Starts.same rfl
  · rename_i k _
    have h := Starts.of_rec (s' := { s with settings := cfg }) rfl (setKey_starts _ k)
    exact h.mono (by split <;> rfl) (fun _ hc => hc)

theorem configured_starts (s : State) (c : ConfigRead) : Starts s (configured s c) := by
  unfold configured
  dsimp only
  have : Starts s (readConfig s c) := by
    unfold readConfig
    split
    · exact Starts.same rfl
    · exact applySettings_starts _ _
    · exact applySettings_starts _ _
  exact this.mono rfl (fun _ hc => List.mem_append_left _ hc)

theorem menu_starts (s : State) (m : MenuAction) : Starts s (menu s m) := by
  cases m <;> simp only [menu]
  case toggleEnabled =>
    split
    · exact Starts.same rfl
    · exact Starts.none rfl
  all_goals first
    | exact Starts.same rfl
    | (split <;> exact Starts.same rfl)

theorem step_starts (s : State) (i : Input) : Starts s (step s i) := by
  cases i with
  | keyDown t f =>
    simp only [step]
    split
    · exact Starts.same rfl
    · exact Starts.of_rec (s' := { s with now := max s.now t, keyHeld := true }) rfl (press_starts _ _)
  | keyUp t =>
    simp only [step]
    split
    · exact Starts.of_rec (s' := { s with now := max s.now t, keyHeld := false }) rfl (release_starts _)
    · exact Starts.same rfl
  | otherKey => simp only [step]; split <;> exact Starts.same rfl
  | tick t => exact Starts.of_rec (s' := { s with now := max s.now t }) rfl (tick_starts _)
  | audio c a => exact audio_starts _ _ _
  | micFailed c e => exact micFailed_starts _ _ _
  | reply q x => exact reply_starts _ _ _
  | config c => exact configured_starts _ _
  | menu m => exact menu_starts _ _
  | front c a =>
    apply Starts.clip
    simp only [step, setFront, Option.map_map]
    cases s.recording with
    | none => rfl
    | some r => simp only [Option.map_some, Function.comp_apply]; split <;> rfl
  | keyLost =>
    simp only [step, keyLost]
    split
    · exact Starts.none rfl
    · exact Starts.same rfl
  | transcriptDays => simp only [step]; exact Starts.same rfl
  | _ => exact Starts.same rfl

/-- **A recording the machine didn't have is one it started**: a new clip, the next number, and
there was no recording before. -/
theorem step_new_recording (s : State) (i : Input) {r' : Recording}
    (h : (step s i).1.recording = some r') (hn : s.recording.map (·.clip) ≠ some r'.clip) :
    s.recording = none ∧ r'.clip = s.nextClip := by
  rcases step_starts s i r' h with h' | h'
  · exact absurd h' hn
  · obtain ⟨h1, h2, -⟩ := step_start s i h'
    exact ⟨h1, h2⟩

end Examples.Yap

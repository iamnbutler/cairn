module

public import Examples.Yap.Keys

/-! # Yap: what is sent for transcription

Every `transcribe` comes from sending a recording that was long enough, loud enough and had an
app to go to, and every prompt (whole clip or preview chunk) is the dictionary's, so only its
first 25 terms reach the model. -/

@[expose] public section

namespace Examples.Yap

/-- Recording `r` was worth sending, under dictionary `d`, as transcription `p` of clip `n`. -/
def Sendable (d : Dictionary) (r : Recording) (n : Nat) (p : Option String) : Prop :=
  r.clip = n ∧ minimumFrames ≤ r.frames ∧ silencePeak ≤ r.peak ∧ r.target.isSome ∧
    p = d.promptFor none

theorem Sendable.congr {d : Dictionary} {r r' : Recording} {n : Nat} {p : Option String}
    (hc : r'.clip = r.clip) (hf : r'.frames = r.frames) (hp : r'.peak = r.peak)
    (ht : r'.target = r.target) (h : Sendable d r n p) : Sendable d r' n p := by
  rw [Sendable, hc, hf, hp, ht]; exact h

theorem Sendable.of_same {d : Dictionary} {r r' : Recording} {n : Nat} {p : Option String}
    (hs : r.Same r') (h : Sendable d r' n p) : Sendable d r n p := by
  obtain ⟨_, _, rfl⟩ := hs; exact h

theorem send_transcribe (s : State) (r : Recording) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (send s r).2) : Sendable s.dict r n p := by
  unfold send at h
  dsimp only at h
  split at h
  · simp at h
  · rename_i hf
    split at h
    · simp at h
    · rename_i hp
      split at h
      · simp at h
      · rename_i app ht
        simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false, reduceCtorEq,
          Cmd.transcribe.injEq, false_or] at h
        rcases h with h | h
        · split at h <;> simp at h
        · obtain ⟨-, rfl, -, rfl⟩ := h
          exact ⟨rfl, Nat.le_of_not_lt hf, Nat.le_of_not_lt hp, by simp [ht], rfl⟩

theorem release_transcribe (s : State) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (release s).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold release at h
  split at h
  · simp at h
  · rename_i r hr
    refine ⟨r, hr, ?_⟩
    split at h
    · split at h
      · simp at h
      · exact absurd rfl ((drop_kinds _ _).not_mem (by simp [Cmd.kind]) h)
    · split at h
      · simp at h
      · exact send_transcribe _ _ h

theorem poll_transcribe (s : State) (r : Recording) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (poll s r).2) : False :=
  (poll_kinds s r).not_mem (by simp [Cmd.kind]) h rfl

theorem tickRec_transcribe (s : State) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (tickRec s).2) :
    ∃ r, s.recording = some r ∧ r.started = true ∧ Sendable s.dict r n p := by
  unfold tickRec at h
  split at h
  · simp at h
  · rename_i r hr
    split at h
    · split at h
      · exact absurd rfl ((drop_kinds _ _).not_mem (by simp [Cmd.kind]) h)
      · simp at h
    · rename_i hst
      refine ⟨r, hr, by simpa using hst, ?_⟩
      split at h
      · exact send_transcribe _ _ h
      · split at h
        · exact (poll_transcribe _ _ h).elim
        · simp at h

theorem stepKey_transcribe (s : State) (k : Key) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (stepKey s k).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  cases k with
  | up t =>
    simp only [stepKey] at h
    split at h
    · exact release_transcribe { s with now := max s.now t, keyHeld := false } h
    · simp at h
  | _ => exact absurd rfl ((stepKey_kinds _ _).not_mem (by simp [keyKinds, Cmd.kind]) h)

theorem drain_transcribe (s : State) (ks : List Key) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (drain s ks).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  induction ks generalizing s with
  | nil => simp [drain] at h
  | cons k ks ih =>
    simp only [drain] at h
    split at h
    · rename_i he
      rcases List.mem_append.1 h with h | h
      · exact stepKey_transcribe s k h
      · obtain ⟨r', hr', hs⟩ := ih _ h
        rw [(stepKey_frame s k).dict] at hs
        rcases stepKey_some s k hr' with ⟨r, hr, hsm⟩ | ⟨h0, -⟩
        · exact ⟨r, hr, hs.of_same hsm⟩
        · rw [hr', h0] at he; cases he
    · rcases List.mem_append.1 h with h | h
      · exact stepKey_transcribe s k h
      · split at h <;> simp at h

theorem tick_transcribe (s : State) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (tick s).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold tick at h
  split at h
  · obtain ⟨r, hr, -, hs⟩ := tickRec_transcribe s h
    exact ⟨r, hr, hs⟩
  · rcases List.mem_append.1 h with h | h
    · exact drain_transcribe { s with keys := [] } s.keys h
    · obtain ⟨r', hr', hst, hs⟩ := tickRec_transcribe _ h
      rw [(drain_frame _ _).1] at hs
      rcases drain_some { s with keys := [] } s.keys hr' with ⟨r, hr, hsm⟩ | ⟨-, h2, -⟩
      · exact ⟨r, hr, hs.of_same hsm⟩
      · rw [hst] at h2; cases h2

theorem micStarted_transcribe (s : State) (c : Nat) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (micStarted s c).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold micStarted at h
  split at h
  · rename_i r hr
    split at h
    · rcases List.mem_append.1 h with h | h
      · split at h <;> simp at h
      · obtain ⟨r', hr', hs⟩ := drain_transcribe _ _ h
        simp only [Option.some.injEq] at hr'
        subst hr'
        exact ⟨r, hr, hs.congr rfl rfl rfl rfl⟩
    · simp at h
  · simp at h

theorem keyIn_transcribe (s : State) (k : Key) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (keyIn s k).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold keyIn at h
  split at h
  · simp at h
  · exact stepKey_transcribe s k h

theorem setKey_transcribe (s : State) (k : Hotkey) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (setKey s k).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold setKey at h
  split at h
  · simp at h
  · dsimp only at h
    rcases List.mem_append.1 h with h | h
    · split at h
      · simp at h
      · split at h
        · exact release_transcribe { s with keyHeld := false } h
        · simp at h
    · simp at h

theorem configured_transcribe (s : State) (c : ConfigRead) {q n : Nat} {m : String}
    {p : Option String} (h : Cmd.transcribe q n m p ∈ (configured s c).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold configured at h
  dsimp only at h
  rcases List.mem_append.1 h with h | h
  · unfold readConfig at h
    split at h
    · simp at h
    all_goals
      unfold applySettings at h
      dsimp only at h
      split at h
      · simp at h
      · change _ ∈ (setKey _ _).2 at h
        obtain ⟨r, hr, hs⟩ := setKey_transcribe _ _ h
        exact ⟨r, hr, hs⟩
  · split at h <;> simp at h

/-- **Too short, silent or nowhere to go: never sent.** Every whole-clip transcription asked
for is of the recording in progress, at least 0.3 s long, with a sample at or above the silence
peak, and an app to type into; its prompt is the dictionary's. -/
theorem step_transcribe (s : State) (i : Input) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (step s i).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  cases i with
  | keyDown t f => exact keyIn_transcribe s _ h
  | keyUp t => exact keyIn_transcribe s _ h
  | otherKey => exact keyIn_transcribe s _ h
  | tick t =>
    simp only [step] at h
    obtain ⟨r, hr, hs⟩ := tick_transcribe _ h
    exact ⟨r, hr, hs⟩
  | micStarted c t =>
    simp only [step] at h
    obtain ⟨r, hr, hs⟩ := micStarted_transcribe _ _ h
    exact ⟨r, hr, hs⟩
  | config c => exact configured_transcribe _ _ h
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, drainKinds, Cmd.kind]) h)

theorem poll_chunk (s : State) (r : Recording) {q n a b : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribeChunk q n a b m p ∈ (poll s r).2) : ∃ ctx, p = s.dict.promptFor ctx := by
  unfold poll at h
  dsimp only at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · simp only [List.mem_cons, reduceCtorEq, Cmd.transcribeChunk.injEq, List.not_mem_nil,
        or_false, false_or] at h
      exact ⟨_, h.2.2.2.2.2⟩

theorem tickRec_chunk (s : State) {q n a b : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribeChunk q n a b m p ∈ (tickRec s).2) : ∃ ctx, p = s.dict.promptFor ctx := by
  unfold tickRec at h
  split at h
  · simp at h
  · split at h
    · split at h
      · exact absurd rfl ((drop_kinds _ _).not_mem (by simp [Cmd.kind]) h)
      · simp at h
    · split at h
      · exact absurd rfl ((send_kinds _ _).not_mem (by simp [Cmd.kind]) h)
      · split at h
        · exact poll_chunk _ _ h
        · simp at h

theorem tick_chunk (s : State) {q n a b : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribeChunk q n a b m p ∈ (tick s).2) : ∃ ctx, p = s.dict.promptFor ctx := by
  unfold tick at h
  split at h
  · exact tickRec_chunk s h
  · rcases List.mem_append.1 h with h | h
    · exact absurd rfl ((drain_kinds _ _).not_mem (by simp [drainKinds, Cmd.kind]) h)
    · obtain ⟨ctx, he⟩ := tickRec_chunk _ h
      rw [(drain_frame _ _).1] at he
      exact ⟨ctx, he⟩

/-- **Preview chunks are prompted with the dictionary too.** -/
theorem step_chunk (s : State) (i : Input) {q n a b : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribeChunk q n a b m p ∈ (step s i).2) : ∃ ctx, p = s.dict.promptFor ctx := by
  cases i with
  | tick t =>
    simp only [step] at h
    obtain ⟨ctx, he⟩ := tick_chunk _ h
    exact ⟨ctx, he⟩
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, drainKinds, Cmd.kind]) h)

/-- The prompt of a transcription command, if it is one. -/
def Cmd.prompt? : Cmd → Option (Option String)
  | .transcribe _ _ _ p => some p
  | .transcribeChunk _ _ _ _ _ p => some p
  | _ => none

/-- **Only the first 25 dictionary terms are sent.** Every prompt `step` sends is the one a
dictionary of just the first 25 terms would give. -/
theorem step_prompt (s : State) (i : Input) {c : Cmd} (hc : c ∈ (step s i).2) {p : Option String}
    (hp : c.prompt? = some p) :
    ∃ ctx, p = { s.dict with terms := s.dict.terms.take promptLimit }.promptFor ctx := by
  cases c <;> simp only [Cmd.prompt?, reduceCtorEq, Option.some.injEq] at hp
  · subst hp
    obtain ⟨_, _, -, -, -, -, he⟩ := step_transcribe s i hc
    exact ⟨none, he.trans (promptFor_take _ _)⟩
  · subst hp
    obtain ⟨ctx, he⟩ := step_chunk s i hc
    exact ⟨ctx, he.trans (promptFor_take _ _)⟩

end Examples.Yap

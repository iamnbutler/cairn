module

public import Examples.Yap.Proofs

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

theorem tick_transcribe (s : State) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (tick s).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold tick at h
  split at h
  · simp at h
  · rename_i r hr
    refine ⟨r, hr, ?_⟩
    split at h
    · exact send_transcribe _ _ h
    · split at h
      · exact (poll_transcribe _ _ h).elim
      · simp at h

theorem setKey_transcribe (s : State) (k : Hotkey) {q n : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribe q n m p ∈ (setKey s k).2) :
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p := by
  unfold setKey at h
  split at h
  · simp at h
  · dsimp only at h
    split at h
    · rcases List.mem_append.1 h with h | h
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
  | keyUp t =>
    simp only [step] at h
    split at h
    · obtain ⟨r, hr, hs⟩ := release_transcribe _ h
      exact ⟨r, hr, hs⟩
    · simp at h
  | tick t =>
    simp only [step] at h
    obtain ⟨r, hr, hs⟩ := tick_transcribe _ h
    exact ⟨r, hr, hs⟩
  | config c => exact configured_transcribe _ _ h
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, Cmd.kind]) h)

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

/-- **Preview chunks are prompted with the dictionary too.** -/
theorem step_chunk (s : State) (i : Input) {q n a b : Nat} {m : String} {p : Option String}
    (h : Cmd.transcribeChunk q n a b m p ∈ (step s i).2) : ∃ ctx, p = s.dict.promptFor ctx := by
  cases i with
  | tick t =>
    simp only [step, tick] at h
    split at h
    · simp at h
    · split at h
      · exact absurd rfl ((send_kinds _ _).not_mem (by simp [Cmd.kind]) h)
      · split at h
        · obtain ⟨ctx, he⟩ := poll_chunk _ _ h
          exact ⟨ctx, he⟩
        · simp at h
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, Cmd.kind]) h)

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

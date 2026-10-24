module

public import Examples.Yap.Proofs

/-! # Yap: key events that wait for the microphone

While a recording's microphone is starting, Yap's main thread is inside `AudioCapture.start`, so
the key's events wait and are handled, in order, once it returns. The model keeps them in
`State.keys` and handles them with `drain` once the microphone has started (`micStarted`) or
failed (the next `tick`). These lemmas say what handling them can do: a recording it keeps is
the same recording (only its latch can change), and a new one is the next clip, still starting,
and asked for in the same step. -/

@[expose] public section

namespace Examples.Yap

/-- `r'` is `r`, hands free or not: all a key event can change in a recording. -/
def Recording.Same (r r' : Recording) : Prop := ∃ l d, r' = { r with latched := l, deadline := d }

theorem Recording.Same.refl (r : Recording) : r.Same r := ⟨r.latched, r.deadline, rfl⟩

theorem Recording.Same.trans {a b c : Recording} (h1 : a.Same b) (h2 : b.Same c) : a.Same c := by
  obtain ⟨l, d, rfl⟩ := h1
  obtain ⟨l', d', rfl⟩ := h2
  exact ⟨l', d', rfl⟩

theorem Recording.Same.clip {r r' : Recording} (h : r.Same r') : r'.clip = r.clip := by
  obtain ⟨_, _, rfl⟩ := h; rfl

theorem Recording.Same.started {r r' : Recording} (h : r.Same r') : r'.started = r.started := by
  obtain ⟨_, _, rfl⟩ := h; rfl

/-- What a key event leaves of the state's other parts. -/
structure KeyFrame (s s' : State) : Prop where
  dict : s'.dict = s.dict
  keys : s'.keys = s.keys
  settings : s'.settings = s.settings
  now : s.now ≤ s'.now
  turn : s'.turn = s.turn

theorem KeyFrame.refl (s : State) : KeyFrame s s := ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩

theorem KeyFrame.trans {a b c : State} (h1 : KeyFrame a b) (h2 : KeyFrame b c) : KeyFrame a c :=
  ⟨h2.dict.trans h1.dict, h2.keys.trans h1.keys, h2.settings.trans h1.settings,
    Nat.le_trans h1.now h2.now, h2.turn.trans h1.turn⟩

theorem send_frame (s : State) (r : Recording) : KeyFrame s (send s r).1 := by
  unfold send; dsimp only
  repeat' split
  all_goals exact ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩

theorem release_frame (s : State) : KeyFrame s (release s).1 := by
  unfold release
  split
  · exact KeyFrame.refl _
  · split
    · split
      · exact KeyFrame.refl _
      · exact ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩
    · split
      · exact ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩
      · exact send_frame _ _

theorem press_frame (s : State) (f : Option Target) : KeyFrame s (press s f).1 := by
  unfold press
  split
  · exact KeyFrame.refl _
  · dsimp only
    split
    · exact ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩
    · exact ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩

theorem stepKey_frame (s : State) (k : Key) : KeyFrame s (stepKey s k).1 := by
  cases k with
  | down t f =>
    simp only [stepKey]
    split
    · exact ⟨rfl, rfl, rfl, Nat.le_max_left _ _, rfl⟩
    · exact KeyFrame.trans (b := { s with now := max s.now t, keyHeld := true })
        ⟨rfl, rfl, rfl, Nat.le_max_left _ _, rfl⟩ (press_frame _ _)
  | up t =>
    simp only [stepKey]
    split
    · exact KeyFrame.trans (b := { s with now := max s.now t, keyHeld := false })
        ⟨rfl, rfl, rfl, Nat.le_max_left _ _, rfl⟩ (release_frame _)
    · exact ⟨rfl, rfl, rfl, Nat.le_max_left _ _, rfl⟩
  | other => simp only [stepKey]; split <;> exact ⟨rfl, rfl, rfl, Nat.le_refl _, rfl⟩

/-! ## The recording -/

/-- The recording a release leaves: none, or the same one. -/
theorem release_some (s : State) {r' : Recording} (h : (release s).1.recording = some r') :
    ∃ r, s.recording = some r ∧ r.Same r' := by
  unfold release at h
  split at h
  · rename_i hr; rw [hr] at h; cases h
  · rename_i r hr
    split at h
    · split at h
      · simp only [hr, Option.some.injEq] at h; subst h; exact ⟨_, hr, Recording.Same.refl _⟩
      · simp [drop] at h
    · split at h
      · simp only [Option.some.injEq] at h; subst h; exact ⟨r, hr, _, _, rfl⟩
      · rw [send_recording] at h; cases h

/-- The recording after a press: the same one, or a new one, starting, for the next clip, asked
for. -/
def NewRec (s : State) (o : State × List Cmd) (r' : Recording) : Prop :=
  s.recording = none ∧ r'.started = false ∧ r'.latched = false ∧ r'.clip = s.nextClip ∧
    Cmd.startRecording r'.clip ∈ o.2 ∧ o.1.nextClip = s.nextClip + 1

theorem press_some (s : State) (f : Option Target) {r' : Recording}
    (h : (press s f).1.recording = some r') :
    (∃ r, s.recording = some r ∧ r.Same r') ∨ NewRec s (press s f) r' := by
  unfold press at h ⊢
  split at h
  · exact Or.inl ⟨r', h, Recording.Same.refl _⟩
  · rename_i he
    simp only [he] at ⊢
    dsimp only at h ⊢
    split at h
    · rename_i r hr
      rw [hr] at h ⊢
      exact Or.inl ⟨r', h, Recording.Same.refl _⟩
    · rename_i hr
      simp only [Option.some.injEq] at h
      subst h
      rw [hr]
      exact Or.inr ⟨hr, rfl, rfl, rfl, by simp, rfl⟩

theorem stepKey_some (s : State) (k : Key) {r' : Recording}
    (h : (stepKey s k).1.recording = some r') :
    (∃ r, s.recording = some r ∧ r.Same r') ∨ NewRec s (stepKey s k) r' := by
  cases k with
  | down t f =>
    simp only [stepKey] at h ⊢
    split at h
    · rename_i hk; simp only [hk, ↓reduceIte]; exact Or.inl ⟨r', h, Recording.Same.refl _⟩
    · rename_i hk
      simp only [hk, Bool.false_eq_true, ↓reduceIte]
      exact press_some _ _ h
  | up t =>
    simp only [stepKey] at h
    split at h
    · obtain ⟨r, hr, hs⟩ := release_some _ h; exact Or.inl ⟨r, hr, hs⟩
    · exact Or.inl ⟨r', h, Recording.Same.refl _⟩
  | other =>
    simp only [stepKey] at h
    split at h <;> exact Or.inl ⟨r', h, Recording.Same.refl _⟩

theorem press_start (s : State) (f : Option Target) {n : Nat}
    (h : Cmd.startRecording n ∈ (press s f).2) :
    s.recording = none ∧ n = s.nextClip ∧ (press s f).1.nextClip = n + 1 ∧
      (press s f).1.recording.isSome = true := by
  unfold press at h ⊢
  split at h
  · simp at h
  · rename_i he
    simp only [he] at ⊢
    dsimp only at h ⊢
    split at h
    · simp at h
    · rename_i hr
      simp only [List.mem_singleton, Cmd.startRecording.injEq] at h
      subst h
      simp [hr]

theorem stepKey_start (s : State) (k : Key) {n : Nat} (h : Cmd.startRecording n ∈ (stepKey s k).2) :
    s.recording = none ∧ n = s.nextClip ∧ (stepKey s k).1.nextClip = n + 1 ∧
      (stepKey s k).1.recording.isSome = true := by
  cases k with
  | down t f =>
    simp only [stepKey] at h ⊢
    split at h
    · simp at h
    · rename_i hk
      simp only [hk, Bool.false_eq_true, ↓reduceIte]
      exact press_start _ _ h
  | up t =>
    simp only [stepKey] at h
    split at h
    · exact absurd rfl ((release_kinds _).not_mem (k := Kind.start) (by simp) h)
    · simp at h
  | other => simp only [stepKey] at h; split at h <;> simp at h

theorem press_nextClip (s : State) (f : Option Target) :
    (press s f).1.nextClip = s.nextClip ∨ Cmd.startRecording s.nextClip ∈ (press s f).2 := by
  unfold press
  split
  · exact Or.inl rfl
  · dsimp only
    split
    · exact Or.inl rfl
    · exact Or.inr (by simp)

theorem release_nextClip (s : State) : (release s).1.nextClip = s.nextClip := by
  unfold release
  split
  · rfl
  · split
    · split <;> rfl
    · split
      · rfl
      · unfold send; dsimp only; repeat' split
        all_goals rfl

theorem stepKey_nextClip (s : State) (k : Key) :
    (stepKey s k).1.nextClip = s.nextClip ∨ Cmd.startRecording s.nextClip ∈ (stepKey s k).2 := by
  cases k with
  | down t f =>
    simp only [stepKey]
    split
    · exact Or.inl rfl
    · exact press_nextClip _ _
  | up t =>
    simp only [stepKey]
    split
    · exact Or.inl (release_nextClip _)
    · exact Or.inl rfl
  | other => simp only [stepKey]; split <;> exact Or.inl rfl

/-- A key event that keeps whether there is a recording asks for no new one. -/
theorem stepKey_same_nextClip (s : State) (k : Key)
    (h : (stepKey s k).1.recording.isSome = s.recording.isSome) :
    (stepKey s k).1.nextClip = s.nextClip ∧ ∀ n, Cmd.startRecording n ∉ (stepKey s k).2 := by
  have hn : ∀ n, Cmd.startRecording n ∉ (stepKey s k).2 := by
    intro n hn
    obtain ⟨h1, -, -, h2⟩ := stepKey_start s k hn
    rw [h1, h2] at h; cases h
  refine ⟨?_, hn⟩
  rcases stepKey_nextClip s k with h' | h'
  · exact h'
  · exact absurd h' (hn _)

/-! ## Draining -/

theorem drain_frame (s : State) (ks : List Key) :
    (drain s ks).1.dict = s.dict ∧ (drain s ks).1.settings = s.settings ∧ s.now ≤ (drain s ks).1.now ∧
      (drain s ks).1.turn = s.turn := by
  induction ks generalizing s with
  | nil => exact ⟨rfl, rfl, Nat.le_refl _, rfl⟩
  | cons k ks ih =>
    have hf := stepKey_frame s k
    simp only [drain]
    split
    · obtain ⟨h1, h2, h3, h4⟩ := ih (stepKey s k).1
      exact ⟨h1.trans hf.dict, h2.trans hf.settings, Nat.le_trans hf.now h3, h4.trans hf.turn⟩
    · exact ⟨hf.dict, hf.settings, hf.now, hf.turn⟩

theorem drain_some (s : State) (ks : List Key) {r' : Recording}
    (h : (drain s ks).1.recording = some r') :
    (∃ r, s.recording = some r ∧ r.Same r') ∨ NewRec s (drain s ks) r' := by
  induction ks generalizing s with
  | nil => exact Or.inl ⟨r', h, Recording.Same.refl _⟩
  | cons k ks ih =>
    simp only [drain] at h ⊢
    split at h
    · rename_i he
      simp only [he, ↓reduceIte]
      rcases ih _ h with ⟨r1, h1, hs1⟩ | ⟨h1, h2, h3, h4, h5, h6⟩
      · rcases stepKey_some s k h1 with ⟨r0, h0, hs0⟩ | ⟨h0, -⟩
        · exact Or.inl ⟨r0, h0, hs0.trans hs1⟩
        · rw [h0, h1] at he; cases he
      · -- No recording before or after `k`: `k` asked for nothing.
        have hs : s.recording = none := by
          cases hs : s.recording with
          | none => rfl
          | some _ => rw [h1, hs] at he; cases he
        obtain ⟨hn, -⟩ := stepKey_same_nextClip s k he
        refine Or.inr ⟨hs, h2, h3, h4.trans hn, List.mem_append_right _ h5, by rw [h6, hn]⟩
    · rename_i he
      simp only [he, ↓reduceIte]
      rcases stepKey_some s k h with ⟨r0, h0, hs0⟩ | ⟨h0, h2, h3, h4, h5, h6⟩
      · exact Or.inl ⟨r0, h0, hs0⟩
      · exact Or.inr ⟨h0, h2, h3, h4, List.mem_append_left _ h5, h6⟩

theorem drain_start (s : State) (ks : List Key) {n : Nat} (h : Cmd.startRecording n ∈ (drain s ks).2) :
    s.recording = none ∧ n = s.nextClip ∧ (drain s ks).1.nextClip = n + 1 := by
  induction ks generalizing s with
  | nil => simp [drain] at h
  | cons k ks ih =>
    simp only [drain] at h ⊢
    split at h
    · rename_i he
      simp only [he, ↓reduceIte]
      obtain ⟨hn, hs⟩ := stepKey_same_nextClip s k he
      rcases List.mem_append.1 h with h | h
      · exact absurd h (hs n)
      · obtain ⟨h1, h2, h3⟩ := ih _ h
        refine ⟨?_, h2.trans hn, h3⟩
        cases hs' : s.recording with
        | none => rfl
        | some _ => rw [h1, hs'] at he; cases he
    · rename_i he
      simp only [he, ↓reduceIte]
      rcases List.mem_append.1 h with h | h
      · obtain ⟨h1, h2, h3, -⟩ := stepKey_start s k h
        exact ⟨h1, h2, h3⟩
      · split at h
        · simp at h
        · simp at h

theorem drain_nextClip (s : State) (ks : List Key) :
    (drain s ks).1.nextClip = s.nextClip ∨ Cmd.startRecording s.nextClip ∈ (drain s ks).2 := by
  induction ks generalizing s with
  | nil => exact Or.inl rfl
  | cons k ks ih =>
    simp only [drain]
    split
    · rename_i he
      obtain ⟨hn, -⟩ := stepKey_same_nextClip s k he
      rcases ih (stepKey s k).1 with h | h
      · exact Or.inl (h.trans hn)
      · exact Or.inr (List.mem_append_right _ (hn ▸ h))
    · rcases stepKey_nextClip s k with h | h
      · exact Or.inl h
      · exact Or.inr (List.mem_append_left _ h)

/-- What waits after draining: nothing, or, once a key event started or ended a recording, the
events after it. -/
theorem drain_keys (s : State) (ks : List Key) :
    ((drain s ks).1.keys = s.keys ∧ (drain s ks).1.recording.isSome = s.recording.isSome) ∨
      ((drain s ks).1.recording.isSome ≠ s.recording.isSome ∧ ∃ pre, ks = pre ++ (drain s ks).1.keys) := by
  induction ks generalizing s with
  | nil => exact Or.inl ⟨rfl, rfl⟩
  | cons k ks ih =>
    have hf := stepKey_frame s k
    simp only [drain]
    split
    · rename_i he
      rcases ih (stepKey s k).1 with ⟨h1, h2⟩ | ⟨h1, pre, h2⟩
      · exact Or.inl ⟨h1.trans hf.keys, h2.trans he⟩
      · refine Or.inr ⟨by rw [← he]; exact h1, k :: pre, ?_⟩
        show k :: ks = (k :: pre) ++ (drain (stepKey s k).1 ks).1.keys
        rw [List.cons_append, ← h2]
    · rename_i he
      exact Or.inr ⟨he, [k], rfl⟩

/-- From no recording, a release last among the events waiting is still waiting if a recording
started before it. -/
theorem drain_none_up (s : State) (ks : List Key) (u : Ms) (hs : s.recording = none) :
    (drain s (ks ++ [.up u])).1.recording = none ∨
      (Key.up u ∈ (drain s (ks ++ [.up u])).1.keys ∧
        ∃ r, (drain s (ks ++ [.up u])).1.recording = some r ∧ r.started = false) := by
  induction ks generalizing s with
  | nil =>
    left
    simp only [List.nil_append, drain]
    have h0 : (stepKey s (.up u)).1.recording = none := by
      simp only [stepKey]
      split
      · simp [release, hs]
      · exact hs
    simp [h0, hs]
  | cons k ks ih =>
    simp only [List.cons_append, drain]
    split
    · rename_i he
      have h0 : (stepKey s k).1.recording = none := by
        cases h0 : (stepKey s k).1.recording with
        | none => rfl
        | some _ => rw [h0, hs] at he; cases he
      exact ih _ h0
    · rename_i he
      cases h0 : (stepKey s k).1.recording with
      | none => rw [h0, hs] at he; exact absurd rfl he
      | some r =>
        right
        refine ⟨by simp, r, rfl, ?_⟩
        rcases stepKey_some s k h0 with ⟨r0, h1, -⟩ | ⟨-, h2, -⟩
        · rw [hs] at h1; cases h1
        · exact h2

end Examples.Yap

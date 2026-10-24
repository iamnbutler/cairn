module

public import Examples.Yap.Recording

/-! # Yap: each clip is typed at most once

Whatever the host does with replies (late, duplicated, out of order, never), no clip's
transcript is typed twice. The argument counts clips: a clip is *live* while it is recording
or its transcription is in flight; starting a recording makes a new clip live, and typing a
clip uses up its transcription request. So over any run, the clips typed plus the clips still
live never count a clip more than once. -/

@[expose] public section

namespace Examples.Yap

/-- The clips whose whole-clip transcription is in flight. -/
def clipsOf (reqs : List (Nat × Req)) : List Nat :=
  reqs.filterMap fun p => match p.2 with
    | .clip c => some c.clip
    | _ => none

/-- The clips that may yet be typed: the one recording, and those being transcribed. -/
def live (s : State) : List Nat := (s.recording.map (·.clip)).toList ++ clipsOf s.reqs

/-- The clips typed by these commands, in order. -/
def typedClips (cs : List Cmd) : List Nat :=
  cs.filterMap fun c => match c with
    | .type _ n _ _ _ => some n
    | _ => none

/-- One for a clip numbered in `[a, b)`: started on the way from `a` to `b`. -/
def fresh (a b n : Nat) : Nat := if a ≤ n ∧ n < b then 1 else 0

/-- Going from `s` to `o`, no clip is typed or stays live more often than it was live, or was
started. -/
def Rel (s : State) (o : State × List Cmd) : Prop :=
  s.nextClip ≤ o.1.nextClip ∧
    ∀ n, (typedClips o.2).count n + (live o.1).count n ≤ fresh s.nextClip o.1.nextClip n + (live s).count n

theorem typedClips_nil {ks : List Kind} {cs : List Cmd} (h : Kinds ks cs) (hk : Kind.type ∉ ks) :
    typedClips cs = [] := by
  simp only [typedClips, List.filterMap_eq_nil_iff]
  intro c hc
  split
  · exact absurd rfl (h.not_mem hk hc)
  · rfl

theorem typedClips_append (a b : List Cmd) : typedClips (a ++ b) = typedClips a ++ typedClips b := by
  simp [typedClips]

theorem Rel.of {s : State} {o : State × List Cmd} (hn : o.1.nextClip = s.nextClip)
    (ht : typedClips o.2 = []) (hl : (live o.1).Sublist (live s)) : Rel s o := by
  refine ⟨Nat.le_of_eq hn.symm, fun n => ?_⟩
  rw [ht, hn]
  have := hl.count_le n
  simp [fresh]
  omega

theorem Rel.congr {s s' : State} {o : State × List Cmd} (hn : s'.nextClip = s.nextClip)
    (hl : live s' = live s) (h : Rel s' o) : Rel s o := by
  unfold Rel at h ⊢; rw [hn, hl] at h; exact h

theorem Rel.weaken {s s' : State} {o : State × List Cmd} (hn : s'.nextClip = s.nextClip)
    (hl : ∀ n, (live s').count n ≤ (live s).count n) (h : Rel s' o) : Rel s o := by
  unfold Rel at h ⊢
  rw [hn] at h
  exact ⟨h.1, fun n => Nat.le_trans (h.2 n) (Nat.add_le_add_left (hl n) _)⟩

theorem Rel.trans_same {s : State} {o o' : State × List Cmd} (h : Rel s o)
    (hn : o'.1.nextClip = o.1.nextClip) (ht : typedClips o'.2 = typedClips o.2)
    (hl : live o'.1 = live o.1) : Rel s o' := by
  rw [Rel, hn, ht, hl]; exact h

theorem fresh_add {a b c : Nat} (h₁ : a ≤ b) (h₂ : b ≤ c) (n : Nat) :
    fresh b c n + fresh a b n ≤ fresh a c n := by
  unfold fresh
  split <;> split <;> split <;> omega

theorem Rel.comp {s : State} {o₁ o₂ : State × List Cmd} (ha : Rel s o₁) (hb : Rel o₁.1 o₂) :
    Rel s (o₂.1, o₁.2 ++ o₂.2) := by
  obtain ⟨h₁, h₂⟩ := ha
  obtain ⟨h₃, h₄⟩ := hb
  refine ⟨Nat.le_trans h₁ h₃, fun n => ?_⟩
  simp only [typedClips_append, List.count_append]
  have := h₂ n
  have := h₄ n
  have := fresh_add h₁ h₃ n
  omega

theorem live_none {s : State} (h : s.recording = none) : live s = clipsOf s.reqs := by
  simp [live, h]

theorem live_some {s : State} {r : Recording} (h : s.recording = some r) :
    live s = r.clip :: clipsOf s.reqs := by
  simp [live, h]

theorem send_rel (s : State) (r : Recording) (hr : s.recording = some r) : Rel s (send s r) := by
  unfold send; dsimp only
  repeat' split
  all_goals
    refine Rel.of rfl (typedClips_nil (ks := [.play, .stop, .overlay, .transcribe]) ?_ (by decide)) ?_
  all_goals first
    | (simp [Kinds, Cmd.kind]; done)
    | (split <;> simp [Kinds, Cmd.kind])
    | skip
  all_goals simp [live, hr, clipsOf]

theorem drop_rel (s : State) (r : Recording) (hr : s.recording = some r) : Rel s (drop s r) :=
  Rel.of rfl rfl (by simp [drop, live, hr])

theorem release_rel (s : State) : Rel s (release s) := by
  unfold release
  split
  · exact Rel.of rfl rfl (List.Sublist.refl _)
  · rename_i r hr
    split
    · split
      · exact Rel.of rfl rfl (List.Sublist.refl _)
      · exact drop_rel _ _ hr
    · split
      · exact Rel.of rfl rfl (by simp [live, hr])
      · exact send_rel _ _ hr

theorem press_rel (s : State) (f : Option Target) : Rel s (press s f) := by
  unfold press
  split
  · exact Rel.of rfl rfl (List.Sublist.refl _)
  · dsimp only
    split
    · exact Rel.of rfl rfl (List.Sublist.refl _)
    · rename_i hr
      refine ⟨by simp, fun n => ?_⟩
      have ht : typedClips [Cmd.startRecording s.nextClip] = [] := by simp [typedClips]
      rw [ht]
      simp only [live, hr, Option.map_some, Option.toList_some, Option.map_none, Option.toList_none,
        List.singleton_append, List.nil_append, List.count_nil, Nat.zero_add, List.count_cons,
        fresh]
      split <;> split <;> simp_all <;> omega

theorem poll_rel (s : State) (r : Recording) (hr : s.recording = some r) : Rel s (poll s r) := by
  unfold poll; dsimp only
  repeat' split
  all_goals refine Rel.of rfl (by simp [typedClips]) ?_
  all_goals simp [live, hr, clipsOf]

theorem stepKey_rel (s : State) (k : Key) : Rel s (stepKey s k) := by
  cases k with
  | down t f =>
    simp only [stepKey]
    split
    · exact Rel.of rfl rfl (List.Sublist.refl _)
    · exact Rel.congr (s' := { s with now := max s.now t, keyHeld := true }) rfl rfl (press_rel _ _)
  | up t =>
    simp only [stepKey]
    split
    · exact Rel.congr (s' := { s with now := max s.now t, keyHeld := false }) rfl rfl (release_rel _)
    · exact Rel.of rfl rfl (List.Sublist.refl _)
  | other => simp only [stepKey]; split <;> exact Rel.of rfl rfl (List.Sublist.refl _)

theorem drain_rel (s : State) (ks : List Key) : Rel s (drain s ks) := by
  induction ks generalizing s with
  | nil => exact Rel.of rfl rfl (List.Sublist.refl _)
  | cons k ks ih =>
    simp only [drain]
    split
    · exact Rel.comp (stepKey_rel s k) (ih _)
    · refine Rel.trans_same (stepKey_rel s k) rfl ?_ rfl
      rw [typedClips_append]
      split <;> simp [typedClips]

theorem tickRec_rel (s : State) : Rel s (tickRec s) := by
  unfold tickRec
  split
  · exact Rel.of rfl rfl (List.Sublist.refl _)
  · rename_i r hr
    split
    · split
      · exact drop_rel _ _ hr
      · exact Rel.of rfl rfl (List.Sublist.refl _)
    · split
      · exact send_rel _ _ hr
      · split
        · exact poll_rel _ _ hr
        · exact Rel.of rfl rfl (List.Sublist.refl _)

theorem tick_rel (s : State) : Rel s (tick s) := by
  unfold tick
  split
  · exact tickRec_rel _
  · exact Rel.comp (Rel.congr (s' := { s with keys := [] }) rfl rfl (drain_rel _ _)) (tickRec_rel _)

theorem micStarted_rel (s : State) (c : Nat) : Rel s (micStarted s c) := by
  unfold micStarted
  split
  · rename_i r hr
    split
    · have hd := drain_rel { s with
          recording := some { r with started := true, latched := false, nextPoll := s.now + pollMs },
          keys := [], detail := "Listening…" } s.keys
      have := Rel.congr (s := s) (by exact rfl) (by simp [live, hr]) hd
      refine Rel.trans_same this rfl ?_ rfl
      rw [typedClips_append]
      split <;> simp [typedClips]
    · exact Rel.of rfl rfl (List.Sublist.refl _)
  · exact Rel.of rfl rfl (List.Sublist.refl _)

theorem keyIn_rel (s : State) (k : Key) : Rel s (keyIn s k) := by
  unfold keyIn
  split
  · exact Rel.of rfl rfl (by simp [live])
  · exact stepKey_rel _ _

theorem audio_rel (s : State) (c : Nat) (a : Audio) : Rel s (audio s c a) := by
  unfold audio
  split
  · rename_i r hr
    split
    · exact Rel.of rfl rfl (by simp [live, hr])
    · exact Rel.of rfl rfl (List.Sublist.refl _)
  · exact Rel.of rfl rfl (List.Sublist.refl _)

theorem micFailed_rel (s : State) (c : Nat) (e : String) : Rel s (micFailed s c e) := by
  unfold micFailed
  split
  · rename_i r hr
    split
    · split
      · exact Rel.of rfl (by simp [typedClips]) (by simp [live, hr])
      · exact Rel.of rfl (by split <;> simp [typedClips]) (by simp [live, hr])
    · exact Rel.of rfl rfl (List.Sublist.refl _)
  · exact Rel.of rfl rfl (List.Sublist.refl _)

theorem chunkDone_rel (s : State) (c q : Nat) (t : Option String) : Rel s (chunkDone s c q t) := by
  have ht := typedClips_nil (chunkDone_kinds s c q t) (by decide)
  refine Rel.of ?_ ht ?_
  · unfold chunkDone; split
    · split <;> rfl
    · rfl
  · unfold chunkDone
    split
    · rename_i r hr
      split
      · simp [live, hr]
      · exact List.Sublist.refl _
    · exact List.Sublist.refl _

theorem keep_live (s : State) (t : Transcript) : live (keep s t).1 = live s := by
  unfold keep; dsimp only; split <;> simp [live, clipsOf]

theorem typeIt_live (s : State) (c : ClipReq) (t : Transcript) : live (typeIt s c t).1 = live s := by
  simp [typeIt, live, clipsOf]

theorem keep_nextClip (s : State) (t : Transcript) : (keep s t).1.nextClip = s.nextClip := by
  unfold keep; dsimp only; split <;> rfl

/-- A whole clip's transcript types that clip, at most. -/
theorem transcribed_typed (s : State) (c : ClipReq) (raw : String) :
    (typedClips (transcribed s c raw).2).Sublist [c.clip] ∧
      live (transcribed s c raw).1 = live s ∧ (transcribed s c raw).1.nextClip = s.nextClip := by
  unfold transcribed; dsimp only
  split
  · simp [typedClips, live]
  · split
    · refine ⟨?_, ?_, ?_⟩
      · rw [typedClips_append, typedClips_nil (keep_kinds _ _) (by decide)]
        simp [typeIt, typedClips]
      · rw [typeIt_live]; exact keep_live _ _
      · exact keep_nextClip _ _
    · exact ⟨by rw [typedClips_nil (keep_kinds _ _) (by decide)]; simp, keep_live _ _, keep_nextClip _ _⟩

theorem lookup_split {β : Type} {q : Nat} {v : β} :
    ∀ {l : List (Nat × β)}, l.lookup q = some v →
      ∃ l₁ l₂, l = l₁ ++ (q, v) :: l₂ ∧ l.eraseP (·.1 == q) = l₁ ++ l₂
  | [], h => by simp at h
  | (k, w) :: l, h => by
    simp only [List.lookup] at h
    split at h
    · rename_i hk
      simp only [Option.some.injEq] at h
      subst h
      simp only [beq_iff_eq] at hk
      subst hk
      exact ⟨[], l, rfl, by simp⟩
    · rename_i hk
      obtain ⟨l₁, l₂, rfl, he⟩ := lookup_split h
      refine ⟨(k, w) :: l₁, l₂, rfl, ?_⟩
      have : ((k, w).1 == q) = false :=
        Bool.eq_false_iff.2 fun h' => by simp only [beq_iff_eq] at h'; subst h'; simp at hk
      rw [List.eraseP_cons, this]
      simp only [Bool.false_eq_true, ↓reduceIte]
      rw [he]; rfl

theorem clipsOf_append (a b : List (Nat × Req)) : clipsOf (a ++ b) = clipsOf a ++ clipsOf b := by
  simp [clipsOf]

theorem reply_rel (s : State) (q : Nat) (x : Reply) : Rel s (reply s q x) := by
  unfold reply
  cases hq : s.reqs.lookup q with
  | none => exact Rel.of rfl rfl (List.Sublist.refl _)
  | some req =>
    obtain ⟨l₁, l₂, hl, he⟩ := lookup_split hq
    dsimp only
    -- Erasing the request: the live clips lose at most its clip.
    have hlive : ∀ n, (live { s with reqs := s.reqs.eraseP (·.1 == q) }).count n +
        (match req with | .clip c => [c.clip] | _ => []).count n = (live s).count n := by
      intro n
      simp only [live]
      rw [he, hl]
      simp only [clipsOf_append, List.count_append]
      cases req <;> simp [clipsOf, List.count_cons] <;> (try split) <;> omega
    cases req <;> cases x <;> dsimp only
    case clip.ok c raw =>
      obtain ⟨ht, hlv, hn⟩ := transcribed_typed { s with reqs := s.reqs.eraseP (·.1 == q) } c raw
      refine ⟨Nat.le_of_eq hn.symm, fun n => ?_⟩
      have := ht.count_le n
      have h2 := hlive n
      dsimp only at h2
      rw [hlv, hn]
      unfold fresh
      dsimp only
      split <;> omega
    all_goals
      refine Rel.weaken (s' := { s with reqs := s.reqs.eraseP (·.1 == q) }) rfl
        (fun n => by have := hlive n; (try dsimp only at this); (try simp only [List.count_nil] at this); omega) ?_
    case chunk.ok => exact chunkDone_rel _ _ _ _
    case chunk.failed => exact chunkDone_rel _ _ _ _
    case type.ok =>
      exact Rel.of rfl (typedClips_nil (typedOk_kinds _ _ _) (by decide)) (List.Sublist.refl _)
    case type.failed =>
      exact Rel.of rfl (typedClips_nil (typedFailed_kinds _ _ _ _) (by decide)) (List.Sublist.refl _)
    case clip.failed => exact Rel.of rfl (by simp [typedClips]) (List.Sublist.refl _)
    all_goals exact Rel.of rfl rfl (List.Sublist.refl _)

theorem cancel_rel (s : State) : Rel s (cancel s) :=
  Rel.of rfl (typedClips_nil (cancel_kinds s) (by decide)) (by simp [cancel, live])

theorem setKey_rel (s : State) (k : Hotkey) : Rel s (setKey s k) := by
  unfold setKey
  split
  · exact Rel.of rfl rfl (List.Sublist.refl _)
  · dsimp only
    split
    · exact Rel.of rfl (by simp [typedClips]) (by simp [live])
    · split
      · refine Rel.trans_same (Rel.congr (s' := { s with keyHeld := false }) rfl rfl
          (release_rel _)) rfl ?_ rfl
        simp [typedClips]
      · exact Rel.of rfl (by simp [typedClips]) (List.Sublist.refl _)

theorem applySettings_rel (s : State) (cfg : Settings) : Rel s (applySettings s cfg) := by
  unfold applySettings
  dsimp only
  split
  · exact Rel.of rfl rfl (List.Sublist.refl _)
  · rename_i k _
    have := Rel.congr (s' := { s with settings := cfg }) rfl rfl (setKey_rel _ k)
    split
    · exact Rel.trans_same this rfl rfl rfl
    · exact this

theorem configured_rel (s : State) (c : ConfigRead) : Rel s (configured s c) := by
  have : Rel s (readConfig s c) := by
    unfold readConfig
    split
    · exact Rel.of rfl rfl (List.Sublist.refl _)
    · exact applySettings_rel _ _
    · exact applySettings_rel _ _
  unfold configured
  dsimp only
  refine Rel.trans_same this rfl ?_ rfl
  rw [typedClips_append]
  split <;> simp [typedClips]

theorem menu_rel (s : State) (m : MenuAction) : Rel s (menu s m) := by
  have ht := typedClips_nil (menu_kinds s m) (by decide)
  cases m <;> simp only [menu] at ht ⊢
  case toggleKeep => exact Rel.of rfl ht (by simp [live, clipsOf])
  case toggleEnabled =>
    split <;> rename_i hen <;> simp only [hen, ↓reduceIte] at ht
    · exact Rel.of rfl ht (List.Sublist.refl _)
    · exact Rel.of rfl ht (by simp [cancel, live])
  all_goals first
    | exact Rel.of rfl ht (List.Sublist.refl _)
    | (split <;> exact Rel.of rfl (by simp [typedClips]) (List.Sublist.refl _))

theorem setFront_live (s : State) (c : Nat) (a : Target) : live (setFront s c a) = live s := by
  cases h : s.recording with
  | none => simp [live, setFront, h]
  | some r => simp only [live, setFront, h, Option.map_some]; split <;> rfl

theorem keyLost_rel (s : State) : Rel s (keyLost s) := by
  unfold keyLost
  split
  · rename_i r hr; exact Rel.trans_same (drop_rel s r hr) rfl rfl rfl
  · exact Rel.of rfl rfl (List.Sublist.refl _)

theorem step_rel (s : State) (i : Input) : Rel s (step s i) := by
  cases i with
  | keyDown t f => exact keyIn_rel _ _
  | keyUp t => exact keyIn_rel _ _
  | otherKey => exact keyIn_rel _ _
  | tick t => exact Rel.congr (s' := { s with now := max s.now t }) rfl rfl (tick_rel _)
  | micStarted c t =>
    exact Rel.congr (s' := { s with now := max s.now t }) rfl rfl (micStarted_rel _ _)
  | audio c a => exact audio_rel _ _ _
  | micFailed c e => exact micFailed_rel _ _ _
  | reply q x => exact reply_rel _ _ _
  | config c => exact configured_rel _ _
  | menu m => exact menu_rel _ _
  | transcriptDays d ds =>
    exact Rel.of rfl (by simp only [step]; split <;> simp [typedClips]) (List.Sublist.refl _)
  | front c a => exact Rel.of rfl rfl (by rw [show (step s (.front c a)).1 = setFront s c a from rfl, setFront_live]; exact List.Sublist.refl _)
  | keyLost => exact keyLost_rel s
  | _ => exact Rel.of rfl (by simp [step, typedClips]) (List.Sublist.refl _)

theorem exec_rel (s : State) (is : List Input) : Rel s (exec s is) := by
  induction is generalizing s with
  | nil => exact Rel.of rfl rfl (List.Sublist.refl _)
  | cons i is ih =>
    obtain ⟨h₁, h₂⟩ := step_rel s i
    obtain ⟨h₃, h₄⟩ := ih (step s i).1
    refine ⟨Nat.le_trans h₁ h₃, fun n => ?_⟩
    simp only [exec, typedClips_append, List.count_append]
    have := h₂ n
    have := h₄ n
    have := fresh_add h₁ h₃ n
    omega

/-- **Each clip is typed at most once**, along every sequence of inputs from launch: however
the host delivers replies (late, twice, out of order, or never), no clip's transcript is typed
twice. -/
theorem typed_once (is : List Input) (n : Nat) : (typedClips (exec init is).2).count n ≤ 1 := by
  have := (exec_rel init is).2 n
  have h0 : (live init).count n = 0 := by simp [live, init, clipsOf]
  have h1 : fresh init.nextClip (exec init is).1.nextClip n ≤ 1 := by unfold fresh; split <;> omega
  omega

theorem exec_append (s : State) (a b : List Input) :
    exec s (a ++ b) = ((exec (exec s a).1 b).1, (exec s a).2 ++ (exec (exec s a).1 b).2) := by
  induction a generalizing s with
  | nil => simp [exec]
  | cons i a ih => simp [exec, ih]

theorem exec_fst (s : State) (is : List Input) : (exec s is).1 = run s is := by
  induction is generalizing s with
  | nil => rfl
  | cons i is ih => simp [exec, run, ih, List.foldl_cons]

/-- The same from any reachable state: nothing typed before it is typed again after it. -/
theorem typed_once_from (pre is : List Input) (n : Nat) :
    (typedClips ((exec (run init pre) is).2)).count n ≤ 1 := by
  have := typed_once (pre ++ is) n
  rw [exec_append, typedClips_append, List.count_append] at this
  rw [← exec_fst]
  omega

end Examples.Yap

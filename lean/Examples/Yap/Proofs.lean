module

public import Examples.Yap.Model

/-! # Yap: what the machine never does

Lemmas about `step` that the claims in `Examples.Yap` rest on. Most say which kinds of command
each part of the machine can issue (`Kinds`), so "only a reply can type" or "only the key and
the clock can send" are short case splits. -/

@[expose] public section

namespace Examples.Yap

inductive Kind where
  | readConfig | readDictionary | listen | storePrefs | saveConfig | start | stop | transcribe
  | chunk | save | markTyped | type | play | wakeAt | listDays | deleteDays | loadRecent | copy
  | overlay | opens
deriving DecidableEq, Repr

def Cmd.kind : Cmd → Kind
  | .readConfig => .readConfig
  | .readDictionary => .readDictionary
  | .listen _ => .listen
  | .storePrefs _ => .storePrefs
  | .saveConfig .. => .saveConfig
  | .startRecording _ => .start
  | .stopRecording _ => .stop
  | .transcribe .. => .transcribe
  | .transcribeChunk .. => .chunk
  | .save .. => .save
  | .markTyped _ => .markTyped
  | .type .. => .type
  | .play _ => .play
  | .wakeAt _ => .wakeAt
  | .listDays => .listDays
  | .deleteDays _ => .deleteDays
  | .loadRecent _ => .loadRecent
  | .copy _ => .copy
  | .overlay .. => .overlay
  | .open _ => .opens

/-- Every command in `cs` is of one of the kinds `ks`. -/
def Kinds (ks : List Kind) (cs : List Cmd) : Prop := ∀ c ∈ cs, c.kind ∈ ks

namespace Kinds

theorem nil {ks : List Kind} : Kinds ks [] := by simp [Kinds]

theorem append {ks : List Kind} {a b : List Cmd} (ha : Kinds ks a) (hb : Kinds ks b) :
    Kinds ks (a ++ b) := by
  intro c hc
  rcases List.mem_append.1 hc with h | h
  · exact ha c h
  · exact hb c h

theorem mono {ks ks' : List Kind} {cs : List Cmd} (h : Kinds ks cs) (hs : ∀ k ∈ ks, k ∈ ks') :
    Kinds ks' cs := fun c hc => hs _ (h c hc)

/-- No command of kind `k`. -/
theorem not_mem {ks : List Kind} {cs : List Cmd} (h : Kinds ks cs) {k : Kind} (hk : k ∉ ks)
    {c : Cmd} (hc : c ∈ cs) : c.kind ≠ k := fun he => hk (he ▸ h c hc)

end Kinds

/-- Close a `Kinds` goal over literal lists, after splitting `if`s and `match`es. -/
macro "kinds" : tactic =>
  `(tactic| (try dsimp only) <;> (repeat' (split <;> try dsimp only)) <;> first
    | exact Kinds.nil
    | (simp [Kinds, Cmd.kind]; done)
    | skip)

theorem send_kinds (s : State) (r : Recording) :
    Kinds [.play, .stop, .overlay, .transcribe] (send s r).2 := by
  unfold send; kinds

theorem drop_kinds (s : State) (r : Recording) : Kinds [.stop, .overlay] (drop s r).2 := by
  unfold drop; kinds

theorem release_kinds (s : State) :
    Kinds [.play, .stop, .overlay, .transcribe, .wakeAt] (release s).2 := by
  unfold release
  try dsimp only
  repeat' (split <;> try dsimp only)
  all_goals first
    | exact Kinds.nil
    | with_reducible exact (send_kinds _ _).mono (by decide)
    | with_reducible exact (drop_kinds _ _).mono (by decide)
    | (simp [Kinds, Cmd.kind]; done)

/-- After a shortcut, the key's release only stops and hides. -/
theorem release_chorded_kinds (s : State) (h : s.chorded = true) :
    Kinds [.stop, .overlay] (release s).2 := by
  unfold release
  split
  · exact Kinds.nil
  · simp only [h, ite_true]
    split
    · exact Kinds.nil
    · exact drop_kinds _ _

theorem press_kinds (s : State) (f : Option Target) : Kinds [.start, .overlay, .wakeAt] (press s f).2 := by
  unfold press; kinds

theorem poll_kinds (s : State) (r : Recording) : Kinds [.overlay, .wakeAt, .chunk] (poll s r).2 := by
  unfold poll; kinds

theorem tick_kinds (s : State) :
    Kinds [.play, .stop, .overlay, .transcribe, .wakeAt, .chunk] (tick s).2 := by
  unfold tick
  try dsimp only
  repeat' (split <;> try dsimp only)
  all_goals first
    | exact Kinds.nil
    | with_reducible exact (send_kinds _ _).mono (by decide)
    | with_reducible exact (poll_kinds _ _).mono (by decide)

theorem audio_kinds (s : State) (c : Nat) (a : Audio) : Kinds [] (audio s c a).2 := by
  unfold audio; kinds

theorem micFailed_kinds (s : State) (c : Nat) (e : String) : Kinds [.overlay] (micFailed s c e).2 := by
  unfold micFailed; kinds

theorem keep_kinds (s : State) (t : Transcript) : Kinds [.save, .listDays] (keep s t).2 := by
  unfold keep; kinds

theorem typeIt_kinds (s : State) (c : ClipReq) (t : Transcript) : Kinds [.overlay, .type] (typeIt s c t).2 := by
  unfold typeIt; kinds

theorem transcribed_kinds (s : State) (c : ClipReq) (raw : String) :
    Kinds [.overlay, .save, .listDays, .type] (transcribed s c raw).2 := by
  unfold transcribed
  try dsimp only
  repeat' (split <;> try dsimp only)
  all_goals first
    | (simp [Kinds, Cmd.kind]; done)
    | with_reducible exact ((keep_kinds _ _).mono (by decide)).append ((typeIt_kinds _ _ _).mono (by decide))
    | with_reducible exact (keep_kinds _ _).mono (by decide)

theorem typedOk_kinds (s : State) (c : Nat) (t : Transcript) : Kinds [.markTyped, .overlay] (typedOk s c t).2 := by
  unfold typedOk; kinds

theorem typedFailed_kinds (s : State) (c : Nat) (t : Transcript) (e : String) :
    Kinds [.play, .overlay] (typedFailed s c t e).2 := by
  unfold typedFailed; kinds

theorem chunkDone_kinds (s : State) (c q : Nat) (t : Option String) :
    Kinds [.overlay, .wakeAt] (chunkDone s c q t).2 := by
  unfold chunkDone
  try dsimp only
  repeat' (split <;> try dsimp only)
  all_goals first
    | exact Kinds.nil
    | (simp [Kinds, Cmd.kind]; done)

theorem reply_kinds (s : State) (q : Nat) (x : Reply) :
    Kinds [.overlay, .save, .listDays, .type, .markTyped, .play, .wakeAt] (reply s q x).2 := by
  unfold reply
  try dsimp only
  repeat' (split <;> try dsimp only)
  all_goals first
    | exact Kinds.nil
    | (simp [Kinds, Cmd.kind]; done)
    | with_reducible exact (transcribed_kinds _ _ _).mono (by decide)
    | with_reducible exact (chunkDone_kinds _ _ _ _).mono (by decide)
    | with_reducible exact (typedOk_kinds _ _ _).mono (by decide)
    | with_reducible exact (typedFailed_kinds _ _ _ _).mono (by decide)

theorem cancel_kinds (s : State) : Kinds [.stop, .overlay] (cancel s).2 := by
  unfold cancel; kinds

theorem setKey_kinds (s : State) (k : Hotkey) :
    Kinds [.play, .stop, .overlay, .transcribe, .wakeAt, .listen] (setKey s k).2 := by
  unfold setKey
  split
  · exact Kinds.nil
  · split
    · refine Kinds.append ((release_kinds _).mono (by decide)) ?_
      simp [Kinds, Cmd.kind]
    · refine Kinds.append Kinds.nil ?_
      simp [Kinds, Cmd.kind]

theorem setKey_chorded_kinds (s : State) (k : Hotkey) (h : s.chorded = true) :
    Kinds [.stop, .overlay, .listen] (setKey s k).2 := by
  unfold setKey
  split
  · exact Kinds.nil
  · split
    · refine Kinds.append (ks := [.stop, .overlay, .listen]) ((release_chorded_kinds { s with keyHeld := false } h).mono (by decide)) ?_
      simp [Kinds, Cmd.kind]
    · refine Kinds.append Kinds.nil ?_
      simp [Kinds, Cmd.kind]

theorem applySettings_kinds (s : State) (cfg : Settings) {ks : List Kind}
    (h : ∀ k, Kinds ks (setKey { s with settings := cfg } k).2) : Kinds ks (applySettings s cfg).2 := by
  unfold applySettings
  split
  · exact Kinds.nil
  · exact h _

theorem configured_kinds (s : State) (r : ConfigRead) :
    Kinds [.play, .stop, .overlay, .transcribe, .wakeAt, .listen, .listDays, .loadRecent]
      (configured s r).2 := by
  unfold configured
  refine Kinds.append ?_ ?_
  · unfold readConfig
    split
    · exact Kinds.nil
    all_goals exact applySettings_kinds _ _ fun _ => (setKey_kinds _ _).mono (by decide)
  · split
    · simp [Kinds, Cmd.kind]
    · exact Kinds.nil

theorem configured_chorded_kinds (s : State) (r : ConfigRead) (h : s.chorded = true) :
    Kinds [.stop, .overlay, .listen, .listDays, .loadRecent] (configured s r).2 := by
  unfold configured
  refine Kinds.append ?_ ?_
  · unfold readConfig
    split
    · exact Kinds.nil
    all_goals exact applySettings_kinds _ _ fun k => (setKey_chorded_kinds _ k (by exact h)).mono (by decide)
  · split
    · simp [Kinds, Cmd.kind]
    · exact Kinds.nil

theorem menu_kinds (s : State) (m : MenuAction) :
    Kinds [.copy, .saveConfig, .storePrefs, .stop, .overlay, .opens] (menu s m).2 := by
  cases m <;> simp only [menu]
  case toggleEnabled =>
    split
    · simp [Kinds, Cmd.kind]
    · intro c hc
      rcases List.mem_cons.1 hc with rfl | h
      · simp [Cmd.kind]
      · exact (cancel_kinds _).mono (by decide) c h
  all_goals kinds

/-- The kinds of command each input can lead to. -/
def stepKinds : Input → List Kind
  | .launch _ => [.listen, .readConfig, .readDictionary]
  | .keyDown .. => [.start, .overlay, .wakeAt]
  | .keyUp _ => [.play, .stop, .overlay, .transcribe, .wakeAt]
  | .otherKey => []
  | .tick _ => [.play, .stop, .overlay, .transcribe, .wakeAt, .chunk]
  | .audio .. => []
  | .micFailed .. => [.overlay]
  | .reply .. => [.overlay, .save, .listDays, .type, .markTyped, .play, .wakeAt]
  | .config _ => [.play, .stop, .overlay, .transcribe, .wakeAt, .listen, .listDays, .loadRecent]
  | .dictionary _ => []
  | .transcriptDays .. => [.deleteDays]
  | .recentLoaded _ => []
  | .trust _ => []
  | .menu _ => [.copy, .saveConfig, .storePrefs, .stop, .overlay, .opens]

theorem step_kinds (s : State) (i : Input) : Kinds (stepKinds i) (step s i).2 := by
  cases i <;> simp only [step, stepKinds]
  case keyDown => split; exact Kinds.nil; exact press_kinds _ _
  case keyUp => split; exact release_kinds _; exact Kinds.nil
  case otherKey => split <;> exact Kinds.nil
  case tick => exact tick_kinds _
  case audio => exact audio_kinds _ _ _
  case micFailed => exact micFailed_kinds _ _ _
  case reply => exact reply_kinds _ _ _
  case config => exact configured_kinds _ _
  case menu => exact menu_kinds _ _
  case transcriptDays => split <;> simp [Kinds, Cmd.kind]
  all_goals simp [Kinds, Cmd.kind]

/-- A command of kind `k` from input `i` means `k` is one of `i`'s kinds. -/
theorem kind_of_step {s : State} {i : Input} {c : Cmd} (hc : c ∈ (step s i).2) :
    c.kind ∈ stepKinds i := step_kinds s i c hc

/-! ## A shortcut never sends -/

/-- **A key used in a shortcut never sends.** While the dictation key is down and another key
has gone down with it, nothing the host reports (its release, a key change in `config.json`,
a reply, the menu) asks for a clip to be transcribed. Only the clock can, through the
10-minute limit of a hands-free recording that started earlier. -/
theorem shortcut_never_sends (s : State) (i : Input) (hk : s.keyHeld = true)
    (hc : s.chorded = true) (ht : ∀ t, i ≠ .tick t) :
    ∀ c ∈ (step s i).2, c.kind ≠ .transcribe := by
  intro c h
  cases i with
  | keyDown t f => simp [step, hk] at h
  | keyUp t =>
    simp only [step, hk, ite_true] at h
    exact (release_chorded_kinds _ (by exact hc)).not_mem (by decide) h
  | tick t => exact absurd rfl (ht t)
  | config r => exact (configured_chorded_kinds _ _ hc).not_mem (by decide) h
  | _ => exact (step_kinds _ _).not_mem (by simp [stepKinds]) h

/-! ## Hold or tap -/

theorem send_recording (s : State) (r : Recording) : (send s r).1.recording = none := by
  unfold send; repeat' (split <;> try rfl)

theorem send_now (s : State) (r : Recording) : (send s r).1.now = s.now := by
  unfold send; repeat' (split <;> try rfl)

/-- **The hold/tap split is exactly 300 ms.** Releasing the key ends a press it began (not
after a shortcut): held under 300 ms, the recording latches hands free and will send itself
10 minutes later; held 300 ms or more, it is sent (the recording ends). -/
theorem hold_tap_split (s : State) (r : Recording) (t : Ms) (hr : s.recording = some r)
    (hl : r.latched = false) (hk : s.keyHeld = true) (hc : s.chorded = false) :
    (step s (.keyUp t)).1.recording =
      if max s.now t - s.pressedAt < tapLimit then
        some { r with latched := true, deadline := max s.now t + latchLimit }
      else none := by
  simp only [step, hk, ite_true, release, hr, hc, hl, Bool.not_false, Bool.true_and,
    Bool.false_eq_true, ↓reduceIte, decide_eq_true_eq]
  split
  · rfl
  · exact send_recording _ _

/-! ## Ten minutes hands free -/

/-- The preview's poll keeps the recording, changing neither its clip nor its latch. -/
theorem poll_recording (s : State) (r : Recording) :
    ∃ r', (poll s r).1.recording = some r' ∧ r'.clip = r.clip ∧ r'.latched = r.latched ∧
      r'.deadline = r.deadline := by
  unfold poll; dsimp only
  repeat' (split <;> try dsimp only)
  all_goals exact ⟨_, rfl, rfl, rfl, rfl⟩

theorem poll_recording_ne (s : State) (r : Recording) : (poll s r).1.recording ≠ none := by
  obtain ⟨r', h', -⟩ := poll_recording s r
  simp [h']

/-- **A hands-free recording sends itself at its deadline, and the clock alone doesn't end it
before.** -/
theorem latch_deadline (s : State) (r : Recording) (t : Ms) (hr : s.recording = some r)
    (hl : r.latched = true) :
    (step s (.tick t)).1.recording = none ↔ r.deadline ≤ max s.now t := by
  simp only [step, tick, hr, hl, true_and]
  split
  · simp only [send_recording, true_iff]; assumption
  · rename_i h
    simp only [h, iff_false]
    split
    · exact poll_recording_ne _ _
    · simp

/-! ## Retention -/

/-- **Retention never deletes today's file**: the only deletions are of reported day files
before today. -/
theorem retention_never_today (s : State) (i : Input) (ds : List Nat)
    (h : Cmd.deleteDays ds ∈ (step s i).2) :
    ∃ today days, i = .transcriptDays today days ∧ today ∉ ds ∧ ∀ d ∈ ds, d ∈ days ∧ d < today := by
  cases i with
  | transcriptDays today days =>
    refine ⟨today, days, rfl, ?_⟩
    simp only [step] at h
    split at h
    · simp at h
    · simp only [List.mem_singleton, Cmd.deleteDays.injEq] at h
      subst h
      exact ⟨today_not_deleted _ _ _, fun d hd => ⟨(mem_daysToDelete.1 hd).1, daysToDelete_lt hd⟩⟩
  | _ => exact absurd rfl ((step_kinds _ _).not_mem (by simp [stepKinds, Cmd.kind]) h)

end Examples.Yap

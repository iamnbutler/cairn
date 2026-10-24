module

public import Examples.Yap.Proofs

/-! # Yap: the recent list holds five -/

@[expose] public section

namespace Examples.Yap

/-- The recent list holds at most five transcripts. -/
def Small (s : State) : Prop := s.recent.length ≤ recentLimit

/-- Close `Small` goals for parts of the machine that keep the recent list as it is. -/
macro "small" h:term : tactic =>
  `(tactic| ((try dsimp only) <;> (repeat' split) <;> first | exact $h | skip))

theorem send_small (s : State) (r : Recording) (h : Small s) : Small (send s r).1 := by
  unfold send; small h

theorem release_small (s : State) (h : Small s) : Small (release s).1 := by
  unfold release; dsimp only
  split
  · exact h
  · split
    · split
      · exact h
      · exact h
    · split
      · exact h
      · exact send_small _ _ h

theorem press_small (s : State) (f : Option Target) (h : Small s) : Small (press s f).1 := by
  unfold press; small h

theorem stepKey_small (s : State) (k : Key) (h : Small s) : Small (stepKey s k).1 := by
  cases k with
  | down t f =>
    simp only [stepKey]; split
    · exact h
    · exact press_small { s with now := max s.now t, keyHeld := true } f h
  | up t =>
    simp only [stepKey]; split
    · exact release_small { s with now := max s.now t, keyHeld := false } h
    · exact h
  | other => simp only [stepKey]; split <;> exact h

theorem drain_small (s : State) (ks : List Key) (h : Small s) : Small (drain s ks).1 := by
  induction ks generalizing s with
  | nil => exact h
  | cons k ks ih =>
    simp only [drain]
    split
    · exact ih _ (stepKey_small s k h)
    · exact stepKey_small s k h

theorem tickRec_small (s : State) (h : Small s) : Small (tickRec s).1 := by
  unfold tickRec
  split
  · exact h
  · split
    · split
      · exact h
      · exact h
    · split
      · exact send_small _ _ h
      · split
        · unfold poll; small h
        · exact h

theorem tick_small (s : State) (h : Small s) : Small (tick s).1 := by
  unfold tick
  split
  · exact tickRec_small _ h
  · exact tickRec_small _ (drain_small { s with keys := [] } _ h)

theorem micStarted_small (s : State) (c : Nat) (h : Small s) : Small (micStarted s c).1 := by
  unfold micStarted
  split
  · split
    · exact drain_small _ _ h
    · exact h
  · exact h

theorem keyIn_small (s : State) (k : Key) (h : Small s) : Small (keyIn s k).1 := by
  unfold keyIn; split
  · exact h
  · exact stepKey_small _ _ h

theorem keep_small (s : State) (t : Transcript) : Small (keep s t).1 := by
  unfold keep; dsimp only; split <;> exact remember_length _ _

theorem transcribed_small (s : State) (c : ClipReq) (raw : String) (h : Small s) :
    Small (transcribed s c raw).1 := by
  unfold transcribed; dsimp only
  split
  · exact h
  · split
    · exact keep_small _ _
    · exact keep_small _ _

theorem reply_small (s : State) (q : Nat) (x : Reply) (h : Small s) : Small (reply s q x).1 := by
  unfold reply
  split
  · exact h
  · dsimp only
    split
    · exact transcribed_small _ _ _ h
    · exact h
    · unfold chunkDone; small h
    · unfold chunkDone; small h
    · simp only [Small, typedOk, setTyped, List.length_map]; exact h
    · exact remember_length _ _
    all_goals exact h

theorem setKey_small (s : State) (k : Hotkey) (h : Small s) : Small (setKey s k).1 := by
  unfold setKey
  split
  · exact h
  · dsimp only
    split
    · exact h
    · split
      · exact release_small { s with keyHeld := false } h
      · exact h

theorem configured_small (s : State) (c : ConfigRead) (h : Small s) : Small (configured s c).1 := by
  unfold configured readConfig
  dsimp only
  split
  · exact h
  all_goals
    unfold applySettings
    dsimp only
    split
    · exact h
    · split
      · exact setKey_small _ _ h
      · exact setKey_small _ _ h

theorem menu_small (s : State) (m : MenuAction) (h : Small s) : Small (menu s m).1 := by
  cases m <;> simp only [menu]
  all_goals small h

/-- **The recent list never holds more than five transcripts.** -/
theorem step_small (s : State) (i : Input) (h : Small s) : Small (step s i).1 := by
  cases i with
  | keyDown t f => exact keyIn_small _ _ h
  | keyUp t => exact keyIn_small _ _ h
  | otherKey => exact keyIn_small _ _ h
  | micStarted c t => exact micStarted_small _ _ h
  | tick t => exact tick_small { s with now := max s.now t } h
  | audio c a => unfold step audio; small h
  | micFailed c e => unfold step micFailed; small h
  | reply q x => exact reply_small _ _ _ h
  | config c => exact configured_small _ _ h
  | menu m => exact menu_small _ _ h
  | recentLoaded ts => simp only [step, Small, List.length_take]; exact Nat.min_le_left _ _
  | transcriptDays => exact h
  | keyLost => simp only [step, keyLost]; split <;> simp only [drop] <;> exact h
  | _ => exact h

end Examples.Yap

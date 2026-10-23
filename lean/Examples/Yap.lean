module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Examples.Yap.Model
public import Examples.Yap.Proofs
public import Examples.Yap.Sending
public import Examples.Yap.Recording
public import Examples.Yap.Once
public import Examples.Yap.Recent

/-! # Yap: the dictation machine's claims

Workstream P, step 1a of M2 (GOAL.md): Yap (`~/code/yap`) as a headless model,
`Examples.Yap.step : State → Input → State × List Cmd`, with its claims proved. No view and no
host yet. What is modelled, what is assumed of the host, and where the model differs from
Swift Yap are in `Examples/Yap/README.md`.

The claim commands only know machines driven by `Action`s on controls, and Yap is driven by the
host: the key, the clock, replies. So the menu items are `move`s over `menu` (their `Cmd`s, other
than copying, are dropped until the framework has effects for them), and everything about
dictation is an `invariant` whose `holds` quantifies over every host input (`∀ i`) or every
sequence of host inputs (`∀ is`), so it is a statement about `step` itself.

| Id | Kind | What |
|---|---|---|
| ^301 | place | the menu bar menu |
| ^302–^310 | move | the menu items (^303 keyed by position) |
| ^311 | invariant | a shortcut never sends |
| ^312 | invariant | the hold/tap split is exactly 300 ms |
| ^313 | invariant | one recording at a time |
| ^314 | invariant | every recording ends: ten minutes after the key is up |
| ^315 | invariant | a transcript is kept (and saved) before it is typed |
| ^316 | invariant | a failed type stays recoverable and flagged |
| ^317 | invariant | only an uncancelled transcription in flight can type |
| ^318 | invariant | each clip is typed at most once |
| ^319 | invariant | what is typed is the transcript with fixes on whole words |
| ^320 | invariant | retention never deletes today |
| ^321 | invariant | only the first 25 dictionary terms are sent |
| ^322 | invariant | the recent list holds five |
| ^323 | invariant | too short, silent or nowhere to type: never sent |
| ^330–^337 | assume | what the host does |
| ^340, ^341 | flow | through the menu | -/

@[expose] public section

namespace Examples.Yap
open Cairn Cairn.Claims

/-! ## The menu -/

place ^301 menuBar "Menu bar menu" where
  does "Yap's menu bar menu: the status line, Copy Last Transcript, Recent Transcripts, Keep Transcripts, Press Return After Dictating, Dictate with Key, Open Transcripts Folder, Edit Dictionary, Edit Settings, and Grant Accessibility Access while it is missing."

move ^302 copyLast (s : State) "Copy Last Transcript" in ^301 where
  does "Choose Copy Last Transcript."
  sees "The newest transcript is on the clipboard, typed or not. Nothing else changes."
  enabled := !s.recent.isEmpty
  on press
    emit := (s, match s.recent with
      | t :: _ => [.setClipboard t.text]
      | [] => [])
    post s' := s' = s
    sound := by intro s _; rfl

move ^303 copyRecent (s : State) (k : Nat) "Recent transcript" in ^301 where
  does "Choose a transcript under Recent Transcripts (the newest first, five at most)."
  sees "That transcript is on the clipboard. Nothing else changes."
  enabled := decide (k < s.recent.length)
  on press
    emit := (s, match s.recent[k]? with
      | some t => [.setClipboard t.text]
      | none => [])
    post s' := s' = s
    sound := by intro s k _; rfl

move ^304 toggleKeep (s : State) "Keep Transcripts" in ^301 where
  does "Choose Keep Transcripts."
  sees "The setting flips and is written to config.json; the recording and the recent list are untouched."
  on press
    apply := (menu s .toggleKeep).1
    post s' := s'.settings.keepTranscripts = !s.settings.keepTranscripts ∧
      s'.recording = s.recording ∧ s'.recent = s.recent
    sound := by intro s; exact ⟨rfl, rfl, rfl⟩

move ^305 toggleSubmits (s : State) "Press Return After Dictating" in ^301 where
  does "Choose Press Return After Dictating, available while Dictate with Key is on."
  sees "The setting flips: transcripts sent from now on end with Return instead of a space."
  enabled := s.enabled
  on press
    apply := (menu s .toggleSubmits).1
    post s' := s'.submits = !s.submits ∧ s'.recording = s.recording
    sound := by intro s h; simp only [enabled] at h; simp [press.post, press.apply, menu, h]

move ^306 toggleEnabled (s : State) "Dictate with Key" in ^301 where
  does "Choose Dictate with Key."
  sees "The setting flips. Turning it off cancels: the recording stops, and a transcript still on its way is kept but not typed."
  on press
    apply := (menu s .toggleEnabled).1
    post s' := s'.enabled = !s.enabled ∧
      (s.enabled = true → s'.recording = none ∧ s'.turn = s.turn + 1)
    sound := by intro s; cases h : s.enabled <;> simp [press.post, press.apply, menu, h, cancel]

move ^307 openTranscripts (s : State) "Open Transcripts Folder" in ^301 where
  does "Choose Open Transcripts Folder."
  sees "The folder of day files opens in the Finder. Nothing in Yap changes."
  on press
    apply := s
    post s' := s' = s
    sound := by intro s; rfl

move ^308 editDictionary (s : State) "Edit Dictionary" in ^301 where
  does "Choose Edit Dictionary."
  sees "dictionary.txt opens in the default editor; Yap reads it again when it changes."
  on press
    apply := s
    post s' := s' = s
    sound := by intro s; rfl

move ^309 editSettings (s : State) "Edit Settings" in ^301 where
  does "Choose Edit Settings."
  sees "config.json opens in the default editor; Yap reads it again when it changes."
  on press
    apply := s
    post s' := s' = s
    sound := by intro s; rfl

move ^310 grantAccess (s : State) "Grant Accessibility Access" in ^301 where
  does "Choose Grant Accessibility Access, shown while Yap can't type."
  sees "System Settings opens at Accessibility."
  enabled := !s.trusted
  on press
    apply := s
    post s' := s' = s
    sound := by intro s _; rfl

/-- Yap's menu: its moves, from launch. The host's inputs are `step`'s, not the machine's. -/
def machine : Machine State := { init := init, moves := moves% }

/-- What every menu item keeps, every move keeps. -/
theorem machine_preserves {P : State → Prop} (h : ∀ s m, P s → P (menu s m).1) :
    ∀ s a, P s → P (machine.update s a).1 :=
  machine.preserves <|
    Move.all_cons (copyLast.preserves _ fun _ _ hs => hs)
    (Move.all_cons (copyRecent.preserves _ fun _ _ _ hs => hs)
    (Move.all_cons (toggleKeep.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (toggleSubmits.preserves _ fun s _ hs => h s _ hs)
    (Move.all_cons (toggleEnabled.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (openTranscripts.preserves _ fun _ hs => hs)
    (Move.all_cons (editDictionary.preserves _ fun _ hs => hs)
    (Move.all_cons (editSettings.preserves _ fun _ hs => hs)
    (Move.all_cons (grantAccess.preserves _ fun _ _ hs => hs) Move.all_nil))))))))

/-! ## Dictation -/

invariant ^311 shortcutNeverSends "A shortcut never sends" for machine where
  does "While the dictation key is held and another key has gone down with it (a shortcut such as the key plus C), nothing the host reports sends a clip for transcription: not the key's release, not a new key in config.json, not a reply or the menu. Only the clock can, for a hands-free recording that hits its ten-minute limit (`shortcut_never_sends`)."
  holds s := ∀ i, s.keyHeld = true → s.chorded = true → (∀ t, i ≠ .tick t) →
    ∀ c ∈ (step s i).2, c.kind ≠ .transcribe
  init := fun i => shortcut_never_sends _ i
  step := fun _ _ _ i => shortcut_never_sends _ i

invariant ^312 holdTapSplit "Hold to talk, tap to latch: 300 ms" for machine where
  does "Releasing the key ends a press that began a recording, not part of a shortcut: held for less than 300 ms it was a tap, and the recording goes on hands free with its deadline ten minutes on; held 300 ms or more, the recording ends and is sent (`hold_tap_split`)."
  holds s := ∀ r t, s.recording = some r → r.latched = false → s.keyHeld = true →
    s.chorded = false →
    (step s (.keyUp t)).1.recording =
      if max s.now t - s.pressedAt < tapLimit then
        some { r with latched := true, deadline := max s.now t + latchLimit }
      else none
  init := fun r t => hold_tap_split _ r t
  step := fun _ _ _ r t => hold_tap_split _ r t

invariant ^313 oneRecording "One recording at a time" for machine where
  does "The host is asked to start a recording only when none is in progress, and always a new clip; a recording leaves the model only when the host is told to stop it, or reported that its microphone failed (`step_start`, `step_ends`)."
  holds s := (∀ i n, Cmd.startRecording n ∈ (step s i).2 →
      s.recording = none ∧ n = s.nextClip ∧ (step s i).1.recording.map (·.clip) = some n ∧
        (step s i).1.nextClip = n + 1) ∧
    (∀ i r, s.recording = some r →
      (step s i).1.recording.map (·.clip) = some r.clip ∨
        Cmd.stopRecording r.clip ∈ (step s i).2 ∨ ∃ e, i = .micFailed r.clip e)
  init := ⟨fun i _ h => step_start _ i h, fun i r h => step_ends _ i r h⟩
  step := fun _ _ _ => ⟨fun i _ h => step_start _ i h, fun i r h => step_ends _ i r h⟩

invariant ^314 recordingEnds "Every recording ends" for machine where
  does "A recording is either held down or hands free with its deadline at most ten minutes away; so once the key is up and ten minutes pass (the host delivering the tick it asked for), there is no recording. A recording held down has no limit, as in Swift Yap (`step_recInv`, `recording_ends`)."
  holds s := RecInv s ∧ ∀ t, s.now ≤ t → (run s [.keyUp t, .tick (t + latchLimit)]).recording = none
  init := ⟨recInv_init, recording_ends _ recInv_init⟩
  step := machine_preserves fun s m h =>
    have h' := h.1.calm (menu_calm s m)
    ⟨h', recording_ends _ h'⟩

invariant ^315 keptBeforeTyped "Kept before it is typed" for machine where
  does "When Yap types a transcript, it is already first in Recent Transcripts, marked not yet typed, and when transcripts are kept the command saving it to today's file comes before the command typing it (`saved_before_typed`). Swift Yap saves after typing; see the README."
  holds s := ∀ i a n pid text ret, Cmd.type a n pid text ret ∈ (step s i).2 →
    ∃ t ∈ (step s i).1.recent, t.clip = some n ∧ t.typed = false ∧
      ∃ pre post, (step s i).2 = pre ++ Cmd.type a n pid text ret :: post ∧
        (s.settings.keepTranscripts = true → ∃ r, Cmd.save r t ∈ pre)
  init := fun i _ _ _ _ _ h => saved_before_typed _ i h
  step := fun _ _ _ i _ _ _ _ _ h => saved_before_typed _ i h

invariant ^316 failedTypeFlagged "A failed type is kept and flagged" for machine where
  does "When typing fails, the transcript is first in Recent Transcripts (so Copy Last Transcript copies it), marked as never having reached its app, and the error sound plays (`failed_type_flagged`)."
  holds s := ∀ q c t e, s.reqs.lookup q = some (.type c t) →
    (step s (.reply q (.failed e))).1.recent.head? = some { t with typed := false } ∧
      Cmd.play .basso ∈ (step s (.reply q (.failed e))).2
  init := fun q c t e h => failed_type_flagged _ q c t e h
  step := fun _ _ _ q c t e h => failed_type_flagged _ q c t e h

invariant ^317 onlyLiveRepliesType "Late and cancelled replies never type" for machine where
  does "Only a reply to a whole-clip transcription that is still in flight, and was not cancelled since it was sent, types anything; a duplicate, a reply to something else, or a reply after Dictate with Key was turned off types nothing (`late_reply_never_types`)."
  holds s := ∀ i a n pid text ret, Cmd.type a n pid text ret ∈ (step s i).2 →
    ∃ q x cr, i = .reply q x ∧ (q, Req.clip cr) ∈ s.reqs ∧ cr.clip = n ∧ cr.turn = s.turn
  init := fun i _ _ _ _ _ h => late_reply_never_types _ i h
  step := fun _ _ _ i _ _ _ _ _ h => late_reply_never_types _ i h

invariant ^318 typedOnce "Each clip is typed at most once" for machine where
  does "Along every sequence of host inputs, however replies arrive (late, twice, out of order, or never), no clip's transcript is typed twice (`typed_once`, `typed_once_from`)."
  holds s := ∀ is n, (typedClips (exec s is).2).count n ≤ 1
  init := typed_once
  step := machine_preserves fun s m h is n => by
    have := h (.menu m :: is) n
    simp only [exec, typedClips_append, List.count_append] at this
    exact Nat.le_trans (Nat.le_add_left _ _) this

invariant ^319 wholeWordFixes "Fixes replace whole words" for machine where
  does "What is typed is the transcript with each dictionary fix applied to whole words only, case-insensitively, then trimmed, then a space (or Return) (`typed_text`, `replaceWord_replaces`)."
  holds s := ∀ i a n pid text ret, Cmd.type a n pid text ret ∈ (step s i).2 →
    ∃ q raw cr, i = .reply q (.ok raw) ∧ (q, Req.clip cr) ∈ s.reqs ∧
      ReplacesAll cr.fixes raw.toList (applyFixes cr.fixes raw).toList ∧
      text = (if cr.submits then trimText (applyFixes cr.fixes raw)
              else trimText (applyFixes cr.fixes raw) ++ " ")
  init := fun i _ _ _ _ _ h => typed_text _ i h
  step := fun _ _ _ i _ _ _ _ _ h => typed_text _ i h

invariant ^320 retentionKeepsToday "Retention never deletes today" for machine where
  does "The only day files deleted are ones the host listed that are older than today; today's is never deleted, whatever retentionDays says (`retention_never_today`)."
  holds s := ∀ i ds, Cmd.deleteDays ds ∈ (step s i).2 →
    ∃ today days, i = .transcriptDays today days ∧ today ∉ ds ∧ ∀ d ∈ ds, d ∈ days ∧ d < today
  init := fun i _ h => retention_never_today _ i _ h
  step := fun _ _ _ i _ h => retention_never_today _ i _ h

invariant ^321 first25Terms "Only the first 25 terms are sent" for machine where
  does "Every prompt sent with a transcription, of a whole clip or a preview chunk, is the one a dictionary of just its first 25 terms would give (`step_prompt`)."
  holds s := ∀ i c p, c ∈ (step s i).2 → c.prompt? = some p →
    ∃ ctx, p = { s.dict with terms := s.dict.terms.take promptLimit }.promptFor ctx
  init := fun i _ _ h hp => step_prompt _ i h hp
  step := fun _ _ _ i _ _ h hp => step_prompt _ i h hp

invariant ^322 recentFive "Recent Transcripts holds five" for machine where
  does "The recent list never holds more than five transcripts (`step_small`)."
  holds s := s.recent.length ≤ recentLimit
  init := Nat.zero_le _
  step := machine_preserves fun s m h => menu_small s m h

invariant ^323 onlySendable "Too short, silent or nowhere to type: never sent" for machine where
  does "Every whole-clip transcription asked for is of the recording in progress, at least 0.3 s long, with a sample at or above the silence peak, and with an app to type into (`step_transcribe`)."
  holds s := ∀ i q n m p, Cmd.transcribe q n m p ∈ (step s i).2 →
    ∃ r, s.recording = some r ∧ Sendable s.dict r n p
  init := fun i _ _ _ _ h => step_transcribe _ i h
  step := fun _ _ _ i _ _ _ _ h => step_transcribe _ i h

/-! ## What the host does -/

assume ^330 hostKeys "The host reports the dictation key and every other key" where
  does "The host reports the dictation key going down and up, once each per press, with its monotonic clock in milliseconds, and reports every other key that goes down while the dictation key is held, before the dictation key's release. Key repeats are not reported as presses."

assume ^331 hostTicks "The host delivers the ticks it is asked for" where
  does "After `wakeAt t`, the host sends a `tick` with a time at or after `t`, while the app runs. Ticks may come late, early ones are ignored, and the clock may jump."

assume ^332 hostRequests "The host answers requests by id, in order of commands" where
  does "The host runs a step's commands in the order given, and a reply carries the id of the request it answers. Replies may be slow, fail, come out of order, twice, or never."

assume ^333 hostAudio "The host reports the microphone faithfully" where
  does "Audio reports name the clip they belong to and come between its start and stop; frames and peak are of the 16 kHz mono samples since the last report, and windows are the 320-sample windows those samples complete, counted from the start of the clip. A microphone that fails to start is reported once as `micFailed`."

assume ^334 hostTranscribes "The host transcribes the samples it was asked for" where
  does "A transcription reply's text is the transcript of the whole clip (or of the samples asked for), from the model asked for, with the prompt given."

assume ^335 hostTypes "The host types into the app it was given" where
  does "The host brings the app with the given process forward and types the text, then Return if asked; it replies failed when it can't (no Accessibility access, the app is gone), and ok only when the text was typed."

assume ^336 hostFiles "The host reports config.json and dictionary.txt when they change" where
  does "After `readConfig` and `readDictionary`, the host reports each file's contents now and whenever it changes, decoding config.json's fields (a field left out is none) and reporting a file that won't parse as unreadable."

assume ^337 hostDays "The host lists day files and today by the local calendar" where
  does "After `listDays`, the host reports today's day number and the day files there are, as day numbers on the same calendar, and deletes exactly the files named by `deleteDays`."

/-! ## Flows -/

flow ^340 turnOff "Turn Dictate with Key off" for machine where
  does "Choose Dictate with Key."
  sees "Dictation is off, Press Return After Dictating is unavailable, and nothing is recording."
  goal s := s.enabled = false ∧ toggleSubmits.enabled s = false ∧ s.recording = none
  witness press ^306

flow ^341 keepTwice "Keep Transcripts off and on again" for machine where
  does "Choose Keep Transcripts twice."
  sees "Transcripts are kept again, after two writes of config.json."
  goal s := s.settings.keepTranscripts = true ∧ s.reqs.length = 2
  witness press ^304, press ^304

/-- Every claim Yap makes. -/
def claimInfos : List ClaimInfo := claims%

end Examples.Yap

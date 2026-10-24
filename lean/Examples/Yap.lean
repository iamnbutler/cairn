module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Examples.Yap.Model
public import Examples.Yap.Proofs
public import Examples.Yap.Sending
public import Examples.Yap.Recording
public import Examples.Yap.Once
public import Examples.Yap.Recent
public import Examples.Yap.App
public import Examples.Yap.View
public import Examples.Yap.AppProofs
public import Examples.Yap.MarkProofs

/-! # Yap on Cairn: the app and its claims

Workstream P made Yap (`~/code/yap`) a headless machine, `Examples.Yap.step : State → Input →
State × List Cmd`, and proved its claims of `step`. Workstream W (M2 step 3) runs that machine
as a Cairn app: `AppState` is the machine's state, the app's own bookkeeping (`Io`: pending
requests, the clock, the overlay) and the log of clips typed so far. The host's events arrive
through `receive` (`Examples.Yap.App`), which turns each into at most one machine input and
translates the machine's commands into framework effects. The menu items are moves over
`menuStep`, the menu run the same way.

So the dictation claims are now statements about what reaches the host: `receive`'s effects
and the app's state, in every state, and the ones about state are invariants of the app's
machine, carried through the runtime by `steps_reachableAll` (`Examples.Yap.AppProofs` and the
theorems at the end of this file).

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
| ^340, ^341 | flow | through the menu |
| ^342 | move | Quit |
| ^343 | move | grant the microphone |
| ^344 | move | open the menu |
| ^345 | retired | was the overlay panel with a bar waveform and four lines |
| ^346 | invariant | the key is left alone while the original Yap runs |
| ^347 | invariant | a typed transcript is marked on disk only after its append is answered ok |
| ^399 | place | the overlay panel, as the original's | -/

@[expose] public section

namespace Examples.Yap
open Cairn Cairn.Claims

/-! ## The menu -/

place ^301 menuBar "Menu bar menu" where
  does "Yap's menu bar menu: the status line, Copy Last Transcript, Recent Transcripts, Keep Transcripts, Press Return After Dictating, Dictate with Key, Open Transcripts Folder, Edit Dictionary, Edit Settings, and Grant Accessibility Access while it is missing."

retire ^345 place "Overlay panel" because "The overlay is now the original's, one to one (^399): the tape display instead of a bar waveform, and the transcript's last 280 characters instead of its last four lines."

place ^399 overlayPanel "Overlay panel" where
  does "Yap's panel at the bottom of the screen, over every app, that never takes focus or clicks, drawn as the original's: the phase (REC, hands free, transcribing, typed, not typed) with a glowing dot and a clock that stops when recording does, the tape (the original's shader: the scope, the ruler, the reel and the meter, from the microphone's levels and the preview's cuts) and the live transcript's last 280 characters. Hidden 1.5 s after a transcript is typed and 4 s after one fails."

move ^302 copyLast (s : AppState) "Copy Last Transcript" in ^301 where
  does "Choose Copy Last Transcript."
  sees "The newest transcript is on the clipboard, typed or not. Nothing else changes."
  enabled := !s.core.recent.isEmpty
  on press
    emit := (s, match s.core.recent with
      | t :: _ => [.setClipboard t.text]
      | [] => [])
    post s' := s' = s
    sound := by intro s _; rfl

move ^303 copyRecent (s : AppState) (k : Nat) "Recent transcript" in ^301 where
  does "Choose a transcript under Recent Transcripts (the newest first, five at most)."
  sees "That transcript is on the clipboard. Nothing else changes."
  enabled := decide (k < s.core.recent.length)
  on press
    emit := (s, match s.core.recent[k]? with
      | some t => [.setClipboard t.text]
      | none => [])
    post s' := s' = s
    sound := by intro s k _; rfl

move ^304 toggleKeep (s : AppState) "Keep Transcripts" in ^301 where
  does "Choose Keep Transcripts."
  sees "The setting flips and is written to config.json; the recording and the recent list are untouched."
  on press
    emit := menuStep s .toggleKeep
    post s' := s'.core.settings.keepTranscripts = !s.core.settings.keepTranscripts ∧
      s'.core.recording = s.core.recording ∧ s'.core.recent = s.core.recent
    sound := by intro s; exact ⟨rfl, rfl, rfl⟩

move ^305 toggleSubmits (s : AppState) "Press Return After Dictating" in ^301 where
  does "Choose Press Return After Dictating, available while Dictate with Key is on."
  sees "The setting flips: transcripts sent from now on end with Return instead of a space."
  enabled := s.core.enabled
  on press
    emit := menuStep s .toggleSubmits
    post s' := s'.core.submits = !s.core.submits ∧ s'.core.recording = s.core.recording
    sound := by
      intro s h
      simp only [enabled] at h
      simp [press.post, press.emit, menuStep_core, menu, h]

move ^306 toggleEnabled (s : AppState) "Dictate with Key" in ^301 where
  does "Choose Dictate with Key."
  sees "The setting flips. Turning it off cancels: the recording stops, and a transcript still on its way is kept but not typed."
  on press
    emit := menuStep s .toggleEnabled
    post s' := s'.core.enabled = !s.core.enabled ∧
      (s.core.enabled = true → s'.core.recording = none ∧ s'.core.turn = s.core.turn + 1)
    sound := by
      intro s
      simp only [press.post, press.emit, menuStep_core]
      cases h : s.core.enabled <;> simp [menu, h, cancel]

move ^307 openTranscripts (s : AppState) "Open Transcripts Folder" in ^301 where
  does "Choose Open Transcripts Folder."
  sees "The folder of day files opens in the Finder (made first if missing). Nothing in Yap changes."
  on press
    emit := menuStep s .openTranscripts
    post s' := s'.core = s.core
    sound := by intro s; rfl

move ^308 editDictionary (s : AppState) "Edit Dictionary" in ^301 where
  does "Choose Edit Dictionary."
  sees "dictionary.txt opens in the default editor (written from Yap's template first if missing); Yap reads it again when it changes."
  on press
    emit := menuStep s .editDictionary
    post s' := s'.core = s.core
    sound := by intro s; rfl

move ^309 editSettings (s : AppState) "Edit Settings" in ^301 where
  does "Choose Edit Settings."
  sees "config.json opens in the default editor (written with the current settings first if missing); Yap reads it again when it changes."
  on press
    emit := menuStep s .editSettings
    post s' := s'.core = s.core
    sound := by intro s; rfl

move ^310 grantAccess (s : AppState) "Grant Accessibility Access" in ^301 where
  does "Choose Grant Accessibility Access, shown while Yap can't type."
  sees "System Settings opens at Accessibility."
  enabled := !s.core.trusted
  on press
    emit := menuStep s .grantAccess
    post s' := s'.core = s.core
    sound := by
      intro s _
      show (menu s.core .grantAccess).1 = s.core
      simp only [menu]; split <;> rfl

move ^342 quit (s : AppState) "Quit Yap (Cairn)" in ^301 where
  does "Choose Quit Yap (Cairn), or press ⌘Q with the menu open."
  sees "The menu bar item goes away; the app has quit, and any recording with it."
  on press
    emit := (s, [.quit])
    post s' := s' = s
    sound := by intro s; rfl

move ^343 grantMic (s : AppState) "Grant Microphone Access" in ^301 where
  does "Choose Grant Microphone Access, shown while the microphone is denied."
  sees "macOS asks for the microphone if it hasn't yet; otherwise nothing changes until it is granted in System Settings. Nothing in dictation changes."
  enabled := s.io.micGranted == some false
  on press
    emit :=
      let o := s.io.ask .micAsk (.permission .microphone true)
      ({ s with io := o.1 }, [Ask.effect o.2])
    post s' := s'.core = s.core ∧ s'.typed = s.typed
    sound := by intro s _; exact ⟨rfl, rfl⟩

move ^344 openMenu (s : AppState) "Open the menu" in ^301 where
  does "Click Yap's menu bar item."
  sees "The menu opens, and Yap checks again whether it has Accessibility and the microphone and whether the original Yap is running. Nothing in dictation changes."
  on press
    emit :=
      let o := checks s.io
      ({ s with io := o.1 }, o.2.map Ask.effect)
    post s' := s'.core = s.core ∧ s'.typed = s.typed
    sound := by intro s; exact ⟨rfl, rfl⟩

/-- Yap on Cairn: its moves, from launch, and `receive` for everything the host reports. -/
def machine : Machine AppState := { init := {}, moves := moves%, receive }

/-- What every menu item keeps, every move keeps: the menu, Quit, and the moves that only ask
the host something. -/
theorem machine_preserves {P : AppState → Prop} (h : ∀ s a, P s → P (menuStep s a).1)
    (hio : ∀ s io, P s → P { s with io }) :
    ∀ s a, P s → P (machine.update s a).1 :=
  machine.preserves <|
    Move.all_cons (copyLast.preserves _ fun _ _ hs => hs)
    (Move.all_cons (copyRecent.preserves _ fun _ _ _ hs => hs)
    (Move.all_cons (toggleKeep.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (toggleSubmits.preserves _ fun s _ hs => h s _ hs)
    (Move.all_cons (toggleEnabled.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (openTranscripts.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (editDictionary.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (editSettings.preserves _ fun s hs => h s _ hs)
    (Move.all_cons (grantAccess.preserves _ fun s _ hs => h s _ hs)
    (Move.all_cons (quit.preserves _ fun _ hs => hs)
    (Move.all_cons (grantMic.preserves _ fun s _ hs => hio s _ hs)
    (Move.all_cons (openMenu.preserves _ fun s hs => hio s _ hs) Move.all_nil)))))))))))

/-- A property of the machine's state and the typed log, kept by `step` and the menu, is kept by
every move and by `receive`. -/
theorem Keeps.machine {Q : State → List Nat → Prop} (hq : Keeps Q) :
    (∀ s a, Q s.core s.typed → Q (machine.update s a).1.core (machine.update s a).1.typed) ∧
      ∀ s m, Q s.core s.typed → Q (machine.receive s m).1.core (machine.receive s m).1.typed :=
  ⟨machine_preserves (P := fun s => Q s.core s.typed) (fun s a h => hq.menuStep s a h)
      (fun _ _ h => h),
    fun s m h => hq.receive s m h⟩

/-! ## Dictation -/

invariant ^311 shortcutNeverSends "A shortcut never sends" for machine where
  does "While the dictation key is held and another key has gone down with it (a shortcut such as the key plus C), nothing the host reports leads to a clip's upload for transcription: not the key's release, not a new key in config.json, not a reply, and never the menu. Only the clock (or a timer) can, for a hands-free recording that hits its ten-minute limit (`app_shortcut_never_sends`, `shortcut_never_sends`)."
  holds s := (s.core.keyHeld = true → s.core.chorded = true →
      ∀ m, (∀ t, m ≠ .clock t) → (∀ n, m ≠ .timer n) →
      ∀ id r, Effect.request id r ∈ (receive s m).2 → r.wholeClip = none) ∧
    ∀ a id r, Effect.request id r ∈ (menuStep s a).2 → r.machineOnly = false
  init := ⟨fun hk hc m hcl hti _ _ h => app_shortcut_never_sends _ m hk hc hcl hti h,
    fun a _ _ h => menuStep_no_upload _ a h⟩
  step := fun _ _ _ => ⟨fun hk hc m hcl hti _ _ h => app_shortcut_never_sends _ m hk hc hcl hti h,
    fun a _ _ h => menuStep_no_upload _ a h⟩
  receive := fun _ _ _ => ⟨fun hk hc m hcl hti _ _ h => app_shortcut_never_sends _ m hk hc hcl hti h,
    fun a _ _ h => menuStep_no_upload _ a h⟩

invariant ^312 holdTapSplit "Hold to talk, tap to latch: 300 ms" for machine where
  does "Releasing the key ends a press that began a recording, not part of a shortcut: held for less than 300 ms it was a tap, and the recording goes on hands free with its deadline ten minutes on; held 300 ms or more, the recording ends and is sent (`hold_tap_split`)."
  holds s := ∀ r t k mo, s.core.recording = some r → r.latched = false → s.core.keyHeld = true →
    s.core.chorded = false →
    (receive s (.sub (.globalKey k mo) (.keyUp t))).1.core.recording =
      if max s.core.now t - s.core.pressedAt < tapLimit then
        some { r with latched := true, deadline := max s.core.now t + latchLimit }
      else none
  init := fun r t _ _ => hold_tap_split _ r t
  step := fun _ _ _ r t _ _ => hold_tap_split _ r t
  receive := fun _ _ _ r t _ _ => hold_tap_split _ r t

invariant ^313 oneRecording "One recording at a time" for machine where
  does "The app records exactly while the machine has a recording: one `record` subscription, for its clip. Whatever the host reports, a recording the machine didn't have is the next clip, started when there was none; the menu only ever stops one (`record_sub_iff`, `app_new_recording`, `step_new_recording`)."
  holds s := (∀ c, Sub.record c ∈ subscriptions s ↔ s.core.recording.map (·.clip) = some c) ∧
    (∀ m r', (receive s m).1.core.recording = some r' →
      s.core.recording.map (·.clip) ≠ some r'.clip → s.core.recording = none ∧ r'.clip = s.core.nextClip) ∧
    (∀ a, (menuStep s a).1.core.recording = s.core.recording ∨ (menuStep s a).1.core.recording = none)
  init := ⟨record_sub_iff _, fun m _ h hn => app_new_recording _ m h hn, fun a => menu_recording _ a⟩
  step := fun _ _ _ => ⟨record_sub_iff _, fun m _ h hn => app_new_recording _ m h hn,
    fun a => menu_recording _ a⟩
  receive := fun _ _ _ => ⟨record_sub_iff _, fun m _ h hn => app_new_recording _ m h hn,
    fun a => menu_recording _ a⟩

invariant ^314 recordingEnds "Every recording ends" for machine where
  does "A recording is either held down or hands free with its deadline at most ten minutes away; so once the key's release is heard and the clock reads ten minutes on, there is no recording. A recording held down has no limit, as in Swift Yap (`step_recInv`, `app_recording_ends`)."
  holds s := RecInv s.core ∧ ∀ t k mo (tm : Time), s.core.now ≤ t → t + latchLimit ≤ tm.mono →
    (receive (receive s (.sub (.globalKey k mo) (.keyUp t))).1 (.clock tm)).1.core.recording = none
  init := ⟨recInv_init, fun t k mo tm => app_recording_ends _ recInv_init t k mo tm⟩
  step := fun s a h =>
    have h' := keeps_recInv.machine.1 s a h.1
    ⟨h', fun t k mo tm => app_recording_ends _ h' t k mo tm⟩
  receive := fun s m h =>
    have h' := keeps_recInv.machine.2 s m h.1
    ⟨h', fun t k mo tm => app_recording_ends _ h' t k mo tm⟩

invariant ^315 keptBeforeTyped "Kept before it is typed" for machine where
  does "When Yap types a transcript, it is already in Recent Transcripts, marked not yet typed, and when transcripts are kept the request appending it to its day file comes before the request typing it (`app_saved_before_typed`, `saved_before_typed`). Swift Yap saves after typing; see the README."
  holds s := ∀ m id pid text ret, Effect.request id (.typeText pid text ret) ∈ (receive s m).2 →
    ∃ t ∈ (receive s m).1.core.recent, t.typed = false ∧
      ∃ pre post, (receive s m).2 = pre ++ Effect.request id (.typeText pid text ret) :: post ∧
        (s.core.settings.keepTranscripts = true →
          ∃ id' file, Effect.request id' (.appendFile file (transcriptLine t ++ "\n").toUTF8) ∈ pre)
  init := fun m _ _ _ _ h => app_saved_before_typed _ m h
  step := fun _ _ _ m _ _ _ _ h => app_saved_before_typed _ m h
  receive := fun _ _ _ m _ _ _ _ h => app_saved_before_typed _ m h

invariant ^316 failedTypeFlagged "A failed type is kept and flagged" for machine where
  does "When typing fails, the transcript is first in Recent Transcripts (so Copy Last Transcript copies it), marked as never having reached its app, and the error sound plays (`app_failed_type_flagged`)."
  holds s := ∀ q c t e (f : Fault), s.core.reqs.lookup q = some (.type c t) →
    (receive s (.reply (2 * q) (.failed f e))).1.core.recent.head? = some { t with typed := false } ∧
      ∃ id, Effect.request id (.playSound "Basso") ∈ (receive s (.reply (2 * q) (.failed f e))).2
  init := fun q c t e f h => app_failed_type_flagged _ q c t e f h
  step := fun _ _ _ q c t e f h => app_failed_type_flagged _ q c t e f h
  receive := fun _ _ _ q c t e f h => app_failed_type_flagged _ q c t e f h

invariant ^317 onlyLiveRepliesType "Late and cancelled replies never type" for machine where
  does "Only a reply to a whole-clip transcription that is still in flight, and was not cancelled since it was sent, types anything; a duplicate, a reply to something else, or a reply after Dictate with Key was turned off types nothing (`app_only_live_replies_type`, `late_reply_never_types`)."
  holds s := ∀ m id pid text ret, Effect.request id (.typeText pid text ret) ∈ (receive s m).2 →
    ∃ q r cr, m = .reply (2 * q) r ∧ (q, Req.clip cr) ∈ s.core.reqs ∧ cr.turn = s.core.turn
  init := fun m _ _ _ _ h => app_only_live_replies_type _ m h
  step := fun _ _ _ m _ _ _ _ h => app_only_live_replies_type _ m h
  receive := fun _ _ _ m _ _ _ _ h => app_only_live_replies_type _ m h

invariant ^318 typedOnce "Each clip is typed at most once" for machine where
  does "However replies arrive (late, twice, out of order, or never), and whatever else the host reports, no clip's transcript has been typed twice: the app's log of typed clips counts each at most once (`TypedInv`, `step_rel`)."
  holds s := TypedInv s.core s.typed ∧ ∀ n, s.typed.count n ≤ 1
  init := ⟨typedInv_init, typedInv_init.once⟩
  step := fun s a h =>
    have h' := keeps_typedInv.machine.1 s a h.1
    ⟨h', h'.once⟩
  receive := fun s m h =>
    have h' := keeps_typedInv.machine.2 s m h.1
    ⟨h', h'.once⟩

invariant ^319 wholeWordFixes "Fixes replace whole words" for machine where
  does "What is typed is the text of a successful transcription reply with each dictionary fix applied to whole words only, case-insensitively, then trimmed, then a space (or Return) (`app_typed_text`, `typed_text`, `replaceWord_replaces`)."
  holds s := ∀ m id pid text ret, Effect.request id (.typeText pid text ret) ∈ (receive s m).2 →
    ∃ q r raw cr, m = .reply (2 * q) r ∧ transcriptReply r = .ok raw ∧ (q, Req.clip cr) ∈ s.core.reqs ∧
      ReplacesAll cr.fixes raw.toList (applyFixes cr.fixes raw).toList ∧
      text = (if cr.submits then trimText (applyFixes cr.fixes raw)
              else trimText (applyFixes cr.fixes raw) ++ " ")
  init := fun m _ _ _ _ h => app_typed_text _ m h
  step := fun _ _ _ m _ _ _ _ h => app_typed_text _ m h
  receive := fun _ _ _ m _ _ _ _ h => app_typed_text _ m h

invariant ^320 retentionKeepsToday "Retention never deletes today" for machine where
  does "The only day files deleted are ones the host listed that are older than today by the clock; today's is never deleted, whatever retentionDays says (`app_retention_never_today`, `retention_never_today`)."
  holds s := ∀ m id path, Effect.request id (.deleteFile path) ∈ (receive s m).2 →
    ∃ (id' : Nat) (ns : List String) (d : Nat), m = .reply id' (.names ns) ∧ path = dayPath d ∧
      d ∈ ns.filterMap Dates.parseDayFile ∧ d < (Dates.localDay s.io.wall s.io.zone).toNat
  init := fun m _ _ h => app_retention_never_today _ m h
  step := fun _ _ _ m _ _ h => app_retention_never_today _ m h
  receive := fun _ _ _ m _ _ h => app_retention_never_today _ m h

invariant ^321 first25Terms "Only the first 25 terms are sent" for machine where
  does "Every upload is a transcription, of a whole clip or a preview chunk, whose prompt is the one a dictionary of just its first 25 terms would give (`app_prompt`, `step_prompt`)."
  holds s := ∀ m id me url hs sec body to,
    Effect.request id (.upload me url hs sec body to) ∈ (receive s m).2 →
    ∃ n a b mo p ctx, Request.upload me url hs sec body to = transcription n a b mo p ∧
      p = { s.core.dict with terms := s.core.dict.terms.take promptLimit }.promptFor ctx
  init := fun m _ _ _ _ _ _ _ h => app_prompt _ m h
  step := fun _ _ _ m _ _ _ _ _ _ _ h => app_prompt _ m h
  receive := fun _ _ _ m _ _ _ _ _ _ _ h => app_prompt _ m h

invariant ^322 recentFive "Recent Transcripts holds five" for machine where
  does "The recent list never holds more than five transcripts (`step_small`, `menu_small`)."
  holds s := s.core.recent.length ≤ recentLimit
  init := Nat.zero_le _
  step := keeps_small.machine.1
  receive := keeps_small.machine.2

invariant ^323 onlySendable "Too short, silent or nowhere to type: never sent" for machine where
  does "Every whole-clip upload is of the recording in progress, at least 0.3 s long, with a sample at or above the silence peak, and with an app to type into (`app_sendable`, `step_transcribe`)."
  holds s := ∀ m id n r, Effect.request id r ∈ (receive s m).2 → r.wholeClip = some n →
    ∃ rec mo p, s.core.recording = some rec ∧ Sendable s.core.dict rec n p ∧
      r = transcription n 0 none mo p
  init := fun m _ _ _ h hw => app_sendable _ m h hw
  step := fun _ _ _ m _ _ _ h hw => app_sendable _ m h hw
  receive := fun _ _ _ m _ _ _ h hw => app_sendable _ m h hw

invariant ^346 leaveOriginal "The original Yap keeps its key" for machine where
  does "Yap (Cairn) takes the dictation key only once it has checked that the original Yap (dev.yap.Yap) is not running: while it runs, or before the check is answered, there is no global key subscription, and the menu says so (`wantsKey`)."
  holds s := s.io.original ≠ some false → ∀ k mo, Sub.globalKey k mo ∉ subscriptions s
  init := fun h k mo => leave_original _ h k mo
  step := fun _ _ _ h k mo => leave_original _ h k mo
  receive := fun _ _ _ h k mo => leave_original _ h k mo

invariant ^347 markAfterAppend "A mark waits for the appends" for machine where
  does "Yap marks a typed transcript's line in its day file (`\"typed\":true`) by rewriting the file, and the host runs requests concurrently, so a line is only known to be there once its append is answered. The app keeps the day-file appends it has sent and not heard back from (`Io.appends`): every append it sends is kept, with its line, and one leaves only when a reply with its id arrives; a line is saved for marking only when the reply to its append says it worked; and a mark's read goes out only for a saved line, when no append is in flight after the message, so never before its own append is answered nor in the same frame as another. The menu starts no mark and drops no append (`receive_tracks`, `receive_answers`, `receive_saves`, `receive_marks`, `menuStep_marks`). That a typed transcript then ends up marked on disk is fuzzed, not proved (`yapfuzz`, app mode)."
  holds s := (∀ m id f d, Effect.request id (.appendFile f d) ∈ (receive s m).2 →
      ∃ k line, (id, k, f, line) ∈ (receive s m).1.io.appends ∧ d = line.toUTF8) ∧
    (∀ m x, x ∈ s.io.appends → x ∉ (receive s m).1.io.appends → ∃ r, m = .reply x.1 r) ∧
    (∀ m e, e ∈ (receive s m).1.io.saved → e ∉ s.io.saved →
      ∃ id r, m = .reply id r ∧ r.ok = true ∧ (id, some e.1, e.2.1, e.2.2) ∈ s.io.appends) ∧
    (∀ m id c f l, (id, Pend.markRead c f l) ∈ (receive s m).1.io.pending →
      (id, Pend.markRead c f l) ∉ s.io.pending →
      (receive s m).1.io.appends = [] ∧ (c, f, l) ∈ (receive s m).1.io.saved) ∧
    (∀ a, s.io.Frame (menuStep s a).1.io ∧
      ∀ id f d, Effect.request id (.appendFile f d) ∈ (menuStep s a).2 →
        ∃ k line, (id, k, f, line) ∈ (menuStep s a).1.io.appends ∧ d = line.toUTF8)
  init := ⟨fun m _ _ _ h => receive_tracks _ m h, fun m _ hx hn => receive_answers _ m hx hn,
    fun m _ he hn => receive_saves _ m he hn, fun m _ _ _ _ h hn => receive_marks _ m h hn,
    fun a => menuStep_marks _ a⟩
  step := fun _ _ _ => ⟨fun m _ _ _ h => receive_tracks _ m h, fun m _ hx hn => receive_answers _ m hx hn,
    fun m _ he hn => receive_saves _ m he hn, fun m _ _ _ _ h hn => receive_marks _ m h hn,
    fun a => menuStep_marks _ a⟩
  receive := fun _ _ _ => ⟨fun m _ _ _ h => receive_tracks _ m h, fun m _ hx hn => receive_answers _ m hx hn,
    fun m _ he hn => receive_saves _ m he hn, fun m _ _ _ _ h hn => receive_marks _ m h hn,
    fun a => menuStep_marks _ a⟩

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
  goal s := s.core.enabled = false ∧ toggleSubmits.enabled s = false ∧ s.core.recording = none
  witness press ^306

flow ^341 keepTwice "Keep Transcripts off and on again" for machine where
  does "Choose Keep Transcripts twice."
  sees "Transcripts are kept again, after two writes of config.json."
  goal s := s.core.settings.keepTranscripts = true ∧ s.core.reqs.length = 2
  witness press ^304, press ^304

/-- Every claim Yap makes. -/
def claimInfos : List ClaimInfo := claims%

/-- Yap on Cairn: the status item with Yap's menu, and the overlay. -/
def app : App AppState :=
  { machine.toApp [.statusItem 301 (some ∘ statusItem), .panel 399 (fun _ => panel)] claimInfos with
    subscriptions, initEffects }

end Examples.Yap

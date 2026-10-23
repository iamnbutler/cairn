module

public import Examples.Yap.Dictionary
public import Examples.Yap.Chunker
public import Examples.Yap.Hotkey
public import Examples.Yap.Retention

/-! # Yap: the dictation machine

Yap's behaviour (`~/code/yap`, `App/Yap.swift` and `App/PushToTalk.swift`) as one total, pure
function, `step : State → Input → State × List Cmd`. `Input` is everything the host reports
(the key, the clock, the microphone, replies to requests, files, the menu); `Cmd` is
everything Lean asks the host to do. No UI and no framework effects yet: `Cmd` is local, and
each constructor is a request (it names a request id and gets a `reply`), a timer (`wakeAt`)
or a one-way command, so it maps onto the framework's effects when they land.

Time is the host's monotonic clock in integer milliseconds. The model keeps the latest time
it has seen (`now`) and never goes back, so a clock that jumps backwards is harmless. -/

@[expose] public section

namespace Examples.Yap

abbrev Ms := Nat

/-- A press shorter than this is a tap, which latches the recording on (Swift `tapLimit`). -/
def tapLimit : Ms := 300
/-- A latched recording sends itself this long after the tap (Swift `latchLimit`, 600 s). -/
def latchLimit : Ms := 600000
/-- Shorter than this is not worth a round trip: 0.3 s at 16 kHz (Swift `minimumSeconds`). -/
def minimumFrames : Nat := 4800
/-- A clip or chunk whose loudest sample is below this is silence (Swift `silencePeak`). -/
def silencePeak : Nat := 500
/-- The live preview looks for a cut this often while recording. -/
def pollMs : Ms := 250
def defaultModel : String := "gpt-transcribe"

/-- `config.json`, with defaults for whatever it leaves out. -/
structure Settings where
  keepTranscripts : Bool := true
  retentionDays : Int := 30
  overlay : Bool := true
  key : String := "rightCommand"
deriving Repr, DecidableEq, Inhabited

/-- `config.json` as the host decoded it: none for a field the file leaves out. -/
structure ConfigFile where
  keepTranscripts : Option Bool := none
  retentionDays : Option Int := none
  overlay : Option Bool := none
  key : Option String := none
deriving Repr, DecidableEq, Inhabited

def ConfigFile.settings (f : ConfigFile) : Settings where
  keepTranscripts := f.keepTranscripts.getD true
  retentionDays := f.retentionDays.getD 30
  overlay := f.overlay.getD true
  key := f.key.getD "rightCommand"

inductive ConfigRead where
  /-- No file: every default. -/
  | missing
  /-- A file that won't parse: keep the last settings and say so. -/
  | unreadable (err : String)
  | ok (f : ConfigFile)
deriving Repr, DecidableEq, Inhabited

/-- What Yap keeps in `UserDefaults`. -/
structure Prefs where
  enabled : Bool := true
  submits : Bool := false
  model : Option String := none
deriving Repr, DecidableEq, Inhabited

/-- The app in front when the key went down: where the transcript is typed. -/
structure Target where
  pid : Nat
  name : Option String := none
deriving Repr, DecidableEq, Inhabited

/-- Audio since the last report, for the current clip. -/
structure Audio where
  /-- Samples (16 kHz mono). -/
  frames : Nat
  /-- The loudest sample among them. -/
  peak : Nat
  /-- The 20 ms windows they complete, counted from the start of the clip. -/
  windows : List Window := []
deriving Repr, DecidableEq, Inhabited

/-- A request's answer. Every request can fail; a failure is an ordinary reply. -/
inductive Reply where
  | ok (text : String)
  | failed (err : String)
deriving Repr, DecidableEq, Inhabited

inductive MenuAction where
  | copyLast
  | copyRecent (i : Nat)
  | toggleKeep
  | toggleSubmits
  | toggleEnabled
  | openTranscripts
  | editDictionary
  | editSettings
  | grantAccess
deriving Repr, DecidableEq, Inhabited

/-- What the host reports. -/
inductive Input where
  /-- The app started, with what `UserDefaults` holds. -/
  | launch (p : Prefs)
  /-- The dictation key went down at `t`, with the app in front. -/
  | keyDown (t : Ms) (front : Option Target)
  | keyUp (t : Ms)
  /-- Some other key went down (the host reports them all; Lean decides if it was a shortcut). -/
  | otherKey
  /-- The clock: a timer Lean asked for fired, or any time the host likes. -/
  | tick (t : Ms)
  | audio (clip : Nat) (a : Audio)
  /-- The microphone would not start for this clip. -/
  | micFailed (clip : Nat) (err : String)
  | reply (req : Nat) (r : Reply)
  | config (r : ConfigRead)
  /-- `dictionary.txt`'s contents (empty when there is no file). -/
  | dictionary (text : String)
  /-- The transcript day files there are, and today's day number. -/
  | transcriptDays (today : Nat) (days : List Nat)
  /-- The newest transcripts on disk, newest first. -/
  | recentLoaded (ts : List Transcript)
  /-- Whether Accessibility is granted. -/
  | trust (granted : Bool)
  | menu (m : MenuAction)
deriving Repr, DecidableEq, Inhabited

inductive Sound where
  | tink | pop | basso
deriving Repr, DecidableEq, Inhabited

inductive OverlayPhase where
  | handsFree | transcribing | typed | failed
deriving Repr, DecidableEq, Inhabited

inductive OverlayCmd where
  | begin
  | phase (p : OverlayPhase)
  | text (t : String)
  /-- A chunk was cut at this sample. -/
  | mark (sample : Nat)
  | hide (afterMs : Nat)
deriving Repr, DecidableEq, Inhabited

inductive Opens where
  | transcriptsFolder | dictionary | settings | accessibility
deriving Repr, DecidableEq, Inhabited

/-- What Lean asks the host to do. Those with a `req` are answered by `Input.reply req`. -/
inductive Cmd where
  /-- Report `config.json` (`Input.config`), now and whenever it changes. -/
  | readConfig
  /-- Report `dictionary.txt` (`Input.dictionary`), now and whenever it changes. -/
  | readDictionary
  /-- Listen for this key. -/
  | listen (k : Hotkey)
  | storePrefs (p : Prefs)
  | saveConfig (req : Nat) (c : Settings)
  | startRecording (clip : Nat)
  | stopRecording (clip : Nat)
  /-- Transcribe the whole clip. -/
  | transcribe (req clip : Nat) (model : String) (prompt : Option String)
  /-- Transcribe samples `[fromSample, toSample)` of the clip, for the preview. -/
  | transcribeChunk (req clip fromSample toSample : Nat) (model : String) (prompt : Option String)
  /-- Append the transcript to today's file. -/
  | save (req : Nat) (t : Transcript)
  /-- The clip's saved transcript reached its app. -/
  | markTyped (clip : Nat)
  /-- Bring `pid` forward and type `text`, then Return if `pressReturn`. -/
  | type (req clip pid : Nat) (text : String) (pressReturn : Bool)
  | play (s : Sound)
  /-- Send a `tick` at or after `t`. -/
  | wakeAt (t : Ms)
  /-- Report the transcript day files (`Input.transcriptDays`). -/
  | listDays
  | deleteDays (days : List Nat)
  /-- Report the newest `n` transcripts on disk (`Input.recentLoaded`). -/
  | loadRecent (n : Nat)
  | copy (text : String)
  | overlay (clip : Nat) (o : OverlayCmd)
  | «open» (o : Opens)
deriving Repr, DecidableEq, Inhabited

/-- The recording in progress. -/
structure Recording where
  clip : Nat
  target : Option Target
  /-- Hands free, after a tap. -/
  latched : Bool := false
  /-- When a latched recording sends itself. -/
  deadline : Ms := 0
  frames : Nat := 0
  peak : Nat := 0
  /-- The overlay's live preview is on. -/
  live : Bool := false
  /-- Windows already cut into chunks. -/
  offset : Nat := 0
  /-- Windows since the last cut. -/
  pending : List Window := []
  /-- The preview chunk being transcribed: one at a time, so they arrive in order. -/
  chunk : Option Nat := none
  nextPoll : Ms := 0
  /-- The preview so far. -/
  heard : List String := []
deriving Repr, DecidableEq, Inhabited

/-- A clip sent for transcription, with what it was sent under. -/
structure ClipReq where
  clip : Nat
  /-- `State.turn` when it was sent: a cancel since then means it is kept but not typed. -/
  turn : Nat
  target : Target
  submits : Bool
  fixes : List Fix
deriving Repr, DecidableEq, Inhabited

/-- What a request in flight was for. -/
inductive Req where
  | clip (c : ClipReq)
  | chunk (clip : Nat) (fixes : List Fix)
  | type (clip : Nat) (t : Transcript)
  | save
  | config
deriving Repr, DecidableEq, Inhabited

structure State where
  now : Ms := 0
  /-- **Dictate with key** (`UserDefaults` `enabled`). -/
  enabled : Bool := true
  /-- **Press Return After Dictating**. -/
  submits : Bool := false
  model : String := defaultModel
  settings : Settings := {}
  hotkey : Hotkey := Hotkey.rightCommand
  /-- Until the first `config.json` read, which loads the recent list. -/
  booting : Bool := true
  trusted : Bool := false
  dict : Dictionary := {}
  /-- The dictation key is down. -/
  keyHeld : Bool := false
  /-- Another key went down while it was: a shortcut. -/
  chorded : Bool := false
  pressedAt : Ms := 0
  recording : Option Recording := none
  /-- Bumped by a cancel, so a transcript in flight is kept but not typed. -/
  turn : Nat := 0
  nextClip : Nat := 1
  nextReq : Nat := 1
  /-- Requests in flight, newest first. -/
  reqs : List (Nat × Req) := []
  recent : List Transcript := []
  /-- The menu's status line. -/
  detail : String := ""
deriving Repr, DecidableEq, Inhabited

/-! ## Queries -/

def ready (s : State) : String :=
  s!"Hold {s.hotkey.name} to dictate, or tap to start and tap to send"

/-- A clip's transcript or its typing is still on its way. -/
def transcribing (s : State) : Bool :=
  s.reqs.any fun q => match q.2 with
    | .clip c => c.turn == s.turn
    | .type _ _ => true
    | _ => false

inductive Phase where
  | idle | recording | transcribing
deriving Repr, DecidableEq, Inhabited

/-- What the menu bar icon shows. -/
def phase (s : State) : Phase :=
  if s.recording.isSome then .recording else if transcribing s then .transcribing else .idle

def prefs (s : State) : Prefs := { enabled := s.enabled, submits := s.submits, model := s.model }

/-- "1.5" for 24,000 samples. -/
def seconds (frames : Nat) : String :=
  let tenths := (frames * 10 + 8000) / 16000
  s!"{tenths / 10}.{tenths % 10}"

/-- The preview's context for the next chunk: the end of what came before. -/
def context (heard : List String) : Option String :=
  let prev := " ".intercalate heard
  if prev.isEmpty then none
  else some ("Continues from: \"" ++ String.ofList (prev.toList.drop (prev.length - 200)) ++ "\"")

/-! ## The machine -/

/-- Send the recording: stop it, then transcribe it unless it is too short, silent, or has no
app to go to (`Yap.send`). -/
def send (s : State) (r : Recording) : State × List Cmd :=
  let stop := (if r.latched then [Cmd.play .pop] else []) ++ [.stopRecording r.clip]
  let s := { s with recording := none }
  if r.frames < minimumFrames then
    ({ s with detail := "Too short to send" }, stop ++ [.overlay r.clip (.hide 0)])
  else if r.peak < silencePeak then
    ({ s with detail := "Heard nothing" }, stop ++ [.overlay r.clip (.hide 0)])
  else match r.target with
    | none => ({ s with detail := "No app to type into" }, stop ++ [.overlay r.clip (.hide 0)])
    | some app =>
      let q := s.nextReq
      ({ s with nextReq := q + 1,
                reqs := (q, .clip { clip := r.clip, turn := s.turn, target := app,
                                    submits := s.submits, fixes := s.dict.fixes }) :: s.reqs,
                detail := s!"Transcribing {seconds r.frames}s…" },
       stop ++ [.overlay r.clip (.phase .transcribing),
                .transcribe q r.clip s.model (s.dict.promptFor none)])

/-- Drop the recording: a shortcut, not a dictation. -/
def drop (s : State) (r : Recording) : State × List Cmd :=
  ({ s with recording := none, detail := ready s }, [.stopRecording r.clip, .overlay r.clip (.hide 0)])

/-- The key came up (`Yap.end`); `s.now` is the time. -/
def release (s : State) : State × List Cmd :=
  match s.recording with
  | none => (s, [])
  | some r =>
    if s.chorded then
      -- A shortcut. Mid-latch it is just you using the keyboard; otherwise no dictation.
      if r.latched then (s, []) else drop s r
    else if !r.latched && s.now - s.pressedAt < tapLimit then
      let r' := { r with latched := true, deadline := s.now + latchLimit }
      ({ s with recording := some r', detail := s!"Recording hands free. Tap {s.hotkey.name} to send." },
       [.play .tink, .overlay r.clip (.phase .handsFree), .wakeAt r'.deadline])
    else send s r

/-- The key went down (`Yap.begin`): start a recording, or note the press that will end a
latched one. -/
def press (s : State) (front : Option Target) : State × List Cmd :=
  if !s.enabled then (s, [])
  else
    let s := { s with chorded := false, pressedAt := s.now }
    match s.recording with
    | some _ => (s, [])
    | none =>
      let c := s.nextClip
      let live := s.settings.overlay
      let r : Recording := { clip := c, target := front, live, nextPoll := s.now + pollMs }
      ({ s with nextClip := c + 1, recording := some r, detail := "Listening…" },
       [.startRecording c] ++ (if live then [.overlay c .begin, .wakeAt r.nextPoll] else []))

/-- Look for a cut and send the chunk before it for the preview. -/
def poll (s : State) (r : Recording) : State × List Cmd :=
  let taken := Chunker.taken (r.pending.map (·.sumSq))
  let next := s.now + pollMs
  if taken = 0 then ({ s with recording := some { r with nextPoll := next } }, [.wakeAt next])
  else
    let chunk := r.pending.take taken
    let toS := (r.offset + taken) * Chunker.windowSamples
    let mark := Cmd.overlay r.clip (.mark toS)
    let r' := { r with nextPoll := next, offset := r.offset + taken, pending := r.pending.drop taken }
    if peakOf chunk < silencePeak then ({ s with recording := some r' }, [mark, .wakeAt next])
    else
      let q := s.nextReq
      ({ s with recording := some { r' with chunk := some q }, nextReq := q + 1,
                reqs := (q, .chunk r.clip s.dict.fixes) :: s.reqs },
       [mark, .transcribeChunk q r.clip (r.offset * Chunker.windowSamples) toS s.model
          (s.dict.promptFor (context r.heard))])

/-- The clock (`s.now` is the time): the latch limit, then the preview. -/
def tick (s : State) : State × List Cmd :=
  match s.recording with
  | none => (s, [])
  | some r =>
    if r.latched ∧ r.deadline ≤ s.now then send s r
    else if r.live ∧ r.chunk = none ∧ r.nextPoll ≤ s.now then poll s r
    else (s, [])

def audio (s : State) (clip : Nat) (a : Audio) : State × List Cmd :=
  match s.recording with
  | some r =>
    if r.clip = clip then
      ({ s with recording := some { r with frames := r.frames + a.frames, peak := max r.peak a.peak,
                                           pending := if r.live then r.pending ++ a.windows else r.pending } }, [])
    else (s, [])
  | none => (s, [])

def micFailed (s : State) (clip : Nat) (err : String) : State × List Cmd :=
  match s.recording with
  | some r =>
    if r.clip = clip then
      ({ s with recording := none, detail := s!"Microphone failed: {err}" }, [.overlay clip (.hide 0)])
    else (s, [])
  | none => (s, [])

/-- The whole clip's transcript came back: fix it, keep it, then type it unless it was
cancelled since it was sent. Kept before typing, so a failed type can't lose it. -/
def transcribed (s : State) (c : ClipReq) (raw : String) : State × List Cmd :=
  let text := fixText c.fixes raw
  if text.isEmpty then ({ s with detail := "Heard nothing" }, [.overlay c.clip (.hide 0)])
  else
    let t : Transcript := { clip := some c.clip, text, app := c.target.name, typed := false }
    let s := { s with recent := remember t s.recent }
    let q := s.nextReq
    let saved := if s.settings.keepTranscripts then [Cmd.save q t, .listDays] else []
    let s := if s.settings.keepTranscripts then { s with nextReq := q + 1, reqs := (q, .save) :: s.reqs } else s
    if c.turn ≠ s.turn then (s, saved)
    else
      let q := s.nextReq
      ({ s with nextReq := q + 1, reqs := (q, .type c.clip t) :: s.reqs },
       saved ++ [.overlay c.clip (.text text),
                 .type q c.clip c.target.pid (if c.submits then text else text ++ " ") c.submits])

/-- Mark the clip's transcript in the recent list. -/
def setTyped (clip : Nat) (b : Bool) (recent : List Transcript) : List Transcript :=
  recent.map fun x => if x.clip = some clip then { x with typed := b } else x

/-- Typing failed: the transcript is flagged in the recent list, put back at the front if newer
ones pushed it out. -/
def flagFailed (clip : Nat) (t : Transcript) (recent : List Transcript) : List Transcript :=
  if recent.any (·.clip == some clip) then setTyped clip false recent
  else remember { t with typed := false } recent

def typedOk (s : State) (clip : Nat) (t : Transcript) : State × List Cmd :=
  ({ s with recent := setTyped clip true s.recent, detail := s!"Typed {t.text.length} characters" },
   (if s.settings.keepTranscripts then [Cmd.markTyped clip] else []) ++
     [.overlay clip (.phase .typed), .overlay clip (.hide 1500)])

def typedFailed (s : State) (clip : Nat) (t : Transcript) (err : String) : State × List Cmd :=
  ({ s with recent := flagFailed clip t s.recent,
            detail := s!"Couldn't type it ({err}). It's in Recent Transcripts." },
   [.play .basso, .overlay clip (.phase .failed), .overlay clip (.hide 4000)])

/-- A preview chunk came back: add it to the preview if it is still this recording's. -/
def chunkDone (s : State) (clip q : Nat) (text : Option String) : State × List Cmd :=
  match s.recording with
  | some r =>
    if r.clip = clip ∧ r.chunk = some q then
      let heard := match text with
        | some t => if t.isEmpty then r.heard else r.heard ++ [t]
        | none => r.heard
      let next := s.now + pollMs
      ({ s with recording := some { r with chunk := none, heard, nextPoll := next } },
       (if heard.length ≠ r.heard.length then [.overlay clip (.text (" ".intercalate heard))] else []) ++
         [.wakeAt next])
    else (s, [])
  | none => (s, [])

def reply (s : State) (q : Nat) (x : Reply) : State × List Cmd :=
  match s.reqs.lookup q with
  | none => (s, [])  -- a duplicate, or a reply to nothing: ignored
  | some req =>
    let s := { s with reqs := s.reqs.filter (·.1 != q) }
    match req, x with
    | .clip c, .ok raw => transcribed s c raw
    | .clip c, .failed e =>
      ({ s with detail := if c.turn = s.turn then e else s.detail }, [.overlay c.clip (.hide 0)])
    | .chunk clip fixes, .ok raw => chunkDone s clip q (some (fixText fixes raw))
    | .chunk clip _, .failed _ => chunkDone s clip q none
    | .type clip t, .ok _ => typedOk s clip t
    | .type clip t, .failed e => typedFailed s clip t e
    | .save, .ok _ => (s, [])
    | .save, .failed e => ({ s with detail := s!"Couldn't save the transcript: {e}" }, [])
    | .config, .ok _ => (s, [])
    | .config, .failed e => ({ s with detail := s!"Couldn't save settings: {e}" }, [])

/-- Cancel everything (`Yap.cancel`): stop recording, and anything in flight is kept but not
typed. -/
def cancel (s : State) : State × List Cmd :=
  let stop := match s.recording with
    | some r => [Cmd.stopRecording r.clip]
    | none => []
  let hide := if 1 < s.nextClip then [Cmd.overlay (s.nextClip - 1) (.hide 0)] else []
  ({ s with turn := s.turn + 1, recording := none, detail := ready s }, stop ++ hide)

/-- A new key: listen for it, and a hold of the old one ends (its release would never come). -/
def setKey (s : State) (k : Hotkey) : State × List Cmd :=
  if k = s.hotkey then (s, [])
  else
    let r := if s.keyHeld then release { s with keyHeld := false } else (s, [])
    ({ r.1 with hotkey := k }, r.2 ++ [.listen k])

/-- `config.json` was read (`Yap.reloadConfig`). The first read also loads the recent list and
prunes old days, if transcripts are kept. -/
def configured (s : State) (r : ConfigRead) : State × List Cmd :=
  let res : State × List Cmd := match r with
    | .unreadable e =>
      ({ s with detail := s!"config.json won't parse, keeping the last settings: {e}" }, [])
    | .missing | .ok _ =>
      let cfg := match r with
        | .ok f => f.settings
        | _ => {}
      let s := { s with settings := cfg }
      match Hotkey.parse cfg.key with
      | none => ({ s with detail := s!"config.json: no key called \"{cfg.key}\", still using {s.hotkey.name}" }, [])
      | some k =>
        let r := setKey s k
        let s := r.1
        ((if s.recording.isNone ∧ transcribing s = false then { s with detail := ready s } else s), r.2)
  let boot := if s.booting ∧ res.1.settings.keepTranscripts then [Cmd.listDays, .loadRecent recentLimit] else []
  ({ res.1 with booting := false }, res.2 ++ boot)

def menu (s : State) : MenuAction → State × List Cmd
  | .copyLast => match s.recent with
    | t :: _ => (s, [.copy t.text])
    | [] => (s, [])
  | .copyRecent i => match s.recent[i]? with
    | some t => (s, [.copy t.text])
    | none => (s, [])
  | .toggleKeep =>
    let cfg := { s.settings with keepTranscripts := !s.settings.keepTranscripts }
    let q := s.nextReq
    ({ s with settings := cfg, nextReq := q + 1, reqs := (q, .config) :: s.reqs }, [.saveConfig q cfg])
  | .toggleSubmits =>
    if s.enabled then
      let s := { s with submits := !s.submits }
      (s, [.storePrefs (prefs s)])
    else (s, [])
  | .toggleEnabled =>
    let s := { s with enabled := !s.enabled }
    if s.enabled then (s, [.storePrefs (prefs s)])
    else
      let r := cancel s
      (r.1, .storePrefs (prefs s) :: r.2)
  | .openTranscripts => (s, [.open .transcriptsFolder])
  | .editDictionary => (s, [.open .dictionary])
  | .editSettings => (s, [.open .settings])
  | .grantAccess => if s.trusted then (s, []) else (s, [.open .accessibility])

/-- **The machine.** Total and pure: every input in every state has an answer. -/
def step (s : State) : Input → State × List Cmd
  | .launch p =>
    ({ s with enabled := p.enabled, submits := p.submits, model := p.model.getD defaultModel },
     [.listen s.hotkey, .readConfig, .readDictionary])
  | .keyDown t front =>
    let s := { s with now := max s.now t }
    if s.keyHeld then (s, []) else press { s with keyHeld := true } front
  | .keyUp t =>
    let s := { s with now := max s.now t }
    if s.keyHeld then release { s with keyHeld := false } else (s, [])
  | .otherKey => if s.keyHeld then ({ s with chorded := true }, []) else (s, [])
  | .tick t => tick { s with now := max s.now t }
  | .audio clip a => audio s clip a
  | .micFailed clip err => micFailed s clip err
  | .reply q x => reply s q x
  | .config r => configured s r
  | .dictionary text => ({ s with dict := Dictionary.parse text }, [])
  | .transcriptDays today days =>
    let ds := daysToDelete s.settings.retentionDays today days
    (s, if ds.isEmpty then [] else [.deleteDays ds])
  | .recentLoaded ts => ({ s with recent := (s.recent ++ ts).take recentLimit }, [])
  | .trust b => ({ s with trusted := b }, [])
  | .menu m => menu s m

/-- The state after a sequence of inputs. -/
def run (s : State) (is : List Input) : State := is.foldl (fun s i => (step s i).1) s

/-- The state after a sequence of inputs, and every command issued on the way, in order. -/
def exec (s : State) : List Input → State × List Cmd
  | [] => (s, [])
  | i :: is => ((exec (step s i).1 is).1, (step s i).2 ++ (exec (step s i).1 is).2)

def init : State := {}

end Examples.Yap

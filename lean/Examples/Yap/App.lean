module

public import Examples.Yap.Once
public import Examples.Yap.Json
public import Cairn.App

/-! # Yap on Cairn: the machine on the framework

`Examples.Yap.step` is Yap's behaviour as a pure machine over its own `Input`s and `Cmd`s. Here
it becomes a Cairn app (workstream W, M2 step 3; docs/yap.md):

* **State.** `AppState` is the machine's `State` (`core`) and `Io`, what the app needs to talk
  to the host: request ids, the requests in flight that the machine doesn't know about (file
  reads, permission checks, the recent list's day files), the clock, the overlay and a log of
  the clips typed (`Io.typed`, for ^318).
* **In.** `receive` turns each host message into at most one machine `Input` (`prep`), steps
  the machine, then turns its `Cmd`s into effects (`trAll`). The clock and timers become
  `tick`s; the `globalKey` subscription the key; `record` the audio; `watchFile` re-reads of
  `config.json` and `dictionary.txt`; replies are decoded (the transcription's JSON, the day
  files' lines, the config file).
* **Ids.** A machine request `q` goes out as request `2q`, so its reply comes back as
  `reply q`; the app's own requests have odd ids (`Io.ask`).
* **Out.** Requests the machine makes keep their order: a transcript's `appendFile` comes before
  its `typeText`, in one frame (^315). Uploads are built here: OpenAI's multipart framing in
  Lean, the clip's WAV and the API key from the host (`Part.wav`, `Secret`).

Files are the original Yap's (`~/Library/Application Support/yap/`, `Json`): config.json,
dictionary.txt, transcripts/YYYY-MM-DD.jsonl and secrets.env; Cairn's own toggles go to
`~/Library/Application Support/Cairn/Yap/prefs.json`, and the model is read from
`defaults read dev.yap.Yap model`.

The menu, the status item and the overlay panel are at the end; the claims are in
`Examples.Yap` and their proofs through `receive` in `Examples.Yap.AppProofs`. -/

@[expose] public section

namespace Examples.Yap
open Cairn
open Examples.Yap.Json (Json)

/-! ## Where things are -/

def supportDir : String := "~/Library/Application Support/yap"
def configPath : String := supportDir ++ "/config.json"
def dictionaryPath : String := supportDir ++ "/dictionary.txt"
def transcriptsDir : String := supportDir ++ "/transcripts"
def secretsPath : String := supportDir ++ "/secrets.env"
/-- Cairn's own toggles (Dictate with Key, Press Return After Dictating): the original keeps
them in its `UserDefaults`, which this app reads at launch but never writes. -/
def prefsPath : String := "~/Library/Application Support/Cairn/Yap/prefs.json"
/-- The original app's bundle identifier: its defaults domain, and the app to stand aside for. -/
def originalBundle : String := "dev.yap.Yap"
def accessibilitySettings : String :=
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
def microphoneSettings : String :=
  "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
def transcriptionURL : String := "https://api.openai.com/v1/audio/transcriptions"
def transcriptionTimeoutMs : Nat := 30000
/-- The multipart boundary for a request: `yap-` and a version-4 UUID, as Yap's
`"yap-\(UUID().uuidString)"`. Yap's is random; this one is mixed from the clip and its windows
(a 64-bit linear congruential generator), so it has the same form and differs per request. -/
def boundaryFor (clip start : Nat) (stop : Option Nat) : String :=
  let next (x : Nat) : Nat := (x * 6364136223846793005 + 1442695040888963407) % 2 ^ 64
  let a := next (next (clip * 1000003 + start * 7919 + (stop.map (· + 1)).getD 0 + 0x79617001))
  let b := next a
  let hex (x : Nat) : List Char :=
    (List.range 16).reverse.map fun i => (Nat.toDigits 16 (x / 16 ^ i % 16)).head!.toUpper
  let d := hex a ++ hex b
  let d := d.set 12 '4' |>.set 16 ("89AB".toList.getD (b % 4) '8')
  let part (i n : Nat) : String := String.ofList ((d.drop i).take n)
  s!"yap-{part 0 8}-{part 8 4}-{part 12 4}-{part 16 4}-{part 20 12}"
def dictionaryTemplate : String :=
  "# Yap dictionary. One term per line; only the first 25 are sent.\n# \"heard => written\" fixes a mishearing after transcription.\n"
/-- How often the app checks its permissions and whether the original Yap is running. -/
def pollEveryMs : Nat := 2000

/-- A transcript's day file: named by its local date. -/
def dayPath (day : Int) : String := transcriptsDir ++ "/" ++ Dates.dayFile day

/-! ## The app's own requests

Everything the app asks the host for itself (not for the machine) is an `Ask`, so what it can
be is fixed by this type: never an upload, a `typeText` or a `deleteFile` (`Ask.request`). -/

inductive Ask where
  | read (path : String)
  | write (path : String) (data : String)
  | append (path : String) (data : String)
  | list (path : String)
  | front
  | permission (p : Permission) (prompt : Bool)
  | running (bundleId : String)
  | readDefault (domain key : String)
  | openItem (target : String)
  | sound (name : String)
  | forget (clip : Nat)
deriving Repr, Inhabited

def Ask.request : Ask → Request
  | .read p => .readFile p
  | .write p d => .writeFile p d.toUTF8
  | .append p d => .appendFile p d.toUTF8
  | .list p => .listDir p
  | .front => .frontmostApp
  | .permission p b => .permission p b
  | .running b => .appRunning b
  | .readDefault d k => .readDefault d k
  | .openItem t => .openItem t
  | .sound n => .playSound n
  | .forget c => .forgetClip c

/-- An `Ask` sent under an id. -/
def Ask.effect (x : Nat × Ask) : Effect := .request x.1 x.2.request

/-- What a request of the app's own is for, so its reply can be understood. -/
inductive Pend where
  | config | dictionary
  /-- Launch: prefs.json, then the original's `model`, `enabled` and `submits` defaults. -/
  | bootPrefs | bootModel | bootEnabled | bootSubmits
  /-- The original's `model` default, read again as each recording starts (Yap reads it per
  clip). -/
  | model
  /-- The app in front for this clip. -/
  | front (clip : Nat)
  /-- The day files, for retention. -/
  | days
  /-- The day files, for the newest `n` transcripts. -/
  | recentList (n : Nat)
  /-- A day file's transcripts, then the files still to read, newest first. -/
  | recentFile (n : Nat) (rest : List String) (acc : List Transcript)
  | trust | mic
  /-- Asked for the microphone from the menu: refused opens System Settings. -/
  | micAsk
  | original
  /-- Does `path` exist? If not, write `data` to it; then open `target`. -/
  | ensure (path data target : String)
  /-- Wrote the template: now open `target`. -/
  | create (target : String)
  | opening (target : String)
  /-- Marking the clip's line typed: read the day file `file`, which has `line`. -/
  | markRead (clip : Nat) (file line : String)
  | markWrite (file : String)
  /-- After a mark's rewrite: lines whose appends to `file` landed while it ran must still be
  there. -/
  | verify (file : String) (lines : List String)
  | ignore
deriving Repr, Inhabited

/-- What the overlay is showing. -/
inductive Look where
  | listening | handsFree | transcribing | typed | failed
deriving Repr, DecidableEq, Inhabited

/-- How many bars the waveform has: about 2.4 s of 20 ms windows. -/
def bars : Nat := 120

structure Overlay where
  clip : Nat := 0
  shown : Bool := false
  look : Look := .listening
  text : String := ""
  /-- When the recording began (monotonic ms), for the elapsed clock. -/
  since : Nat := 0
  /-- Bar heights, oldest first, at most `bars`. -/
  levels : List Nat := []
  /-- Where the preview cut the recording (in samples), newest first. -/
  marks : List Nat := []
deriving Repr, Inhabited

/-- What launch has heard back: `none` while waiting, `some none` for nothing there. -/
structure Boot where
  prefs : Option (Option (Option Bool × Option Bool)) := none
  model : Option (Option String) := none
  enabled : Option (Option Bool) := none
  submits : Option (Option Bool) := none
deriving Repr, Inhabited

/-- The launch requests, sent with the first clock (`initEffects`), under fixed odd ids. Yap's
`start` asks for Accessibility with the system prompt (`ensureAccessibilityPermission()`). -/
def bootAsks : List (Nat × Ask) :=
  [(1, .read prefsPath), (3, .readDefault originalBundle "model"),
   (5, .readDefault originalBundle "enabled"), (7, .readDefault originalBundle "submits"),
   (9, .permission .accessibility true), (11, .permission .microphone false),
   (13, .running originalBundle)]

/-- Where a mark (rewriting a day file with one line marked typed) is. -/
inductive MarkPhase where
  /-- Its read or its write is out. -/
  | rewriting
  /-- Its write is answered: it checks the file once no append is in flight. -/
  | settling
  /-- Its check (a read of the file) is out. -/
  | verifying
deriving Repr, DecidableEq, Inhabited

/-- A mark in progress. -/
structure Mark where
  file : String
  phase : MarkPhase := .rewriting
  /-- Lines whose appends to `file` were answered ok since the mark's read was sent: the
  rewrite may have lost them, so they are checked when it is done. -/
  landed : List String := []
deriving Repr, Inhabited

structure Io where
  /-- The next id for the app's own requests: odd, so never a machine request's `2q`. -/
  nextId : Nat := 15
  /-- The app's own requests in flight, newest first. -/
  pending : List (Nat × Pend) :=
    [(1, .bootPrefs), (3, .bootModel), (5, .bootEnabled), (7, .bootSubmits), (9, .trust),
     (11, .mic), (13, .original)]
  boot : Boot := {}
  /-- Launch is done: the machine has had `launch`, and files are watched. -/
  launched : Bool := false
  /-- The host's clock as last heard. -/
  mono : Nat := 0
  wall : Int := 0
  zone : Int := 0
  /-- Whether the original Yap is running: `none` until the host has said. -/
  original : Option Bool := none
  micGranted : Option Bool := none
  /-- A problem of the app's own (opening a file), for the menu. -/
  note : String := ""
  /-- Appends to day files in flight: request id, clip (none for a line appended again after
  a mark), file and line, newest first. An entry leaves only when its reply arrives
  (`Io.landed`). Requests run concurrently on the host (docs/effects.md), so a line is in its
  file only once its append is answered. -/
  appends : List (Nat × Option Nat × String × String) := []
  /-- Transcripts whose appends were answered ok: clip, file and line, newest first. -/
  saved : List (Nat × String × String) := []
  /-- Clips whose lines are waiting to be marked typed, oldest first. -/
  marks : List Nat := []
  /-- The mark in progress. -/
  marking : Option Mark := none
  /-- Lines a mark's rewrite lost, to append again (file, line). -/
  reappend : List (String × String) := []
  /-- Clips the host holds samples for. -/
  held : List Nat := []
  overlay : Overlay := {}
deriving Repr, Inhabited

structure AppState where
  core : State := init
  io : Io := {}
  /-- Every clip a `typeText` was sent for, in order: what ^318 counts. Only `feedCore` and
  `menuStep` add to it, with the clips of the machine's `type` commands, each of which `tr`
  sends as exactly one `typeText`. -/
  typed : List Nat := []
deriving Repr, Inhabited

namespace Io

/-- A fresh odd id, remembering what its request is for. -/
def fresh (io : Io) (p : Pend) : Io × Nat :=
  ({ io with nextId := io.nextId + 2, pending := (io.nextId, p) :: io.pending }, io.nextId)

/-- Send `a` under a fresh odd id, remembering what it is for. -/
def ask (io : Io) (p : Pend) (a : Ask) : Io × (Nat × Ask) :=
  let (io, id) := io.fresh p
  (io, (id, a))

/-- The request `id` is answered: what it was for, and the rest. -/
def take (io : Io) (id : Nat) : Option (Pend × Io) :=
  (io.pending.lookup id).map fun p => (p, { io with pending := io.pending.filter (·.1 != id) })

def asking (io : Io) (f : Pend → Bool) : Bool := io.pending.any (f ·.2)

/-- Whether a reply says a request worked. -/
def _root_.Cairn.Reply.ok : Cairn.Reply → Bool
  | .failed .. => false
  | _ => true

/-- The reply `r` to request `id` is in: if `id` was an append to a day file, it is no longer in
flight; if it worked, its line is in the file, so its clip can be marked, and a mark running
checks the line when it is done. A failed append is dropped: its line isn't there (the machine
reports the failure), so its clip's mark is dropped too (`startMark`). -/
def landed (io : Io) (id : Nat) (r : Cairn.Reply) : Io :=
  match io.appends.find? (·.1 == id) with
  | none => io
  | some (_, clip, file, line) =>
    { io with
      appends := io.appends.filter (·.1 != id)
      saved := match r.ok, clip with
        | true, some c => ((c, file, line) :: io.saved).take 20
        | _, _ => io.saved
      marking := if r.ok then io.marking.map (fun m =>
          if m.file = file ∧ m.phase ≠ .verifying then { m with landed := m.landed ++ [line] } else m)
        else io.marking }

end Io

/-! ## Encoding -/

def utf8 (d : ByteArray) : String := (String.fromUTF8? d).getD ""

/-- A text file as `String(contentsOf:encoding: .utf8)` reads it: one leading byte order mark
dropped; none if it isn't UTF-8. -/
def readUtf8 (d : ByteArray) : Option String :=
  (String.fromUTF8? d).map fun t => if t.startsWith "\uFEFF" then (t.drop 1).toString else t

/-- The scalar a well-formed UTF-8 sequence of 2 to 4 bytes starts with `b` takes, and the
range its second byte must be in (Unicode's table 3-7). -/
def utf8Lead (b : Nat) : Option (Nat × Nat × Nat × Nat) :=
  if 0xC2 ≤ b ∧ b ≤ 0xDF then some (1, b - 0xC0, 0x80, 0xBF)
  else if b = 0xE0 then some (2, b - 0xE0, 0xA0, 0xBF)
  else if (0xE1 ≤ b ∧ b ≤ 0xEC) ∨ b = 0xEE ∨ b = 0xEF then some (2, b - 0xE0, 0x80, 0xBF)
  else if b = 0xED then some (2, b - 0xE0, 0x80, 0x9F)
  else if b = 0xF0 then some (3, b - 0xF0, 0x90, 0xBF)
  else if 0xF1 ≤ b ∧ b ≤ 0xF3 then some (3, b - 0xF0, 0x80, 0xBF)
  else if b = 0xF4 then some (3, b - 0xF0, 0x80, 0x8F)
  else none

/-- `String(decoding:as: UTF8.self)`: each maximal ill-formed subpart becomes U+FFFD. -/
def utf8Lossy (bs : List UInt8) : String :=
  String.ofList (go bs.length bs [])
where
  go : Nat → List UInt8 → List Char → List Char
  | 0, _, acc => acc.reverse
  | _ + 1, [], acc => acc.reverse
  | fuel + 1, b :: rest, acc =>
    if b.toNat < 0x80 then go fuel rest (Char.ofNat b.toNat :: acc)
    else match utf8Lead b.toNat with
      | none => go fuel rest ('\uFFFD' :: acc)
      | some (n, v, lo, hi) =>
        -- Continuation bytes: the second in `[lo, hi]`, the rest in `[0x80, 0xBF]`.
        let rec cont : Nat → Nat → Bool → List UInt8 → Option Nat × List UInt8
          | 0, v, _, r => (some v, r)
          | k + 1, v, first, c :: r =>
            let ok := if first then lo ≤ c.toNat ∧ c.toNat ≤ hi else 0x80 ≤ c.toNat ∧ c.toNat ≤ 0xBF
            if ok then cont k (v * 64 + (c.toNat - 0x80)) false r else (none, c :: r)
          | _ + 1, _, _, [] => (none, [])
        match cont n v true rest with
        | (some v, r) => go fuel r (Char.ofNat v :: acc)
        | (none, r) => go fuel r ('\uFFFD' :: acc)

/-- One transcript as a line of its day file, as Yap's `TranscriptLog` writes it: sorted keys,
no `app` when there is none, the date in ISO 8601 UTC. -/
def transcriptLine (t : Transcript) : String :=
  Json.compact ((match t.app with
      | some a => [("app", Json.str a)]
      | none => []) ++
    [("date", .str (Dates.iso t.date)), ("text", .str t.text), ("typed", .bool t.typed)])

/-- A day file's line read back, as `JSONDecoder` decodes Yap's `Transcript`: none unless it is
an object with a text, an ISO 8601 date (`Dates.parseIso`) and `typed`, and an `app` that is a
string, null or left out. -/
def parseTranscript (line : String) : Option Transcript := do
  let j ← Json.parseBytes line.toUTF8
  match j with
  | .obj _ =>
    let text ← (j.field "text").bind Json.Json.getStr
    let date ← ((j.field "date").bind Json.Json.getStr).bind Dates.parseIso
    let typed ← (j.field "typed").bind Json.Json.getBool
    let app ← match j.field "app" with
      | none | some .null => some none
      | some v => v.getStr.map some
    some { clip := none, text, app, typed, date }
  | _ => none

/-- The line breaks a day file is split at: Swift's `Character.isNewline` but for U+0085,
U+2028 and U+2029, which `JSONEncoder` leaves unescaped inside a transcript's text (Yap splits
at them too, and loses the transcript; docs/yap-parity.md). The others can't be in a line
`JSONEncoder` wrote. -/
def isLineBreak (c : Char) : Bool := c == '\n' || c == '\r' || c.val == 0x0B || c.val == 0x0C

/-- A day file's transcripts, newest (last) first, skipping lines that don't parse; nothing if
the file isn't UTF-8. -/
def fileTranscripts (data : ByteArray) : List Transcript :=
  match readUtf8 data with
  | some t => ((splitWhen isLineBreak t.toList).map String.ofList).reverse.filterMap parseTranscript
  | none => []

/-- `config.json` as Yap's `Config.save` writes it: pretty, sorted keys. -/
def configText (c : Settings) : String :=
  Json.pretty [("keepTranscripts", .bool c.keepTranscripts), ("key", .str c.key),
    ("overlay", .bool c.overlay), ("retentionDays", .int c.retentionDays)]

/-- `DecodingError`'s `localizedDescription`s, in English. -/
def notInFormat : String := "The data couldn’t be read because it isn’t in the correct format."
def isMissing : String := "The data couldn’t be read because it is missing."

/-- A field of `config.json` (`decodeIfPresent`): left out or null is none; the wrong type
makes the file unreadable. -/
def fieldOf {α : Type} (j : Json) (k : String) (get : Json → Option α) : Option (Option α) :=
  match j.field k with
  | none | some .null => some none
  | some v => (get v).map some

/-- `config.json` as Yap's `Config.load` decodes it with `JSONDecoder`: the error is
`DecodingError`'s description. -/
def parseConfig (data : ByteArray) : ConfigRead :=
  match Json.parseBytes data with
  | some j@(.obj _) =>
    let r : Option ConfigFile := do
      let keepTranscripts ← fieldOf j "keepTranscripts" Json.Json.getBool
      let retentionDays ← fieldOf j "retentionDays" Json.Json.getInt
      let overlay ← fieldOf j "overlay" Json.Json.getBool
      let key ← fieldOf j "key" Json.Json.getStr
      pure { keepTranscripts, retentionDays, overlay, key }
    match r with
    | some f => .ok f
    | none => .unreadable notInFormat
  | some .null => .unreadable isMissing
  | _ => .unreadable notInFormat

def prefsText (enabled submits : Bool) : String :=
  Json.compact [("enabled", .bool enabled), ("submits", .bool submits)] ++ "\n"

def parsePrefs (data : ByteArray) : Option (Option Bool × Option Bool) := do
  let j ← Json.parse (utf8 data)
  some (((j.field "enabled").bind Json.Json.getBool), ((j.field "submits").bind Json.Json.getBool))

/-- A boolean default as `UserDefaults.bool(forKey:)` reads the text `readDefault` gives: "1",
or "yes" or "true" in any case, is true; anything else is false. -/
def parseFlag (data : ByteArray) : Bool :=
  match (utf8 data).toList.map Char.toLower with
  | ['1'] | ['y', 'e', 's'] | ['t', 'r', 'u', 'e'] => true
  | _ => false

/-- The machine's launch input, once every launch read is back. Toggles come from prefs.json,
else from the original's defaults, else Yap's defaults (on, no Return). -/
def launchPrefs (b : Boot) : Option Prefs := do
  let p ← b.prefs
  let m ← b.model
  let e ← b.enabled
  let u ← b.submits
  let (pe, pu) := p.getD (none, none)
  some { enabled := (pe <|> e).getD true, submits := (pu <|> u).getD false, model := m }

/-! ### The transcription request

OpenAI's `audio/transcriptions` as Yap's `OpenAITranscription` sends it: multipart with
`model`, `response_format=json`, the prompt if there is one, then the WAV. -/

def formField (boundary name value : String) : String :=
  s!"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"

def uploadHead (boundary model : String) (prompt : Option String) : String :=
  formField boundary "model" model ++ formField boundary "response_format" "json" ++
    (match prompt with
     | some p => if p.isEmpty then "" else formField boundary "prompt" p
     | none => "") ++
    s!"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n"

def uploadTail (boundary : String) : String := s!"\r\n--{boundary}--\r\n"

def apiKey : Secret :=
  { header := "Authorization", scheme := "Bearer ", file := secretsPath, name := "OPENAI_API_KEY" }

/-- Windows `[start, stop)` of `clip` (all of it with `none`), transcribed. -/
def transcription (clip start : Nat) (stop : Option Nat) (model : String) (prompt : Option String) :
    Request :=
  let boundary := boundaryFor clip start stop
  .upload "POST" transcriptionURL
    [("Content-Type", s!"multipart/form-data; boundary={boundary}")] (some apiKey)
    [.bytes (uploadHead boundary model prompt).toUTF8, .wav clip start stop,
     .bytes (uploadTail boundary).toUTF8]
    transcriptionTimeoutMs

/-- An upload of a whole clip: what ^311 and ^323 are about. -/
def _root_.Cairn.Request.wholeClip : Request → Option Nat
  | .upload _ _ _ _ [_, .wav c 0 none, _] _ => some c
  | _ => none

/-- What OpenAI said: the transcript, or Yap's error text (`OpenAITranscription.decode`): a
2xx's `{"text": …}` as `JSONDecoder` decodes it, else `OpenAI <status>: ` and the error's
message, or the body's first 500 bytes. -/
def transcriptReply : Cairn.Reply → Reply
  | .http status _ body =>
    let j := Json.parseBytes body
    if 200 ≤ status ∧ status < 300 then
      match j with
      | some j@(.obj _) =>
        match j.field "text" with
        | some (.str t) => .ok t
        | none | some .null => .failed isMissing
        | some _ => .failed notInFormat
      | some .null => .failed isMissing
      | _ => .failed notInFormat
    else
      match j.bind (·.field "error") |>.bind (·.field "message") |>.bind Json.Json.getStr with
      | some m => .failed s!"OpenAI {status}: {m}"
      | none => .failed s!"OpenAI {status}: {utf8Lossy (body.toList.take 500)}"
  | .failed _ m => .failed m
  | _ => .failed "unexpected reply"

/-- Why typing failed, in Yap's words (`TextInjector.Failure`): the host's faults are the
same checks in the same order, its texts the framework's. -/
def typeFault (app : Option String) : Fault → String → String
  | .invalid, _ => "nothing to type"
  | .denied, _ => "Accessibility is not granted, so Yap cannot type"
  | .notFound, _ => "that app is no longer running"
  | .other, _ => s!"{app.getD "that app"} would not come to the front"
  | _, m => m

/-- A reply to machine request `q`, in the machine's terms. -/
def coreReply (s : State) (q : Nat) (r : Cairn.Reply) : Reply :=
  match s.reqs.lookup q with
  | some (.clip _) | some (.chunk _ _) => transcriptReply r
  | some (.type _ t) => match r with
    | .failed f m => .failed (typeFault t.app f m)
    | _ => .ok ""
  | _ => match r with
    | .failed _ m => .failed m
    | _ => .ok ""

/-! ## The overlay -/

/-- A 20 ms window's bar: 2 to 58 points, on a square-root scale of its RMS. -/
def barHeight (l : Level) : Nat :=
  let rms := Nat.sqrt (l.sumSq / 320)
  2 + min 56 (Nat.sqrt rms * 56 / 60)

def Overlay.apply (o : Overlay) (now c : Nat) : OverlayCmd → Overlay × List Effect
  | .begin => ({ clip := c, shown := true, since := now }, [])
  | .phase p =>
    if o.clip = c ∧ o.shown then
      ({ o with look := match p with
          | .handsFree => .handsFree | .transcribing => .transcribing
          | .typed => .typed | .failed => .failed }, [])
    else (o, [])
  | .text t => if o.clip = c ∧ o.shown then ({ o with text := t }, []) else (o, [])
  | .mark n => if o.clip = c ∧ o.shown then ({ o with marks := n :: o.marks.take 20 }, []) else (o, [])
  | .hide ms =>
    if ms = 0 then (if o.clip = c then ({ o with shown := false }, []) else (o, []))
    else (o, [.setTimer s!"hide{c}" ms])

def Overlay.hear (o : Overlay) (c : Nat) (ls : List Level) : Overlay :=
  if o.clip = c ∧ o.shown then
    let hs := o.levels ++ ls.map barHeight
    { o with levels := hs.drop (hs.length - bars) }
  else o

/-! ## Commands to effects -/

/-! ### Marking a line typed

A typed transcript's line in its day file is rewritten with `"typed":true`: read the file,
replace the line, write the file (atomically). That races with appends: requests run
concurrently on the host and nothing orders their completion (docs/effects.md), so a line is
only known to be in its file once its append is answered, and an append in flight while the
file is rewritten can be lost. So:

* a mark starts only when no append is in flight (`nextMark`; ^347), so its clip's own append
  has been answered, and answered ok, or the clip isn't in `saved` and its mark is dropped;
* once its write is answered, it waits again for the appends in flight, then reads the file
  and appends again any line that landed while it ran and is gone (`Pend.verify`);
* a line that still can't be found, or a read or write that fails, leaves a note in the menu
  (`markNote`) rather than vanishing.

This all runs at the end of each message (`prep` for messages the machine doesn't hear,
`collect` for those it does), so a mark never starts in the same frame as an append. -/

def markNote (file why : String) : String := s!"Couldn't mark a transcript typed in {file}: {why}"

/-- Start the next mark whose clip's line is saved; a clip whose append failed has nothing to
mark and is dropped. Called only when no append is in flight. -/
def startMark (io : Io) : List Nat → Io × List (Nat × Ask)
  | [] => ({ io with marks := [] }, [])
  | c :: rest =>
    match io.saved.find? (·.1 == c) with
    | some (_, file, line) =>
      let (io, a) := { io with marks := rest, marking := some { file := file } }.ask
        (.markRead c file line) (.read file)
      (io, [a])
    | none => startMark io rest

/-- Append again the lines a mark's rewrite lost; each is an append in flight. -/
def reappendAll (io : Io) : List (String × String) → Io × List (Nat × Ask)
  | [] => ({ io with reappend := [] }, [])
  | (f, l) :: rest =>
    let (io, a) := io.ask .ignore (.append f l)
    let (io, as) := reappendAll { io with appends := (a.1, none, f, l) :: io.appends } rest
    (io, a :: as)

/-- Once no append is in flight: check a settled mark's file, or start the next mark. -/
def nextMark (io : Io) : Io × List (Nat × Ask) :=
  if io.appends.isEmpty then
    match io.marking with
    | none => startMark io io.marks
    | some m =>
      if m.phase = .settling then
        if m.landed.isEmpty then startMark { io with marking := none } io.marks
        else
          let (io, a) := { io with marking := some { m with phase := .verifying } }.ask
            (.verify m.file m.landed) (.read m.file)
          (io, [a])
      else (io, [])
  else (io, [])

/-- The marks' next requests, at the end of a message. -/
def pumpMarks (io : Io) : Io × List (Nat × Ask) :=
  let r := reappendAll io io.reappend
  let n := nextMark r.1
  (n.1, r.2 ++ n.2)

/-- The machine's commands that become the app's own requests. -/
def trAsk (io : Io) : Cmd → Io × List (Nat × Ask)
  | .readConfig => let (io, a) := io.ask .config (.read configPath); (io, [a])
  | .readDictionary => let (io, a) := io.ask .dictionary (.read dictionaryPath); (io, [a])
  | .startRecording c =>
    let (io, a) := { io with held := c :: io.held }.ask (.front c) .front
    let (io, b) := io.ask .model (.readDefault originalBundle "model")
    (io, [a, b])
  | .storePrefs p =>
    let (io, a) := io.ask .ignore (.write prefsPath (prefsText p.enabled p.submits)); (io, [a])
  | .play snd =>
    let name := match snd with | .tink => "Tink" | .pop => "Pop" | .basso => "Basso"
    let (io, a) := io.ask .ignore (.sound name); (io, [a])
  | .listDays => let (io, a) := io.ask .days (.list transcriptsDir); (io, [a])
  | .loadRecent n => let (io, a) := io.ask (.recentList n) (.list transcriptsDir); (io, [a])
  | .markTyped c => ({ io with marks := io.marks ++ [c] }, [])
  | .open o =>
    let (p, a) : Pend × Ask := match o with
      | .transcriptsFolder => (.opening transcriptsDir, .openItem transcriptsDir)
      | .accessibility => (.opening accessibilitySettings, .openItem accessibilitySettings)
      | .dictionary => (.ensure dictionaryPath dictionaryTemplate dictionaryPath, .read dictionaryPath)
      | .settings => (.ensure configPath "" configPath, .read configPath)
    let (io, a) := io.ask p a
    (io, [a])
  | _ => (io, [])

/-- The ids for deleting these days' files. -/
def deletes (io : Io) : List Nat → Io × List Effect
  | [] => (io, [])
  | d :: ds =>
    let (io1, id) := io.fresh .ignore
    let (io2, es) := deletes io1 ds
    (io2, .request id (.deleteFile (dayPath d)) :: es)

/-- One machine command as effects. A request `q` is sent as `2q`. -/
def tr (io : Io) : Cmd → Io × List Effect
  | .transcribe q c model prompt => (io, [.request (2 * q) (transcription c 0 none model prompt)])
  | .transcribeChunk q c a b model prompt =>
    (io, [.request (2 * q)
      (transcription c (a / Chunker.windowSamples) (some (b / Chunker.windowSamples)) model prompt)])
  | .type q _ pid text ret => (io, [.request (2 * q) (.typeText pid text ret)])
  | .save q t =>
    let file := dayPath (Dates.localDay t.date io.zone)
    let line := transcriptLine t ++ "\n"
    ({ io with appends := (2 * q, t.clip, file, line) :: io.appends },
     [.request (2 * q) (.appendFile file line.toUTF8)])
  | .saveConfig q c => (io, [.request (2 * q) (.writeFile configPath (configText c).toUTF8)])
  | .deleteDays ds => deletes io ds
  | .copy t => (io, [.setClipboard t])
  | .wakeAt t => (io, [.setTimer s!"wake{t}" (t - io.mono)])
  | .overlay c o =>
    let (ov, es) := io.overlay.apply io.mono c o
    ({ io with overlay := ov }, es)
  | c => let (io, as) := trAsk io c; (io, as.map Ask.effect)

/-- The machine's commands as effects, in order. -/
def trAll : Io → List Cmd → Io × List Effect
  | io, [] => (io, [])
  | io, c :: cs =>
    let a := tr io c
    let b := trAll a.1 cs
    (b.1, a.2 ++ b.2)

/-- The clips the machine may still need samples of: recording, or being transcribed. -/
def needed (s : State) : List Nat :=
  (s.recording.map (·.clip)).toList ++ s.reqs.filterMap fun p => match p.2 with
    | .clip c => some c.clip
    | .chunk c _ => some c
    | _ => none

/-- Ask the host to drop these clips' samples, in order. -/
def forgetAll (io : Io) : List Nat → Io × List (Nat × Ask)
  | [] => (io, [])
  | c :: cs =>
    let (io, a) := io.ask .ignore (.forget c)
    let (io, as) := forgetAll io cs
    (io, a :: as)

/-- Let the host drop the samples of clips no longer needed. -/
def forget (io : Io) (s : State) : Io × List (Nat × Ask) :=
  forgetAll { io with held := io.held.filter (fun c => (needed s).contains c) }
    (io.held.filter (fun c => !(needed s).contains c))

/-- The end of a step: forget the samples no longer needed, then the marks' next requests. -/
def collect (io : Io) (s : State) : Io × List (Nat × Ask) :=
  let f := forget io s
  let p := pumpMarks f.1
  (p.1, f.2 ++ p.2)

/-! ## Messages to inputs -/

/-- What a message is to the app: its new `Io`, its own requests, at most one input for the
machine, and the wall clock if it changed. -/
structure Prep where
  io : Io
  asks : List (Nat × Ask) := []
  input : Option Input := none
  wall : Option Int := none

/-- Read the next day file for the recent list, or hand what was read to the machine. -/
def nextRecent (io : Io) (n : Nat) (rest : List String) (acc : List Transcript) : Prep :=
  if n ≤ acc.length then { io, input := some (.recentLoaded (acc.take n)) }
  else match rest with
    | [] => { io, input := some (.recentLoaded acc) }
    | f :: fs =>
      let (io, a) := io.ask (.recentFile n fs acc) (.read (transcriptsDir ++ "/" ++ f))
      { io, asks := [a] }

/-- The day files among a folder's names, newest first. -/
def dayFiles (names : List String) : List String :=
  ((names.filterMap fun n => (Dates.parseDayFile n).map fun d => (d, n)).mergeSort
    (fun a b => decide (b.1 ≤ a.1))).map (·.2)

/-- Replace the last line equal to `line` (without its newline) by `line'`. -/
def replaceLast (content line line' : String) : Option String :=
  let ls := content.splitOn "\n"
  let target := (line.dropEnd 1).toString
  let rec go : List String → Option (List String)
    | [] => none
    | l :: rest =>
      match go rest with
      | some rest' => some (l :: rest')
      | none => if l = target then some ((line'.dropEnd 1).toString :: rest) else none
  (go ls).map ("\n".intercalate ·)

/-- A mark's rewrite is over (written, or given up): it settles, and is checked once no append
is in flight (`nextMark`). -/
def markDone (io : Io) : Prep :=
  { io := { io with marking := io.marking.map ({ · with phase := .settling }) } }

/-- The launch input, once every launch read is back. -/
def booted (io : Io) : Prep :=
  if io.launched then { io } else
  match launchPrefs io.boot with
  | some p => { io := { io with launched := true }, input := some (.launch p) }
  | none => { io }

def faultNote (target m : String) : String := s!"Couldn't open {target}: {m}"

/-- A reply to one of the app's own requests. -/
def ownReply (s : AppState) (p : Pend) (io : Io) (r : Cairn.Reply) : Prep :=
  match p with
  | .config =>
    { io, input := some (.config (match r with
        | .bytes d => parseConfig d
        -- `Config.load`: a file that can't be read at all is the defaults.
        | _ => .missing)) }
  | .dictionary =>
    { io, input := some (.dictionary (match r with
        | .bytes d => (readUtf8 d).getD ""
        | _ => "")) }
  | .bootPrefs =>
    booted { io with boot := { io.boot with prefs := some (match r with
      | .bytes d => parsePrefs d
      | _ => none) } }
  | .bootModel =>
    booted { io with boot := { io.boot with model := some (match r with
      | .bytes d => some (utf8 d)
      | _ => none) } }
  | .model =>
    { io, input := some (.model (match r with
        | .bytes d => some (utf8 d)
        | _ => none)) }
  | .bootEnabled =>
    booted { io with boot := { io.boot with enabled := some (match r with
      | .bytes d => some (parseFlag d)
      | .failed .invalid _ => some false
      | _ => none) } }
  | .bootSubmits =>
    booted { io with boot := { io.boot with submits := some (match r with
      | .bytes d => some (parseFlag d)
      | .failed .invalid _ => some false
      | _ => none) } }
  | .front c =>
    match r with
    | .app pid name =>
      { io, input := some (.front c { pid, name := if name.isEmpty then none else some name }) }
    | _ => { io }
  | .days =>
    match r with
    | .names ns =>
      { io, input := some (.transcriptDays (Dates.localDay io.wall io.zone).toNat
          (ns.filterMap Dates.parseDayFile)) }
    | _ => { io }
  | .recentList n =>
    match r with
    | .names ns => nextRecent io n (dayFiles ns) []
    | _ => { io, input := some (.recentLoaded []) }
  | .recentFile n rest acc =>
    match r with
    | .bytes d => nextRecent io n rest (acc ++ fileTranscripts d)
    | _ => nextRecent io n rest acc
  | .trust =>
    match r with
    | .flag b => { io, input := some (.trust b) }
    | _ => { io }
  | .mic =>
    -- Granted clears the warning; not granted may only mean not asked yet, which the first
    -- recording asks (as Yap's does), so only a recording that was refused sets it.
    match r with
    | .flag true => { io := { io with micGranted := some true } }
    | _ => { io }
  | .micAsk =>
    match r with
    | .flag true => { io := { io with micGranted := some true } }
    | _ =>
      let (io, a) := { io with micGranted := some false }.ask (.opening microphoneSettings)
        (.openItem microphoneSettings)
      { io, asks := [a] }
  | .original =>
    match r with
    | .flag b =>
      let io' := { io with original := some b }
      if b ∧ (s.core.keyHeld ∨ s.core.recording.isSome) then { io := io', input := some .keyLost }
      else { io := io' }
    | _ => { io }
  | .ensure path data target =>
    match r with
    | .failed .notFound _ =>
      let data := if path = configPath then configText s.core.settings else data
      let (io, a) := io.ask (.create target) (.write path data)
      { io, asks := [a] }
    | _ =>
      let (io, a) := io.ask (.opening target) (.openItem target)
      { io, asks := [a] }
  | .create target =>
    match r with
    | .failed _ m => { io := { io with note := faultNote target m } }
    | _ =>
      let (io, a) := io.ask (.opening target) (.openItem target)
      { io, asks := [a] }
  | .opening target =>
    match r with
    | .failed _ m => { io := { io with note := faultNote target m } }
    | _ => { io := { io with note := "" } }
  | .markRead c file line =>
    match r with
    | .bytes d =>
      let line' := transcriptLine ({ (parseTranscript (line.dropEnd 1).toString).getD
        { clip := none, text := "" } with typed := true }) ++ "\n"
      match replaceLast (utf8 d) line line' with
      | some content =>
        let (io, a) := { io with saved := io.saved.filter (·.1 != c) }.ask (.markWrite file)
          (.write file content)
        { io, asks := [a] }
      | none =>
        -- Its append was answered ok, so the line was there: something else changed the file
        -- (an edit, a half-written line before it). The transcript stays untyped on disk.
        markDone { io with saved := io.saved.filter (·.1 != c),
                           note := markNote file "its line isn't there" }
    | .failed _ m => markDone { io with note := markNote file m }
    | _ => markDone io
  | .markWrite file =>
    match r with
    | .failed _ m => markDone { io with note := markNote file m }
    | _ => markDone io
  | .verify file lines =>
    match r with
    | .bytes d =>
      let present := (utf8 d).splitOn "\n"
      let missing := lines.filter fun l => !present.contains (l.dropEnd 1).toString
      { io := { io with marking := none, reappend := io.reappend ++ missing.map (file, ·) } }
    | .failed _ m => { io := { io with marking := none, note := markNote file m } }
    | _ => { io := { io with marking := none } }
  | .ignore => { io }

/-- Check the permissions and the original Yap, unless a check is still out. -/
def checks (io : Io) : Io × List (Nat × Ask) :=
  if io.asking (fun p => match p with | .trust | .mic | .original => true | _ => false) then (io, [])
  else
    let (io, a) := io.ask .trust (.permission .accessibility false)
    let (io, b) := io.ask .mic (.permission .microphone false)
    let (io, c) := io.ask .original (.running originalBundle)
    (io, [a, b, c])

/-- What a message is, before the marks' next requests. -/
def prepMsg (s : AppState) : Msg → Prep
  | .clock t =>
    { io := { s.io with mono := t.mono, wall := t.wall, zone := t.zone },
      input := some (.tick t.mono), wall := some t.wall }
  | .timer n =>
    if n = s!"hide{s.io.overlay.clip}" then
      { io := { s.io with overlay := { s.io.overlay with shown := false } } }
    else { io := s.io, input := some (.tick s.io.mono) }
  | .reply id r =>
    let io := s.io.landed id r
    if id % 2 = 0 then { io, input := some (.reply (id / 2) (coreReply s.core (id / 2) r)) }
    else match io.take id with
      | some (p, io) => ownReply s p io r
      | none => { io }
  | .sub (.every _) .tick => let (io, as) := checks s.io; { io, asks := as }
  | .sub (.watchFile p) .changed =>
    if p = configPath then let (io, a) := s.io.ask .config (.read configPath); { io, asks := [a] }
    else if p = dictionaryPath then
      let (io, a) := s.io.ask .dictionary (.read dictionaryPath); { io, asks := [a] }
    else { io := s.io }
  | .sub (.record c) (.audio frames peak ws) =>
    { io := { s.io with overlay := s.io.overlay.hear c ws },
      input := some (.audio c { frames, peak, windows := ws.map fun l => ⟨l.sumSq, l.peak⟩ }) }
  | .sub (.record c) (.failed f m) =>
    { io := if f = .denied then { s.io with micGranted := some false } else s.io,
      input := some (.micFailed c m) }
  | .sub (.globalKey ..) (.keyDown t) => { io := s.io, input := some (.keyDown t none) }
  | .sub (.globalKey ..) (.keyUp t) => { io := s.io, input := some (.keyUp t) }
  | .sub (.globalKey ..) (.otherKey _) => { io := s.io, input := some .otherKey }
  | .sub (.globalKey ..) (.failed _ _) => { io := s.io, input := some .keyLost }
  | .sub _ _ => { io := s.io }

/-- What a message is to the app. When the machine hears nothing, the marks' next requests come
last here; otherwise they come last in `collect`. -/
def prep (s : AppState) (m : Msg) : Prep :=
  let p := prepMsg s m
  match p.input with
  | none => let k := pumpMarks p.io; { p with io := k.1, asks := p.asks ++ k.2 }
  | some _ => p

/-! ## The app's `receive` -/

/-- The machine's step, as effects: one input, then its commands in order, then the clips it
no longer needs. -/
def feedCore (core : State) (io : Io) (typed : List Nat) (i : Input) : AppState × List Effect :=
  let o := step core i
  let t := trAll io o.2
  let g := collect t.1 o.1
  ({ core := o.1, io := g.1, typed := typed ++ typedClips o.2 }, t.2 ++ g.2.map Ask.effect)

/-- The machine's state as the message finds it: the wall clock moves with `Msg.clock`. -/
def coreAt (s : AppState) (p : Prep) : State :=
  match p.wall with
  | some w => { s.core with wall := w }
  | none => s.core

def receive (s : AppState) (m : Msg) : AppState × List Effect :=
  let p := prep s m
  match p.input with
  | none => ({ core := coreAt s p, io := p.io, typed := s.typed }, p.asks.map Ask.effect)
  | some i =>
    let o := feedCore (coreAt s p) p.io s.typed i
    (o.1, p.asks.map Ask.effect ++ o.2)

/-- A menu item's machine action, as effects. -/
def menuStep (s : AppState) (a : MenuAction) : AppState × List Effect :=
  let o := menu s.core a
  let t := trAll s.io o.2
  ({ core := o.1, io := t.1, typed := s.typed ++ typedClips o.2 }, t.2)

/-! ## Subscriptions -/

/-- The app listens for the key once launched, while Dictate with Key is on, Accessibility is
granted and the host has said the original Yap is not running. Yap's key monitor starts
regardless and hears nothing until Accessibility is granted; a `globalKey` subscription fails
without it, so it starts (again) once the grant is seen. -/
def wantsKey (s : AppState) : Bool :=
  s.io.launched && s.core.enabled && s.core.trusted && s.io.original == some false

def subscriptions (s : AppState) : List Sub :=
  [.every pollEveryMs] ++
  (if s.io.launched then [.watchFile configPath, .watchFile dictionaryPath] else []) ++
  (match s.core.recording with
   | some r => [.record r.clip]
   | none => []) ++
  (if wantsKey s then [.globalKey s.core.hotkey.code s.core.hotkey.modifier] else [])

def initEffects : List Effect := bootAsks.map Ask.effect

end Examples.Yap

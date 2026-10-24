import Examples.Yap.Fuzz
import Examples.Yap.App

/-! # Yap's fuzzer, through the app

`Examples.Yap.Fuzz` plays a random host against `step`. This plays one against the app Nate
runs: the messages a Cairn host sends `receive` (the clock, timers, replies to the requests the
app made, events of the subscriptions it has on), and the menu (`menuStep`). The host answers
what was asked, plausibly and not: files that are there or not, config.json and dictionary.txt
good and bad, OpenAI's transcripts and errors, typing that works or fails, the original Yap
starting and quitting; and replies late, twice, for nothing, or never.

After every step it checks the claims as the app states them (`Examples.Yap`, over
`AppState`, what `receive` returns), as runnable predicates: ^311, ^313–^323, ^346 and ^347.
^312 is an equation about one message from one state, checked when a key-up comes in the state
it names. A failing sequence is shrunk as in the host mode.

The host keeps the day files' contents: an append, a write or a delete changes them when its
answer says it worked, and a read of a day file gives what is there. Requests are answered in
any order (an append can land after the read that marks its line), as a real host's run
concurrently (docs/effects.md). So ^347 is checked twice: a mark's read never goes out while an
append is in flight, and whenever every request is answered, each transcript typed while
transcripts are kept, whose append worked, is `"typed":true` on disk, and no other line is.
A mark the app gives up on must say so in the menu (`markNote`); that excuses the clips
typed so far. -/

namespace Examples.Yap.Fuzz.App
open Examples.Yap Examples.Yap.Fuzz Cairn Cairn.Fuzz

/-- One step of the app: a message from the host, or a menu item. -/
inductive Step where
  | msg (m : Msg)
  | menu (a : MenuAction)
deriving Repr, Inhabited

def Step.run (s : AppState) : Step → AppState × List Effect
  | .msg m => receive s m
  | .menu a => menuStep s a

/-! ## The host -/

/-- What the random host keeps: its clock, requests it hasn't answered (and some it has, to
answer again), the timers asked for, and what is on disk as far as it says. -/
structure Host where
  mono : Nat := 1000
  wall : Int := 1792749600000
  zone : Int := 3600
  pending : List (Nat × Request) := []
  answered : List (Nat × Request) := []
  timers : List String := []
  original : Bool := false
  /-- The day files on disk: path and contents. -/
  files : List (String × String) := []
  /-- Lines appended to day files whose answer said they worked. -/
  appended : List String := []
  /-- Transcripts typed (their lines as saved, untyped), and whether they must be marked
  typed: transcripts were kept when the type was answered. -/
  expect : List (String × Bool) := []
  /-- Every transcript typed: how many lines may be marked. -/
  typedLines : List String := []
  /-- A request was dropped unanswered, or answered in the wrong shape: the disk check is off. -/
  loose : Bool := false
deriving Inhabited

def Host.time (h : Host) : Time := { mono := h.mono, wall := h.wall, zone := h.zone }

def replyOk : Cairn.Reply → Bool
  | .failed .. => false
  | _ => true

def isDayFile (p : String) : Bool := p.startsWith (transcriptsDir ++ "/")

def Host.file (h : Host) (p : String) : Option String := h.files.lookup p

def Host.setFile (h : Host) (p : String) (c : Option String) : Host :=
  let rest := h.files.filter (·.1 != p)
  { h with files := match c with | some c => (p, c) :: rest | none => rest }

/-- A line as the app marks it typed. -/
def typedForm (line : String) : String :=
  transcriptLine ({ (parseTranscript (line.dropEnd 1).toString).getD { clip := none, text := "" }
    with typed := true })

/-- What the host's answer `rep` to `r` did on disk, and what it means for the check. -/
def Host.land (h : Host) (s s' : AppState) (id : Nat) (r : Request) (rep : Cairn.Reply) : Host :=
  if !rep.answers r.kind then { h with loose := true } else
  let h := if replyOk rep then
    match r with
    | .appendFile p d =>
      if isDayFile p then
        let line := utf8 d
        { (h.setFile p (some ((h.file p).getD "" ++ line))) with appended := line :: h.appended }
      else h
    | .writeFile p d => if isDayFile p then h.setFile p (some (utf8 d)) else h
    | .deleteFile p =>
      -- Retention: lines in a deleted file can't be marked.
      let gone := ((h.file p).getD "").splitOn "\n"
      { (h.setFile p none) with expect := h.expect.filter fun (l, _) => !gone.contains (l.dropEnd 1).toString }
    | _ => h
  else h
  match r, s.core.reqs.lookup (id / 2) with
  | .typeText .., some (.type _ t) =>
    if id % 2 == 0 && replyOk rep then
      let line := transcriptLine t ++ "\n"
      { h with expect := h.expect ++ [(line, s.core.settings.keepTranscripts)],
               typedLines := line :: h.typedLines }
    else h
  | _, _ => h

def Host.after (h : Host) (s s' : AppState) (st : Step) (es : List Effect) : Host :=
  let h := match st with
    | .msg (.reply id rep) => match h.pending.lookup id with
      | some r => h.land s s' id r rep
      | none => h
    | _ => h
  -- A mark the app gave up on, said in the menu: the clips typed so far are excused.
  let h := if s'.io.note != s.io.note && s'.io.note.startsWith "Couldn't mark" then { h with expect := [] } else h
  let answered := match st with
    | .msg (.reply id _) => match h.pending.lookup id with
      | some r => ((id, r) :: h.answered).take 12
      | none => h.answered
    | _ => h.answered
  let pending := match st with
    | .msg (.reply id _) => h.pending.filter (·.1 != id)
    | _ => h.pending
  let asked := es.filterMap fun | .request id r => some (id, r) | _ => none
  let timers := es.filterMap fun | .setTimer n _ => some n | _ => none
  let (mono, wall) := match st with
    | .msg (.clock t) => (t.mono, t.wall)
    | _ => (h.mono, h.wall)
  let all := asked ++ pending
  { h with pending := all.take 200, answered, mono, wall, loose := h.loose || all.length > 200,
           timers := (timers ++ h.timers).take 8 }

def configText' : Gen String := Gen.weighted [
  (6, do
    let k ← Gen.elem ["rightCommand", "f13", "F13", "fn", "keycode:61", "nope", ""]
    return s!"\{\"keepTranscripts\":{← Gen.elem ["true", "false"]},\"key\":\"{k}\",\"overlay\":{← Gen.elem ["true", "false"]},\"retentionDays\":{← Gen.elem ["0", "1", "7", "30", "-3"]}}"),
  (1, do return "{\"keepTranscripts\":\"yes\"}"),
  (1, do return "not json"),
  (1, do return "[1,2]"),
  (1, do return "")]


def dayLines : Gen String := do
  let n ← Gen.range 0 4
  let mut out := ""
  for _ in [0:n] do
    let t ← Fuzz.transcript
    out := out ++ transcriptLine { t with date := 1792700000000 - (← Gen.range 0 900000000) } ++ "\n"
  if ← Gen.chance 1 6 then out := out ++ "not a line\n"
  return out

/-- The day files the host lists: around today, some old. -/
def dayNames (h : Host) : Gen (List String) := do
  let today := (Dates.localDay h.wall h.zone).toNat
  let n ← Gen.range 0 6
  let mut out : List String := []
  for _ in [0:n] do
    out := Dates.dayFile ((today - min today (← Gen.range 0 40) : Nat) : Int) :: out
  if ← Gen.chance 1 4 then out := "notes.txt" :: out
  return out

/-- An answer to `r`, plausible or not. -/
def answer (h : Host) (r : Request) : Gen Cairn.Reply := do
  let dayFile := match r with
    | .readFile p | .writeFile p _ => isDayFile p
    | _ => false
  if ← Gen.chance 1 (if dayFile then 30 else 12) then
    return .failed (← Gen.elem [.notFound, .denied, .timeout, .network, .invalid, .other]) "it failed"
  match r with
  | .readFile p =>
    if let some c := h.file p then return .bytes c.toUTF8
    if p == configPath then
      Gen.weighted [(5, do return .bytes (← configText').toUTF8), (2, do return .failed .notFound "no file")]
    else if p == dictionaryPath then
      Gen.weighted [(5, do return .bytes (← Fuzz.dictionaryText).toUTF8), (1, do return .failed .notFound "no file")]
    else if p == prefsPath then
      Gen.weighted [(3, do return .bytes s!"\{\"enabled\":{← Gen.elem ["true", "true", "true", "false"]},\"submits\":{← Gen.elem ["true", "false"]}}".toUTF8),
                    (2, do return .failed .notFound "no file"), (1, do return .bytes "{".toUTF8)]
    else Gen.weighted [(5, do return .bytes (← dayLines).toUTF8), (1, do return .failed .notFound "no file")]
  | .listDir _ => return .names (← dayNames h)
  | .frontmostApp => Gen.weighted [(6, do return .app (← Gen.range 1 4) (← Gen.elem ["Notes", "Terminal", ""])),
                                   (1, do return .failed .other "none")]
  | .permission _ _ => return .flag (← Gen.chance 5 6)
  | .appRunning _ => return .flag h.original
  | .readDefault _ k =>
    if k == "model" then Gen.weighted [(2, do return .bytes "gpt-transcribe".toUTF8), (1, do return .failed .notFound "none"), (1, do return .bytes "".toUTF8)]
    else Gen.weighted [(1, do return .bytes (← Gen.elem ["1", "1", "0", "YES", "x"]).toUTF8), (2, do return .failed .notFound "none")]
  | .upload .. => Gen.weighted [
      (6, do return .http 200 [] s!"\{\"text\":{(Lean.Json.str (← Fuzz.text)).compress}}".toUTF8),
      (1, do return .http 401 [] "{\"error\":{\"message\":\"Incorrect API key\"}}".toUTF8),
      (1, do return .http 500 [] "oops".toUTF8),
      (1, do return .http 200 [] "{}".toUTF8)]
  | .typeText .. => Gen.weighted [(5, do return .done), (1, do return .failed .denied "not trusted")]
  | _ => return .done

def level : Gen Level := do
  let peak ← Gen.weighted [(3, Gen.range 0 400), (5, Gen.range 400 20000)]
  return ⟨peak * peak * 320 / (← Gen.range 1 4), peak⟩

def audioEvent : Gen SubEvent := do
  let ws ← Gen.listOf (← Gen.weighted [(3, Gen.range 0 6), (2, Gen.range 6 30)]) level
  let peak := ws.foldl (fun m l => max m l.peak) 0
  return .audio (ws.length * 320 + (← Gen.range 0 319)) peak ws

def dictation : Request → Bool
  | .frontmostApp | .upload .. | .typeText .. => true
  | _ => false

/-- One step from the host or the person. -/
def nextStep (s : AppState) (h : Host) : Gen Step := do
  let subs := subscriptions s
  let key := subs.find? fun | .globalKey .. => true | _ => false
  let rec_ := subs.find? fun | .record _ => true | _ => false
  let later : Gen Nat := Gen.weighted [(10, do return h.mono + (← Gen.range 0 400)),
    (2, do return h.mono + (← Gen.range 300 5000)), (1, do return h.mono + latchLimit + 1)]
  Gen.weighted [
    (10, do return .msg (.clock { h.time with mono := ← later, wall := h.wall + ((← Gen.range 0 400000 : Nat) : Int) })),
    (16, do match h.pending with
      | [] => return .msg (.clock h.time)
      | ps =>
        -- Often in order; as often any of them, as the host's concurrent requests finish.
        let (id, r) ← if ← Gen.chance 1 2 then pure (ps.getLast?.getD default) else Gen.elem ps
        return .msg (.reply id (← answer h r))),
    -- Dictation's requests (the app in front, the upload, the typing) answered soon, as a
    -- host does while the rest wait.
    (if h.pending.any (dictation ·.2) then 10 else 0, do
      match h.pending.reverse.find? (dictation ·.2) with
      | some (id, r) => return .msg (.reply id (← answer h r))
      | none => return .msg (.clock h.time)),
    (2, do match h.answered with
      | [] => return .msg (.reply (← Gen.range 0 40) .done)
      | as => let (id, r) ← Gen.elem as; return .msg (.reply id (← answer h r))),
    (1, do return .msg (.reply (← Gen.range 0 60) (.failed .other "stray"))),
    (12, do match key with
      | some k => return .msg (.sub k (← Gen.weighted [
          (5, do return .keyDown (← later)), (3, do return .keyUp (← later)),
          -- A release after a real hold, once there is something to send.
          (if s.core.recording.any (·.frames ≥ minimumFrames) then 6 else 0,
            do return .keyUp (max h.mono (s.core.pressedAt + (← Gen.range 300 3000)))),
          (2, do return .otherKey h.mono), (1, do return .failed .denied "gone")]))
      | none => return .msg (.clock h.time)),
    (24, do match rec_ with
      | some r => Gen.weighted [(12, do return .msg (.sub r (← audioEvent))),
                                (1, do return .msg (.sub r (.failed .denied "no microphone")))]
      | none => return .msg (.sub (.record (← Gen.range 0 4)) (← audioEvent))),
    (2, do return .msg (.sub (.every pollEveryMs) .tick)),
    (2, do return .msg (.sub (.watchFile (← Gen.elem [configPath, dictionaryPath])) .changed)),
    (2, do match h.timers with
      | [] => return .msg (.timer "hide0")
      | ts => return .msg (.timer (← Gen.elem ts))),
    (2, do return .menu (← Fuzz.menuAction))]

/-! ## The checks, as the app states the claims -/

def isUpload : Request → Bool
  | .upload .. => true
  | _ => false

def requests (es : List Effect) : List (Nat × Request) :=
  es.filterMap fun | .request id r => some (id, r) | _ => none

def heads (r : Request) : Option ByteArray :=
  match r with
  | .upload _ _ _ _ (.bytes b :: _) _ => some b
  | _ => none

/-- An upload's multipart boundary, from its `Content-Type`. -/
def boundaryOf (r : Request) : Option String :=
  match r with
  | .upload _ _ hs _ _ _ => (hs.lookup "Content-Type").bind fun v =>
      (v.dropPrefix? "multipart/form-data; boundary=").map (·.toString)
  | _ => none

abbrev Check := AppState → Step → AppState → List Effect → Option Bool

def isClockOrTimer : Step → Bool
  | .msg (.clock _) | .msg (.timer _) => true
  | _ => false

def a311 : Check := fun s st _ es =>
  if s.core.keyHeld && s.core.chorded && !isClockOrTimer st then
    some ((requests es).all fun (_, r) => r.wholeClip.isNone)
  else match st with
    | .menu _ => some ((requests es).all fun (_, r) => !isUpload r)
    | _ => none

def a312 : Check := fun s st s' _ =>
  match st, s.core.recording with
  | .msg (.sub (.globalKey ..) (.keyUp t)), some r =>
    if !r.latched && s.core.keyHeld && !s.core.chorded then
      some (s'.core.recording == if max s.core.now t - s.core.pressedAt < tapLimit then
          some { r with latched := true, deadline := max s.core.now t + latchLimit }
        else none)
    else none
  | _, _ => none

def a313 : Check := fun s _ s' _ =>
  let recs := (subscriptions s').filterMap fun | .record c => some c | _ => none
  let subOk := recs == (s'.core.recording.map (·.clip)).toList
  let newOk := match s'.core.recording with
    | some r' => s.core.recording.map (·.clip) == some r'.clip ||
        (s.core.recording.isNone && r'.clip == s.core.nextClip)
    | none => true
  if s.core.recording.isNone && s'.core.recording.isNone then none else some (subOk && newOk)

def a314 : Check := fun _ _ s' _ =>
  if s'.core.recording.isNone then none
  else
    let t := s'.core.now
    let a := (receive s' (.sub (.globalKey 0 none) (.keyUp t))).1
    let b := (receive a (.clock { mono := t + latchLimit, wall := s'.io.wall, zone := s'.io.zone })).1
    some (recOk s'.core && b.core.recording.isNone)

def typeTexts (es : List Effect) : List (Nat × String × Bool) :=
  es.filterMap fun | .request id (.typeText _ t r) => some (id, t, r) | _ => none

def a315 : Check := fun s _ s' es =>
  let ts := typeTexts es
  if ts.isEmpty then none else
  some <| ts.all fun (id, _, _) =>
    let pre := es.takeWhile fun | .request id' (.typeText ..) => id' != id | _ => true
    match s'.core.reqs.lookup (id / 2) with
    | some (.type _ t) =>
      s'.core.recent.any fun t' => t'.clip == t.clip && !t'.typed &&
        (!s.core.settings.keepTranscripts || pre.any fun
          | .request _ (.appendFile _ d) => d.toList == (transcriptLine t' ++ "\n").toUTF8.toList
          | _ => false)
    | _ => false

def a316 : Check := fun s st s' es =>
  match st with
  | .msg (.reply id (.failed _ _)) =>
    if id % 2 != 0 then none else
    match s.core.reqs.lookup (id / 2) with
    | some (.type _ t) =>
      some (s'.core.recent.head? == some { t with typed := false } &&
        es.any fun | .request _ (.playSound "Basso") => true | _ => false)
    | _ => none
  | _ => none

def clipOf (s : AppState) (st : Step) : Option ClipReq :=
  match st with
  | .msg (.reply id _) =>
    if id % 2 != 0 then none else
    match s.core.reqs.lookup (id / 2) with
    | some (.clip cr) => some cr
    | _ => none
  | _ => none

def a317 : Check := fun s st _ es =>
  if (typeTexts es).isEmpty then none else
  some (match clipOf s st with
    | some cr => cr.turn == s.core.turn
    | none => false)

def a318 : Check := fun _ _ s' es =>
  if (typeTexts es).isEmpty then none else
  some (s'.typed.all fun n => s'.typed.count n ≤ 1)

def a319 : Check := fun s st _ es =>
  let ts := typeTexts es
  if ts.isEmpty then none else
  some <| ts.all fun (_, text, _) => match clipOf s st, st with
    | some cr, .msg (.reply _ r) => match transcriptReply r with
      | .ok raw => text == if cr.submits then trimText (applyFixes cr.fixes raw)
          else trimText (applyFixes cr.fixes raw) ++ " "
      | _ => false
    | _, _ => false

def a320 : Check := fun s st _ es =>
  let dels := es.filterMap fun | .request _ (.deleteFile p) => some p | _ => none
  if dels.isEmpty then none else
  let today := (Dates.localDay s.io.wall s.io.zone).toNat
  some <| match st with
    | .msg (.reply _ (.names ns)) =>
      let days := ns.filterMap Dates.parseDayFile
      dels.all fun p => days.any fun d => d < today && p == dayPath d
    | _ => false

def a321 : Check := fun s _ _ es =>
  let ups := (requests es).filter (isUpload ·.2)
  if ups.isEmpty then none else
  let d := first25 s.core.dict
  let ctx := match s.core.recording with
    | some r => [none, context r.heard]
    | none => [none]
  some <| ups.all fun (_, r) => match heads r with
    | some b => match boundaryOf r with
      | some bd => ctx.any fun c => b.toList == (uploadHead bd s.core.model (d.promptFor c)).toUTF8.toList
      | none => false
    | none => false

def a322 : Check := fun _ _ s' _ => some (s'.core.recent.length ≤ recentLimit)

def a323 : Check := fun s _ _ es =>
  let whole := (requests es).filterMap (·.2.wholeClip)
  if whole.isEmpty then none else
  some <| whole.all fun n => match s.core.recording with
    | some r => r.clip == n && r.frames ≥ minimumFrames && r.peak ≥ silencePeak && r.target.isSome
    | none => false

def a346 : Check := fun _ _ s' _ =>
  let keyed := (subscriptions s').any fun | .globalKey .. => true | _ => false
  if s'.io.original == some false then (if keyed then some true else none)
  else some !keyed

/-- ^347, the safety half: a mark's read goes out only when no append is in flight, counting
this step's. -/
def a347 (h' : Host) (s' : AppState) (es : List Effect) : Option Bool :=
  let reads := (requests es).filter fun (id, r) => match r, s'.io.pending.lookup id with
    | .readFile _, some (.markRead ..) => true
    | _, _ => false
  if reads.isEmpty then none else
  some !(h'.pending.any fun (_, r) => match r with | .appendFile .. => true | _ => false)

/-- ^347 on disk: once every request is answered, each transcript typed while transcripts were
kept, whose append worked, is marked typed, and no more lines are marked than were typed. -/
def a347disk (h : Host) : Option Bool :=
  if !h.pending.isEmpty || h.loose || h.typedLines.isEmpty then none else
  let lines := h.files.flatMap fun (_, c) => c.splitOn "\n"
  some <| h.typedLines.all fun l =>
    let marked := lines.count (typedForm l)
    let need := (h.expect.filter fun (l', must) => l' == l && must && h.appended.contains l).length
    need ≤ marked && marked ≤ h.typedLines.count l

/-- The checks that need the host after the step. -/
def hostChecks (h' : Host) (s' : AppState) (es : List Effect) : List (Nat × Option Bool) :=
  [(347, a347 h' s' es), (347, a347disk h')]

def checks : List (Nat × Check) :=
  [(311, a311), (312, a312), (313, a313), (314, a314), (315, a315), (316, a316), (317, a317),
   (318, a318), (319, a319), (320, a320), (321, a321), (322, a322), (323, a323), (346, a346)]

def claimIds : List Nat := checks.map (·.1) ++ [347]

/-! ## Running -/

def stepChecks (st : Fuzz.Stats) (s : AppState) (x : Step) (s' : AppState) (es : List Effect)
    (h' : Host) : Fuzz.Stats × Option Nat := Id.run do
  let mut st := st
  for (id, r) in checks.map (fun (id, c) => (id, c s x s' es)) ++ hostChecks h' s' es do
    match r with
    | some true => st := st.bump id
    | some false => return (st, some id)
    | none => pure ()
  return (st, none)

/-- The first message: the host's clock, which runs the app's launch requests. -/
def launch (h : Host) : AppState × List Effect :=
  let (s, es) := receive {} (.clock h.time)
  (s, initEffects ++ es)

def replay (xs : List Step) : Option (Nat × Nat) := Id.run do
  let mut h : Host := {}
  let (s0, es0) := launch h
  let mut s := s0
  h := h.after {} s0 (.msg (.clock h.time)) es0
  let mut k := 0
  for x in xs do
    let (s', es) := x.run s
    let h' := h.after s s' x es
    match (stepChecks {} s x s' es h').2 with
    | some c => return some (c, k)
    | none => pure ()
    s := s'
    h := h'
    k := k + 1
  return none

structure Failure where
  claim : Nat
  step : Nat
  steps : List Step

def runSeq (seed n : Nat) (st : Fuzz.Stats) : Fuzz.Stats × Option Failure := Id.run do
  let mut g := Rng.ofSeed (seed * 7919 + 1)
  let mut h : Host := {}
  let (s0, es0) := launch h
  let mut s := s0
  h := h.after {} s0 (.msg (.clock h.time)) es0
  let mut xs : Array Step := #[]
  let mut st := st
  for k in [0:n] do
    -- The original Yap starts and quits now and then.
    let (flip, g1) := (Gen.chance 1 150).run g
    g := g1
    if flip then h := { h with original := !h.original }
    let (x, g2) := (nextStep s h).run g
    g := g2
    xs := xs.push x
    let (s', es) := x.run s
    let h' := h.after s s' x es
    let (st', bad) := stepChecks st s x s' es h'
    st := { st' with steps := st'.steps + 1 }
    if let some c := bad then
      return (st, some { claim := c, step := k, steps := xs.toList })
    h := h'
    s := s'
  return (st, none)

partial def ddmin (claim : Nat) (xs : List Step) : List Step :=
  let fails (ys : List Step) := match replay ys with
    | some (c, _) => c == claim
    | none => false
  let rec single (ys : List Step) (j : Nat) : List Step :=
    if j ≥ ys.length then ys else
    let zs := ys.eraseIdx j
    if fails zs then single zs j else single ys (j + 1)
  let ys := match replay xs with
    | some (_, k) => xs.take (k + 1)
    | none => xs
  single ys 0

def claimTitle : Nat → String
  | 346 => "The original Yap keeps its key"
  | 347 => "A mark waits for the appends"
  | n => Fuzz.claimTitle n

/-- Runs the options' sequences through the app; per claim, how many steps exercised it, and
the first failure of each claim, shrunk. -/
def run (o : Opts) : IO AppReport := do
  let mut st : Fuzz.Stats := {}
  let mut fails : Array Failure := #[]
  for j in [0:o.iterations] do
    let (st', f) := runSeq (o.seed + j) o.steps st
    st := st'
    if let some f := f then
      fails := fails.push f
      IO.println s!"FAIL (app) ^{f.claim} {claimTitle f.claim}: seed {o.seed + j}, step {f.step}"
  let mut out : List (Nat × Nat × Nat × String) := []
  for f in fails do
    if out.any (·.1 == f.claim) then continue
    let small := ddmin f.claim f.steps
    let text := (repr small).pretty 200
    IO.println s!"^{f.claim} (app) shrunk from {f.steps.length} steps to {small.length}:\n  {text}"
    out := out ++ [(f.claim, f.step, f.steps.length, text)]
  return { stats := st, claims := claimIds.map fun id => (id, claimTitle id), failures := out,
           failing := fails.size }

/-- `lake exe yapfuzz`: the host mode, then the app mode, one report. -/
def main (args : List String) : IO UInt32 := Fuzz.main args (some run)

end Examples.Yap.Fuzz.App

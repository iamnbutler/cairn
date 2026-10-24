import Lean.Data.Json
import Examples.Yap.Model
import Cairn.Fuzz.Rng

/-! # Yap's fuzzer: a random host

`lake exe yapfuzz [--seed S] [--iterations N] [--steps K] [--out DIR] [-v]` (`make fuzz-yap`).

The generic fuzzer (`lake exe fuzz`, docs/fuzz.md) drives a machine through its moves, which for
Yap are only the menu. Dictation is driven by the host, so this harness plays a random host
against `step`: the key with random timings (taps, holds, repeats, releases that never come),
shortcuts, ticks early, late and jumping (forwards ten minutes, backwards), audio loud, quiet
and for the wrong clip, microphone failures, and replies slow, failed, duplicated, out of order,
for nothing, or never; config.json and dictionary.txt edits, including bad keys and files that
won't parse; day files; and the menu. After every step it checks each of the dictation claims
(^311–^323) as a runnable predicate on that step, and "typed at most once" (^318) over the
whole run. A failing sequence is shrunk (ddmin) to the fewest inputs that fail the same claim,
and printed as a Lean list to paste into `Examples/Yap/Tests.lean`.

It imports the model only, not the proofs, so it still builds when the model is mutated to
check that it catches bugs. The proofs cover the same claims; the fuzzer guards the statements (a claim proved about the
wrong function is caught here) and gives the map its "fuzzed" evidence. -/

namespace Examples.Yap.Fuzz
open Examples.Yap Cairn.Fuzz
open Lean (Json toJson)

/-! ## Generators -/

def words : List String :=
  ["hello", "world", "Kubernetes", "kubernetes", "postgres", "post gress", "Yap", "yap", "uh",
   "café", "CAFÉ", "x-ray", "foo_bar", "naïve", "😀", "a", "I", "rust", "Rust's", "github",
   "git hub", "GitHub", "ok", "okay", "the", "end."]

def seps : List String := [" ", " ", " ", ", ", ". ", "-", "  ", "\n", "", "? "]

def text : Gen String := do
  let n ← Gen.range 0 8
  let mut out := ""
  for _ in [0:n] do
    out := out ++ (← Gen.elem words) ++ (← Gen.elem seps)
  if ← Gen.chance 1 10 then out := "  " ++ out
  return out

def dictionaryText : Gen String := do
  let n ← Gen.range 0 40
  let mut lines : Array String := #[]
  for _ in [0:n] do
    let line ← Gen.weighted [
      (6, do return (← Gen.elem words)),
      (3, do return s!"{← Gen.elem words} => {← Gen.elem words}"),
      (1, do return s!"  {← Gen.elem words}  =>  {← Gen.elem words} "),
      (1, do return "# a comment"),
      (1, do return ""),
      (1, do return " => nothing heard"),
      (1, do return "=>")]
    lines := lines.push line
  return "\n".intercalate lines.toList

def keyNames : List String :=
  ["rightCommand", "rightOption", "rightControl", "rightShift", "fn", "f5", "F13", "f21",
   "keycode:61", "keycode:+54", "keycode:70000", "keycode:", "nope", "", "Right Command"]

def opt {α : Type} [Inhabited α] (g : Gen α) : Gen (Option α) := do
  if ← Gen.chance 1 3 then return none else return some (← g)

def configRead : Gen ConfigRead := Gen.weighted [
  (1, do return .missing),
  (1, do return .unreadable "The data couldn't be read"),
  (6, do return .ok {
      keepTranscripts := ← opt Gen.bool,
      retentionDays := ← opt (Gen.int (-2) 40),
      overlay := ← opt Gen.bool,
      key := ← opt (Gen.elem keyNames) })]

def target : Gen (Option Target) := Gen.weighted [
  (8, do return some ⟨← Gen.range 1 4, some (← Gen.elem ["Terminal", "Notes", "Safari"])⟩),
  (1, do return some ⟨← Gen.range 1 4, none⟩),
  (1, do return none)]

/-- One 20 ms window: speech, or near silence (the chunker's quiet test). -/
def window : Gen Window := Gen.weighted [
  (3, do let a ← Gen.range 150 6000; return ⟨320 * a * a, a * 2⟩),
  (2, do let a ← Gen.range 0 149; return ⟨320 * a * a, a⟩)]

def audio : Gen Audio := do
  let n ← Gen.weighted [(4, Gen.range 0 30), (1, Gen.range 30 200), (1, do return 0)]
  let ws ← Gen.listOf n window
  let peak := ws.foldl (fun m w => max m w.peak) 0
  let peak ← Gen.weighted [(6, do return peak), (1, Gen.range 0 600), (1, do return 0)]
  return { frames := n * 320, peak, windows := ws }

def menuAction : Gen MenuAction := Gen.weighted [
  (2, do return .copyLast), (2, do return .copyRecent (← Gen.range 0 6)), (2, do return .toggleKeep),
  (2, do return .toggleSubmits), (3, do return .toggleEnabled), (1, do return .openTranscripts),
  (1, do return .editDictionary), (1, do return .editSettings), (1, do return .grantAccess)]

def transcript : Gen Transcript := do
  return { clip := ← opt (Gen.range 1 20), text := ← text, app := some "Notes", typed := ← Gen.bool }

/-- What the random host remembers beyond the state: its clock, the ids it has answered (to
answer again), and the times it was asked to wake at. -/
structure Host where
  clock : Nat := 0
  answered : Array Nat := #[]
  wakes : List Nat := []
  /-- Clips whose microphone it was asked to start and hasn't reported on: it reports the start
  (or a failure) when it gets to it, so a start may be slow, and key events come meanwhile. -/
  starting : List Nat := []
deriving Inhabited

def reqOf : Cmd → Option Nat
  | .saveConfig q _ | .transcribe q .. | .transcribeChunk q .. | .save q _ | .type q .. => some q
  | _ => none

def wakeOf : Cmd → Option Nat
  | .wakeAt t => some t
  | _ => none

/-- The next time: mostly a little later, sometimes much later or earlier. -/
def later (h : Host) : Gen Nat := Gen.weighted [
  (10, do return h.clock + (← Gen.range 0 400)),
  (3, do return h.clock + (← Gen.range 0 50)),
  (2, do return h.clock + (← Gen.range 300 5000)),
  (1, do return h.clock + latchLimit + (← Gen.range 0 2)),
  (1, do return h.clock + latchLimit - 1),
  (1, do return h.clock - min h.clock (← Gen.range 0 3000))]

def reply : Gen Reply := Gen.weighted [
  (5, do return .ok (← text)),
  (1, do return .ok ""),
  (2, do return .failed "timed out"),
  (1, do return .failed "The disk is full.")]

/-- One input from the host, given what the model and the host know. -/
def input (s : State) (h : Host) : Gen Input := do
  let clip := match s.recording with
    | some r => r.clip
    | none => s.nextClip - 1
  let started : List (Nat × Gen Input) := match h.starting with
    | [] => []
    | c :: _ =>
      [(12, do return .micStarted c (← later h)),
       (2, do return .micFailed c (← Gen.elem ["no input device", "The operation couldn't be completed."]))]
  Gen.weighted <| started ++ [
    (14, do return .keyDown (← later h) (← target)),
    (14, do return .keyUp (← later h)),
    (4, do return .otherKey),
    (8, do return .tick (← later h)),
    (6, do match h.wakes with
      | [] => return .tick (← later h)
      | ws => return .tick (← Gen.elem ws)),
    (14, do return .audio (if ← Gen.chance 1 10 then clip + 1 else clip) (← audio)),
    (1, do return .micFailed clip "no input device"),
    (18, do match s.reqs with
      | [] => return .reply (← Gen.range 0 (s.nextReq + 1)) (← reply)
      | rs => return .reply (← Gen.elem rs).1 (← reply)),
    (3, do match h.answered.toList with
      | [] => return .reply (← Gen.range 0 (s.nextReq + 1)) (← reply)
      | as => return .reply (← Gen.elem as) (← reply)),
    (2, do return .config (← configRead)),
    (2, do return .dictionary (← dictionaryText)),
    (2, do
      let today ← Gen.range 0 60
      return .transcriptDays today (← Gen.listOf (← Gen.range 0 8) (Gen.range 0 (today + 2)))),
    (1, do return .recentLoaded (← Gen.listOf (← Gen.range 0 7) transcript)),
    (1, do return .trust (← Gen.bool)),
    (4, do match ← target with
      | some t => return .front (if ← Gen.chance 1 10 then clip + 1 else clip) t
      | none => return .otherKey),
    (1, do return .keyLost),
    (1, do return .model (← opt (Gen.elem ["gpt-transcribe", "whisper-1", ""]))),
    (5, do return .menu (← menuAction)),
    (1, do return .launch { enabled := ← Gen.chance 5 6, submits := ← Gen.bool,
                            model := ← opt (Gen.elem ["gpt-transcribe", "whisper-1"]) })]

def Host.after (h : Host) (i : Input) (cs : List Cmd) : Host :=
  let clock := match i with
    | .keyDown t _ | .keyUp t | .tick t | .micStarted _ t => t
    | _ => h.clock
  let reported := match i with
    | .micStarted c _ | .micFailed c _ => [c]
    | _ => []
  let stopped := cs.filterMap fun | .stopRecording c => some c | _ => none
  let starting := (h.starting ++ cs.filterMap fun | .startRecording c => some c | _ => none).filter
    fun c => !reported.contains c && !stopped.contains c
  let answered := match i with
    | .reply q _ => if h.answered.contains q then h.answered else h.answered.push q
    | _ => h.answered
  let wakes := (cs.filterMap wakeOf ++ h.wakes).filter (· + latchLimit ≥ clock) |>.take 8
  { clock, answered, wakes, starting }

/-! ## The checks: each claim as a predicate on one step -/

/-- The clips these commands type (`Examples.Yap.typedClips`, restated so that this file
depends on the model only and builds against a mutated model, whose proofs break). -/
def typedOf (cs : List Cmd) : List Nat := cs.filterMap fun | .type _ n _ _ _ => some n | _ => none

def isTick : Input → Bool
  | .tick _ => true
  | _ => false

def isTranscribe : Cmd → Bool
  | .transcribe .. => true
  | _ => false

/-- `RecInv`, as a `Bool`. -/
def recOk (s : State) : Bool :=
  match s.recording with
  | none => true
  | some r => (r.latched || s.keyHeld) && (!r.latched || decide (r.deadline ≤ s.now + latchLimit)) &&
      (r.started || !r.latched) && (s.keys.isEmpty || !r.started)

def first25 (d : Dictionary) : Dictionary := { d with terms := d.terms.take promptLimit }

def typedTexts (cs : List Cmd) : List (Nat × Nat × String × Bool) :=
  cs.filterMap fun | .type a n _ t r => some (a, n, t, r) | _ => none

/-- A claim's check on one step `s —i→ (s', cs)`: `none` when the step doesn't exercise the
claim, `some ok` when it does. -/
abbrev Check := State → Input → State → List Cmd → Option Bool

def c311 : Check := fun s i _ cs =>
  if s.keyHeld && s.chorded && !isTick i then some (cs.all (!isTranscribe ·)) else none

/-- ^351: the hold/tap split, for a release handled at once, or one that waited for the start
and is timed from when it finished. -/
def c351 : Check := fun s i s' _ =>
  match i, s.recording with
  | .keyUp t, some r =>
    if r.started && s.keys.isEmpty && !r.latched && s.keyHeld && !s.chorded then
      some (s'.recording == if max s.now t - s.pressedAt < tapLimit then
          some { r with latched := true, deadline := max s.now t + latchLimit }
        else none)
    else none
  | .micStarted c u, some r =>
    match s.keys with
    | [.up t] =>
      if r.clip == c && !r.started && t ≤ u && s.keyHeld && !s.chorded then
        some (s'.recording == if max s.now u - s.pressedAt < tapLimit then
            some { r with started := true, nextPoll := max s.now u + pollMs, latched := true,
                          deadline := max s.now u + latchLimit }
          else none)
      else none
    | _ => none
  | _, _ => none

def isBegin : Cmd → Option Nat
  | .overlay n .begin => some n
  | _ => none

/-- ^349, of `step`: only the microphone's start begins the overlay, for the recording's clip,
and the recording it leaves, if any, is started. -/
def c349 : Check := fun s i s' cs =>
  let begins := cs.filterMap isBegin
  if begins.isEmpty then none else
  some <| match i, s.recording with
    | .micStarted _ _, some r => begins.all (· == r.clip) && s'.recording.all (·.started)
    | _, _ => false

/-- ^350: while the microphone starts, key events leave the recording as it is. -/
def c350 : Check := fun s i s' _ =>
  match s.recording with
  | some r =>
    if r.started then none else
    match i with
    | .keyDown .. | .keyUp _ | .otherKey => some (s'.recording == some r)
    | _ => none
  | none => none

def c313 : Check := fun s i s' cs =>
  let starts := cs.filterMap fun | .startRecording n => some n | _ => none
  let startOk := starts.all fun n =>
    s.recording.isNone && n == s.nextClip &&
      (s'.recording.map (·.clip) == some n || cs.contains (.stopRecording n)) &&
      s'.nextClip == n + 1
  let endOk := match s.recording with
    | some r => s'.recording.map (·.clip) == some r.clip || cs.contains (.stopRecording r.clip) ||
        (match i with | .micFailed c _ => c == r.clip | _ => false)
    | none => true
  if starts.isEmpty && s.recording.isNone then none else some (startOk && endOk && starts.length ≤ 1)

def c314 : Check := fun _ _ s' _ =>
  if s'.recording.isNone then none
  else some (recOk s' && (run s' [.keyUp s'.now, .tick (s'.now + latchLimit)]).recording.isNone)

def c315 : Check := fun s _ s' cs =>
  let ts := typedTexts cs
  if ts.isEmpty then none else
  some <| ts.all fun (a, n, _, _) =>
    let pre := cs.takeWhile fun | .type a' .. => a' != a | _ => true
    let kept := s'.recent.filter fun t => t.clip == some n && !t.typed
    !kept.isEmpty &&
      (!s.settings.keepTranscripts ||
        pre.any fun | .save _ t => t.clip == some n && kept.contains t | _ => false)

def c316 : Check := fun s i s' cs =>
  match i with
  | .reply q (.failed _) =>
    match s.reqs.lookup q with
    | some (.type _ t) => some (s'.recent.head? == some { t with typed := false } && cs.contains (.play .basso))
    | _ => none
  | _ => none

def c317 : Check := fun s i _ cs =>
  let ts := typedTexts cs
  if ts.isEmpty then none else
  some <| ts.all fun (_, n, _, _) => match i with
    | .reply q _ => s.reqs.any fun (q', r) => q' == q && match r with
        | .clip cr => cr.clip == n && cr.turn == s.turn
        | _ => false
    | _ => false

def c319 : Check := fun s i _ cs =>
  let ts := typedTexts cs
  if ts.isEmpty then none else
  some <| ts.all fun (_, _, text, _) => match i with
    | .reply q (.ok raw) => match s.reqs.lookup q with
      | some (.clip cr) =>
        text == if cr.submits then trimText (applyFixes cr.fixes raw)
          else trimText (applyFixes cr.fixes raw) ++ " "
      | _ => false
    | _ => false

def c320 : Check := fun _ i _ cs =>
  let dels := cs.filterMap fun | .deleteDays ds => some ds | _ => none
  if dels.isEmpty then none else
  some <| dels.all fun ds => match i with
    | .transcriptDays today days => !ds.contains today && ds.all fun d => days.contains d && d < today
    | _ => false

def c321 : Check := fun s _ _ cs =>
  let ps := cs.filterMap fun
    | .transcribe _ _ _ p => some (p, none)
    | .transcribeChunk _ _ _ _ _ p => some (p, some ())
    | _ => none
  if ps.isEmpty then none else
  some <| ps.all fun (p, chunk) => match chunk, s.recording with
    | none, _ => p == (first25 s.dict).promptFor none
    | some _, some r => p == (first25 s.dict).promptFor (context r.heard)
    | some _, none => false

def c322 : Check := fun _ _ s' _ => some (s'.recent.length ≤ recentLimit)

def c323 : Check := fun s _ _ cs =>
  let sent := cs.filterMap fun | .transcribe _ n _ _ => some n | _ => none
  if sent.isEmpty then none else
  some <| sent.all fun n => match s.recording with
    | some r => r.clip == n && r.frames ≥ minimumFrames && r.peak ≥ silencePeak && r.target.isSome
    | none => false

/-- The per-step checks, by claim id. ^318 is checked over the run. -/
def checks : List (Nat × Check) :=
  [(311, c311), (351, c351), (313, c313), (314, c314), (315, c315), (316, c316), (317, c317),
   (319, c319), (320, c320), (321, c321), (322, c322), (323, c323), (349, c349), (350, c350)]

def claimIds : List Nat :=
  [311, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 349, 350, 351]

/-! ## Running a sequence -/

structure Stats where
  exercised : Std.HashMap Nat Nat := {}
  steps : Nat := 0

def Stats.bump (st : Stats) (c : Nat) : Stats :=
  { st with exercised := st.exercised.insert c (st.exercised.getD c 0 + 1) }

/-- A failure: the claim, the step it failed at, and the inputs up to and including it. -/
structure Failure where
  claim : Nat
  step : Nat
  inputs : List Input

/-- Check one step against every claim; the first that fails. -/
def stepChecks (st : Stats) (typed : List Nat) (s : State) (i : Input) (s' : State)
    (cs : List Cmd) : Stats × Option Nat := Id.run do
  let mut st := st
  for (id, c) in checks do
    match c s i s' cs with
    | some true => st := st.bump id
    | some false => return (st, some id)
    | none => pure ()
  let now := typedOf cs
  if !now.isEmpty then
    st := st.bump 318
    if now.any (typed.contains ·) || (now.eraseDups.length != now.length) then
      return (st, some 318)
  return (st, none)

/-- Replay inputs from launch: the first failing claim and its step. -/
def replay (is : List Input) : Option (Nat × Nat) := Id.run do
  let mut s := init
  let mut typed : List Nat := []
  let mut k := 0
  for i in is do
    let (s', cs) := step s i
    match (stepChecks {} typed s i s' cs).2 with
    | some c => return some (c, k)
    | none => pure ()
    typed := typedOf cs ++ typed
    s := s'
    k := k + 1
  return none

/-- One random sequence from `seed`. -/
def runSeq (seed steps : Nat) (st : Stats) : Stats × Option Failure := Id.run do
  let mut g := Rng.ofSeed seed
  let mut s := init
  let mut h : Host := {}
  let mut typed : List Nat := []
  let mut inputs : Array Input := #[]
  let mut st := st
  -- Most runs launch and read their files first, as the app does.
  let boot : List Input := [.launch {}, .config .missing, .dictionary "", .trust true]
  let (doBoot, g') := (Gen.chance 7 8).run g
  g := g'
  let pre := if doBoot then boot else []
  for k in [0:steps + pre.length] do
    let i ← match pre[k]? with
      | some i => pure i
      | none =>
        let (i, g') := (input s h).run g
        g := g'
        pure i
    inputs := inputs.push i
    let (s', cs) := step s i
    let (st', bad) := stepChecks st typed s i s' cs
    st := { st' with steps := st'.steps + 1 }
    if let some c := bad then
      return (st, some { claim := c, step := k, inputs := inputs.toList })
    typed := typedOf cs ++ typed
    h := h.after i cs
    s := s'
  return (st, none)

/-! ## Shrinking -/

/-- Delta debugging: the shortest subsequence found that still fails `claim`. -/
partial def ddmin (claim : Nat) (is : List Input) : List Input :=
  let fails (xs : List Input) := match replay xs with
    | some (c, _) => c == claim
    | none => false
  let rec go (xs : List Input) (n : Nat) : List Input :=
    if xs.length < 2 then xs else
    let size := (xs.length + n - 1) / n
    let chunks := (List.range n).map fun j => (j * size, size)
    let complement := chunks.findSome? fun (from_, len) =>
      let ys := xs.take from_ ++ xs.drop (from_ + len)
      if ys.length < xs.length && fails ys then some ys else none
    match complement with
    | some ys => go ys (max (n - 1) 2)
    | none => if n ≥ xs.length then xs else go xs (min xs.length (2 * n))
  -- Then cut at the failing step, and drop single inputs.
  let xs := match replay is with
    | some (_, k) => is.take (k + 1)
    | none => is
  let xs := go xs 2
  let rec single (xs : List Input) (j : Nat) : List Input :=
    if j ≥ xs.length then xs else
    let ys := xs.eraseIdx j
    if fails ys then single ys j else single xs (j + 1)
  single xs 0

/-! ## The report -/

def claimTitle : Nat → String
  | 311 => "A shortcut never sends"
  | 313 => "One recording at a time"
  | 314 => "Every recording ends"
  | 315 => "Kept before it is typed"
  | 316 => "A failed type is kept and flagged"
  | 317 => "Late and cancelled replies never type"
  | 318 => "Each clip is typed at most once"
  | 319 => "Fixes replace whole words"
  | 320 => "Retention never deletes today"
  | 321 => "Only the first 25 terms are sent"
  | 322 => "Recent Transcripts holds five"
  | 323 => "Too short, silent or nowhere to type: never sent"
  | 349 => "The overlay waits for the microphone"
  | 350 => "Keys wait for the microphone"
  | 351 => "Hold to talk, tap to latch: 300 ms, timed as the original"
  | _ => ""

def inputsLean (is : List Input) : String :=
  "[" ++ ", ".intercalate (is.map fun i => (repr i).pretty 200) ++ "]"

structure Opts where
  seed : Nat := 0
  iterations : Nat := 200
  steps : Nat := 200
  out : Option String := none
  verbose : Bool := false

def parseArgs (o : Opts) : List String → Except String Opts
  | [] => .ok o
  | "--seed" :: v :: rest => num v fun n => parseArgs { o with seed := n } rest
  | "--iterations" :: v :: rest => num v fun n => parseArgs { o with iterations := n } rest
  | "--steps" :: v :: rest => num v fun n => parseArgs { o with steps := n } rest
  | "--out" :: v :: rest => parseArgs { o with out := some v } rest
  | "-v" :: rest => parseArgs { o with verbose := true } rest
  | a :: _ => .error s!"unknown argument {a}"
where
  num (v : String) (k : Nat → Except String Opts) : Except String Opts :=
    match v.toNat? with
    | some n => k n
    | none => .error s!"expected a number, got {v}"

/-- What the app-mode fuzzer (`Examples.Yap.Fuzz.App`, which plays a host against the app's
`receive` and `menuStep`) reports, for the shared summary and `Yap.json`. -/
structure AppReport where
  stats : Stats
  claims : List (Nat × String)
  /-- Claim, step, steps before shrinking, and the shrunk steps. -/
  failures : List (Nat × Nat × Nat × String)
  failing : Nat

/-- Runs the host mode, then the app mode if given, and writes one report. -/
def main (args : List String) (app : Option (Opts → IO AppReport) := none) : IO UInt32 := do
  let o ← match parseArgs {} args with
    | .ok o => pure o
    | .error e =>
      IO.eprintln e
      IO.eprintln "usage: lake exe yapfuzz [--seed S] [--iterations N] [--steps K] [--out DIR] [-v]"
      return 2
  let t0 ← IO.monoNanosNow
  let mut st : Stats := {}
  let mut fails : Array Failure := #[]
  for j in [0:o.iterations] do
    let (st', f) := runSeq (o.seed + j) o.steps st
    st := st'
    if let some f := f then
      fails := fails.push f
      IO.println s!"FAIL ^{f.claim} {claimTitle f.claim}: seed {o.seed + j}, step {f.step}"
  let t1 ← IO.monoNanosNow
  let secs := (t1 - t0).toFloat / 1e9
  let perSec := if secs > 0 then (st.steps.toFloat / secs).round else 0
  -- Shrink the first failure of each claim.
  let mut shrunk : Array (Failure × List Input) := #[]
  for f in fails do
    if shrunk.any (·.1.claim == f.claim) then continue
    let small := ddmin f.claim f.inputs
    shrunk := shrunk.push (f, small)
    IO.println s!"^{f.claim} shrunk from {f.inputs.length} inputs to {small.length}:\n  {inputsLean small}"
  for id in claimIds do
    let n := st.exercised.getD id 0
    let failed := fails.any (·.claim == id)
    IO.println s!"^{id} {claimTitle id}: {if failed then "FAIL" else if n == 0 then "not run" else "pass"} ({n} steps exercised it)"
  IO.println s!"{o.iterations} sequences × {o.steps} steps from seed {o.seed}: {st.steps} steps in {secs} s ({perSec.toUInt64} steps/s), {fails.size} failing"
  let a ← match app with
    | some run => some <$> run o
    | none => pure none
  if let some a := a then
    for (id, title) in a.claims do
      let n := a.stats.exercised.getD id 0
      let failed := a.failures.any (·.1 == id)
      IO.println s!"^{id} {title} (app): {if failed then "FAIL" else if n == 0 then "not run" else "pass"} ({n} steps exercised it)"
    IO.println s!"app mode: {a.stats.steps} steps through receive and menuStep, {a.failing} failing"
  let appClaims := (a.map (·.claims)).getD []
  let ids := claimIds ++ (appClaims.map (·.1)).filter (!claimIds.contains ·)
  let title (id : Nat) := (appClaims.lookup id).getD (claimTitle id)
  if let some dir := o.out then
    IO.FS.createDirAll dir
    let claimJ := ids.map fun id =>
      let hostN := st.exercised.getD id 0
      let appN := (a.map (·.stats.exercised.getD id 0)).getD 0
      let n := hostN + appN
      let failed := fails.any (·.claim == id) || (a.map (·.failures.any (·.1 == id))).getD false
      (s!"^{id}", Json.mkObj ([("kind", Json.str "invariant"), ("title", Json.str (title id)),
        ("steps", toJson n), ("hostSteps", toJson hostN), ("appSteps", toJson appN)] ++
        (if failed then [("pass", Json.bool false)]
         else if n == 0 then [("pass", Json.null), ("note", Json.str "not run")]
         else [("pass", Json.bool true)])))
    let failJ := shrunk.toList.map fun (f, small) => Json.mkObj [
      ("check", Json.str "invariant"), ("claim", toJson f.claim), ("step", toJson f.step),
      ("shrunkFrom", toJson f.inputs.length), ("inputs", Json.str (inputsLean small)),
      ("mode", Json.str "host")]
    let appFailJ := ((a.map (·.failures)).getD []).map fun (c, k, n, xs) => Json.mkObj [
      ("check", Json.str "invariant"), ("claim", toJson c), ("step", toJson k),
      ("shrunkFrom", toJson n), ("inputs", Json.str xs), ("mode", Json.str "app")]
    let j := Json.mkObj [
      ("app", Json.str "Yap"), ("module", Json.str "Examples.Yap"), ("mode", Json.str (if a.isSome then "host+app" else "host")),
      ("seed", toJson o.seed), ("iterations", toJson o.iterations), ("steps", toJson o.steps),
      ("sequences", toJson o.iterations), ("stepsRun", toJson st.steps),
      ("seconds", Json.num ⟨((t1 - t0 + 5000000) / 10000000 : Nat), 2⟩),
      ("stepsPerSecond", toJson perSec.toUInt64.toNat),
      ("failingSequences", toJson (fails.size + (a.map (·.failing)).getD 0)),
      ("appStepsRun", toJson ((a.map (·.stats.steps)).getD 0)),
      ("claims", Json.mkObj claimJ), ("failures", Json.arr (failJ ++ appFailJ).toArray)]
    IO.FS.writeFile (dir ++ "/Yap.json") (j.pretty ++ "\n")
  return if fails.isEmpty && (a.map (·.failing == 0)).getD true then 0 else 1

end Examples.Yap.Fuzz

module

public import Cairn.Claims.Core
meta import Cairn.Claims.Elab
public import Cairn.App
public import Cairn.Layout.Core

/-! # Clock: a stopwatch on the outside world

The example for effects (docs/effects.md). A stopwatch with Start/Stop, Lap and Reset, the time
of day, and Save and Load buttons that write the laps to a file and read them back.

* **Time.** The app hears the clock as `Msg.clock` (monotonic ms for the stopwatch, wall time
  and zone for the time of day). While running it keeps a timer, `tick`, set 100 ms ahead, so
  the display moves; Stop cancels it.
* **Requests.** Lap plays a sound; Save writes `lapsPath` (atomically); Load, and the first
  clock (`initEffects`), read it back. Replies come back to `receive` under the request's id.
* **Subscriptions.** `every 1000` for the time of day, whenever the app runs.

| Id | Kind | What |
|---|---|---|
| ^401 | move | Start / Stop |
| ^402 | move | Lap: enabled while running |
| ^403 | move | Reset: enabled when stopped with time or laps to clear |
| ^404 | move | Save laps: enabled when there are laps |
| ^405 | move | Load laps |
| ^406 | place | the window |
| ^407, ^408 | flow | two laps; start over |
| ^409 | invariant | pending requests have fresh ids (kept by moves and by `receive`) |

The moves only start things: what comes back (the time, the tick, the file's contents) arrives
through `receive`. Runtime checks are in `Examples.Clock.Tests`; the v1 exports in
`Examples.Clock.Abi`; the host side is `host/Sources/CairnClock`. -/

@[expose] public section

namespace Examples.Clock
open Cairn Cairn.Claims

/-- Where the laps are saved: one lap per line, in milliseconds. -/
def lapsPath : String := "~/Library/Application Support/Cairn/Clock/laps.txt"

/-- The stopwatch's timer. -/
def tick : String := "tick"

/-- The tick's period: the display shows tenths. -/
def tickMs : Nat := 100

structure State where
  /-- The time as last heard: monotonic ms, wall ms since the epoch, and the zone's offset in
  seconds. -/
  now : Nat := 0
  wall : Int := 0
  zone : Int := 0
  running : Bool := false
  /-- When the current run started (monotonic ms). -/
  since : Nat := 0
  /-- Time from earlier runs. -/
  banked : Nat := 0
  laps : List Nat := []
  /-- The id the next request gets; 0 is the launch read. -/
  nextReq : Nat := 1
  /-- The pending save and load, if any. -/
  saving : Option Nat := none
  loading : Option Nat := some 0
  status : String := ""
deriving Repr, DecidableEq, Inhabited

/-- The stopwatch's reading. -/
def elapsed (s : State) : Nat := s.banked + (if s.running then s.now - s.since else 0)

def resetEnabled (s : State) : Bool := !s.running && (s.banked > 0 || !s.laps.isEmpty)

def lapsText (laps : List Nat) : String := String.join (laps.map fun n => s!"{n}\n")

/-- The laps in a file's contents: `none` unless every non-empty line is a number. -/
def parseLaps (data : ByteArray) : Option (List Nat) :=
  (String.fromUTF8? data).bind fun t =>
    ((t.splitOn "\n").filter (· ≠ "")).mapM String.toNat?

def startStopRef : ControlRef := ⟨401, 0⟩
def lapRef : ControlRef := ⟨402, 0⟩
def resetRef : ControlRef := ⟨403, 0⟩
def saveRef : ControlRef := ⟨404, 0⟩
def loadRef : ControlRef := ⟨405, 0⟩

/-- Start, or stop: stopping banks the run and cancels the tick. -/
def startStop (s : State) : State × List Effect :=
  if s.running then ({ s with running := false, banked := elapsed s }, [.cancelTimer tick])
  else ({ s with running := true, since := s.now }, [.setTimer tick tickMs])

theorem startStop_post (s : State) :
    (startStop s).1.running = !s.running ∧ elapsed (startStop s).1 = elapsed s := by
  unfold startStop elapsed
  cases s.running <;> simp only [Bool.not_false, Bool.not_true, ↓reduceIte, Bool.false_eq_true,
    Nat.sub_self, Nat.add_zero, and_self]

place ^406 window "Clock window" where
  does "The stopwatch's window: the reading, the time of day, Start/Stop, Lap, Reset, Save laps, Load laps, a status line and the laps."

move ^401 startStopMove (s : State) "Start / Stop" in ^406 where
  does "Press Start (Stop while running)."
  sees "The stopwatch runs from where it was, or stops and keeps its reading."
  on press
    emit := startStop s
    post s' := s'.running = !s.running ∧ elapsed s' = elapsed s
    sound := by intro s; exact startStop_post s

move ^402 lapMove (s : State) "Lap" in ^406 where
  does "Press Lap while the stopwatch runs."
  sees "The reading is added to the laps, and a sound plays."
  enabled := s.running
  on press
    emit := ({ s with laps := s.laps ++ [elapsed s], nextReq := s.nextReq + 1 },
      [.request s.nextReq (.playSound "Tink")])
    post s' := s'.laps = s.laps ++ [elapsed s] ∧ s'.running = s.running
    sound := by intro s _; exact ⟨rfl, rfl⟩

move ^403 resetMove (s : State) "Reset" in ^406 where
  does "Press Reset while stopped."
  sees "The reading is zero and the laps are gone."
  enabled := resetEnabled s
  on press
    apply := { s with banked := 0, laps := [] }
    post s' := s'.laps = [] ∧ (s.running = false → elapsed s' = 0)
    sound := by
      intro s _
      refine ⟨rfl, fun h => ?_⟩
      show 0 + (if s.running = true then s.now - s.since else 0) = 0
      rw [h]; rfl

move ^404 saveMove (s : State) "Save laps" in ^406 where
  does "Press Save laps."
  sees "The laps are written to the laps file, replacing it; the status line says when it is done."
  enabled := !s.laps.isEmpty
  on press
    emit := ({ s with nextReq := s.nextReq + 1, saving := some s.nextReq, status := "Saving…" },
      [.request s.nextReq (.writeFile lapsPath (lapsText s.laps).toUTF8)])
    post s' := s'.laps = s.laps ∧ s'.saving = some s.nextReq
    sound := by intro s _; exact ⟨rfl, rfl⟩

move ^405 loadMove (s : State) "Load laps" in ^406 where
  does "Press Load laps."
  sees "The laps are read back from the laps file; the status line says how many."
  on press
    emit := ({ s with nextReq := s.nextReq + 1, loading := some s.nextReq, status := "Loading…" },
      [.request s.nextReq (.readFile lapsPath)])
    post s' := s'.laps = s.laps ∧ s'.loading = some s.nextReq
    sound := by intro s; exact ⟨rfl, rfl⟩

/-! ## The outside world -/

def faultText : Fault → String
  | .notFound => "no such file" | .denied => "permission denied" | .timeout => "timed out"
  | .network => "network error" | .invalid => "invalid request" | .other => "failed"

/-- A reply to the pending save or load; anything else (the lap sound) is ignored. -/
def onReply (s : State) (id : Nat) (r : Reply) : State :=
  if s.saving = some id then
    { s with saving := none,
             status := match r with
               | .done => s!"Saved {s.laps.length} laps"
               | .failed f m => s!"Could not save: {faultText f} {m}"
               | _ => s.status }
  else if s.loading = some id then
    match r with
    | .bytes data =>
      match parseLaps data with
      | some ls => { s with loading := none, laps := ls, status := s!"Loaded {ls.length} laps" }
      | none => { s with loading := none, status := "The laps file is not a list of laps" }
    | .failed .notFound _ =>
      { s with loading := none, status := if id = 0 then "" else "No saved laps" }
    | .failed f m => { s with loading := none, status := s!"Could not load: {faultText f} {m}" }
    | _ => s
  else s

def receive (s : State) : Msg → State × List Effect
  | .clock t => ({ s with now := t.mono, wall := t.wall, zone := t.zone }, [])
  | .timer n => (s, if n = tick && s.running then [.setTimer tick tickMs] else [])
  | .reply id r => (onReply s id r, [])
  | .sub _ _ => (s, [])

/-- A stopped stopwatch's tick sets nothing: after Stop no tick comes back. -/
theorem stopped_tick (s : State) (h : s.running = false) : receive s (.timer tick) = (s, []) := by
  simp only [receive, h, Bool.and_false, ↓reduceIte, decide_true,
    Bool.false_eq_true]

/-- A reply only clears the pending save or load. -/
theorem onReply_fields (s : State) (id : Nat) (r : Reply) :
    (onReply s id r).nextReq = s.nextReq ∧
      ((onReply s id r).saving = none ∨ (onReply s id r).saving = s.saving) ∧
      ((onReply s id r).loading = none ∨ (onReply s id r).loading = s.loading) := by
  unfold onReply
  split
  · exact ⟨rfl, Or.inl rfl, Or.inr rfl⟩
  · split
    · split
      · split
        · exact ⟨rfl, Or.inr rfl, Or.inl rfl⟩
        · exact ⟨rfl, Or.inr rfl, Or.inl rfl⟩
      all_goals first
        | exact ⟨rfl, Or.inr rfl, Or.inl rfl⟩
        | exact ⟨rfl, Or.inr rfl, Or.inr rfl⟩
    · exact ⟨rfl, Or.inr rfl, Or.inr rfl⟩

/-- The stopwatch: its moves, and what the world does to it. -/
def machine : Machine State := { init := {}, moves := moves%, receive }

invariant ^409 freshRequests "Pending requests have fresh ids" for machine where
  does "The pending save and load, if any, have ids below the next request's, so a reply to a later request is never taken for theirs."
  holds s := (∀ id, s.saving = some id → id < s.nextReq) ∧ (∀ id, s.loading = some id → id < s.nextReq)
  init := And.intro (fun _ h => nomatch (h : none = some _))
    (fun _ h => by cases (Option.some.inj (h : some 0 = some _)); decide)
  step := machine.preserves <|
    Move.all_cons (startStopMove.preserves _ fun s h => by
        unfold startStopMove.press.emit startStop; split <;> exact h)
      (Move.all_cons (lapMove.preserves _ fun s _ h =>
        And.intro (fun id hi => Nat.lt_succ_of_lt (h.1 id hi))
          (fun id hi => Nat.lt_succ_of_lt (h.2 id hi)))
      (Move.all_cons (resetMove.preserves _ fun _ _ h => h)
      (Move.all_cons (saveMove.preserves _ fun s _ h =>
        And.intro (fun id hi => by
            cases (Option.some.inj (hi : some s.nextReq = some id)); exact Nat.lt_succ_self _)
          (fun id hi => Nat.lt_succ_of_lt (h.2 id hi)))
      (Move.all_cons (loadMove.preserves _ fun s h =>
        And.intro (fun id hi => Nat.lt_succ_of_lt (h.1 id hi))
          (fun id hi => by
            cases (Option.some.inj (hi : some s.nextReq = some id)); exact Nat.lt_succ_self _))
        Move.all_nil))))
  receive := by
    intro s m h
    cases m with
    | reply id r =>
      obtain ⟨hn, hs, hl⟩ := onReply_fields s id r
      show (∀ x, (onReply s id r).saving = some x → x < (onReply s id r).nextReq) ∧
        (∀ x, (onReply s id r).loading = some x → x < (onReply s id r).nextReq)
      rw [hn]
      constructor <;> intro x hx
      · rcases hs with hs | hs <;> rw [hs] at hx
        · cases hx
        · exact h.1 x hx
      · rcases hl with hl | hl <;> rw [hl] at hx
        · cases hx
        · exact h.2 x hx
    | _ => exact h

flow ^407 twoLaps "Two laps" for machine where
  does "Press Start, then Lap twice."
  sees "Two laps are listed."
  goal s := s.laps.length = 2 ∧ s.running = true
  witness press ^401, press ^402, press ^402

flow ^408 startOver "Start over" for machine where
  does "Press Start, Lap, Stop, then Reset."
  sees "The reading is zero and no laps are listed."
  goal s := s.laps = [] ∧ elapsed s = 0
  witness press ^401, press ^402, press ^401, press ^403

/-- Every claim the stopwatch makes. -/
def claimInfos : List ClaimInfo := claims%

/-! ## View -/

def bg : Color := ⟨246, 246, 248, 255⟩
def ink : Color := ⟨28, 28, 30, 255⟩
def muted : Color := ⟨110, 110, 118, 255⟩
def green : Color := ⟨48, 160, 80, 255⟩
def greenDark : Color := ⟨36, 128, 62, 255⟩
def red : Color := ⟨208, 64, 64, 255⟩
def redDark : Color := ⟨172, 44, 44, 255⟩
def blue : Color := ⟨64, 96, 255, 255⟩
def blueDark : Color := ⟨44, 72, 214, 255⟩
def grey : Color := ⟨120, 120, 128, 255⟩
def greyDark : Color := ⟨96, 96, 104, 255⟩
def white : Color := ⟨255, 255, 255, 255⟩
def focusRing : Color := ⟨0, 122, 255, 255⟩

def pad2 (n : Nat) : String := if n < 10 then s!"0{n}" else toString n

/-- `m:ss.t`. -/
def reading (ms : Nat) : String :=
  s!"{ms / 60000}:{pad2 (ms / 1000 % 60)}.{ms / 100 % 10}"

/-- Local `hh:mm:ss` from wall time and zone. -/
def timeOfDay (wall zone : Int) : String :=
  let secs := ((wall / 1000 + zone) % 86400).toNat
  s!"{pad2 (secs / 3600)}:{pad2 (secs / 60 % 60)}:{pad2 (secs % 60)}"

def button (ui : UI) (r : ControlRef) (label : String) (fill hover : Color) : Node :=
  .box { width := .fixed 110, height := .fixed 36, radius := 6, align := .center,
         justify := .center, clip := true,
         background := some (if ui.hover = some r then hover else fill),
         border := if ui.focus = some r then some ⟨2, focusRing⟩ else none }
    (some { ref := r, label := label })
    [.text { font := { size := 14, weight := 600 }, color := white } label]

def line (size : Nat) (color : Color) (t : String) (weight : Nat := 400) (family : Nat := 0) :
    Node :=
  .box { width := .fill, height := .fixed (size + 8), clip := true } none
    [.text { font := { size, weight, family }, color } t]

def row (kids : List Node) : Node :=
  .box { axis := .row, width := .fill, height := .fixed 36, gap := 10 } none kids

/-- The last eight laps, numbered. -/
def lapLines (laps : List Nat) : List Node :=
  let numbered := (List.range laps.length).zip laps
  (numbered.drop (laps.length - 8)).map fun (i, ms) =>
    line 14 ink s!"Lap {i + 1}    {reading ms}" (family := 1)

def view (s : State) (ui : UI) : Node :=
  .box { width := .fill, height := .fill, padding := ⟨32, 32, 32, 32⟩, gap := 12,
         background := some bg, clip := true } none
    ([ line 44 ink (reading (elapsed s)) (weight := 600) (family := 1),
       line 14 muted s!"Time of day {timeOfDay s.wall s.zone}",
       row ([ if s.running then button ui startStopRef "Stop" red redDark
              else button ui startStopRef "Start" green greenDark ] ++
            (if s.running then [button ui lapRef "Lap" blue blueDark] else []) ++
            (if resetEnabled s then [button ui resetRef "Reset" grey greyDark] else [])),
       row ((if !s.laps.isEmpty then [button ui saveRef "Save laps" blue blueDark] else []) ++
            [button ui loadRef "Load laps" grey greyDark]),
       line 13 muted s.status ] ++
     lapLines s.laps)

def app : App State :=
  { machine.toApp view claimInfos with
    subscriptions := fun _ => [.every 1000]
    initEffects := [.request 0 (.readFile lapsPath)] }

example : claimInfos.map (·.id) = [401, 402, 403, 404, 405, 406, 407, 408, 409] := by decide

end Examples.Clock

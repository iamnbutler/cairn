import Lean.Data.Json
import Cairn.Fuzz.Shrink

/-! # `lake exe fuzz`

```
lake exe fuzz <App> [--seed S|random] [--iterations N] [--steps K] [--budget-ms M]
                    [--out DIR] [--shrink N] [-v]
lake exe fuzz --list [--deps]
```

Runs sequences with seeds `S, S+1, …, S+N−1` (the `SEED` and `ITERATIONS` environment variables
set the defaults), stops each at its first failure, shrinks the first failure of each kind,
prints it as a `flow`, and writes `<DIR>/<App>.json` (docs/fuzz.md). Exit code 1 when anything
failed. `--list` names the package's own targets, and its dependencies' too with `--deps`; any
target can be run by name (`cairn_atproto/Claims`). Two targets with one name are refused (exit
code 2), never one shadowing the other. -/

namespace Cairn.Fuzz
open Lean (Json toJson)
open Cairn Cairn.Runtime

/-! ## JSON -/

def opJson : TextOp → Json
  | .insert s => Json.mkObj [("kind", "insert"), ("text", s)]
  | .paste s => Json.mkObj [("kind", "paste"), ("text", s)]
  | .setMarked s a b => Json.mkObj [("kind", "setMarked"), ("text", s), ("selStart", a), ("selLen", b)]
  | .setCaret i e => Json.mkObj [("kind", "setCaret"), ("index", i), ("extend", e)]
  | .moveLeft e => ext "moveLeft" e
  | .moveRight e => ext "moveRight" e
  | .moveWordLeft e => ext "moveWordLeft" e
  | .moveWordRight e => ext "moveWordRight" e
  | .moveHome e => ext "moveHome" e
  | .moveEnd e => ext "moveEnd" e
  | .deleteBackward => kind "deleteBackward"
  | .deleteForward => kind "deleteForward"
  | .deleteWordBackward => kind "deleteWordBackward"
  | .deleteWordForward => kind "deleteWordForward"
  | .selectAll => kind "selectAll"
  | .unmark => kind "unmark"
  | .cut => kind "cut"
  | .copy => kind "copy"
  | .undo => kind "undo"
  | .redo => kind "redo"
where
  kind (k : String) : Json := Json.mkObj [("kind", k)]
  ext (k : String) (e : Bool) : Json := Json.mkObj [("kind", k), ("extend", e)]

/-- An action step, in the shape of a flow's witness in `lake exe claims`. -/
def actionJson (a : Action) : Json :=
  let c := a.control
  let base := [("trigger", Json.str a.trigger.name), ("ref", Json.str c.label),
    ("claim", toJson c.claim), ("key", toJson c.key)]
  match a with
  | .edit _ op => Json.mkObj (base ++ [("op", opJson op)])
  | _ => Json.mkObj base

def keyName : Key → String
  | .enter => "enter" | .escape => "escape" | .tab => "tab" | .backspace => "backspace"
  | .delete => "delete" | .left => "left" | .right => "right" | .up => "up" | .down => "down"
  | .home => "home" | .finish => "end" | .pageUp => "pageUp" | .pageDown => "pageDown"
  | .char c => c.toString

def faultName (f : Fault) : String := match f with
  | .notFound => "notFound" | .denied => "denied" | .timeout => "timeout" | .network => "network"
  | .invalid => "invalid" | .other => "other"

def hexOf (b : ByteArray) : String :=
  b.foldl (fun acc x => acc ++ String.ofList (Nat.toDigits 16 (x.toNat / 16) ++ Nat.toDigits 16 (x.toNat % 16))) ""

def replyJson : Reply → Json
  | .done => Json.mkObj [("kind", "done")]
  | .bytes b => Json.mkObj [("kind", "bytes"), ("hex", Json.str (hexOf b))]
  | .http st hs b => Json.mkObj [("kind", "http"), ("status", toJson st),
      ("headers", Json.arr (hs.toArray.map fun (k, v) => Json.arr #[Json.str k, Json.str v])),
      ("hex", Json.str (hexOf b))]
  | .failed f m => Json.mkObj [("kind", "failed"), ("fault", Json.str (faultName f)), ("message", Json.str m)]
  | .names ns => Json.mkObj [("kind", "names"), ("names", toJson ns)]
  | .app pid n => Json.mkObj [("kind", "app"), ("pid", toJson pid), ("name", Json.str n)]
  | .flag b => Json.mkObj [("kind", "flag"), ("granted", toJson b)]
  | .image w h => Json.mkObj [("kind", "image"), ("w", toJson w), ("h", toJson h)]

def hostJson : HostOp → Json
  | .advance ms j => Json.mkObj [("host", "advance"), ("ms", toJson ms), ("wallJump", toJson j)]
  | .wake l => Json.mkObj [("host", "wake"), ("late", toJson l)]
  | .reply id r => Json.mkObj [("host", "reply"), ("id", toJson id), ("reply", replyJson r)]
  | .load id w h => Json.mkObj [("host", "load"), ("id", toJson id), ("w", toJson w), ("h", toJson h)]
  | .sub s e dt => Json.mkObj [("host", "sub"), ("sub", Json.str (subText s)),
      ("event", Json.str (reprStr e)), ("dt", toJson dt)]
  | .late id e => Json.mkObj [("host", "late"), ("id", toJson id), ("event", Json.str (reprStr e))]
  | .evict src => Json.mkObj [("host", "evict"), ("source", Json.str src)]
  | .stray id r => Json.mkObj [("host", "stray"), ("id", toJson id), ("reply", replyJson r)]
  | .serve id sd => Json.mkObj [("host", "serve"), ("id", toJson id), ("seed", toJson sd)]
  | .lose id r => Json.mkObj [("host", "lose"), ("fault", "lostAfter"), ("id", toJson id), ("reply", replyJson r)]
  | .fail id r => Json.mkObj [("host", "fail"), ("fault", "failedBefore"), ("id", toJson id), ("reply", replyJson r)]
  | .tick sd => Json.mkObj [("host", "tick"), ("seed", toJson sd)]

def hostStatsJson (h : HostStats) : Json := Json.mkObj [
  ("requests", toJson h.requests), ("cancels", toJson h.cancels), ("replies", toJson h.replies),
  ("failedReplies", toJson h.failed), ("cancelledReplies", toJson h.cancelledReplies),
  ("strayReplies", toJson h.stray), ("clocks", toJson h.clocks), ("wakes", toJson h.wakes),
  ("timersDue", toJson h.timersDue), ("subEvents", toJson h.subEvents),
  ("lateSubEvents", toJson h.lateSubEvents), ("loads", toJson h.loads),
  ("evictions", toJson h.evictions), ("maxOutstanding", toJson h.maxOutstanding),
  ("leftOver", toJson h.leftOver), ("served", toJson h.served),
  ("retransmits", toJson h.retransmits), ("lostAfter", toJson h.lostAfter),
  ("failedBefore", toJson h.failedBefore), ("ticks", toJson h.ticks),
  ("badges", toJson h.badges), ("announcements", toJson h.announcements)]

def stepJson (tr : Traced) : Json :=
  let hit : Json := match tr.hit with | some r => Json.str r.label | none => Json.null
  match tr.op with
  | .act a => actionJson a
  | .click p n => Json.mkObj [("event", "click"), ("x", toJson p.x), ("y", toJson p.y),
      ("clicks", toJson n), ("hit", hit)]
  | .move p => Json.mkObj [("event", "move"), ("x", toJson p.x), ("y", toJson p.y), ("hit", hit)]
  | .tab back => Json.mkObj [("event", "key"), ("key", "tab"), ("shift", toJson back)]
  | .key k m => Json.mkObj [("event", "key"), ("key", Json.str (keyName k)), ("shift", toJson m.shift)]
  | .scroll p dx dy => Json.mkObj [("event", "scroll"), ("x", toJson p.x), ("y", toJson p.y),
      ("dx", toJson dx), ("dy", toJson dy), ("hit", hit)]
  | .resize z => Json.mkObj [("event", "resize"), ("w", toJson z.w), ("h", toJson z.h)]
  | .exit => Json.mkObj [("event", "pointerExit")]
  | .windowFocus b => Json.mkObj [("event", "windowFocus"), ("focused", toJson b)]
  | .host h => hostJson h

def metricsJson : MetricsChoice → Json
  | .mono => Json.mkObj [("kind", "mono")]
  | .random s => Json.mkObj [("kind", "random"), ("seed", toJson s.toNat)]

def sequenceJson (t : Target) (setup : Setup) (traced : Array Traced) : Json :=
  Json.mkObj [("app", Json.str t.name), ("seed", toJson setup.seed),
    ("window", Json.mkObj [("w", toJson setup.size.w), ("h", toJson setup.size.h)]),
    ("clock", Json.mkObj [("mono", toJson setup.start.mono), ("wall", toJson setup.start.wall),
      ("zone", toJson setup.start.zone)]),
    ("metrics", metricsJson setup.metrics), ("steps", Json.arr (traced.map stepJson))]

/-! ## Options -/

structure Opts where
  app : String := ""
  seed : Nat := 0
  iterations : Nat := 100
  steps : Nat := 50
  budgetMs : Option Nat := none
  out : Option String := none
  shrinks : Nat := 5
  verbose : Bool := false
  list : Bool := false
  deps : Bool := false

def parseArgs (o : Opts) : List String → Except String Opts
  | [] => .ok o
  | "--seed" :: "random" :: rest => parseArgs { o with seed := 0xFFFFFFFF } rest
  | "--seed" :: v :: rest => num v fun n => parseArgs { o with seed := n } rest
  | "--iterations" :: v :: rest => num v fun n => parseArgs { o with iterations := n } rest
  | "--steps" :: v :: rest => num v fun n => parseArgs { o with steps := n } rest
  | "--budget-ms" :: v :: rest => num v fun n => parseArgs { o with budgetMs := some n } rest
  | "--shrink" :: v :: rest => num v fun n => parseArgs { o with shrinks := n } rest
  | "--out" :: v :: rest => parseArgs { o with out := some v } rest
  | "-v" :: rest => parseArgs { o with verbose := true } rest
  | "--list" :: rest => parseArgs { o with list := true } rest
  | "--deps" :: rest => parseArgs { o with deps := true } rest
  | a :: rest =>
    if a.startsWith "-" then .error s!"unknown option {a}"
    else parseArgs { o with app := a } rest
where
  num (v : String) (k : Nat → Except String Opts) : Except String Opts :=
    match v.toNat? with
    | some n => k n
    | none => .error s!"expected a number, got {v}"

def usage : String :=
  "usage: lake exe fuzz <App> [--seed S|random] [--iterations N] [--steps K] [--budget-ms M] [--out DIR] [--shrink N] [-v]\n       lake exe fuzz --list [--deps]"

/-! ## The run -/

/-- Hundredths, as text: `fmt2 1234 = "12.34"`. -/
def fmt2 (hundredths : Nat) : String :=
  let r := hundredths % 100
  s!"{hundredths / 100}.{if r < 10 then "0" else ""}{r}"

/-- Nanoseconds as milliseconds, to hundredths. -/
def msText (ns : Nat) : String := fmt2 ((ns + 5000) / 10000)
def msJson (ns : Nat) : Json := Json.num ⟨((ns + 5000) / 10000 : Nat), 2⟩

/-- Per-claim evidence: pass (true/false), or null with a note when it wasn't run. -/
def claimJson (t : Target) (stats : Stats) (fails : Array (Failure × Setup)) (c : ClaimInfo) :
    Json :=
  let kind := match c.kind with
    | .move => "move" | .flow => "flow" | .invariant => "invariant" | .assume => "assume"
    | .place => "place"
  let base := [("kind", Json.str kind)]
  let failed := fails.filter (·.1.claim == c.id)
  if c.retired.isSome then Json.mkObj (base ++ [("pass", Json.null), ("note", "retired")]) else
  match c.kind with
  | .move | .invariant =>
    let runnable := c.kind == .move ||
      (t.invariants.any fun (i : InvCheck t.S) => i.info.id == c.id && i.check.isSome) ||
      t.custom.relations.any (·.1 == c.id) || t.custom.drained.any (·.1 == c.id) ||
      t.custom.outstanding.any (·.1 == c.id) || t.srv.checks.any (·.1 == c.id) ||
      t.srv.drained.any (·.1 == c.id)
    match stats.get? c.id with
    | none => Json.mkObj (base ++ [("pass", Json.null),
        ("note", Json.str (if runnable then "not run" else "not runnable: no Decidable instance"))])
    | some st =>
      let checks := Json.mkObj (st.checks.toList.map fun (k, n) => (k, toJson n))
      let pass := failed.isEmpty
      Json.mkObj (base ++ [("pass", toJson pass), ("steps", toJson st.steps),
        ("sequences", toJson st.sequences), ("checks", checks)] ++
        (match failed[0]? with
         | some (f, s) => [("failure", Json.mkObj [("check", Json.str f.check), ("seed", toJson s.seed),
              ("step", toJson f.step), ("message", Json.str f.message)])]
         | none => []))
  | .place =>
    -- A place's checks: the images its frame draws are held by the host.
    match stats.get? c.id with
    | some st =>
      Json.mkObj (base ++ [("pass", toJson failed.isEmpty), ("steps", toJson st.steps),
        ("sequences", toJson st.sequences),
        ("checks", Json.mkObj (st.checks.toList.map fun (k, n) => (k, toJson n)))])
    | none => Json.mkObj (base ++ [("pass", Json.null), ("note", "n/a")])
  | _ => Json.mkObj (base ++ [("pass", Json.null), ("note", "n/a")])

def runTarget (t : Target) (o : Opts) : IO UInt32 := do
  let t := match o.budgetMs with
    | some b => { t with custom := { t.custom with budgetNs := some (b * 1_000_000) } }
    | none => t
  let seed0 ← if o.seed == 0xFFFFFFFF then do
      let n ← IO.monoNanosNow; pure (n % 1_000_000_000)
    else pure o.seed
  let mode := if t.app.isSome then "through the runtime" else "model only (no App)"
  IO.println s!"fuzz {t.name} ({t.module}, {mode}): seeds {seed0}..{seed0 + o.iterations - 1}, {o.steps} steps each"
  let lockPath : System.FilePath := if ← System.FilePath.pathExists "../claims.lock" then "../claims.lock" else "claims.lock"
  let mut nextId := ((← lockMax lockPath).getD 0) + 1
  let mut stats : Stats := {}
  let mut fails : Array (Failure × Setup) := #[]
  let mut reports : Array Json := #[]
  let mut stepsRun := 0
  let mut over : Array Json := #[]
  let mut maxNs := 0
  let mut skipped := 0
  let mut mono := 0
  let mut host : HostStats := {}
  let t0 ← IO.monoNanosNow
  for i in [0:o.iterations] do
    let seed := seed0 + i
    let (setup, rng) := genSetup t seed
    if setup.metrics matches .mono then mono := mono + 1
    if o.verbose then
      IO.println s!"seed {seed}: window {setup.size.w}×{setup.size.h}, metrics {reprStr setup.metrics}"
    let out ← runSeq t setup (.gen rng o.steps) stats o.verbose
    stats := out.stats
    stepsRun := stepsRun + out.steps
    maxNs := max maxNs out.maxNs
    skipped := skipped + out.skipped
    host := host.add out.host
    for (step, ns) in out.over do
      if over.size < 20 then
        over := over.push (Json.mkObj [("seed", toJson seed), ("step", toJson step), ("ms", msJson ns)])
    if let some f := out.failure then
      let first := !(fails.any (·.1.same f))
      fails := fails.push (f, setup)
      if fails.size ≤ 10 then
        IO.println s!"FAIL seed {seed} step {f.step}: {f.check} ^{f.claim}{if f.key = 0 then "" else s!"#{f.key}"}: {f.message}"
      else if fails.size == 11 then
        IO.println "(further failures are counted, not printed)"
      if first && reports.size < o.shrinks then
        let (ops, tries) ← shrink t setup f out.ops
        let traced ← trace t setup ops
        let flow := flowSource t setup f traced nextId
        nextId := nextId + 1
        IO.println s!"  shrunk {out.ops.size} → {ops.size} operations in {tries} replays:"
        for tr in traced do
          IO.println s!"    {opText tr.op}"
        IO.println s!"\n{flow}\n"
        reports := reports.push (Json.mkObj [("check", Json.str f.check), ("claim", toJson f.claim),
          ("key", toJson f.key), ("seed", toJson seed), ("step", toJson f.step),
          ("message", Json.str f.message), ("shrunkFrom", toJson out.ops.size),
          ("sequence", sequenceJson t setup traced), ("flow", Json.str flow)])
    if o.verbose && out.failure.isNone then
      IO.println s!"seed {seed}: {out.steps} steps ok"
  let t1 ← IO.monoNanosNow
  let ns := max 1 (t1 - t0)
  let seqPerS := o.iterations * 1_000_000_000 / ns
  let stepsPerS := stepsRun * 1_000_000_000 / ns
  IO.println s!"{o.iterations} sequences, {stepsRun} steps in {msText ns} ms: {seqPerS} sequences/s, {stepsPerS} steps/s; slowest step {msText maxNs} ms (budget {t.budgetNs / 1_000_000} ms, {over.size} over); {fails.size} failing sequences"
  let dropped : Nat := stats.fold (fun (n : Nat) _ (st : ClaimStat) => n + (st.checks.get? droppedCheck).getD 0) 0
  if t.app.isSome then
    IO.println s!"pressability skipped in {skipped} of {stepsRun} steps (window below the app's minimum); {mono} sequences with mono metrics"
    if dropped > 0 then
      IO.println s!"{dropped} clicks dropped by design: the pointerDown's blur saved an edit that moved the clicked control (T33; counted as {droppedCheck}, not failed)"
  if t.app.isSome then
    IO.println s!"host: {host.requests} requests ({host.cancels} cancelled), {host.replies} answered ({host.failed} failed), {host.cancelledReplies} answers to cancelled requests, {host.stray} stray; {host.clocks} clocks, {host.wakes} wakes, {host.timersDue} timers due; {host.subEvents} subscription events ({host.lateSubEvents} after a stop); {host.loads} early loads, {host.evictions} evictions; at most {host.maxOutstanding} outstanding, {host.leftOver} unanswered at the end; {host.badges} badges, {host.announcements} announcements"
    if t.custom.server.isSome then
      IO.println s!"server: {host.served} requests handled ({host.retransmits} delivered twice), {host.lostAfter} replies lost after it acted, {host.failedBefore} requests failed before reaching it, {host.ticks} times its world acted on its own"
  for inv in t.invariants do
    if inv.check.isNone && !(t.custom.relations.any (·.1 == inv.info.id)) &&
        !(t.custom.drained.any (·.1 == inv.info.id)) && !(t.custom.outstanding.any (·.1 == inv.info.id)) &&
        !(t.srv.checks.any (·.1 == inv.info.id)) && !(t.srv.drained.any (·.1 == inv.info.id)) then IO.println s!"note: ^{inv.info.id} {inv.info.title} is not runnable (no Decidable instance)"
  let json := Json.mkObj [
    ("app", Json.str t.name), ("module", Json.str t.module), ("package", Json.str t.package),
    ("mode", Json.str (if t.app.isSome then "runtime" else "model")),
    ("seed", toJson seed0), ("iterations", toJson o.iterations), ("steps", toJson o.steps),
    ("sequences", toJson o.iterations), ("stepsRun", toJson stepsRun),
    ("seconds", Json.num ⟨((ns + 5_000_000) / 10_000_000 : Nat), 2⟩),
    ("sequencesPerSecond", toJson seqPerS), ("stepsPerSecond", toJson stepsPerS), ("budgetMs", toJson (t.budgetNs / 1_000_000)),
    ("claims", Json.mkObj (t.claims.map fun c => (s!"^{c.id}", claimJson t stats fails c))),
    ("failures", Json.arr reports),
    ("failingSequences", toJson fails.size),
    ("budget", Json.mkObj [("maxMs", msJson maxNs), ("over", Json.arr over)]),
    ("pressableSkipped", toJson skipped), ("droppedClicks", toJson dropped),
    ("host", hostStatsJson host)]
  let dir : System.FilePath := o.out.getD (if ← System.FilePath.pathExists "../claims.lock" then "../build/fuzz" else "build/fuzz")
  -- A dependency's target, `cairn_atproto/Claims`, goes in a directory of its package's.
  let file := dir / s!"{t.name}.json"
  if let some parent := file.parent then IO.FS.createDirAll parent
  IO.FS.writeFile file (json.pretty ++ "\n")
  IO.println s!"wrote {file}"
  return if fails.isEmpty then 0 else 1

/-- A name two of `targets` share, if any (cairn#221). -/
def duplicate? : List Target → Option String
  | [] => none
  | t :: ts => if ts.any (·.name == t.name) then some t.name else duplicate? ts

def main (targets : List Target) (args : List String) : IO UInt32 := do
  if let some n := duplicate? targets then
    let mods := targets.filter (·.name == n) |>.map (·.module)
    IO.eprintln s!"two fuzz targets are named {n.quote} ({mods}); a name must pick one machine (cairn#221)"
    return 2
  let env (k : String) : IO (Option Nat) := do return (← IO.getEnv k).bind String.toNat?
  let o : Opts := { seed := (← env "SEED").getD 0, iterations := (← env "ITERATIONS").getD 100 }
  match parseArgs o args with
  | .error e => IO.eprintln e; IO.eprintln usage; return 2
  | .ok o =>
    if o.list then
      for t in targets do
        if o.deps || !t.dependency then IO.println s!"{t.name}\t{t.module}"
      return 0
    match targets.find? (·.name == o.app) with
    | some t => runTarget t o
    | none =>
      IO.eprintln s!"unknown app {o.app.quote}; fuzzable: {targets.map (·.name)}"
      IO.eprintln usage
      return 2

end Cairn.Fuzz

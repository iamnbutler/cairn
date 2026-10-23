module

/-! # Yap: where the live preview cuts

Mirrors `Chunker.swift`: while recording, the overlay transcribes the audio in chunks cut at
pauses, so a cut never lands mid-word. The host reports the recording as 20 ms windows (320
samples at 16 kHz), each with its sum of squared samples and its peak; this is the cut, on
those numbers, in integers.

Swift compares root-mean-square levels as `Double`s: a window is quiet when its level is below
`max(150, 0.12 × loudest)`. With `sumSq = 320 × level²` that is exactly
`sumSq < 150² × 320 ∨ 10000 × sumSq < 144 × loudestSumSq`, so no `Float` is needed. Swift's
constants come from `Double` arithmetic: the pause is `(0.45 / 0.02).rounded()` = 23 windows
(Swift rounds half away from zero), the earliest cut 60, the latest 500, and the fallback
searches the last `Int(2 / 0.02)` = 100 windows. -/

@[expose] public section

namespace Examples.Yap

/-- One 20 ms window of the recording, as the host measures it. -/
structure Window where
  /-- The sum of the squares of its 320 samples. -/
  sumSq : Nat
  /-- Its largest absolute sample (`Int16.min` counts as `Int16.max`, as in Swift). -/
  peak : Nat
deriving Repr, DecidableEq, Inhabited

namespace Chunker

/-- Samples in a window: `Int(16000 × 0.02)`. -/
def windowSamples : Nat := 320
/-- A pause is this many quiet windows (0.45 s). -/
def pauseWindows : Nat := 23
/-- No cut before this window (1.2 s): too little context. -/
def earliest : Nat := 60
/-- Past this many windows (10 s) without a pause, cut anyway. -/
def latest : Nat := 500
/-- …at the quietest window of the last 100 (2 s). -/
def tail : Nat := 100

/-- A window quieter than `max(150, 0.12 × loudest)` RMS, in sums of squares. -/
def quiet (loudest w : Nat) : Bool := w < 150 * 150 * windowSamples || w * 10000 < 144 * loudest

/-- The first window where `pauseWindows` quiet windows end, with the cut in the pause's middle
and not before `earliest`. `i` is the window's index, `run` the quiet run before it. -/
def scan (q : Nat → Bool) : List Nat → Nat → Nat → Option Nat
  | [], _, _ => none
  | l :: ls, i, run =>
    let run := if q l then run + 1 else 0
    if pauseWindows ≤ run ∧ earliest + run ≤ i + 1 + pauseWindows / 2 then
      some (i + 1 + pauseWindows / 2 - run)
    else scan q ls (i + 1) run

/-- The index of the first smallest level among windows `lo ≤ i < hi`. -/
def argmin (levels : List Nat) (lo hi : Nat) : Nat :=
  (((levels.drop lo).take (hi - lo)).zipIdx lo).foldl
    (fun (best : Nat × Nat) (x : Nat × Nat) => if x.1 < best.2 then (x.2, x.1) else best)
    (lo, (levels.drop lo).headD 0) |>.1

/-- `Chunker.boundary`: the first cut, in windows from the start of `levels`, or none while it
is too early to tell. -/
def boundary (levels : List Nat) : Option Nat :=
  if levels.isEmpty then none
  else match scan (quiet (levels.foldl max 0)) levels 0 0 with
    | some c => some c
    | none => if latest ≤ levels.length then some (argmin levels (latest - tail) latest + 1) else none

/-- How many windows the live preview takes in one poll: it cuts, then cuts what remains,
until no cut is found (`Yap.startLive`). -/
def taken (levels : List Nat) : Nat := go levels.length levels
where
  go : Nat → List Nat → Nat
    | 0, _ => 0
    | fuel + 1, ls => match boundary ls with
      | none => 0
      | some 0 => 0
      | some c => c + go fuel (ls.drop c)

end Chunker

/-- The loudest sample of some windows. -/
def peakOf (ws : List Window) : Nat := ws.foldl (fun m w => max m w.peak) 0

end Examples.Yap

module

/-! # Yap: what is kept

Mirrors `TranscriptLog.swift`. With **Keep Transcripts** on, each transcript is appended to
`transcripts/YYYY-MM-DD.jsonl`, and days older than the retention period are deleted. Days are
numbered (the host turns a file name into a day number in the local calendar and back), so
deciding what to delete is arithmetic here. The menu's recent list is the newest five,
on disk or not. -/

@[expose] public section

namespace Examples.Yap

/-- One dictation. -/
structure Transcript where
  /-- The clip it came from; none for one read back from disk at launch. -/
  clip : Option Nat
  text : String
  /-- The app it was meant for. -/
  app : Option String := none
  /-- Whether it reached that app. -/
  typed : Bool := false
deriving Repr, DecidableEq, Inhabited

/-- The recent list holds the newest five. -/
def recentLimit : Nat := 5

/-- A transcript joins the front of the recent list. -/
def remember (t : Transcript) (recent : List Transcript) : List Transcript :=
  (t :: recent).take recentLimit

theorem remember_length (t : Transcript) (recent : List Transcript) :
    (remember t recent).length ≤ recentLimit := by
  simp only [remember, List.length_take]
  exact Nat.min_le_left _ _

theorem mem_remember (t : Transcript) (recent : List Transcript) : t ∈ remember t recent := by
  simp [remember, recentLimit]

/-- `TranscriptLog.prune(keepingDays:)`: the day files to delete, given today's day number and
the files there are. Counting today as the first day, files older than `retention` days go;
`retention ≤ 0` keeps everything. -/
def daysToDelete (retention : Int) (today : Nat) (days : List Nat) : List Nat :=
  if retention ≤ 0 then [] else days.filter fun d => (d : Int) + retention ≤ today

theorem mem_daysToDelete {retention : Int} {today d : Nat} {days : List Nat} :
    d ∈ daysToDelete retention today days ↔ d ∈ days ∧ 0 < retention ∧ (d : Int) + retention ≤ today := by
  unfold daysToDelete
  split
  · simp only [List.not_mem_nil, false_iff, not_and]
    intro _ h
    omega
  · simp only [List.mem_filter, decide_eq_true_eq]
    constructor
    · rintro ⟨h1, h2⟩; exact ⟨h1, by omega, h2⟩
    · rintro ⟨h1, -, h2⟩; exact ⟨h1, h2⟩

/-- **Retention never deletes today's file**, nor any day after it. -/
theorem daysToDelete_lt {retention : Int} {today d : Nat} {days : List Nat}
    (h : d ∈ daysToDelete retention today days) : d < today := by
  have := mem_daysToDelete.1 h
  omega

theorem today_not_deleted (retention : Int) (today : Nat) (days : List Nat) :
    today ∉ daysToDelete retention today days :=
  fun h => Nat.lt_irrefl _ (daysToDelete_lt h)

end Examples.Yap

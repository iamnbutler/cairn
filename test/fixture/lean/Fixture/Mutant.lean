import Fixture

/-! A bug the fixture's tests miss and its invariant catches, for the docs page "How much to trust
a claim" (site/web/content/docs/reference/trust.md). `addBuggy` is `add` with one plausible slip;
nothing uses it, and it declares no claims. -/

namespace Fixture.Mutant
open Cairn Fixture

-- region: mutant-add
/-- `add`, except that it works out the next id from how many items there are, instead of
keeping it. -/
def addBuggy (s : State) : State :=
  if trimmed s.field.text = [] then s
  else
    let items := s.items ++ [{ id := s.nextId, text := String.ofList (trimmed s.field.text) }]
    { s with items, nextId := items.length + 1, field := Text.Field.empty placeholder }
-- endregion: mutant-add

-- region: mutant-tests
/-- `s` with `t` typed into the New item field. -/
def typing (t : String) (s : State) : State := { s with field := { s.field with text := t.toList } }

def ids (s : State) : List Nat := s.items.map (·.id)

-- The fixture's tests: add milk, add eggs, check one off. Same ids, same next id as `add`.
#guard ids (addBuggy (typing "eggs" (addBuggy (typing "milk" {})))) == [1, 2]
#guard (addBuggy (typing "eggs" (addBuggy (typing "milk" {})))).nextId == 3
-- Blank text adds nothing, and deleting at the end leaves the rest.
#guard addBuggy (typing "  " {}) == typing "  " {}
#guard ids (delete 2 (addBuggy (typing "eggs" (addBuggy (typing "milk" {}))))) == [1]
-- endregion: mutant-tests

-- region: mutant-attempt
/--
error: omega could not prove the goal:
a possible counterexample may satisfy the constraints
  c ≥ 0
  b ≥ 0
  b - c ≥ 2
  a ≥ 1
  a - b ≥ 0
where
 a := ↑s.nextId
 b := ↑i.id
 c := ↑s.items.length
-/
#guard_msgs in
/-- ^7's step for `addBuggy`, written like `add_inv`. It fails, and `#guard_msgs` checks that it
fails with exactly this message. -/
example {s : State} (h : Inv s) : Inv (addBuggy s) := by
  obtain ⟨hn, hb⟩ := h
  unfold addBuggy
  split
  · exact ⟨hn, hb⟩
  · refine ⟨Nat.succ_pos _, fun i hi => ?_⟩
    simp only [List.mem_append, List.mem_singleton, List.length_append,
      List.length_singleton] at hi ⊢
    have : i.id < s.nextId + 1 := by
      rcases hi with hi | rfl
      · exact Nat.lt_succ_of_lt (hb i hi)
      · exact Nat.lt_succ_self _
    omega
-- endregion: mutant-attempt

-- region: mutant-counterexample
/-- Add milk and eggs, then delete milk: one item left, and the next id is 3. -/
def eggsLeft : State := { items := [⟨2, "eggs", false⟩], nextId := 3 }

/-- The state the failed proof asks about: more ids issued than items left. Adding bread to
`eggsLeft` with `addBuggy` gives it id 3 and sets the next id to 3, so ^7 no longer holds. -/
theorem addBuggy_breaks : Inv eggsLeft ∧ ¬ Inv (addBuggy (typing "bread" eggsLeft)) := by
  refine ⟨⟨by decide, fun i hi => ?_⟩, fun h => ?_⟩
  · simp only [eggsLeft, List.mem_singleton] at hi; subst hi; decide
  · have hid : ids (addBuggy (typing "bread" eggsLeft)) = [2, 3] := by decide
    have hn : (addBuggy (typing "bread" eggsLeft)).nextId = 3 := by decide
    have h3 : 3 ∈ ids (addBuggy (typing "bread" eggsLeft)) := by rw [hid]; decide
    obtain ⟨it, hit, he⟩ := List.mem_map.mp h3
    have := h.2 it hit
    omega
-- endregion: mutant-counterexample

end Fixture.Mutant

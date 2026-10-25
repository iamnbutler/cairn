import Examples.Basics

/-! A bug Basics' tests miss and its invariant catches, for the docs page "How much to trust a
claim" (site/web/content/docs/reference/trust.md). `deleteBuggy` is `delete` with one plausible
slip; nothing uses it, and it declares no claims. -/

namespace Examples.Basics.Mutant
open Examples.Basics

-- region: mutant-delete
/-- `delete`, except that it takes one off the count of items left whatever the item
was. -/
def deleteBuggy (k : Nat) (s : State) : State :=
  match s.items.find? (·.id = k) with
  | none => s
  | some _ => { s with items := s.items.filter (·.id ≠ k), left := s.left - 1 }
-- endregion: mutant-delete

-- region: mutant-tests
/-- A state with the given items, as the moves would have left it. -/
def withItems (items : List Item) : State :=
  { items, nextId := items.length + 1, left := undone items }

-- Basics' test: milk and eggs, milk done, delete eggs. None left, as it should be.
#guard (deleteBuggy 2 (withItems [⟨1, "milk", true⟩, ⟨2, "eggs", false⟩])).left == 0
-- Delete the only item, done or not: none left.
#guard (deleteBuggy 1 (withItems [⟨1, "milk", false⟩])).left == 0
#guard (deleteBuggy 1 (withItems [⟨1, "milk", true⟩])).left == 0
-- endregion: mutant-tests

-- region: mutant-attempt
/--
error: omega could not prove the goal:
a possible counterexample may satisfy the constraints
  d ≥ 0
  c ≥ 0
  c - d ≥ 1
  b ≥ 0
  b - d ≤ 1
  a ≥ 1
where
 a := ↑s.nextId
 b := ↑(if it.done = true then 0 else 1)
 c := ↑(undone
    { items := List.filter (fun x => decide (x.id ≠ k)) s.items, nextId := s.nextId, left := s.left - 1,
        field := s.field }.items)
 d := ↑(s.left - 1)
-/
#guard_msgs in
/-- ^105's step for `deleteBuggy`, written like `delete_inv`. It fails, and
`#guard_msgs` checks that it fails with exactly this message. -/
example (k : Nat) {s : State} (h : Inv s) : Inv (deleteBuggy k s) := by
  obtain ⟨hl, ha, hb, hn⟩ := h
  unfold deleteBuggy
  split
  · exact ⟨hl, ha, hb, hn⟩
  · rename_i it hf
    have hu := undone_delete k ha hf
    refine ⟨?_, Ascending.filter _ ha, ?_, hn⟩
    · show s.left - 1 = _
      omega
    · intro i hi
      exact hb i (List.mem_filter.mp hi).1
-- endregion: mutant-attempt

-- region: mutant-counterexample
/-- The state the failed proof asks about: two items, the first done. Deleting it should
leave the count at 1; `deleteBuggy` makes it 0, so ^105 no longer holds. -/
theorem deleteBuggy_breaks :
    Inv (withItems [⟨1, "milk", true⟩, ⟨2, "eggs", false⟩]) ∧
    ¬ Inv (deleteBuggy 1 (withItems [⟨1, "milk", true⟩, ⟨2, "eggs", false⟩])) := by
  refine ⟨⟨rfl, by decide, by decide, by decide⟩, fun h => ?_⟩
  have : (0 : Nat) = 1 := h.1
  omega
-- endregion: mutant-counterexample

end Examples.Basics.Mutant

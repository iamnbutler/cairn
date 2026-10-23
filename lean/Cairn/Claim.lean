/-! Claims: statements about the product with durable ids.

The vocabulary is fixed here; the `move`, `flow`, `invariant`, `assume` and `place` commands
that create claims, and the ledger that guards their ids, live in `Cairn.Claims`. -/

namespace Cairn

/-- A claim id, written `^N`. Never renumbered, reused or deleted. -/
abbrev ClaimId := Nat

inductive ClaimKind where
  | move | flow | invariant | assume | place
deriving Repr, DecidableEq, Inhabited

/-- The human half of a claim: what a reviewer reads next to the formal statement. -/
structure ClaimInfo where
  id : ClaimId
  kind : ClaimKind
  title : String
  /-- What the person does (moves) or what the claim states (others). -/
  does : String := ""
  /-- What follows. -/
  sees : String := ""
  /-- The `place` claim this one appears in, if any. -/
  place : Option ClaimId := none
  /-- Retired claims keep their id and say why. -/
  retired : Option String := none
deriving Repr, Inhabited

/-- One instance of a move's control on screen. A move like "toggle a todo" has one control
per todo; `key` tells them apart (0 when there is only one). Shown as `^5` or `^5#12`. -/
structure ControlRef where
  claim : ClaimId
  key : Nat := 0
deriving Repr, DecidableEq, Inhabited, Hashable

def ControlRef.label (c : ControlRef) : String :=
  if c.key == 0 then s!"^{c.claim}" else s!"^{c.claim}#{c.key}"

end Cairn

/-- `==` on control references is the lawful one from `DecidableEq`, so proofs can use it. -/
example : LawfulBEq Cairn.ControlRef := inferInstance

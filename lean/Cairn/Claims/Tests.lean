import Cairn.Claims

/-! Tests for the claim commands: a small machine that uses every command, and one failing
declaration per compile-time check, with the error it must give.

Not imported by `Cairn` or `Examples`, so its ids (9100 and up) stay out of the ledger. -/

namespace Cairn.Claims.Tests
open Cairn Cairn.Claims

structure St where
  n : Nat := 0
  log : List Nat := []
  text : String := ""
deriving Repr, DecidableEq

place ^9100 main "Main" where
  does "The window."

move ^9101 inc (s : St) "Increment" in ^9100 where
  does "Press +."
  sees "n goes up by one."
  on press
    apply := { s with n := s.n + 1 }
    post s' := s'.n = s.n + 1
    sound := by intro s; rfl

move ^9102 reset (s : St) "Reset" in ^9100 where
  does "Press Reset."
  sees "n is zero."
  enabled := s.n > 0
  on press
    apply := { s with n := 0 }
    post s' := s'.n = 0
    sound := by intro s _; rfl

move ^9103 item (s : St) (k : Nat) "Toggle item" where
  does "Press an item."
  sees "Its key is logged."
  enabled := k < 10
  on press
    emit := ({ s with log := k :: s.log }, [.beep])
    post s' := s'.log = k :: s.log
    sound := by intro s k _; rfl

move ^9104 field (s : St) "Type" where
  does "Type in the field."
  sees "The text is appended."
  on edit (op : TextOp)
    apply := match op with | .insert t => { s with text := s.text ++ t } | _ => s
    post s' := ∀ t, op = .insert t → s'.text = s.text ++ t
    sound := by intro s op t h; subst h; rfl
  on submit
    apply := { s with text := "" }
    post s' := s'.text = ""
    sound := by intro s; rfl

def machine : Machine St := { init := {}, moves := moves% }

flow ^9105 countTwo "Count to two" for machine where
  does "Press + twice."
  goal s := s.n = 2
  witness press ^9101, press ^9101

flow ^9106 typeHi "Type hi" for machine where
  does "Type hi then press 3."
  goal s := s.text = "hi" ∧ s.log = [3]
  witness edit ^9104 (.insert "h"), edit ^9104 (.insert "i"), press ^9103#3

invariant ^9107 small "Log keys are small" for machine where
  does "Every logged key is below 10."
  holds s := ∀ k ∈ s.log, k < 10
  init := by intro k h; simp [machine] at h
  step := machine.preserves <| by
    simp only [machine]
    exact Move.all_cons (inc.preserves _ fun s h => h)
      (Move.all_cons (reset.preserves _ fun s _ h => h)
      (Move.all_cons (item.preserves _ fun s k he h => by
          simp only [item.enabled, decide_eq_true_eq] at he
          intro x hx; simp [item.press.emit] at hx; rcases hx with rfl | hx; exact he; exact h x hx)
      (Move.all_cons (field.preserves _ (fun s op h => by cases op <;> exact h) fun s h => h)
      Move.all_nil)))

-- A decidable invariant gets a runnable `check` (`decide (holds s)`).
#guard small.check { log := [1, 9] } && !small.check { log := [10] }

/-- An invariant over a predicate with no `Decidable` instance gets no `check`. -/
def Opaque (s : St) : Prop := ∃ f : Nat → Nat, f s.n = 0

invariant ^9110 undecidable "Opaque" for machine where
  does "Holds, but can't be decided."
  holds s := Opaque s
  init := ⟨fun _ => 0, rfl⟩
  step := fun _ _ _ => ⟨fun _ => 0, rfl⟩

open Lean in
#eval show MetaM Unit from do
  if (← getEnv).contains `Cairn.Claims.Tests.undecidable.check then throwError "undecidable.check should not exist"

assume ^9108 world "Clicks arrive" where
  does "The host delivers clicks."
  check "host.clicks"

open Lean in
#eval show MetaM Unit from do
  let e? := (entries (← getEnv)).find? (·.info.id == 9108)
  unless e?.bind (·.check) == some "host.clicks" do throwError "^9108 should record its check"

retire ^9109 move "Old thing" because "Replaced by ^9101."

def claims : List ClaimInfo := claims%

#guard claims.map (·.id) == [9100, 9101, 9102, 9103, 9104, 9105, 9106, 9107, 9108, 9109, 9110]
#guard (claims.find? (·.id == 9109)).bind (·.retired) == some "Replaced by ^9101."
#guard (claims.find? (·.id == 9101)).bind (·.place) == some 9100
#guard (machine.update {} (.press ⟨9101, 0⟩)).1.n == 1
#guard (machine.update {} (.press ⟨9102, 0⟩)).1 == {}
#guard (machine.update { n := 3 } (.press ⟨9102, 0⟩)).1.n == 0
#guard (machine.update {} (.press ⟨9103, 4⟩)).2.length == 1
#guard (machine.update {} (.press ⟨9103, 12⟩)).2.isEmpty
#guard (machine.update {} (.doublePress ⟨9101, 0⟩)).1 == {}
#guard (machine.update {} (.edit ⟨9104, 0⟩ (.insert "a"))).1.text == "a"
#guard (machine.update {} (.press ⟨1, 0⟩)).1 == {}

/-- The generated statement of a move's soundness, as a reviewer reads it. -/
example : (∀ s : St, reset.enabled s = true → reset.press.post s (reset.press.apply s)) :=
  reset.press.sound

example : ∀ s : St, machine.Reachable s → ∀ k ∈ s.log, k < 10 := small.reachable

/-! ### Each check, failing

`#reject` elaborates a declaration and then throws away whatever it added to the environment,
keeping only its messages, so a failing proof doesn't leave a `sorry` behind for the kernel
replay (`make kernel`) to find. -/

open Lean Elab Command in
/-- Elaborate `cmd` for its messages only. -/
elab "#reject " cmd:command : command => do
  let env ← getEnv
  try elabCommand cmd finally setEnv env

namespace Bad

/--
error: claim id cairn^9101 is already issued: cairn^9101 move “Increment” (Cairn.Claims.Tests.inc, module Cairn.Claims.Tests). Ids are never reused; take a new one
-/
#guard_msgs in
#reject move ^9101 again (s : St) "Increment again" where
  does "Press +."
  sees "n goes up."
  on press
    apply := s
    post _ := True
    sound := by intro; trivial

/--
error: missing `sees "…"`: what follows
-/
#guard_msgs in
#reject move ^9120 noSees (s : St) "No sees" where
  does "Press it."
  on press
    apply := s
    post _ := True
    sound := by intro; trivial

/-- error: missing `sound`: the proof that `apply` meets `post` -/
#guard_msgs in
#reject move ^9121 noProof (s : St) "No proof" where
  does "Press it."
  sees "Nothing."
  on press
    apply := s
    post _ := True

/--
error: unsolved goals
s : St
⊢ s.n = 1
-/
#guard_msgs in
#reject move ^9122 badProof (s : St) "Wrong proof" where
  does "Press it."
  sees "n is one."
  on press
    apply := s
    post s' := s'.n = 1
    sound := by intro s; simp only [post, apply]

/--
error: unknown place ^9999: declare it with `place ^9999 …` first
-/
#guard_msgs in
#reject place ^9123 nowhere "Nowhere" in ^9999 where
  does "Inside a place that does not exist."

/--
error: ^9101 is not a place: cairn^9101 move “Increment” (Cairn.Claims.Tests.inc, module Cairn.Claims.Tests)
-/
#guard_msgs in
#reject move ^9124 inMove (s : St) "In a move" in ^9101 where
  does "Press it."
  sees "Nothing."
  on press
    apply := s
    post _ := True
    sound := by intro; trivial

/--
error: `check` names a fuzzer check, like "frame.decode" (lowercase, digits, `.` and `-`); got "Frame decode"
-/
#guard_msgs in
#reject assume ^9126 badCheck "Bad check" where
  does "Something."
  check "Frame decode"

/--
error: a retired claim says why it was retired
-/
#guard_msgs in
#reject retire ^9125 move "Gone" because ""

/--
error: Tactic `decide` proved that the proposition
  machine.live machine.init witness = true
is false
-/
#guard_msgs in
#reject flow ^9126 stuck "Reset at zero" for machine where
  does "Press Reset at zero."
  goal s := s.n = 0
  witness press ^9102

/--
error: a witness step names a move, and ^9100 is not one: cairn^9100 place “Main” (Cairn.Claims.Tests.main, module Cairn.Claims.Tests)
-/
#guard_msgs in
#reject flow ^9127 notAMove "Through a place" for machine where
  does "Press the place."
  goal s := s.n = 0
  witness press ^9100

namespace Late
def moves : List (Move St) := moves%

/--
error: `moves%` already collected namespace Cairn.Claims.Tests.Bad.Late; a move declared now would never be dispatched. Declare moves before it
-/
#guard_msgs in
#reject move ^9128 late (s : St) "Too late" where
  does "Press it."
  sees "Nothing."
  on press
    apply := s
    post _ := True
    sound := by intro; trivial
end Late

/--
error: `on edit` names its text operation: `on edit (op : TextOp)`
-/
#guard_msgs in
#reject move ^9129 twoApplies (s : St) "Edit without op" where
  does "Type."
  sees "Nothing."
  on edit
    apply := s
    post _ := True
    sound := by intro; trivial

end Bad

/-! Scopes (`cairn.claims.scope`): another package issues its own `^9101`, which is not Cairn's;
inside that scope `^9101` is taken, and `in ^9100` doesn't see Cairn's place. -/
namespace Scoped

set_option cairn.claims.scope "other" in
move ^9101 inc (s : St) "Increment, in another package" where
  does "Press +."
  sees "n goes up."
  on press
    apply := { n := s.n + 1 }
    post s' := s'.n = s.n + 1
    sound := by intro; rfl

open Lean in
#eval show MetaM Unit from do
  let some e := lookup? (← getEnv) "other" 9101 | throwError "other^9101 should be issued"
  unless e.ref == "other^9101" && e.decl == `Cairn.Claims.Tests.Scoped.inc do
    throwError "other^9101 is {e.label}"
  unless (← getEnv).contains `Cairn.Claims.Issued.«other^9101» do
    throwError "other^9101 should have its Issued declaration"
  let some c := lookup? (← getEnv) "cairn" 9101 | throwError "cairn^9101 should still be issued"
  unless c.decl == `Cairn.Claims.Tests.inc do throwError "cairn^9101 is {c.label}"

/--
error: claim id other^9101 is already issued: other^9101 move “Increment, in another package” (Cairn.Claims.Tests.Scoped.inc, module Cairn.Claims.Tests). Ids are never reused; take a new one
-/
#guard_msgs in
set_option cairn.claims.scope "other" in
#reject move ^9101 again (s : St) "Again" where
  does "Press +."
  sees "n goes up."
  on press
    apply := s
    post _ := True
    sound := by intro; trivial

/--
error: unknown place ^9100: declare it with `place ^9100 …` first
-/
#guard_msgs in
set_option cairn.claims.scope "other" in
#reject move ^9102 placed (s : St) "Placed in Cairn's place" in ^9100 where
  does "Press."
  sees "Nothing."
  on press
    apply := s
    post _ := True
    sound := by intro; trivial

end Scoped
end Cairn.Claims.Tests

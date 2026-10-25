import Cairn.Claims
import Cairn.Claims.Ledger

/-! Tests for the ledger's `moved:<scope>` status (`Cairn.Claims.Ledger`): ids that left a package
for another (Yap's, `moved:yap`; the example apps', `moved:cairn_examples`) stay issued, aren't
counted as missing, can't come back, and end like a retirement, so they need a breaking version.

In `CairnTools` with the ledger, not `ClaimsTests`: the ledger defines a root `main`, and the kernel
replay (`make kernel`) loads every default target into one environment. `make ledger` builds it. -/

namespace Cairn.Claims.LedgerTests
open Lean Cairn.Claims Cairn.Claims.Ledger

set_option cairn.claims.scope "ledgertest" in
place ^1 kept "Kept" where
  does "A place that stays."

private def lock : String :=
  header ++
  "1\tplace\tactive\t-\tKept\n" ++
  "2\tplace\tmoved:elsewhere\t-\tMoved\n" ++
  "3\tplace\tretired\t-\tRetired\n"

private def lines : Array Line := match parse lock with
  | .ok ls => ls
  | .error _ => #[]

-- `moved:<scope>` parses, keeps the scope, and renders back as it was.
#guard lines.size == 3
#guard lines.map (·.moved) == #[none, some "elsewhere", none]
#guard lines.map (·.retired) == #[false, false, true]
#guard render lines == lock
#guard (parse (header ++ "2\tplace\tmoved:\t-\tMoved\n")).toOption.isNone
#guard (parse (header ++ "2\tplace\tgone\t-\tMoved\n")).toOption.isNone

#eval show MetaM Unit from do
  let env ← getEnv
  -- A moved id gone from the code is fine, as a retired one is.
  let r := compare env "ledgertest" lines
  unless r.errors.isEmpty && r.fresh.isEmpty do
    throwError "moved and retired ids should pass: {r.errors ++ r.fresh}"
  -- Both have ended: they count for the release rule like a retirement.
  unless ended env "ledgertest" lines == [2, 3] do
    throwError "ended: {ended env "ledgertest" lines}"
  -- `update` never rewrites a moved line, even with `--accept`.
  let out := update env "ledgertest" lines true
  unless render out == lock do throwError "update changed the lock:\n{render out}"
  -- An id marked moved can't come back in the scope it left.
  let back := lines.map fun l => if l.id == 1 then { l with moved := some "elsewhere" } else l
  let r := compare env "ledgertest" back
  unless r.errors.any (·.startsWith "^1 “Kept” moved to elsewhere^1 and has come back") do
    throwError "a moved id that came back should fail: {r.errors}"

/-- The last release had ^1 and ^2 active and ^3 retired. -/
private def released : Array Line :=
  match parse (header ++ "1\tplace\tactive\t-\tKept\n2\tplace\tactive\t-\tMoved\n3\tplace\tretired\t-\tRetired\n") with
  | .ok ls => ls
  | .error _ => #[]

private def v (s : String) : Release.Version := (Release.Version.parse? s).getD default

#eval show MetaM Unit from do
  let env ← getEnv
  -- Moving ^2 out after 0.2.5 needs 0.3.0, as retiring it would; ^3 was already retired.
  let patch := retirements env "ledgertest" lines (v "0.2.5") released (v "0.2.6")
  unless patch.size == 1 && patch[0]!.startsWith "^2 “Moved” was active in 0.2.5" do
    throwError "a move in a patch release should be refused: {patch}"
  let minor := retirements env "ledgertest" lines (v "0.2.5") released (v "0.3.0")
  unless minor.isEmpty do throwError "a move in 0.3.0 should be allowed: {minor}"

end Cairn.Claims.LedgerTests

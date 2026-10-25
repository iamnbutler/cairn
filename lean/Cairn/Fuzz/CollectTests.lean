import Cairn.Fuzz.Collect

/-! # Tests of how `fuzz_targets%` names targets (cairn#221)

An app (`sky`) whose machine's module is `Sky.Claims` depends on a package (`cairn_atproto`)
whose machine's module is `CairnAtproto.Claims`. Both modules end in `Claims`; the app's target
keeps the short name and the dependency's gets its package in front, so neither shadows the
other. Two machines that would still share a name are an error. test/fuzz-scope builds the same
case as two real Lake packages. -/

namespace Cairn.Fuzz.CollectTests
open Cairn.Fuzz.Collect

def sky : Found := { machine := `Sky.machine, module := `Sky.Claims, package := some "sky", inModule := 1 }
def atproto : Found :=
  { machine := `CairnAtproto.machine, module := `CairnAtproto.Claims, package := some "cairn_atproto",
    inModule := 1 }

#guard (names (some "sky") #[atproto, sky]).toOption == some #[("cairn_atproto/Claims", true), ("Claims", false)]

-- Built outside Lake: no package is named, so every machine is the package's own, as before.
#guard (names none #[{ sky with package := none }]).toOption == some #[("Claims", false)]

-- Two machines in one module are told apart by the machine's name.
#guard (names (some "ex") #[
    { machine := `Gallery.machine, module := `Gallery, package := some "ex", inModule := 2 },
    { machine := `Gallery.picker, module := `Gallery, package := some "ex", inModule := 2 }]).toOption ==
  some #[("Gallery.machine", false), ("Gallery.picker", false)]

-- Two of the package's own modules ending in `Claims`: an error, not a shadow.
#guard match names (some "sky") #[sky, { sky with machine := `Sky.Other.machine, module := `Sky.Other.Claims }] with
  | .error e => (e.splitOn "Sky.machine and Sky.Other.machine").length == 2
  | .ok _ => false

end Cairn.Fuzz.CollectTests

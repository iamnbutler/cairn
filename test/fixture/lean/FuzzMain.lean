import Checks
import Cairn.Fuzz.Collect
import Cairn.Fuzz.Main

/-! `lake exe fuzz Fixture` (`cairn fuzz`): Cairn's claim-driven fuzzer on the fixture
(Cairn's docs/fuzz.md). The targets are found at compile time. -/

def targets : List Cairn.Fuzz.Target := fuzz_targets%

def main (args : List String) : IO UInt32 := Cairn.Fuzz.main targets args

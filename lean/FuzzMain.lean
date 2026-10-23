import Examples
import Cairn.Fuzz.Collect
import Cairn.Fuzz.Main

/-! `lake exe fuzz <App>`: claim-driven randomized testing of every app in `Examples`
(docs/fuzz.md). The targets are found at compile time, so a new app needs no code here. -/

def targets : List Cairn.Fuzz.Target := fuzz_targets%

def main (args : List String) : IO UInt32 := Cairn.Fuzz.main targets args

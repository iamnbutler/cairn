import App
import Dep
import Cairn.Fuzz.Collect
import Cairn.Fuzz.Main

/-! `lake exe fuzz`, as an app's: `Claims` is the app's machine, `fuzzdep/Claims` the
dependency's (cairn#221). -/

def targets : List Cairn.Fuzz.Target := fuzz_targets%

def main (args : List String) : IO UInt32 := Cairn.Fuzz.main targets args

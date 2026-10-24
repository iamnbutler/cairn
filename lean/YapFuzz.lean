import Examples.Yap.AppFuzz

/-! `lake exe yapfuzz`: Yap's dictation machine against a random host (`Examples/Yap/Fuzz.lean`),
then the app (`receive` and the menu) against one (`Examples/Yap/AppFuzz.lean`). -/

def main (args : List String) : IO UInt32 := Examples.Yap.Fuzz.App.main args

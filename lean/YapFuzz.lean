import Examples.Yap.Fuzz

/-! `lake exe yapfuzz`: Yap's dictation machine against a random host (`Examples/Yap/Fuzz.lean`). -/

def main (args : List String) : IO UInt32 := Examples.Yap.Fuzz.main args

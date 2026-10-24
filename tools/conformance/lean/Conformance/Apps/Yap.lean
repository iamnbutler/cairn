module

public import Conformance.Gen
public import Examples.Yap.Abi

/-! The conformance generator for Yap on Cairn (docs/conformance.md, docs/yap.md): no window,
so every step is a status-item gesture: opening the menu, choosing an item, or choosing a
greyed-out one. The app runs detached with a silent world (`CairnYap --debug-socket`: nothing
records, listens to keys, types or answers a request), so like the model it hears no replies,
and the dictation itself is checked by the proofs, `yapfuzz` and `CairnYap --selftest`. -/

@[export cairn_conformance_run]
public def Conformance.Apps.Yap.run (args : List String) : IO UInt32 :=
  Conformance.run Examples.Yap.machine Examples.Yap.app Examples.Yap.cfg args

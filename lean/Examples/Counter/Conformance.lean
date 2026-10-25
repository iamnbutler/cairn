module

public import Conformance.Gen
public import Examples.Counter.Abi

/-! The conformance generator for Counter (docs/conformance.md). -/

@[export cairn_conformance_run]
public def Examples.Counter.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Examples.Counter.machine Examples.Counter.app Examples.Counter.cfg args

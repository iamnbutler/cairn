module

public import Conformance.Gen
public import Examples.Todo.Abi

/-! The conformance generator for TodoMVC (docs/conformance.md). -/

@[export cairn_conformance_run]
public def Examples.Todo.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Examples.Todo.machine Examples.Todo.app Examples.Todo.cfg args

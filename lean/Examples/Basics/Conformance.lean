module

public import Conformance.Gen
public import Examples.Basics

/-! The conformance generator for Basics (docs/conformance.md). Another app adds a file like
this one, `<App>/Conformance.lean`, naming its machine, app and config. -/

@[export cairn_conformance_run]
public def Examples.Basics.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Examples.Basics.machine Examples.Basics.app Examples.Basics.cfg args

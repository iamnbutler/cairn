module

public import Conformance.Gen
public import Fixture.Abi

/-! The conformance generator for the fixture (Cairn's docs/conformance.md): `cairn conformance`
links this module's `cairn_conformance_run` with the app's library. -/

@[export cairn_conformance_run]
public def Fixture.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Fixture.machine Fixture.app Fixture.cfg args

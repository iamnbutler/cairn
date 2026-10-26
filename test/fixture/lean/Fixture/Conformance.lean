module

public import Conformance.Gen
public import Fixture.Abi
public import Fixture.Fuzz

/-! The conformance generator for the fixture (Cairn's docs/conformance.md): `cairn conformance`
links this module's `cairn_conformance_run` with the app's library. Its world is `cairn fuzz`'s
(`Fixture.fuzz`): the Like and Refresh requests are answered by the same fake server. -/

@[export cairn_conformance_run]
public def Fixture.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Fixture.machine Fixture.app Fixture.cfg args (custom := Fixture.fuzz)

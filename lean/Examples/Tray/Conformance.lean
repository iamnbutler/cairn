module

public import Conformance.Gen
public import Examples.Tray.Abi

/-! The conformance generator for Tray (docs/conformance.md): no window, so every step is a
status-item gesture: opening the menu, choosing an item, or choosing a greyed-out one. -/

@[export cairn_conformance_run]
public def Examples.Tray.Conformance.run (args : List String) : IO UInt32 :=
  _root_.Conformance.run Examples.Tray.machine Examples.Tray.app Examples.Tray.cfg args

import Cairn.Frame.Boundary

/-! Checks for `Cairn.Frame.Boundary`, kept out of the module so they can use `#guard`
(a `#guard` in a `module` needs a `meta import` of what it evaluates). -/

namespace Cairn

private def hugeFont : Frame := .single
  { size := ⟨1, 1⟩, draws := #[.text ⟨0, 0⟩ { size := 4294967296 + 12 } ⟨0, 0, 0, 255⟩ "x"],
    ax := #[] }

-- An out-of-range font size crosses clamped, not wrapped.
#guard (decodeFrame (encodeFrame hugeFont)).map (·.draws) ==
  some #[.text ⟨0, 0⟩ { size := 4294967295 } ⟨0, 0, 0, 255⟩ "x"]



end Cairn

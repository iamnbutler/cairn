import Cairn.Frame.Build
import Cairn.Frame.Events
import Cairn.Runtime.Abi
import Cairn.Text.Host

/-! The runtime's `Boundary`, filled in: v1 event decoding, `Frame.ofLaid`, v1 frame encoding.
An app's ABI file passes `Cairn.Frame.boundary` to `Runtime.stepBytes` and `Runtime.frameBytes`
(docs/runtime.md). -/

namespace Cairn

/-- A batch that does not decode is dropped whole: the host's encoder is checked against Lean's
decoder by the corpus test, so a bad batch means a host bug, and running half of it would be
worse than running none. -/
def Frame.boundary : Runtime.Boundary where
  decode b := ((decodeEvents b).getD #[]).toList
  render l ui := Frame.ofLaid ui l
  encode := encodeFrame

/-- The frame encoder clamps font fields exactly as the text host does, so the font painted is
the font measured. -/
theorem satU32_eq_host_sat (n : Nat) : Wire.satU32 n = (Text.Host.sat n).toNat := by
  unfold Wire.satU32 Text.Host.sat
  split <;> simp_all only [Nat.toUInt32, UInt32.toNat_ofNat', Nat.reducePow, Nat.not_lt,
      UInt32.size, Nat.add_one_sub_one, UInt32.reduceOfNat, UInt32.reduceToNat] <;> omega

private def hugeFont : Frame where
  size := ⟨1, 1⟩
  draws := #[.text ⟨0, 0⟩ { size := 4294967296 + 12 } ⟨0, 0, 0, 255⟩ "x"]
  ax := #[]

-- An out-of-range font size crosses clamped, not wrapped.
#guard (decodeFrame (encodeFrame hugeFont)).map (·.draws) ==
  some #[.text ⟨0, 0⟩ { size := 4294967295 } ⟨0, 0, 0, 255⟩ "x"]

end Cairn

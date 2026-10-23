import CairnFrame
import Testing

/// Minimal repros of disagreements `cairn-fuzz-trusted` found (docs/fuzz.md, "Trusted base"),
/// kept as regression tests.
@Suite struct FuzzRegressionTests {
    /// The empty frame: "CAFR", version 2, flags 0, size 0×0, no draws, no ax, no text input,
    /// arrow, no effects, no subscription commands, no wake.
    static let empty: [UInt8] = [0x43, 0x41, 0x46, 0x52, 2, 0, 0, 0] + [UInt8](repeating: 0, count: 60)

    @Test func emptyFrameDecodes() throws {
        #expect(try Frame(bytes: Self.empty) == Frame(size: Size(w: 0, h: 0), draws: []))
    }

    /// Flags are reserved and zero; Lean's decoder rejects any other value, and Swift's
    /// accepted them (fixed: FrameSections checks the u16 at offset 6).
    @Test func nonzeroFlagsAreRejected() {
        for (i, v) in [(6, UInt8(0xC5)), (6, 1), (7, 0x9B), (7, 0x80)] {
            var b = Self.empty
            b[i] = v
            #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: b) }
        }
    }
}

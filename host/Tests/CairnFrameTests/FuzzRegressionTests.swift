import CairnFrame
import Testing

/// Minimal repros of disagreements `cairn-fuzz-trusted` found (docs/fuzz.md, "Trusted base"),
/// kept as regression tests.
@Suite struct FuzzRegressionTests {
    /// The empty frame: "CAFR", version 5, flags 0, no surfaces, no effects, no subscription
    /// commands, no wake.
    static let empty: [UInt8] = [0x43, 0x41, 0x46, 0x52, 8, 0, 0, 0] + [UInt8](repeating: 0, count: 36)

    @Test func emptyFrameDecodes() throws {
        #expect(try Frame(bytes: Self.empty) == Frame(surfaces: []))
    }

    /// Flags are reserved and zero; Lean's decoder rejects any other value, and Swift's
    /// accepted them (fixed: the decoder checks the u16 at offset 6).
    @Test func nonzeroFlagsAreRejected() {
        for (i, v) in [(6, UInt8(0xC5)), (6, 1), (7, 0x9B), (7, 0x80)] {
            var b = Self.empty
            b[i] = v
            #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: b) }
        }
    }
}

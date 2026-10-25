import CairnFrame
import Foundation

/// The Swift frame decoder (`Frame(bytes:)`) against Lean's proved `decodeFrame`, on Lean's random
/// valid frames and on mutated, truncated and spliced bytes. Both must accept or reject alike,
/// and on accept decode to the same canonical dump.
final class FrameSuite: Suite {
    let name = "frame"
    let crashCheck = "frame.decode"
    let checks: [String: CheckInfo] = [
        "frame.decode": CheckInfo(
            title: "The Swift frame decoder agrees with Lean's",
            trusted: ["host/Sources/CairnFrame/Decode.swift", "host/Sources/CairnFrame/Model.swift"],
            oracle: "Lean's decodeFrame (decodeFrame_encodeFrame), through the canonical dump"),
    ]

    func cases(for n: Int) -> Int { n }
    func setUp() { Lean.start() }

    /// A mutation: what it did, and the bytes.
    func make(_ g: inout SplitMix) -> (String, [UInt8]) {
        let base = Lean.genFrame(g.next())
        var b = base
        func u32(_ o: Int) -> UInt32 {
            UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
        }
        func put(_ o: Int, _ v: UInt32) { for k in 0..<4 { b[o + k] = UInt8(truncatingIfNeeded: v >> (8 * k)) } }
        // Offsets of the section headers (count, byteLength) in a valid frame: the surfaces, and
        // the first surface's draws and accessibility nodes.
        var sections = [8]
        if u32(8) > 0, b.count >= 32 {
            let canvas = 32 + Int(u32(28))
            let drawsAt = canvas + 8
            if drawsAt + 8 <= b.count {
                sections.append(drawsAt)
                let axAt = drawsAt + 8 + Int(u32(drawsAt + 4))
                if axAt + 8 <= b.count { sections.append(axAt) }
            }
        }
        var lengthFields = sections.flatMap { [$0, $0 + 4] }.filter { $0 + 4 <= b.count }
        // The tail ends with the effects and subs sections, then the 12-byte wake record: find
        // each section header by its byte length reaching the next one.
        func header(endingAt end: Int) -> Int? {
            stride(from: end - 8, through: 0, by: -4).first { $0 + 8 + Int(u32($0 + 4)) == end }
        }
        if b.count >= 12 {
            lengthFields.append(b.count - 12)  // the wake's presence byte (and padding)
            if let subs = header(endingAt: b.count - 12) {
                lengthFields += [subs, subs + 4]
                if let effects = header(endingAt: subs) { lengthFields += [effects, effects + 4] }
            }
        }
        let kind = g.below(13)
        switch kind {
        case 0, 1:
            return ("valid frame", b)
        case 2:
            let k = g.range(1, 3)
            var at: [String] = []
            for _ in 0..<k {
                let i = g.below(b.count), bit = g.below(8)
                b[i] ^= UInt8(1 << bit)
                at.append("\(i).\(bit)")
            }
            return ("flip bits \(at.joined(separator: ","))", b)
        case 3:
            let i = g.below(b.count), v: UInt8 = g.elem([0, 1, 2, 3, 0x7F, 0x80, 0xFF, 0xC0, 0xED, 0xF4, 0xF5])
            b[i] = v
            return ("set byte \(i) = \(v)", b)
        case 4:
            let o = g.elem(lengthFields), d: Int64 = g.elem([-1, 1, -4, 4])
            put(o, UInt32(truncatingIfNeeded: Int64(u32(o)) + d))
            return ("u32 at \(o) \(d > 0 ? "+" : "")\(d)", b)
        case 5:
            let o = g.elem(lengthFields), v: UInt32 = g.elem([0xFFFFFFFF, 0x80000000, 0x7FFFFFFF, 0x10000000, 0])
            put(o, v)
            return ("u32 at \(o) = \(v)", b)
        case 6:
            let o = 4 * g.below(max(1, b.count / 4)), d: Int64 = g.elem([-1, 1])
            guard o + 4 <= b.count else { return ("valid frame", b) }
            put(o, UInt32(truncatingIfNeeded: Int64(u32(o)) + d))
            return ("u32 at \(o) \(d > 0 ? "+" : "")\(d)", b)
        case 7:
            let n = g.below(b.count)
            return ("truncate to \(n) of \(b.count)", Array(b.prefix(n)))
        case 8:
            let other = Lean.genFrame(g.next())
            let i = g.below(b.count + 1), j = g.below(other.count + 1)
            return ("splice first \(i) of this with bytes from \(j) of frame seed", Array(b.prefix(i)) + other[j...])
        case 9:
            let i = g.below(b.count + 1), v = UInt8(truncatingIfNeeded: g.next())
            b.insert(v, at: i)
            return ("insert byte \(v) at \(i)", b)
        case 10:
            let i = g.below(b.count)
            b.remove(at: i)
            return ("delete byte \(i)", b)
        case 11:
            // Header: magic, version, flags.
            let i = g.range(0, 7), v = UInt8(truncatingIfNeeded: g.next() | 1)
            b[i] ^= v
            return ("header byte \(i) ^= \(v)", b)
        default:
            let extra = (0..<g.range(1, 8)).map { _ in UInt8(truncatingIfNeeded: g.next()) }
            return ("append \(extra.count) bytes", b + extra)
        }
    }

    /// The empty frame: size 0×0, no draws, no ax, no text input, arrow, no effects, no subs, no wake.
    static let emptyFrame: [UInt8] = [0x43, 0x41, 0x46, 0x52, 5, 0, 0, 0] + [UInt8](repeating: 0, count: 36)

    enum Outcome: Equatable { case agree, leanOnly, swiftOnly, differ }

    func compare(_ b: [UInt8]) -> (Outcome, String) {
        let lean = Lean.decodeFrame(b)
        let swift = try? Frame(bytes: b)
        switch (lean, swift) {
        case (.reject, nil): return (.agree, "")
        case let (.accept(_, dump), f?):
            let mine = Dump.frame(f)
            return mine == dump ? (.agree, "") : (.differ, firstDifference(mine, dump))
        case (.accept, nil):
            let err: String
            do { _ = try Frame(bytes: b); err = "?" } catch { err = "\(error)" }
            return (.leanOnly, "Lean accepts, Swift throws \(err)")
        case (.reject, _?): return (.swiftOnly, "Swift accepts, Lean rejects")
        }
    }

    /// Bytes no decoder should be asked to allocate for: a section count above the buffer size
    /// (each record is at least 4 bytes). Shrinking skips them so it can't trip a crash that the
    /// main loop reports on its own.
    func allocates(_ b: [UInt8]) -> Bool {
        func u32(_ o: Int) -> Int {
            o + 4 <= b.count ? Int(UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24) : 0
        }
        if u32(8) > b.count { return true }
        let drawsAt = 40 + u32(28)
        if u32(drawsAt) > b.count { return true }
        return u32(drawsAt + 8 + u32(drawsAt + 4)) > b.count
    }

    /// Delta debugging over bytes: remove chunks while the same disagreement remains.
    func shrink(_ b0: [UInt8], _ want: Outcome) -> [UInt8] {
        var b = b0
        // First, the same 8-byte header on the empty frame: header bugs shrink to 44 bytes.
        if b.count >= 8 {
            let c = Array(b.prefix(8)) + Self.emptyFrame.dropFirst(8)
            if compare(c).0 == want { b = c }
        }
        var chunk = max(1, b.count / 2)
        var budget = 3000
        while chunk >= 1 && budget > 0 {
            var i = 0
            var progressed = false
            while i < b.count && budget > 0 {
                var c = b
                c.removeSubrange(i..<min(b.count, i + chunk))
                budget -= 1
                if !allocates(c) && compare(c).0 == want { b = c; progressed = true } else { i += chunk }
            }
            if !progressed { chunk /= 2 }
        }
        return b
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let (what, b) = make(&g)
        let lean = Lean.decodeFrame(b)
        r.count("frame.decode", lean.accepted ? "leanAccepts" : "leanRejects")
        if case .accept(false, _) = lean { r.count("frame.decode", "leanAcceptsNonCanonical") }
        if what != "valid frame" { r.count("frame.decode", "mutated") }
        let (outcome, msg) = compare(b)
        if outcome == .agree { r.ran("frame.decode"); return }
        let small = shrink(b, outcome)
        r.fail("frame.decode", "\(what) (\(b.count) bytes): \(msg); shrunk to \(small.count) bytes: \(compare(small).1)",
               repro: { "hex:" + hex(small) })
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let (what, b) = make(&g)
        try? FileManager.default.createDirectory(at: reproDir, withIntermediateDirectories: true)
        let url = reproDir.appendingPathComponent("frame-\(caseIndex).bin")
        try? Data(b).write(to: url)
        return "Frame(bytes:) on \(what) (\(b.count) bytes, written to \(url.path))"
    }
}

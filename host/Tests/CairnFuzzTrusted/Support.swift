import CLean
import CairnHost
import CairnTrustedLean
import Foundation

/// SplitMix64, the same generator as `Cairn.Fuzz.Rng` (lean/Cairn/Fuzz/Rng.lean): a seed replays
/// a case exactly.
struct SplitMix {
    var state: UInt64
    static func mix(_ z0: UInt64) -> UInt64 {
        var z = (z0 ^ (z0 >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    init(seed: UInt64) { state = Self.mix(seed) }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        return Self.mix(state)
    }
    /// In `[0, n)`; 0 when n is 0.
    mutating func below(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + below(hi - lo + 1) }
    mutating func chance(_ num: Int, _ den: Int) -> Bool { below(den) < num }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func elem<T>(_ xs: [T]) -> T { xs[below(xs.count)] }
    /// Pick a branch by weight.
    mutating func weighted<T>(_ gs: [(Int, (inout SplitMix) -> T)]) -> T {
        var r = below(gs.reduce(0) { $0 + $1.0 })
        for (w, g) in gs {
            if r < w { return g(&self) }
            r -= w
        }
        return gs[0].1(&self)
    }
}

/// Text that breaks text code, the Swift twin of `Cairn.Fuzz.Trusted.edgeScalars/edgeStrings`.
enum TextPool {
    static let edgeScalars: [UInt32] = [
        0x0, 0x9, 0xA, 0xD, 0x1F, 0x20, 0x22, 0x5C, 0x7E, 0x7F, 0x80, 0xFF, 0x100, 0x7FF, 0x800,
        0x301, 0x200D, 0x200E, 0x200F, 0x2028, 0x2029, 0xFE0F, 0xFEFF, 0xD7FF, 0xE000, 0xFFFD, 0xFFFE,
        0xFFFF, 0x10000, 0x1F3FB, 0x1F3FF, 0x1F600, 0x1F1EB, 0x1F1F7, 0xE0067, 0x10FFFF, 0x5D0,
        0x627, 0x65E5, 0xD55C, 0x30A2, 0x0E01, 0x0915, 0x094D,
    ]
    static let edgeStrings: [String] = [
        "", "a", "👍🏽", "👨‍👩‍👧", "👩🏽‍💻", "🇫🇷", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "é", "ä́", "Z̤̈", "日本語", "한국어", "אבג", "عربي",
        "abאבc", "क्षि", "\u{FEFF}bom", "tab\there", "a\nb", "\r\n", "x\u{10FFFF}y", "\u{0}", "😀😀",
        "Hello, world", "  padded  ", "e\u{301}\u{301}\u{301}", "👋🏻👋🏼👋🏽👋🏾👋🏿", "🧑‍🤝‍🧑", "1️⃣",
        "مرحبا بالعالم", "שָׁלוֹם", "漢字かなカナ", "a\u{200D}b", "\u{202E}rtl override",
    ]

    static func scalar(_ g: inout SplitMix) -> Unicode.Scalar {
        let v: UInt32 = g.weighted([
            (6, { UInt32($0.range(0x20, 0x7E)) }),
            (3, { $0.elem(edgeScalars) }),
            (1, { UInt32($0.range(0x80, 0xD7FF)) }),
            (1, { UInt32($0.range(0xE000, 0xFFFF)) }),
            (1, { UInt32($0.range(0x10000, 0x10FFFF)) }),
        ])
        return Unicode.Scalar(v)!
    }

    static func string(_ g: inout SplitMix, maxParts: Int = 12) -> String {
        g.weighted([
            (2, { _ in "" }),
            (3, { $0.elem(edgeStrings) }),
            (6, { g in
                var s = String.UnicodeScalarView()
                for _ in 0..<g.below(maxParts) {
                    if g.chance(1, 5) { s.append(contentsOf: g.elem(edgeStrings).unicodeScalars) }
                    else { s.append(scalar(&g)) }
                }
                return String(s)
            }),
            (1, { g in
                let c = scalar(&g)
                return String(String.UnicodeScalarView(repeatElement(c, count: g.range(50, 300))))
            }),
        ])
    }
}

/// Calls into Lean (this process links the Lean library and the host).
enum Lean {
    static func start() {
        LeanRuntime.enter(module: initialize_cairn_Cairn_Fuzz_Trusted_Export)
    }

    static func take(_ o: OpaquePointer) -> [UInt8] {
        LeanRuntime.withBytes(o) { [UInt8]($0) }
    }

    static func genFrame(_ seed: UInt64) -> [UInt8] { take(cairn_tf_gen_frame(seed)) }

    enum Verdict: Equatable {
        case reject
        case accept(canonical: Bool, dump: String)
        var accepted: Bool { if case .accept = self { true } else { false } }
    }

    static func verdict(_ reply: [UInt8]) -> Verdict {
        if reply == [0x52] { return .reject }
        precondition(reply.count >= 2 && reply[0] == 0x41, "bad verdict from Lean")
        return .accept(canonical: reply[1] == 0x3D, dump: String(decoding: reply[2...], as: UTF8.self))
    }

    static func decodeFrame(_ b: [UInt8]) -> Verdict {
        verdict(take(cairn_tf_decode_frame(LeanRuntime.bytes(b))))
    }

    static func decodeEvents(_ b: [UInt8]) -> Verdict {
        verdict(take(cairn_tf_decode_events(LeanRuntime.bytes(b))))
    }

    /// `[linked, ascent, descent, offsets…]` from `TextMetrics.host`.
    static func hostMetrics(family: UInt32, size: UInt32, weight: UInt32, italic: Bool, _ s: String) -> [Int32] {
        var s = s
        let o = s.withUTF8 { cairn_tf_host_metrics(family, size, weight, italic ? 1 : 0, $0.baseAddress, $0.count) }
        let bytes = take(o!)
        return stride(from: 0, to: bytes.count, by: 4).map {
            Int32(bitPattern: UInt32(bytes[$0]) | UInt32(bytes[$0 + 1]) << 8 | UInt32(bytes[$0 + 2]) << 16 | UInt32(bytes[$0 + 3]) << 24)
        }
    }

    /// One line as Lean wraps and lays it out (`cairn_tf_wrap`).
    struct WrapLine { var a: Int, b: Int, width: Int32, x: Int32, y: Int32, w: Int32 }

    static func wrap(family: UInt32, size: UInt32, weight: UInt32, italic: Bool, width: UInt32, _ s: String) -> [WrapLine] {
        var s = s
        let o = s.withUTF8 { cairn_tf_wrap(family, size, weight, italic ? 1 : 0, width, $0.baseAddress, $0.count) }
        let bytes = take(o!)
        let v = stride(from: 0, to: bytes.count, by: 4).map {
            Int32(bitPattern: UInt32(bytes[$0]) | UInt32(bytes[$0 + 1]) << 8 | UInt32(bytes[$0 + 2]) << 16 | UInt32(bytes[$0 + 3]) << 24)
        }
        return (0..<Int(v[0])).map { i in
            let k = 1 + 6 * i
            return WrapLine(a: Int(v[k]), b: Int(v[k + 1]), width: v[k + 2], x: v[k + 3], y: v[k + 4], w: v[k + 5])
        }
    }
}

/// Lowercase hex for repro lines.
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

/// The first line where two dumps differ, for messages.
func firstDifference(_ a: String, _ b: String) -> String {
    let la = a.split(separator: "\n", omittingEmptySubsequences: false)
    let lb = b.split(separator: "\n", omittingEmptySubsequences: false)
    for i in 0..<max(la.count, lb.count) {
        let x = i < la.count ? String(la[i]) : "<end>", y = i < lb.count ? String(lb[i]) : "<end>"
        if x != y { return "line \(i + 1): Swift `\(x.prefix(160))` vs Lean `\(y.prefix(160))`" }
    }
    return "no difference"
}

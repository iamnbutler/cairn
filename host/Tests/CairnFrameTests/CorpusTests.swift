import CairnFrame
import Foundation
import Testing

/// The corpus Lean writes (`lake exe framecorpus gen`, run by `make check`): Swift must decode
/// every frame to the same dump, and encode every event batch to the same bytes. The Swift-made
/// event batches written here are decoded by `framecorpus verify`.
enum Corpus {
    static let root: URL = {
        if let dir = ProcessInfo.processInfo.environment["CAIRN_CORPUS"] { return URL(fileURLWithPath: dir) }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/corpus")
    }()

    static func files(_ dir: String, _ ext: String) throws -> [URL] {
        let d = root.appendingPathComponent(dir)
        return try FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ext }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func bytes(_ url: URL) throws -> [UInt8] { [UInt8](try Data(contentsOf: url)) }
    static func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}

@Suite struct CorpusTests {
    @Test func framesDecodeToLeansDump() throws {
        let bins = try Corpus.files("frames", "bin")
        #expect(bins.count >= 100)
        for bin in bins {
            let frame = try Frame(bytes: try Corpus.bytes(bin))
            let expected = try Corpus.text(bin.deletingPathExtension().appendingPathExtension("txt"))
            #expect(Dump.frame(frame) == expected, "\(bin.lastPathComponent)")
        }
    }

    @Test func eventsEncodeToLeansBytes() throws {
        let txts = try Corpus.files("events", "txt")
        #expect(txts.count >= 100)
        for txt in txts {
            let events = try DumpParser.events(try Corpus.text(txt))
            #expect(Dump.events(events) == (try Corpus.text(txt)), "\(txt.lastPathComponent) reparse")
            let expected = try Corpus.bytes(txt.deletingPathExtension().appendingPathExtension("bin"))
            #expect(encodeEvents(events) == expected, "\(txt.lastPathComponent)")
        }
    }

    /// Writes `swift-events/` for Lean to decode (`framecorpus verify`).
    @Test func writeSwiftEvents() throws {
        let dir = Corpus.root.appendingPathComponent("swift-events")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var g = SplitMix(seed: 0xCA1E)
        var batches: [[Event]] = [[], SwiftEvents.edges]
        for _ in 0..<200 { batches.append((0..<g.below(30)).map { _ in SwiftEvents.random(&g) }) }
        for (i, es) in batches.enumerated() {
            let name = String(format: "%04d", i)
            try Data(encodeEvents(es)).write(to: dir.appendingPathComponent("\(name).bin"))
            try Dump.events(es).write(to: dir.appendingPathComponent("\(name).txt"), atomically: true,
                                      encoding: .utf8)
        }
    }

    @Test func rejectsMalformedFrames() throws {
        let bin = try Corpus.bytes(try Corpus.files("frames", "bin")[1])
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: [0x43, 0x41, 0x46, 0x51] + bin.dropFirst(4)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [2, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.trailingBytes(at: bin.count)) { try Frame(bytes: bin + [0]) }
        for n in [0, 3, 15, 16, 20, bin.count / 2, bin.count - 1] {
            #expect(throws: FrameDecodeError.self) { try Frame(bytes: Array(bin[0..<n])) }
        }
    }

    /// A frame with one text draw whose string bytes are `text`.
    static func textFrame(_ text: [UInt8]) -> [UInt8] {
        func u32(_ n: Int) -> [UInt8] { (0..<4).map { UInt8((n >> (8 * $0)) & 0xFF) } }
        let draw: [UInt8] = [1, 0, 0, 0] + u32(0) + u32(0) + u32(0) + u32(12) + u32(400)
            + [0, 0, 0, 255] + u32(text.count) + text
        return Array("CAFR".utf8) + [1, 0, 0, 0] + u32(10) + u32(10)
            + u32(1) + u32(draw.count) + draw + u32(0) + u32(0)
            + [0, 0, 0, 0] + [0, 0, 0, 0] + u32(0) + u32(0)
    }

    @Test func rejectsInvalidUTF8() throws {
        #expect(try Frame(bytes: Self.textFrame(Array("é🙂".utf8))).draws.count == 1)
        let stringAt = 8 + 8 + 8 + 28
        for bad: [UInt8] in [[0xFF], [0xC3], [0xC0, 0x80], [0xED, 0xA0, 0x80], [0x61, 0xF4, 0x90, 0x80, 0x80]] {
            #expect(throws: FrameDecodeError.badUTF8(at: stringAt)) { try Frame(bytes: Self.textFrame(bad)) }
        }
    }

    @Test func sectionsDecodeAlone() throws {
        for bin in try Corpus.files("frames", "bin").prefix(20) {
            let bytes = try Corpus.bytes(bin)
            let whole = try Frame(bytes: bytes)
            try bytes.withUnsafeBytes { raw in
                let s = try FrameSections(raw)
                #expect(try Frame.decodeDraws(raw, s) == whole.draws)
                #expect(try Frame.decodeAx(raw, s) == whole.ax)
            }
        }
    }
}

struct SplitMix {
    var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { n == 0 ? 0 : Int(next() % UInt64(n)) }
    mutating func coin() -> Bool { below(2) == 0 }
}

enum SwiftEvents {
    static let scalars: [Character] = ["a", "Z", " ", "\"", "\\", "\n", "\u{0}", "é", "ß", "ש", "日",
                                       "한", "ア", "🙂", "\u{301}", "\u{FEFF}", "\u{10FFFF}"]

    static func int(_ g: inout SplitMix) -> Int32 {
        g.below(6) == 0 ? [Int32.min, Int32.max, 0, -1][g.below(4)] : Int32(g.below(20001)) - 10000
    }
    static func nat(_ g: inout SplitMix) -> UInt32 {
        g.below(6) == 0 ? [0, 1, UInt32.max][g.below(3)] : UInt32(g.below(2000))
    }
    static func str(_ g: inout SplitMix) -> String {
        String((0..<g.below(10)).map { _ in scalars[g.below(scalars.count)] })
    }
    static func mods(_ g: inout SplitMix) -> Mods {
        Mods(shift: g.coin(), command: g.coin(), option: g.coin(), control: g.coin())
    }
    static func range(_ g: inout SplitMix) -> ScalarRange? {
        g.coin() ? ScalarRange(start: nat(&g), end: nat(&g)) : nil
    }

    static func random(_ g: inout SplitMix) -> Event {
        switch g.below(18) {
        case 0: return .pointerMove(Point(x: int(&g), y: int(&g)))
        case 1: return .pointerDown(Point(x: int(&g), y: int(&g)), g.coin() ? .primary : .secondary,
                                    clicks: nat(&g), mods(&g))
        case 2: return .pointerUp(Point(x: int(&g), y: int(&g)), .primary, mods(&g))
        case 3: return .pointerExit
        case 4: return .scroll(Point(x: int(&g), y: int(&g)), dx: int(&g), dy: int(&g))
        case 5:
            let named: [Key] = [.enter, .escape, .tab, .backspace, .delete, .left, .right, .up,
                                .down, .home, .finish, .pageUp, .pageDown]
            let k: Key = g.coin() ? .char(scalars[g.below(scalars.count)]) : named[g.below(named.count)]
            return .key(k, mods(&g))
        case 6: return .insertText(str(&g), replacing: range(&g))
        case 7: return .setMarked(str(&g), selStart: nat(&g), selLen: nat(&g), replacing: range(&g))
        case 8: return .unmark
        case 9: return .copy
        case 10: return .cut
        case 11: return .selectAll
        case 12: return .undo
        case 13: return .redo
        case 14: return .paste(str(&g))
        case 15: return .resize(Size(w: int(&g), h: int(&g)))
        case 16: return .scale(percent: nat(&g))
        default: return .windowFocus(g.coin())
        }
    }

    static let edges: [Event] = [
        .pointerMove(Point(x: .min, y: .max)),
        .pointerDown(Point(x: 0, y: 0), .secondary, clicks: .max, Mods(shift: true, command: true, option: true, control: true)),
        .key(.char("\u{10FFFF}"), Mods()), .key(.char("👍🏽"), Mods(command: true)),
        .insertText("", replacing: nil), .insertText("é", replacing: ScalarRange(start: 0, end: .max)),
        .setMarked("にほん", selStart: .max, selLen: 0, replacing: ScalarRange(start: 2, end: 2)),
        .paste("🙂👍🏽日本語"), .scale(percent: 0), .resize(Size(w: -1, h: .max)), .windowFocus(true),
    ]
}

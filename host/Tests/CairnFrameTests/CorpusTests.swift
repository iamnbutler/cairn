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
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [1, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [2, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [3, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [4, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [5, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [6, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [7, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [8, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [9, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [10, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [11, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.badHeader) { try Frame(bytes: Array(bin[0..<4]) + [13, 0] + bin.dropFirst(6)) }
        #expect(throws: FrameDecodeError.trailingBytes(at: bin.count)) { try Frame(bytes: bin + [0]) }
        for n in [0, 3, 15, 16, 20, bin.count / 2, bin.count - 1] {
            #expect(throws: FrameDecodeError.self) { try Frame(bytes: Array(bin[0..<n])) }
        }
    }

    /// A frame with one text draw whose string bytes are `text`.
    static func textFrame(_ text: [UInt8]) -> [UInt8] {
        func u32(_ n: Int) -> [UInt8] { (0..<4).map { UInt8((n >> (8 * $0)) & 0xFF) } }
        let draw: [UInt8] = [1, 0, 0, 0] + u32(0) + u32(0) + u32(0) + u32(12) + u32(400) + u32(0)
            + [0, 0, 0, 255] + u32(text.count) + text
        let canvas: [UInt8] = u32(10) + u32(10) + u32(1) + u32(draw.count) + draw + u32(0) + u32(0)
            + [0, 0, 0, 0] + [0, 0, 0, 0]
        let status: [UInt8] = u32(0) + u32(0) + u32(0) + u32(0) + u32(0) + u32(0) + u32(0)
        let surface: [UInt8] = [0, 1, 0, 0] + u32(0) + u32(0) + u32(0) + u32(0) + u32(0) + canvas + status
        return Array("CAFR".utf8) + [12, 0, 0, 0] + u32(1) + u32(surface.count) + surface
            + u32(0) + u32(0) + u32(0) + u32(0) + [UInt8](repeating: 0, count: 12)
    }

    @Test func rejectsInvalidUTF8() throws {
        #expect(try Frame(bytes: Self.textFrame(Array("é🙂".utf8))).draws.count == 1)
        let stringAt = 8 + 8 + 20 + 4 + 8 + 8 + 32
        for bad: [UInt8] in [[0xFF], [0xC3], [0xC0, 0x80], [0xED, 0xA0, 0x80], [0x61, 0xF4, 0x90, 0x80, 0x80]] {
            #expect(throws: FrameDecodeError.badUTF8(at: stringAt)) { try Frame(bytes: Self.textFrame(bad)) }
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

    static func bytes(_ g: inout SplitMix) -> [UInt8] {
        (0..<g.below(10)).map { _ in UInt8(g.below(256)) }
    }
    static func headers(_ g: inout SplitMix) -> [Header] {
        (0..<g.below(3)).map { _ in Header(str(&g), str(&g)) }
    }
    static func reply(_ g: inout SplitMix) -> Reply {
        switch g.below(7) {
        case 0: return .done
        case 1: return .bytes(bytes(&g))
        case 2: return .http(status: nat(&g), headers: headers(&g), body: bytes(&g))
        case 3: return .names((0..<g.below(4)).map { _ in str(&g) })
        case 4: return .app(pid: nat(&g), name: str(&g))
        case 5: return .flag(g.coin())
        default: return .failed(Fault(rawValue: UInt8(g.below(6)))!, str(&g))
        }
    }

    static func random(_ g: inout SplitMix) -> Event {
        switch g.below(21) {
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
        case 17: return .windowFocus(g.coin())
        case 18:
            let mono = g.below(4) == 0 ? UInt64.max : UInt64(g.below(1 << 40))
            let wall = g.below(4) == 0 ? Int64.min : Int64(g.below(1 << 42)) - (1 << 41)
            return .clock(Time(mono: mono, wall: wall, zone: int(&g)))
        case 19: return .reply(id: nat(&g), reply(&g))
        default: return .subEvent(id: nat(&g), subEvent(&g))
        }
    }

    static func subEvent(_ g: inout SplitMix) -> SubEvent {
        let t = g.below(4) == 0 ? UInt64.max : UInt64(g.below(1 << 40))
        switch g.below(8) {
        case 0: return .tick
        case 1: return .changed
        case 7: return .started(t)
        case 2:
            return .audio(frames: nat(&g), peak: nat(&g), windows: (0..<g.below(5)).map { _ in
                Level(sumSq: g.below(4) == 0 ? UInt64.max : UInt64(g.below(1 << 38)), peak: nat(&g)) })
        case 3: return .keyDown(t)
        case 4: return .keyUp(t)
        case 5: return .otherKey(t)
        default: return .failed(Fault(rawValue: UInt8(g.below(6)))!, str(&g))
        }
    }

    static let edges: [Event] = [
        .pointerMove(Point(x: .min, y: .max)),
        .pointerDown(Point(x: 0, y: 0), .secondary, clicks: .max, Mods(shift: true, command: true, option: true, control: true)),
        .key(.char("\u{10FFFF}"), Mods()), .key(.char("👍🏽"), Mods(command: true)),
        .insertText("", replacing: nil), .insertText("é", replacing: ScalarRange(start: 0, end: .max)),
        .setMarked("にほん", selStart: .max, selLen: 0, replacing: ScalarRange(start: 2, end: 2)),
        .paste("🙂👍🏽日本語"), .scale(percent: 0), .resize(Size(w: -1, h: .max)), .windowFocus(true),
        .clock(Time(mono: .max, wall: .min, zone: .min)), .clock(Time(mono: 0, wall: .max, zone: 0)),
        .reply(id: .max, .bytes([0, 255])), .reply(id: 0, .failed(.notFound, "")),
        .reply(id: 1, .http(status: 200, headers: [Header("a", "b")], body: [])), .subEvent(id: .max, .tick),
        .reply(id: 2, .names([])), .reply(id: 3, .names(["", "2026-10-23.jsonl", "🙂"])),
        .reply(id: 4, .app(pid: .max, name: "")), .reply(id: 5, .flag(true)), .subEvent(id: 0, .changed),
        .subEvent(id: 1, .audio(frames: .max, peak: 32768, windows: [Level(sumSq: .max, peak: 32767), Level(sumSq: 0, peak: 0)])),
        .subEvent(id: 2, .audio(frames: 0, peak: 0, windows: [])), .subEvent(id: 3, .keyDown(.max)),
        .subEvent(id: 4, .keyUp(0)), .subEvent(id: 5, .otherKey(1)), .subEvent(id: 6, .failed(.denied, "Accessibility")),
        .subEvent(id: 7, .started(.max)),
    ]
}

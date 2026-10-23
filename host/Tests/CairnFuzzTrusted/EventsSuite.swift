import CairnFrame
import Foundation

/// The Swift event encoder (`encodeEvents`) against Lean's proved `decodeEvents`: every random
/// batch must decode, to the events Swift meant (canonical dump), and Lean's encoder must give
/// back Swift's bytes exactly (the format has one encoding per value).
final class EventsSuite: Suite {
    let name = "events"
    let crashCheck = "events.encode"
    let checks: [String: CheckInfo] = [
        "events.encode": CheckInfo(
            title: "Lean decodes what the Swift event encoder writes",
            trusted: ["host/Sources/CairnFrame/Encode.swift", "host/Sources/CairnFrame/Model.swift"],
            oracle: "Lean's decodeEvents and encodeEvents (decodeEvents_encodeEvents), dump and bytes"),
    ]

    func cases(for n: Int) -> Int { n }
    func setUp() { Lean.start() }

    static func i32(_ g: inout SplitMix) -> Int32 {
        g.weighted([
            (1, { $0.elem([Int32.min, Int32.max, 0, -1, 1, Int32.min + 1, Int32.max - 1]) }),
            (4, { Int32($0.range(-2000, 4000)) }),
            (1, { Int32(truncatingIfNeeded: $0.next()) }),
        ])
    }

    static func u32(_ g: inout SplitMix) -> UInt32 {
        g.weighted([
            (1, { $0.elem([0, 1, UInt32.max, UInt32.max - 1, 65535, 65536, 0x80000000]) }),
            (4, { UInt32($0.below(2000)) }),
            (1, { UInt32(truncatingIfNeeded: $0.next()) }),
        ])
    }

    static func u64(_ g: inout SplitMix) -> UInt64 {
        g.weighted([
            (1, { $0.elem([0, 1, UInt64.max, UInt64(UInt32.max), UInt64(UInt32.max) + 1, 1 << 63]) }),
            (4, { UInt64($0.below(1 << 40)) }),
            (1, { $0.next() }),
        ])
    }

    static func i64(_ g: inout SplitMix) -> Int64 { Int64(bitPattern: u64(&g)) &* (g.bool() ? 1 : -1) }

    static func bytes(_ g: inout SplitMix) -> [UInt8] {
        g.weighted([
            (2, { _ in [] }),
            (4, { g in (0..<g.below(12)).map { _ in UInt8(truncatingIfNeeded: g.next()) } }),
            (1, { g in [UInt8](TextPool.string(&g).utf8) }),
            (1, { g in (0..<g.range(100, 600)).map { _ in UInt8(truncatingIfNeeded: g.next()) } }),
        ])
    }

    static func headers(_ g: inout SplitMix) -> [Header] {
        (0..<g.below(4)).map { _ in Header(TextPool.string(&g, maxParts: 4), TextPool.string(&g, maxParts: 6)) }
    }

    static func reply(_ g: inout SplitMix) -> Reply {
        switch g.below(7) {
        case 0: return .done
        case 1: return .bytes(bytes(&g))
        case 2: return .http(status: u32(&g), headers: headers(&g), body: bytes(&g))
        case 3: return .names((0..<g.below(5)).map { _ in TextPool.string(&g) })
        case 4: return .app(pid: u32(&g), name: TextPool.string(&g))
        case 5: return .flag(g.bool())
        default:
            return .failed(g.elem([.notFound, .denied, .timeout, .network, .invalid, .other]), TextPool.string(&g))
        }
    }

    static func range(_ g: inout SplitMix) -> ScalarRange? {
        g.bool() ? nil : ScalarRange(start: u32(&g), end: u32(&g))
    }

    static func mods(_ g: inout SplitMix) -> Mods {
        Mods(shift: g.bool(), command: g.bool(), option: g.bool(), control: g.bool())
    }

    static func point(_ g: inout SplitMix) -> Point { Point(x: i32(&g), y: i32(&g)) }

    static func key(_ g: inout SplitMix) -> Key {
        if g.chance(1, 3) {
            // A Character: one scalar, or a cluster (emoji with a skin tone, ZWJ, combining).
            let s = g.bool() ? String(TextPool.scalar(&g)) : g.elem(TextPool.edgeStrings.filter { !$0.isEmpty })
            return .char(s.first!)
        }
        return g.elem([.enter, .escape, .tab, .backspace, .delete, .left, .right, .up, .down, .home, .finish,
                       .pageUp, .pageDown])
    }

    static func event(_ g: inout SplitMix) -> Event {
        switch g.below(21) {
        case 0: return .pointerMove(point(&g))
        case 1: return .pointerDown(point(&g), g.bool() ? .primary : .secondary, clicks: u32(&g), mods(&g))
        case 2: return .pointerUp(point(&g), g.bool() ? .primary : .secondary, mods(&g))
        case 3: return .pointerExit
        case 4: return .scroll(point(&g), dx: i32(&g), dy: i32(&g))
        case 5: return .key(key(&g), mods(&g))
        case 6: return .insertText(TextPool.string(&g), replacing: range(&g))
        case 7: return .setMarked(TextPool.string(&g), selStart: u32(&g), selLen: u32(&g), replacing: range(&g))
        case 8: return .unmark
        case 9: return .copy
        case 10: return .cut
        case 11: return .selectAll
        case 12: return .undo
        case 13: return .redo
        case 14: return .paste(TextPool.string(&g))
        case 15: return .resize(Size(w: i32(&g), h: i32(&g)))
        case 16: return .scale(percent: u32(&g))
        case 17: return .windowFocus(g.bool())
        case 18: return .clock(Time(mono: u64(&g), wall: i64(&g), zone: i32(&g)))
        case 19: return .reply(id: u32(&g), reply(&g))
        default: return .subEvent(id: u32(&g), g.bool() ? .tick : .changed)
        }
    }

    func batch(_ g: inout SplitMix) -> [Event] {
        (0..<g.weighted([(1, { _ in 0 }), (6, { $0.range(1, 6) }), (1, { $0.range(20, 80) })])).map { _ in Self.event(&g) }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let es = batch(&g)
        let bytes = encodeEvents(es)
        if es.contains(where: { if case let .key(.char(c), _) = $0 { c.unicodeScalars.count > 1 } else { false } }) {
            r.count("events.encode", "multiScalarKeys")
        }
        r.count("events.encode", "events", es.count)
        switch Lean.decodeEvents(bytes) {
        case .reject:
            r.fail("events.encode", "Lean rejects Swift's batch \(Dump.events(es).prefix(400))",
                   repro: { "hex:" + hex(bytes) })
        case let .accept(canonical, dump):
            let mine = Dump.events(es)
            r.expect("events.encode", dump == mine, "Lean decodes another batch: \(firstDifference(mine, dump))",
                     repro: { "hex:" + hex(bytes) })
            r.expect("events.encode", canonical, "Lean re-encodes Swift's batch to other bytes: \(mine.prefix(400))",
                     repro: { "hex:" + hex(bytes) })
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "encodeEvents on " + Dump.events(batch(&g)).prefix(600)
    }
}

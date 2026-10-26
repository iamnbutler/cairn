// Event v2 encoder (docs/frame.md). Trusted: the corpus test checks it byte for byte against
// Lean's encoder and checks that Lean's decoder reads what it writes.

extension Event {
    /// Appends this event's record.
    public func encode(into out: inout [UInt8]) {
        func head(_ tag: UInt8, _ a: UInt8 = 0, _ b: UInt8 = 0) { out += [tag, a, b, 0] }
        func u32(_ v: UInt32) {
            out += [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
                    UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
        }
        func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        func point(_ p: Point) { i32(p.x); i32(p.y) }
        func str(_ s: String) {
            var s = s
            s.withUTF8 { u32(UInt32($0.count)); out.append(contentsOf: $0) }
        }
        func range(_ r: ScalarRange?) { u32(r?.start ?? 0); u32(r?.end ?? 0) }
        func u64(_ v: UInt64) { u32(UInt32(truncatingIfNeeded: v)); u32(UInt32(truncatingIfNeeded: v >> 32)) }
        func bytes(_ b: [UInt8]) { u32(UInt32(b.count)); out += b }
        func headers(_ hs: [Header]) { u32(UInt32(hs.count)); for h in hs { str(h.name); str(h.value) } }

        switch self {
        case let .pointerMove(p): head(0); point(p)
        case let .pointerDown(p, b, clicks, m): head(1, b.rawValue, m.code); point(p); u32(clicks)
        case let .pointerUp(p, b, m): head(2, b.rawValue, m.code); point(p)
        case .pointerExit: head(3)
        case let .scroll(p, dx, dy): head(4); point(p); i32(dx); i32(dy)
        case let .key(k, m): head(5, k.code, m.code); u32(k.scalar)
        case let .insertText(s, rep): head(6, rep == nil ? 0 : 1); range(rep); str(s)
        case let .setMarked(s, a, l, rep):
            head(7, rep == nil ? 0 : 1); range(rep); u32(a); u32(l); str(s)
        case .unmark: head(8)
        case .copy: head(9)
        case .cut: head(10)
        case .selectAll: head(11)
        case .undo: head(12)
        case .redo: head(13)
        case let .paste(s): head(14); str(s)
        case let .resize(sz): head(15); i32(sz.w); i32(sz.h)
        case let .scale(p): head(16); u32(p)
        case let .windowFocus(f): head(17, f ? 1 : 0)
        case let .clock(t): head(18); u64(t.mono); u64(UInt64(bitPattern: t.wall)); i32(t.zone)
        case let .reply(id, r):
            if case let .failed(f, _) = r { head(19, r.code, f.rawValue) } else { head(19, r.code) }
            u32(id)
            switch r {
            case .done: break
            case let .bytes(b): bytes(b)
            case let .http(st, hs, b): u32(st); headers(hs); bytes(b)
            case let .failed(_, m): str(m)
            case let .names(ns): u32(UInt32(ns.count)); for n in ns { str(n) }
            case let .app(pid, name): u32(pid); str(name)
            case let .flag(b): out += [b ? 1 : 0, 0, 0, 0]
            case let .image(w, h): u32(w); u32(h)
            }
        case let .subEvent(id, e):
            if case let .failed(f, _) = e { head(20, e.code, f.rawValue) } else { head(20, e.code) }
            u32(id)
            switch e {
            case .tick, .changed: break
            case let .audio(n, pk, ws):
                u32(n); u32(pk); u32(UInt32(ws.count))
                for w in ws { u64(w.sumSq); u32(w.peak) }
            case let .keyDown(t), let .keyUp(t), let .otherKey(t), let .started(t): u64(t)
            case let .failed(_, m): str(m)
            case let .evicted(s): str(s)
            }
        case let .surface(p, e): head(21); u32(p); e.encode(into: &out)
        case let .menuOpen(p): head(22); u32(p)
        case let .menuClose(p): head(23); u32(p)
        case let .menuSelect(p, r): head(24); u32(p); u32(r.claim); u32(r.key)
        }
    }
}

/// A batch of events: header, count, records.
public func encodeEvents(_ events: [Event]) -> [UInt8] {
    var out: [UInt8] = [0x43, 0x41, 0x45, 0x56, 2, 0, 0, 0]  // "CAEV", version 2, flags 0
    out.reserveCapacity(12 + 16 * events.count)
    let n = UInt32(events.count)
    out += [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
            UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
    for e in events { e.encode(into: &out) }
    return out
}

extension Mods {
    /// Bit 0 shift, 1 command, 2 option, 3 control.
    public var code: UInt8 {
        (shift ? 1 : 0) | (command ? 2 : 0) | (option ? 4 : 0) | (control ? 8 : 0)
    }
}

extension Key {
    public var code: UInt8 {
        switch self {
        case .enter: 0
        case .escape: 1
        case .tab: 2
        case .backspace: 3
        case .delete: 4
        case .left: 5
        case .right: 6
        case .up: 7
        case .down: 8
        case .home: 9
        case .finish: 10
        case .pageUp: 11
        case .pageDown: 12
        case .char: 13
        case .menu: 14
        }
    }

    /// The Unicode scalar of a `char` key. Lean's `Char` is one scalar, so a `Character` made
    /// of several (an emoji with a modifier) sends its first; shortcuts are single scalars.
    public var scalar: UInt32 {
        if case let .char(c) = self { return c.unicodeScalars.first!.value }
        return 0
    }
}

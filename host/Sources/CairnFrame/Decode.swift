#if canImport(Darwin)
import Darwin
#endif

// Frame v3 decoder (docs/frame.md). Trusted: checked against the corpus Lean generates
// (Tests/CairnFrameTests), not proved. Reads in place from the buffer: one bounds check per
// record's fixed part and one per string, unaligned little-endian loads, no intermediate copies.

public enum FrameDecodeError: Error, Equatable, Sendable {
    case badHeader
    /// The buffer ended inside the record or field at this offset.
    case truncated(at: Int)
    /// An unknown tag or code byte at this offset.
    case badCode(UInt8, at: Int)
    /// A string at this offset is not valid UTF-8.
    case badUTF8(at: Int)
    /// A section's records did not fill exactly its byte length.
    case sectionLength(at: Int)
    case trailingBytes(at: Int)
}

extension Frame {
    public init(bytes: [UInt8]) throws {
        self = try bytes.withUnsafeBytes { try Frame(decoding: $0) }
    }

    /// Header (magic, version 7, flags 0), surfaces, effects, subscription commands, wake.
    public init(decoding raw: UnsafeRawBufferPointer) throws {
        var r = ByteReader(raw)
        try r.need(8)
        guard r.u8(0) == 0x43, r.u8(1) == 0x41, r.u8(2) == 0x46, r.u8(3) == 0x52, r.u16(4) == 7,
              r.u16(6) == 0  // flags: reserved, zero (found by cairn-fuzz-trusted)
        else { throw FrameDecodeError.badHeader }
        r.i = 8
        let surfaces = try r.list { try Frame.decodeSurface(&$0) }
        let effects = try r.list { try Frame.decodeEffect(&$0) }
        let subs = try r.list { try Frame.decodeSubCmd(&$0) }
        try r.need(12)
        let hasWake = try r.flag(0)
        let wake = r.u64(4)
        r.i += 12
        guard r.i == raw.count else { throw FrameDecodeError.trailingBytes(at: r.i) }
        self.init(surfaces: surfaces, effects: effects, subs: subs, wake: hasWake ? wake : nil)
    }

    static func decodeSurface(_ r: inout ByteReader) throws -> Surface {
        try r.need(20)
        guard let kind = SurfaceKind(rawValue: r.u8(0)) else { throw FrameDecodeError.badCode(r.u8(0), at: r.i) }
        let shown = try r.flag(1)
        guard r.u8(2) == 0 else { throw FrameDecodeError.badCode(r.u8(2), at: r.i + 2) }
        guard let screen = ScreenChoice(rawValue: r.u8(3)) else { throw FrameDecodeError.badCode(r.u8(3), at: r.i + 3) }
        let place = r.u32(4)
        let anchor = Anchor.bottomCenter(offset: r.u32(8))
        let minSize = Size(w: r.i32(12), h: r.i32(16))
        r.i += 20
        let title = try r.string()
        let canvas = try decodeCanvas(&r)
        let status = try decodeStatus(&r)
        return Surface(kind: kind, place: place, shown: shown, title: title, anchor: anchor,
                       screen: screen, minSize: minSize, canvas: canvas, status: status)
    }

    /// Size, draws, accessibility nodes, text input, cursor.
    static func decodeCanvas(_ r: inout ByteReader) throws -> Canvas {
        try r.need(8)
        let size = Size(w: r.i32(0), h: r.i32(4))
        r.i += 8
        let draws = try r.list { try Frame.decodeDraw(&$0) }
        let ax = try r.list { try Frame.decodeAx(&$0) }
        let textInput = try decodeTextInput(&r)
        try r.need(4)
        guard let cursor = Cursor(rawValue: r.u8(0)) else { throw FrameDecodeError.badCode(r.u8(0), at: r.i) }
        r.i += 4
        return Canvas(size: size, draws: draws, ax: ax, textInput: textInput, cursor: cursor)
    }

    static func decodeStatus(_ r: inout ByteReader) throws -> StatusFrame {
        try r.need(8)
        let control = ControlRef(claim: r.u32(0), key: r.u32(4))
        r.i += 8
        let symbol = try r.string(), title = try r.string(), label = try r.string()
        let menu = try r.list { try Frame.decodeMenuRecord(&$0) }
        return StatusFrame(control: control, symbol: symbol, title: title, label: label, menu: menu)
    }

    /// 32 bytes, then the label. Fields a record doesn't have are ignored.
    static func decodeMenuRecord(_ r: inout ByteReader) throws -> MenuRecord {
        try r.need(32)
        guard let kind = MenuKind(rawValue: r.u8(0)) else { throw FrameDecodeError.badCode(r.u8(0), at: r.i) }
        let enabled = try r.flag(1)
        let checked = try r.checked(2)
        let hasShortcut = try r.flag(3), hasControl = try r.flag(4), hasParent = try r.flag(5)
        let hasPlace = try r.flag(6)
        let keyCode = r.u8(7)
        let control = ControlRef(claim: r.u32(8), key: r.u32(12))
        let parent = r.u32(16), place = r.u32(20), scalar = r.u32(24)
        let mods = r.u8(28)
        let at = r.i
        r.i += 32
        let label = try r.string()
        var shortcut: Shortcut?
        if hasShortcut {
            guard let k = Key(code: keyCode, scalar: scalar) else { throw FrameDecodeError.badCode(keyCode, at: at + 7) }
            guard let m = Mods(code: mods) else { throw FrameDecodeError.badCode(mods, at: at + 28) }
            shortcut = Shortcut(key: k, mods: m)
        }
        return MenuRecord(kind: kind, label: label, control: hasControl ? control : nil,
                          place: hasPlace ? place : nil, parent: hasParent ? Int(parent) : nil,
                          enabled: enabled, checked: checked, shortcut: shortcut)
    }

    static func decodeDraw(_ r: inout ByteReader) throws -> Draw {
        try r.need(4)
        let tag = r.u8(0)
        switch tag {
        case 0:
            try r.need(36)
            let hasFill = try r.flag(1), hasBorder = try r.flag(2)
            let rect = r.rect(4)
            let fill = r.color(20)
            let radius = r.u32(24)
            let border = Border(width: r.u32(28), color: r.color(32))
            r.i += 36
            return .rect(rect, fill: hasFill ? fill : nil, radius: radius, border: hasBorder ? border : nil)
        case 1:
            try r.need(32)
            let italic = try r.flag(1)
            guard let width = FontWidth(rawValue: r.u8(2)) else { throw FrameDecodeError.badCode(r.u8(2), at: r.i + 2) }
            let tabular = try r.flag(3)
            let origin = Point(x: r.i32(4), y: r.i32(8))
            let font = Font(family: r.u32(12), size: r.u32(16), weight: r.u32(20), italic: italic,
                            width: width, tracking: r.i32(24), tabular: tabular)
            let color = r.color(28)
            r.i += 32
            return .text(origin: origin, font: font, color: color, string: try r.string())
        case 2:
            try r.need(20)
            defer { r.i += 20 }
            return .pushClip(r.rect(4))
        case 3:
            r.i += 4
            return .popClip
        case 4:
            try r.need(28)
            let rect = r.rect(4)
            let origin = r.u64(20)
            r.i += 28
            let shader = try r.string()
            let scalars = try r.ints()
            try r.need(4)
            let n = Int(r.u32(0))
            r.i += 4
            var arrays: [[Int32]] = []
            for _ in 0..<n { arrays.append(try r.ints()) }
            return .paint(rect, Paint(shader: shader, origin: origin, scalars: scalars, arrays: arrays))
        case 5:
            try r.need(56)
            let hasFill = try r.flag(1), hasBorder = try r.flag(2), hasShadow = try r.flag(3)
            guard let corner = Corner(rawValue: r.u8(4)) else { throw FrameDecodeError.badCode(r.u8(4), at: r.i + 4) }
            let rect = r.rect(8)
            let fill = r.color(24)
            let radius = r.u32(28)
            let border = Border(width: r.u32(32), color: r.color(36))
            let shadow = Shadow(color: r.color(40), radius: r.u32(44), x: r.i32(48), y: r.i32(52))
            r.i += 56
            return .shape(rect, fill: hasFill ? fill : nil, radius: radius, border: hasBorder ? border : nil,
                          corner: corner, shadow: hasShadow ? shadow : nil)
        case 6:
            try r.need(36)
            let rect = r.rect(4), dest = r.rect(20)
            r.i += 36
            return .image(rect, dest: dest, source: try r.string())
        default:
            throw FrameDecodeError.badCode(tag, at: r.i)
        }
    }

    static func decodeAx(_ r: inout ByteReader) throws -> AxNode {
        try r.need(36)
        guard let role = Role(rawValue: r.u8(0)) else { throw FrameDecodeError.badCode(r.u8(0), at: r.i) }
        let focused = try r.flag(1), selected = try r.flag(2)
        let checked = try r.checked(3)
        let hasControl = try r.flag(4), hasParent = try r.flag(5)
        let control = ControlRef(claim: r.u32(8), key: r.u32(12))
        let parent = Int(r.u32(16))
        let rect = r.rect(20)
        r.i += 36
        let label = try r.string()
        let value = try r.string()
        return AxNode(control: hasControl ? control : nil, role: role, rect: rect, label: label,
                      value: value, parent: hasParent ? parent : nil, focused: focused,
                      selected: selected, checked: checked)
    }

    static func decodeTextInput(_ r: inout ByteReader) throws -> TextInput? {
        try r.need(4)
        switch r.u8(0) {
        case 0:
            r.i += 4
            return nil
        case 1:
            try r.need(68)
            let hasMarked = try r.flag(1)
            let control = ControlRef(claim: r.u32(4), key: r.u32(8))
            let rect = r.rect(12), caret = r.rect(28)
            let selection = (start: r.u32(44), end: r.u32(48))
            let marked = (start: r.u32(52), end: r.u32(56))
            let origin = Point(x: r.i32(60), y: r.i32(64))
            r.i += 68
            return TextInput(control: control, rect: rect, caret: caret, text: try r.string(),
                             selection: selection, marked: hasMarked ? marked : nil, textOrigin: origin)
        case let c:
            throw FrameDecodeError.badCode(c, at: r.i)
        }
    }

    static func decodeEffect(_ er: inout ByteReader) throws -> Effect {
        try er.need(4)
        switch er.u8(0) {
        case 0:
            er.i += 4
            return .setClipboard(try er.string())
        case 1:
            er.i += 4
            return .beep
        case 2:
            try er.need(12)
            defer { er.i += 12 }
            return .focus(ControlRef(claim: er.u32(4), key: er.u32(8)))
        case 3:
            try er.need(8)
            let ms = er.u32(4)
            er.i += 8
            return .setTimer(name: try er.string(), ms: ms)
        case 4:
            er.i += 4
            return .cancelTimer(try er.string())
        case 5:
            try er.need(8)
            let kind = er.u8(1), id = er.u32(4)
            let at = er.i + 1
            er.i += 8
            let req: Request
            switch kind {
            case 0: req = .readFile(path: try er.string())
            case 1:
                let path = try er.string()
                req = .writeFile(path: path, data: try er.bytes())
            case 2: req = .playSound(name: try er.string())
            case 3:
                try er.need(4)
                let timeout = er.u32(0)
                er.i += 4
                let method = try er.string()
                let url = try er.string()
                let headers = try er.headers()
                req = .http(method: method, url: url, headers: headers, body: try er.bytes(),
                            timeoutMs: timeout)
            case 4:
                let path = try er.string()
                req = .appendFile(path: path, data: try er.bytes())
            case 5: req = .listDir(path: try er.string())
            case 6: req = .deleteFile(path: try er.string())
            case 7: req = .frontmostApp
            case 8:
                try er.need(4)
                guard let p = Permission(rawValue: er.u8(0)) else {
                    throw FrameDecodeError.badCode(er.u8(0), at: er.i)
                }
                let prompt = try er.flag(1)
                er.i += 4
                req = .permission(p, prompt: prompt)
            case 9:
                try er.need(8)
                let pid = er.u32(0)
                let ret = try er.flag(4)
                er.i += 8
                req = .typeText(pid: pid, text: try er.string(), pressReturn: ret)
            case 10:
                try er.need(4)
                let timeout = er.u32(0)
                er.i += 4
                let method = try er.string()
                let url = try er.string()
                let headers = try er.headers()
                let secret = try er.secret()
                req = .upload(method: method, url: url, headers: headers, secret: secret,
                              body: try er.parts(), timeoutMs: timeout)
            case 11:
                try er.need(4)
                req = .forgetClip(clip: er.u32(0))
                er.i += 4
            case 12: req = .openItem(target: try er.string())
            case 13: req = .appRunning(bundleId: try er.string())
            case 14:
                let domain = try er.string()
                req = .readDefault(domain: domain, key: try er.string())
            case 15: req = .makeDir(path: try er.string())
            case 16:
                try er.need(4)
                let reload = try er.flag(0)
                er.i += 4
                req = .loadImage(source: try er.string(), reload: reload)
            default: throw FrameDecodeError.badCode(kind, at: at)
            }
            return .request(id: id, req)
        case 6:
            er.i += 4
            return .quit
        case 7:
            try er.need(8)
            defer { er.i += 8 }
            return .cancelRequest(id: er.u32(4))
        case let c:
            throw FrameDecodeError.badCode(c, at: er.i)
        }
    }

    static func decodeSubCmd(_ sr: inout ByteReader) throws -> SubCmd {
        try sr.need(4)
        switch sr.u8(0) {
        case 0:
            try sr.need(8)
            let kind = sr.u8(1), id = sr.u32(4)
            switch kind {
            case 0:
                try sr.need(12)
                defer { sr.i += 12 }
                return .start(id: id, .every(ms: sr.u32(8)))
            case 1:
                sr.i += 8
                return .start(id: id, .watchFile(path: try sr.string()))
            case 2:
                try sr.need(12)
                defer { sr.i += 12 }
                return .start(id: id, .record(clip: sr.u32(8)))
            case 3:
                try sr.need(20)
                let has = try sr.flag(12)
                defer { sr.i += 20 }
                return .start(id: id, .globalKey(code: sr.u32(8), modifier: has ? sr.u32(16) : nil))
            default: throw FrameDecodeError.badCode(kind, at: sr.i + 1)
            }
        case 1:
            try sr.need(8)
            defer { sr.i += 8 }
            return .stop(id: sr.u32(4))
        case let c:
            throw FrameDecodeError.badCode(c, at: sr.i)
        }
    }
}

extension Key {
    /// The inverse of `code` and `scalar` (`Key.ofCode`).
    public init?(code: UInt8, scalar: UInt32) {
        switch code {
        case 0: self = .enter
        case 1: self = .escape
        case 2: self = .tab
        case 3: self = .backspace
        case 4: self = .delete
        case 5: self = .left
        case 6: self = .right
        case 7: self = .up
        case 8: self = .down
        case 9: self = .home
        case 10: self = .finish
        case 11: self = .pageUp
        case 12: self = .pageDown
        case 13:
            guard let u = Unicode.Scalar(scalar) else { return nil }
            self = .char(Character(u))
        default: return nil
        }
    }
}

extension Mods {
    /// The inverse of `code` (`Mods.ofCode`).
    public init?(code: UInt8) {
        guard code < 16 else { return nil }
        self.init(shift: code & 1 != 0, command: code & 2 != 0, option: code & 4 != 0,
                  control: code & 8 != 0)
    }
}

/// A cursor over a byte range. `need(n)` checks that `n` bytes remain; the accessors after it
/// read at offsets from `i` without further checks.
struct ByteReader {
    let raw: UnsafeRawBufferPointer
    var i: Int
    let end: Int

    init(_ raw: UnsafeRawBufferPointer) { self.raw = raw; i = 0; end = raw.count }
    init(_ raw: UnsafeRawBufferPointer, _ range: Range<Int>) {
        self.raw = raw; i = range.lowerBound; end = range.upperBound
    }

    @inline(__always) func need(_ n: Int) throws {
        guard n <= end - i else { throw FrameDecodeError.truncated(at: i) }
    }
    @inline(__always) func u8(_ o: Int) -> UInt8 { raw[i + o] }
    @inline(__always) func u16(_ o: Int) -> UInt16 {
        UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: i + o, as: UInt16.self))
    }
    @inline(__always) func u32(_ o: Int) -> UInt32 {
        UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i + o, as: UInt32.self))
    }
    @inline(__always) func u64(_ o: Int) -> UInt64 {
        UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i + o, as: UInt64.self))
    }
    @inline(__always) func i32(_ o: Int) -> Int32 {
        Int32(littleEndian: raw.loadUnaligned(fromByteOffset: i + o, as: Int32.self))
    }
    @inline(__always) func rect(_ o: Int) -> Rect {
        Rect(x: i32(o), y: i32(o + 4), w: i32(o + 8), h: i32(o + 12))
    }
    @inline(__always) func color(_ o: Int) -> Color {
        Color(r: u8(o), g: u8(o + 1), b: u8(o + 2), a: u8(o + 3))
    }
    @inline(__always) func flag(_ o: Int) throws -> Bool {
        switch u8(o) {
        case 0: return false
        case 1: return true
        case let c: throw FrameDecodeError.badCode(c, at: i + o)
        }
    }

    /// `u32` byte length, then UTF-8.
    mutating func string() throws -> String {
        try need(4)
        let n = Int(u32(0))
        try need(4 + n)
        let start = i + 4
        i = start + n
        if n == 0 { return "" }
        // `String(decoding:)` is several times faster than `String(validating:)` but repairs
        // invalid input with U+FFFD; it is valid exactly when its bytes are the input's.
        let bytes = UnsafeRawBufferPointer(rebasing: raw[start..<start + n])
        var s = String(decoding: bytes, as: UTF8.self)
        let same = s.withUTF8 { $0.count == n && memcmp($0.baseAddress!, bytes.baseAddress!, n) == 0 }
        guard same else { throw FrameDecodeError.badUTF8(at: start - 4) }
        return s
    }

    /// `u32` byte length, then the bytes.
    mutating func bytes() throws -> [UInt8] {
        try need(4)
        let n = Int(u32(0))
        try need(4 + n)
        let start = i + 4
        i = start + n
        return Array(raw[start..<start + n])
    }

    /// `u32` count, then that many `i32`s.
    mutating func ints() throws -> [Int32] {
        try need(4)
        let n = Int(u32(0))
        try need(4 + 4 * n)
        i += 4
        var out: [Int32] = []
        out.reserveCapacity(n)
        for k in 0..<n { out.append(i32(4 * k)) }
        i += 4 * n
        return out
    }

    /// `u32` count, then each name and value.
    mutating func headers() throws -> [Header] {
        try need(4)
        let n = Int(u32(0))
        i += 4
        var out: [Header] = []
        for _ in 0..<n {
            let name = try string()
            out.append(Header(name, try string()))
        }
        return out
    }

    /// `[0, 0, 0, 0]`, or `[1, 0, 0, 0]` and four strings (`Dec.optSecret`; padding unchecked).
    mutating func secret() throws -> Secret? {
        try need(4)
        switch u8(0) {
        case 0:
            i += 4
            return nil
        case 1:
            i += 4
            let h = try string(), s = try string(), f = try string()
            return Secret(header: h, scheme: s, file: f, name: try string())
        case let c: throw FrameDecodeError.badCode(c, at: i)
        }
    }

    /// `u32` count, then each part (`Dec.parts`).
    mutating func parts() throws -> [Part] {
        try need(4)
        let n = Int(u32(0))
        i += 4
        var out: [Part] = []
        for _ in 0..<n {
            try need(4)
            switch u8(0) {
            case 0:
                i += 4
                out.append(.bytes(try bytes()))
            case 1:
                try need(16)
                let has = try flag(1)
                out.append(.wav(clip: u32(4), start: u32(8), stop: has ? u32(12) : nil))
                i += 16
            case let c: throw FrameDecodeError.badCode(c, at: i)
            }
        }
        return out
    }

    /// `u32` count, `u32` byte length: the count and the body's range; moves past the body.
    mutating func section() throws -> (Int, Range<Int>) {
        try need(8)
        let count = Int(u32(0)), len = Int(u32(4))
        i += 8
        try need(len)
        defer { i += len }
        return (count, i..<i + len)
    }

    /// `u32` count, then the records as a sized section, each read by `item`, which must fill it.
    mutating func list<T>(_ item: (inout ByteReader) throws -> T) throws -> [T] {
        let (count, range) = try section()
        var sr = ByteReader(raw, range)
        var out: [T] = []
        out.reserveCapacity(Swift.min(count, range.count))
        for _ in 0..<count { out.append(try item(&sr)) }
        try sr.finish(section: range)
        return out
    }

    /// A checkmark code: 0 none, 1 off, 2 on.
    @inline(__always) func checked(_ o: Int) throws -> Bool? {
        switch u8(o) {
        case 0: return nil
        case 1: return false
        case 2: return true
        case let c: throw FrameDecodeError.badCode(c, at: i + o)
        }
    }

    func finish(section: Range<Int>) throws {
        guard i == section.upperBound else { throw FrameDecodeError.sectionLength(at: section.lowerBound) }
    }
}

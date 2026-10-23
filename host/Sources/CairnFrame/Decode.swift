#if canImport(Darwin)
import Darwin
#endif

// Frame v2 decoder (docs/frame.md). Trusted: checked against the corpus Lean generates
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

/// Where each section of a frame sits in its buffer. Finding them reads only the header and
/// the section lengths, so the render thread can decode just the draws and the main thread
/// just the accessibility nodes and text input.
public struct FrameSections: Sendable {
    public var size: Size
    public var drawCount: Int
    public var draws: Range<Int>
    public var axCount: Int
    public var ax: Range<Int>
    /// Text input, cursor, effects, subscription commands and wake.
    public var tail: Range<Int>

    public init(_ raw: UnsafeRawBufferPointer) throws {
        var r = ByteReader(raw)
        try r.need(16)
        guard r.u8(0) == 0x43, r.u8(1) == 0x41, r.u8(2) == 0x46, r.u8(3) == 0x52, r.u16(4) == 2,
              r.u16(6) == 0  // flags: reserved, zero (found by cairn-fuzz-trusted)
        else { throw FrameDecodeError.badHeader }
        size = Size(w: r.i32(8), h: r.i32(12))
        r.i = 16
        (drawCount, draws) = try r.section()
        (axCount, ax) = try r.section()
        tail = r.i..<raw.count
    }
}

extension Frame {
    public init(bytes: [UInt8]) throws {
        self = try bytes.withUnsafeBytes { try Frame(decoding: $0) }
    }

    public init(decoding raw: UnsafeRawBufferPointer) throws {
        let s = try FrameSections(raw)
        let draws = try Frame.decodeDraws(raw, s)
        let ax = try Frame.decodeAx(raw, s)
        let t = try Frame.decodeTail(raw, s)
        self.init(size: s.size, draws: draws, ax: ax, textInput: t.textInput, cursor: t.cursor,
                  effects: t.effects, subs: t.subs, wake: t.wake)
    }

    public static func decodeDraws(_ raw: UnsafeRawBufferPointer, _ s: FrameSections) throws -> [Draw] {
        var r = ByteReader(raw, s.draws)
        var out: [Draw] = []
        out.reserveCapacity(s.drawCount)
        for _ in 0..<s.drawCount {
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
                out.append(.rect(rect, fill: hasFill ? fill : nil, radius: radius,
                                 border: hasBorder ? border : nil))
                r.i += 36
            case 1:
                try r.need(28)
                let italic = try r.flag(1)
                let origin = Point(x: r.i32(4), y: r.i32(8))
                let font = Font(family: r.u32(12), size: r.u32(16), weight: r.u32(20), italic: italic)
                let color = r.color(24)
                r.i += 28
                out.append(.text(origin: origin, font: font, color: color, string: try r.string()))
            case 2:
                try r.need(20)
                out.append(.pushClip(r.rect(4)))
                r.i += 20
            case 3:
                out.append(.popClip)
                r.i += 4
            default:
                throw FrameDecodeError.badCode(tag, at: r.i)
            }
        }
        try r.finish(section: s.draws)
        return out
    }

    public static func decodeAx(_ raw: UnsafeRawBufferPointer, _ s: FrameSections) throws -> [AxNode] {
        var r = ByteReader(raw, s.ax)
        var out: [AxNode] = []
        out.reserveCapacity(s.axCount)
        for _ in 0..<s.axCount {
            try r.need(36)
            guard let role = Role(rawValue: r.u8(0)) else { throw FrameDecodeError.badCode(r.u8(0), at: r.i) }
            let focused = try r.flag(1), selected = try r.flag(2)
            let checked: Bool?
            switch r.u8(3) {
            case 0: checked = nil
            case 1: checked = false
            case 2: checked = true
            case let c: throw FrameDecodeError.badCode(c, at: r.i + 3)
            }
            let hasControl = try r.flag(4), hasParent = try r.flag(5)
            let control = ControlRef(claim: r.u32(8), key: r.u32(12))
            let parent = Int(r.u32(16))
            let rect = r.rect(20)
            r.i += 36
            let label = try r.string()
            let value = try r.string()
            out.append(AxNode(control: hasControl ? control : nil, role: role, rect: rect,
                              label: label, value: value, parent: hasParent ? parent : nil,
                              focused: focused, selected: selected, checked: checked))
        }
        try r.finish(section: s.ax)
        return out
    }

    public static func decodeTail(_ raw: UnsafeRawBufferPointer, _ s: FrameSections) throws
        -> (textInput: TextInput?, cursor: Cursor, effects: [Effect], subs: [SubCmd], wake: UInt64?)
    {
        var r = ByteReader(raw, s.tail)
        try r.need(4)
        var textInput: TextInput?
        switch r.u8(0) {
        case 0:
            r.i += 4
        case 1:
            try r.need(68)
            let hasMarked = try r.flag(1)
            let control = ControlRef(claim: r.u32(4), key: r.u32(8))
            let rect = r.rect(12), caret = r.rect(28)
            let selection = (start: r.u32(44), end: r.u32(48))
            let marked = (start: r.u32(52), end: r.u32(56))
            let origin = Point(x: r.i32(60), y: r.i32(64))
            r.i += 68
            textInput = TextInput(control: control, rect: rect, caret: caret, text: try r.string(),
                                  selection: selection, marked: hasMarked ? marked : nil,
                                  textOrigin: origin)
        case let c:
            throw FrameDecodeError.badCode(c, at: r.i)
        }
        try r.need(4)
        guard let cursor = Cursor(rawValue: r.u8(0)) else { throw FrameDecodeError.badCode(r.u8(0), at: r.i) }
        r.i += 4
        let (count, range) = try r.section()
        var er = ByteReader(raw, range)
        var effects: [Effect] = []
        effects.reserveCapacity(count)
        for _ in 0..<count {
            try er.need(4)
            switch er.u8(0) {
            case 0:
                er.i += 4
                effects.append(.setClipboard(try er.string()))
            case 1:
                er.i += 4
                effects.append(.beep)
            case 2:
                try er.need(12)
                effects.append(.focus(ControlRef(claim: er.u32(4), key: er.u32(8))))
                er.i += 12
            case 3:
                try er.need(8)
                let ms = er.u32(4)
                er.i += 8
                effects.append(.setTimer(name: try er.string(), ms: ms))
            case 4:
                er.i += 4
                effects.append(.cancelTimer(try er.string()))
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
                default: throw FrameDecodeError.badCode(kind, at: at)
                }
                effects.append(.request(id: id, req))
            case 6:
                er.i += 4
                effects.append(.quit)
            case let c:
                throw FrameDecodeError.badCode(c, at: er.i)
            }
        }
        try er.finish(section: range)
        let (subCount, subRange) = try r.section()
        var sr = ByteReader(raw, subRange)
        var subs: [SubCmd] = []
        for _ in 0..<subCount {
            try sr.need(4)
            switch sr.u8(0) {
            case 0:
                try sr.need(8)
                let kind = sr.u8(1), id = sr.u32(4)
                switch kind {
                case 0:
                    try sr.need(12)
                    subs.append(.start(id: id, .every(ms: sr.u32(8))))
                    sr.i += 12
                case 1:
                    sr.i += 8
                    subs.append(.start(id: id, .watchFile(path: try sr.string())))
                case 2:
                    try sr.need(12)
                    subs.append(.start(id: id, .record(clip: sr.u32(8))))
                    sr.i += 12
                case 3:
                    try sr.need(20)
                    let has = try sr.flag(12)
                    subs.append(.start(id: id, .globalKey(code: sr.u32(8), modifier: has ? sr.u32(16) : nil)))
                    sr.i += 20
                default: throw FrameDecodeError.badCode(kind, at: sr.i + 1)
                }
            case 1:
                try sr.need(8)
                subs.append(.stop(id: sr.u32(4)))
                sr.i += 8
            case let c:
                throw FrameDecodeError.badCode(c, at: sr.i)
            }
        }
        try sr.finish(section: subRange)
        try r.need(12)
        let hasWake = try r.flag(0)
        let wake = r.u64(4)
        r.i += 12
        guard r.i == raw.count else { throw FrameDecodeError.trailingBytes(at: r.i) }
        return (textInput, cursor, effects, subs, hasWake ? wake : nil)
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

    func finish(section: Range<Int>) throws {
        guard i == section.upperBound else { throw FrameDecodeError.sectionLength(at: section.lowerBound) }
    }
}

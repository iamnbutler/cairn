import Foundation

/// A decoded frame v0 (see lean/Cairn/Spike/Frame.lean `encode`).
struct Frame {
    struct Quad {
        var x, y, w, h: Int32
        var rgba: UInt32
        var radius: UInt16
    }
    struct Node {
        var claim: UInt32
        var role: UInt8
        var x, y, w, h: Int32
        var label: String
        var center: (Int32, Int32) { (x + w / 2, y + h / 2) }
    }

    var width: Int32 = 0
    var height: Int32 = 0
    var quads: [Quad] = []
    var nodes: [Node] = []

    enum DecodeError: Error { case badMagic, truncated }

    init(bytes: Data) throws {
        self = try bytes.withUnsafeBytes { try Frame(raw: $0) }
    }

    private init(raw: UnsafeRawBufferPointer) throws {
        var r = Reader(raw: raw)
        guard Array(try r.bytes(4)) == [0x43, 0x41, 0x46, 0x52] else { throw DecodeError.badMagic }
        _ = try r.u16()  // version
        _ = try r.u16()
        width = try r.i32()
        height = try r.i32()
        let nq = try r.u32()
        let nn = try r.u32()
        quads.reserveCapacity(Int(nq))
        for _ in 0..<nq {
            let x = try r.i32(), y = try r.i32(), w = try r.i32(), h = try r.i32()
            let c = try r.u32()
            let rad = try r.u16()
            _ = try r.u16()
            quads.append(Quad(x: x, y: y, w: w, h: h, rgba: c, radius: rad))
        }
        nodes.reserveCapacity(Int(nn))
        for _ in 0..<nn {
            let claim = try r.u32()
            let role = try r.u8()
            _ = try r.bytes(3)
            let x = try r.i32(), y = try r.i32(), w = try r.i32(), h = try r.i32()
            let len = Int(try r.u16())
            let label = String(decoding: try r.bytes(len), as: UTF8.self)
            nodes.append(Node(claim: claim, role: role, x: x, y: y, w: w, h: h, label: label))
        }
    }
}

struct Reader {
    let raw: UnsafeRawBufferPointer
    var i = 0

    private mutating func take<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let n = MemoryLayout<T>.size
        guard i + n <= raw.count else { throw Frame.DecodeError.truncated }
        defer { i += n }
        return T(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: T.self))
    }
    mutating func bytes(_ n: Int) throws -> UnsafeRawBufferPointer {
        guard i + n <= raw.count else { throw Frame.DecodeError.truncated }
        defer { i += n }
        return UnsafeRawBufferPointer(rebasing: raw[i ..< i + n])
    }
    mutating func u8() throws -> UInt8 { try take(UInt8.self) }
    mutating func u16() throws -> UInt16 { try take(UInt16.self) }
    mutating func u32() throws -> UInt32 { try take(UInt32.self) }
    mutating func i32() throws -> Int32 { try take(Int32.self) }
}

/// Events v0: tag, then two little-endian i32s.
enum Event {
    case down(Int32, Int32), up(Int32, Int32), resize(Int32, Int32)

    func append(to out: inout [UInt8]) {
        let (tag, a, b): (UInt8, Int32, Int32) = switch self {
        case let .down(x, y): (1, x, y)
        case let .up(x, y): (2, x, y)
        case let .resize(w, h): (3, w, h)
        }
        out.append(tag)
        for v in [a, b] {
            let u = UInt32(bitPattern: v)
            out += [UInt8(u & 0xff), UInt8(u >> 8 & 0xff), UInt8(u >> 16 & 0xff), UInt8(u >> 24)]
        }
    }
}

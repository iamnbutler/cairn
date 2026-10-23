import CairnFrame
import Foundation

/// The boundary spike's byte format (frame v0, `lean/Cairn/Spike/Frame.lean`), adapted to the
/// v1 model so the host can run the spike's Counter until it moves to v1 (workstreams C and E).
///
/// v0 carries quads and accessibility nodes only. Labels exist only on nodes, so this adapter
/// paints each node's label as text; v1 frames carry their own text draws. Events v0 are
/// pointer down, pointer up and resize; everything else is dropped.
public struct SpikeV0Codec: BoundaryCodec {
    public init() {}

    public func encode(_ events: [Event]) -> [UInt8] {
        var out: [UInt8] = []
        for e in events {
            let (tag, a, b): (UInt8, Int32, Int32)
            switch e {
            case let .pointerDown(p, .primary, _, _): (tag, a, b) = (1, p.x, p.y)
            case let .pointerUp(p, .primary, _): (tag, a, b) = (2, p.x, p.y)
            case let .resize(s): (tag, a, b) = (3, s.w, s.h)
            default: continue
            }
            out.append(tag)
            for v in [a, b] { withUnsafeBytes(of: v.littleEndian) { out += $0 } }
        }
        return out
    }

    public func decodeFrame(_ raw: UnsafeRawBufferPointer) throws -> Frame {
        var r = ByteReader(raw)
        guard try Array(r.bytes(4)) == [0x43, 0x41, 0x46, 0x52] else { throw CodecError.badMagic }
        _ = try r.u16()  // version
        _ = try r.u16()
        let size = Size(w: try r.i32(), h: try r.i32())
        let nq = try r.u32(), nn = try r.u32()
        var draws: [Draw] = []
        draws.reserveCapacity(Int(nq + nn))
        for _ in 0..<nq {
            let rect = Rect(x: try r.i32(), y: try r.i32(), w: try r.i32(), h: try r.i32())
            let c = try r.u32()
            let radius = try r.u16()
            _ = try r.u16()
            let color = Color(r: UInt8(c >> 24), g: UInt8(c >> 16 & 0xff), b: UInt8(c >> 8 & 0xff), a: UInt8(c & 0xff))
            draws.append(.rect(rect, fill: color, radius: UInt32(radius), border: nil))
        }
        var ax: [AxNode] = []
        ax.reserveCapacity(Int(nn))
        let font = Font(family: 0, size: 15, weight: 500, italic: false)
        for _ in 0..<nn {
            let claim = try r.u32()
            let role = try r.u8()
            _ = try r.bytes(3)
            let rect = Rect(x: try r.i32(), y: try r.i32(), w: try r.i32(), h: try r.i32())
            let len = Int(try r.u16())
            let label = String(decoding: try r.bytes(len), as: UTF8.self)
            let button = role == 1
            ax.append(AxNode(control: claim == 0 ? nil : ControlRef(claim: claim, key: 0),
                             role: button ? .button : .text, rect: rect, label: label))
            // v0 has no text draws: buttons get a white label inside, other nodes one beside.
            let origin = button ? Point(x: rect.x + 14, y: rect.y + rect.h / 2 + 5)
                                : Point(x: rect.x + rect.w + 10, y: rect.y + rect.h / 2 + 5)
            let color = button ? Color(r: 255, g: 255, b: 255, a: 255) : Color(r: 30, g: 30, b: 30, a: 255)
            draws.append(.text(origin: origin, font: font, color: color, string: label))
        }
        let cursor: Cursor = .arrow
        return Frame(size: size, draws: draws, ax: ax, textInput: nil, cursor: cursor, effects: [])
    }
}

/// Little-endian reads over a byte buffer, without copying.
struct ByteReader {
    let raw: UnsafeRawBufferPointer
    var i = 0

    init(_ raw: UnsafeRawBufferPointer) { self.raw = raw }

    private mutating func take<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let n = MemoryLayout<T>.size
        guard i + n <= raw.count else { throw CodecError.truncated }
        defer { i += n }
        return T(littleEndian: raw.loadUnaligned(fromByteOffset: i, as: T.self))
    }
    mutating func bytes(_ n: Int) throws -> UnsafeRawBufferPointer {
        guard i + n <= raw.count else { throw CodecError.truncated }
        defer { i += n }
        return UnsafeRawBufferPointer(rebasing: raw[i ..< i + n])
    }
    mutating func u8() throws -> UInt8 { try take(UInt8.self) }
    mutating func u16() throws -> UInt16 { try take(UInt16.self) }
    mutating func u32() throws -> UInt32 { try take(UInt32.self) }
    mutating func i32() throws -> Int32 { try take(Int32.self) }
}

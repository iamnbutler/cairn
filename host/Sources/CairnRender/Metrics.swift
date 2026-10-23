import CairnFrame
import Foundation

/// The text metrics Lean lays out with, as a C function (see docs/render.md, "Metrics ABI").
///
///     int32_t cairn_text_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
///                                const uint8_t *utf8, size_t len, int32_t *out, size_t cap);
///
/// Writes `[ascent, descent, offset_0, …, offset_n]` (n = Unicode scalars in the string) to `out`,
/// at most `cap` values, and returns how many the full result has (`n + 3`). Lengths are whole
/// logical points. Invalid UTF-8 is repaired with U+FFFD before shaping. Thread-safe.
@_cdecl("cairn_text_metrics")
public func cairn_text_metrics(
    _ family: UInt32, _ size: UInt32, _ weight: UInt32, _ italic: UInt8,
    _ utf8: UnsafePointer<UInt8>?, _ len: Int, _ out: UnsafeMutablePointer<Int32>?, _ cap: Int
) -> Int32 {
    let bytes = UnsafeBufferPointer(start: len > 0 ? utf8 : nil, count: utf8 == nil ? 0 : len)
    let string = String(decoding: bytes, as: UTF8.self)
    let font = Font(family: family, size: size, weight: weight, italic: italic != 0)
    let line = TextSystem.shared.shape(font, string)
    let total = line.offsets.count + 2
    if let out, cap > 0 {
        let values = [line.ascent, line.descent] + line.offsets
        for i in 0..<min(cap, total) { out[i] = values[i] }
    }
    return Int32(clamping: total)
}

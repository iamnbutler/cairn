import Foundation

/// Converts between Lean's text positions (Unicode scalar indices, `Nat` in Lean) and AppKit's
/// (UTF-16 code unit offsets, `NSRange`). A scalar outside the BMP is one Lean index and two
/// UTF-16 units; everything else is one of each.
///
/// AppKit can name a UTF-16 offset that falls between the two halves of a surrogate pair. Such
/// an offset has no scalar index; `scalarIndex` rounds it down or up as asked, so a range never
/// splits a scalar.
public struct TextIndex: Sendable {
    /// `starts[i]` is the UTF-16 offset of scalar `i`; the last entry is the total UTF-16 length.
    private let starts: [Int]

    public init(_ s: String) {
        var starts: [Int] = []
        starts.reserveCapacity(s.unicodeScalars.count + 1)
        var u = 0
        for scalar in s.unicodeScalars {
            starts.append(u)
            u += scalar.utf16.count
        }
        starts.append(u)
        self.starts = starts
    }

    public var scalarCount: Int { starts.count - 1 }
    public var utf16Count: Int { starts[starts.count - 1] }

    /// The UTF-16 offset of scalar index `i`, clamped to the string.
    public func utf16(_ i: Int) -> Int { starts[min(max(i, 0), scalarCount)] }

    public enum Rounding: Sendable { case down, up }

    /// The scalar index at UTF-16 offset `u`, clamped to the string. An offset inside a
    /// surrogate pair rounds to the scalar's start (`down`) or end (`up`).
    public func scalar(_ u: Int, rounding: Rounding = .down) -> Int {
        if u <= 0 { return 0 }
        if u >= utf16Count { return scalarCount }
        // Largest i with starts[i] <= u.
        var lo = 0, hi = scalarCount
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= u { lo = mid } else { hi = mid - 1 }
        }
        if starts[lo] == u || rounding == .down { return lo }
        return lo + 1
    }

    /// The UTF-16 range of scalar range `[a, b)` (either order).
    public func nsRange(scalars a: Int, _ b: Int) -> NSRange {
        let lo = utf16(min(a, b)), hi = utf16(max(a, b))
        return NSRange(location: lo, length: hi - lo)
    }

    /// The scalar range for an AppKit range: the one conversion every NSTextInputClient and
    /// accessibility range goes through. Input methods send nonsense (native Pinyin sends
    /// out-of-bounds and mid-surrogate offsets), so it is defensive:
    /// - `NSNotFound` or a negative location is no range (nil);
    /// - the location and length are clamped to the string, without overflowing;
    /// - an end inside a surrogate pair widens to the whole scalar, a start narrows to it, and
    ///   an empty range stays empty (a caret inside a pair snaps to before it).
    public func scalars(_ r: NSRange) -> Range<Int>? {
        guard r.location != NSNotFound, r.location >= 0 else { return nil }
        let loU = min(r.location, utf16Count)
        let len = max(0, r.length)
        let hiU = len > utf16Count - loU ? utf16Count : loU + len
        let lo = scalar(loU, rounding: .down)
        if hiU == loU { return lo..<lo }
        return lo..<max(lo, scalar(hiU, rounding: .up))
    }
}

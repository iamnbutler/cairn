import CairnHost
import Foundation

/// `TextIndex` (UTF-16 offsets ↔ Lean's scalar indices) against an oracle built from Swift's own
/// string views, on text full of surrogate pairs, clusters and edge scalars, with AppKit-style
/// ranges: `NSNotFound`, negative, past the end, `Int.max` lengths, and ends inside a pair.
final class TextIndexSuite: Suite {
    let name = "textindex"
    let crashCheck = "text.index"
    let checks: [String: CheckInfo] = [
        "text.index": CheckInfo(
            title: "UTF-16 and scalar indices convert exactly, and AppKit ranges clamp to whole scalars",
            trusted: ["host/Sources/CairnHost/TextIndex.swift"],
            oracle: "Swift's String.UnicodeScalarView and UTF16View, and NSString"),
    ]

    func cases(for n: Int) -> Int { n }
    func setUp() {}

    func text(_ g: inout SplitMix) -> String {
        g.chance(1, 8) ? TextPool.string(&g, maxParts: 60) : TextPool.string(&g)
    }

    /// An offset AppKit might send: in range, at the edges, inside a pair, or nonsense.
    func offset(_ g: inout SplitMix, _ count: Int) -> Int {
        g.weighted([
            (6, { $0.range(0, count) }),
            (1, { $0.elem([0, count, count + 1, -1, Int.max, Int.min, NSNotFound, Int.max - 1]) }),
            (1, { $0.range(count, count + 5) }),
        ])
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let s = text(&g)
        let ix = TextIndex(s)
        let scalars = Array(s.unicodeScalars)
        // The oracle: UTF-16 offset of each scalar boundary.
        var starts = [0]
        for u in scalars { starts.append(starts.last! + u.utf16.count) }
        let n = scalars.count, u16 = s.utf16.count
        let check = "text.index"
        let show = { "in \(Dump.str(s))" }

        r.expect(check, ix.scalarCount == n && ix.utf16Count == u16, "counts \(ix.scalarCount)/\(ix.utf16Count), want \(n)/\(u16) \(show())")
        for i in [-1, 0, n, n + 1, g.range(0, n)] {
            let want = starts[min(max(i, 0), n)]
            r.expect(check, ix.utf16(i) == want, "utf16(\(i)) = \(ix.utf16(i)), want \(want) \(show())")
            if (0...n).contains(i) {
                r.expect(check, ix.scalar(starts[i], rounding: .down) == i && ix.scalar(starts[i], rounding: .up) == i,
                         "scalar(utf16(\(i))) is not \(i) \(show())")
            }
        }
        // Any offset: `down` is the last boundary at or before it, `up` the first at or after.
        for _ in 0..<4 {
            let u = offset(&g, u16)
            let c = min(max(u, 0), u16)
            let down = starts.lastIndex { $0 <= c }!, up = starts.firstIndex { $0 >= c }!
            r.expect(check, ix.scalar(u, rounding: .down) == down, "scalar(\(u), down) = \(ix.scalar(u, rounding: .down)), want \(down) \(show())")
            r.expect(check, ix.scalar(u, rounding: .up) == up, "scalar(\(u), up) = \(ix.scalar(u, rounding: .up)), want \(up) \(show())")
        }
        // Scalar ranges to NSRange and back; the substring is the scalars.
        let a = g.range(0, n), b = g.range(0, n)
        let ns = ix.nsRange(scalars: a, b)
        let lo = min(a, b), hi = max(a, b)
        r.expect(check, ns.location == starts[lo] && ns.length == starts[hi] - starts[lo], "nsRange(\(a), \(b)) = \(ns) \(show())")
        r.expect(check, ix.scalars(ns) == lo..<hi, "scalars(nsRange(\(a), \(b))) = \(String(describing: ix.scalars(ns))) \(show())")
        var sub = String.UnicodeScalarView(); sub.append(contentsOf: scalars[lo..<hi])
        r.expect(check, (s as NSString).substring(with: ns) == String(sub), "substring of nsRange(\(a), \(b)) \(show())")
        // AppKit ranges: nil for NSNotFound or negative; otherwise clamped, whole scalars, the
        // end widened and the start narrowed, empty stays empty.
        for _ in 0..<4 {
            let loc = offset(&g, u16)
            let len: Int = g.weighted([(5, { $0.range(0, u16 + 2) }), (1, { $0.elem([0, -1, Int.max, Int.min, NSNotFound]) })])
            let nr = NSRange(location: loc, length: len)
            let got = ix.scalars(nr)
            let desc = "scalars(\(loc), \(len)) = \(String(describing: got))"
            if loc == NSNotFound || loc < 0 {
                r.expect(check, got == nil, "\(desc), want nil \(show())")
                continue
            }
            guard let got else { r.fail(check, "\(desc), want a range \(show())"); continue }
            let cl = min(loc, u16)
            let ch = len <= 0 ? cl : (len > u16 - cl ? u16 : cl + len)
            let wantLo = starts.lastIndex { $0 <= cl }!
            let wantHi = ch == cl ? wantLo : max(wantLo, starts.firstIndex { $0 >= ch }!)
            r.expect(check, got == wantLo..<wantHi, "\(desc), want \(wantLo)..<\(wantHi) \(show())")
            r.count(check, starts.contains(cl) && starts.contains(ch) ? "rangesOnBoundaries" : "rangesSplittingPairs")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "TextIndex on \(Dump.str(text(&g)))"
    }
}

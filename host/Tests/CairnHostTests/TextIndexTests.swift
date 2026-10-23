import Foundation
import Testing
@testable import CairnHost

// "a😀b": scalars a(0) 😀(1) b(2); UTF-16 a(0) 😀(1,2) b(3).
@Suite struct TextIndexTests {
    let ix = TextIndex("a😀b")

    @Test func counts() {
        #expect(ix.scalarCount == 3)
        #expect(ix.utf16Count == 4)
        #expect(TextIndex("").scalarCount == 0)
        #expect(TextIndex("").utf16Count == 0)
    }

    @Test func scalarToUTF16() {
        #expect((0...3).map(ix.utf16) == [0, 1, 3, 4])
        #expect(ix.utf16(-5) == 0)
        #expect(ix.utf16(99) == 4)
    }

    @Test func utf16ToScalar() {
        #expect(ix.scalar(0) == 0)
        #expect(ix.scalar(1) == 1)
        #expect(ix.scalar(2, rounding: .down) == 1)  // inside the pair
        #expect(ix.scalar(2, rounding: .up) == 2)
        #expect(ix.scalar(3) == 2)
        #expect(ix.scalar(4) == 3)
        #expect(ix.scalar(-1) == 0)
        #expect(ix.scalar(100) == 3)
    }

    @Test func roundTrip() {
        let s = "héllo 👋🏽 世界 \u{1F1E8}\u{1F1E6}"
        let t = TextIndex(s)
        for i in 0...t.scalarCount { #expect(t.scalar(t.utf16(i)) == i) }
        #expect(t.utf16Count == s.utf16.count)
        #expect(t.scalarCount == s.unicodeScalars.count)
    }

    @Test func nsRange() {
        #expect(ix.nsRange(scalars: 1, 2) == NSRange(location: 1, length: 2))
        #expect(ix.nsRange(scalars: 3, 0) == NSRange(location: 0, length: 4))
    }

    @Test func scalarsPlain() {
        #expect(ix.scalars(NSRange(location: 0, length: 4)) == 0..<3)
        #expect(ix.scalars(NSRange(location: 1, length: 2)) == 1..<2)
        #expect(ix.scalars(NSRange(location: 3, length: 0)) == 2..<2)
    }

    @Test func scalarsNotFound() {
        #expect(ix.scalars(NSRange(location: NSNotFound, length: 0)) == nil)
        #expect(ix.scalars(NSRange(location: -1, length: 2)) == nil)
    }

    @Test func scalarsClamp() {
        #expect(ix.scalars(NSRange(location: 2, length: 50)) == 1..<3)
        #expect(ix.scalars(NSRange(location: 40, length: 2)) == 3..<3)
        #expect(ix.scalars(NSRange(location: 0, length: Int.max)) == 0..<3)  // no overflow
        #expect(ix.scalars(NSRange(location: 1, length: -3)) == 1..<1)
    }

    // Pinyin sends ranges that split a surrogate pair at either end.
    @Test func scalarsSurrogateSplit() {
        #expect(ix.scalars(NSRange(location: 2, length: 1)) == 1..<2)  // starts mid-pair: widen down
        #expect(ix.scalars(NSRange(location: 0, length: 2)) == 0..<2)  // ends mid-pair: widen up
        #expect(ix.scalars(NSRange(location: 2, length: 0)) == 1..<1)  // caret mid-pair snaps before
        #expect(ix.scalars(NSRange(location: 2, length: 2)) == 1..<3)
    }
}

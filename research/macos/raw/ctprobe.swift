import CoreText
import Foundation
func probe(_ s: String, _ fontName: String = ".AppleSystemUIFont", size: CGFloat = 13) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let line = CTLineCreateWithAttributedString(attr)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    var out: [String] = []
    var u16 = 0
    for sc in s.unicodeScalars {
        var sec: CGFloat = 0
        let o = CTLineGetOffsetForStringIndex(line, u16, &sec)
        out.append(String(format: "u16=%d U+%04X %.2f/%.2f", u16, sc.value, o, sec))
        u16 += sc.utf16.count
    }
    var sec: CGFloat = 0
    let o = CTLineGetOffsetForStringIndex(line, u16, &sec)
    out.append(String(format: "end u16=%d %.2f/%.2f", u16, o, sec))
    // odd index inside surrogate pair
    if s.utf16.count > s.unicodeScalars.count {
        var sec2: CGFloat = 0
        var idx = 0; for sc in s.unicodeScalars { if sc.utf16.count == 2 { idx += 1; break }; idx += sc.utf16.count }
        out.append(String(format: "mid-surrogate u16=%d %.2f", idx, CTLineGetOffsetForStringIndex(line, idx, &sec2)))
    }
    // prefix-sum check
    let prefix = String(s.unicodeScalars.prefix(1).map(Character.init))
    let pl = CTLineCreateWithAttributedString(NSAttributedString(string: prefix, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    print("\(s.debugDescription) width=\(String(format: "%.2f", width)) prefix1Alone=\(String(format: "%.2f", CTLineGetTypographicBounds(pl, nil, nil, nil)))")
    for l in out { print("  " + l) }
}
probe("AV")
probe("fi", "Times New Roman", size: 24)
probe("e\u{301}x")
probe("a👨‍👩‍👧b")
probe("ab\u{5D0}\u{5D1}c")
probe("ok漢字🙂")
probe("Hello", ".AppleSystemUIFont", size: 13.5)

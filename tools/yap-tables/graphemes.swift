// The class table in lean/Examples/Yap/Graphemes.lean (`tableText`): Swift's stdlib keeps its
// grapheme properties private, so each code point's class is read off how Swift segments it next
// to probes. `swiftc -O graphemes.swift && ./graphemes`; docs/yap-parity.md.
import Foundation
@inline(never) func cnt(_ v: [UInt32]) -> Int {
  var s = ""; for x in v { s.unicodeScalars.append(Unicode.Scalar(x)!) }; return s.count
}
// Same classes as the Lean table: 0 other, 1 CR, 2 LF, 3 control, 4 extend, 5 ZWJ, 6 RI, 7 prepend,
// 8 spacingMark, 9 L, 10 V, 11 T, 12 LV, 13 LVT; +16 ExtPict; +32 InCB consonant; +96 linker
func cls(_ x: UInt32) -> Int {
  if x == 0x0D { return 1 }; if x == 0x0A { return 2 }
  var k: Int
  if cnt([0x61, x]) == 1 {
    if cnt([0x1F600, x, 0x1F600]) == 1 { k = 5 }
    else if cnt([0x1F600, x, 0x200D, 0x1F600]) == 1 { k = 4 }
    else { k = 8 }
  } else if cnt([x, 0x301]) == 2 { k = 3 }
  else if cnt([x, 0x61]) == 1 { k = 7 }
  else if cnt([0x1F1E6, x]) == 1 && cnt([0x1F1E6, x, 0x1F1E6]) == 2 { k = 6 }
  else if cnt([x, 0x1100]) == 1 { k = 9 }
  else if cnt([x, 0x1161]) == 1 && cnt([0x1161, x]) == 1 { k = 10 }
  else if cnt([x, 0x1161]) == 1 { k = 12 }
  else if cnt([0x11A8, x]) == 1 && cnt([x, 0x11A8]) == 1 && cnt([0x1100, x]) == 2 { k = 11 }
  else if cnt([0x1100, x]) == 1 && cnt([x, 0x11A8]) == 1 { k = 13 }
  else { k = 0 }
  if k != 4 && k != 5 && k != 8 && cnt([0x1F600, 0x200D, x]) == 1 { k += 16 }
  if (k % 16) == 0 && cnt([0x915, 0x94D, x]) == 1 { k += 32 }
  if [0x94D, 0x9CD, 0xACD, 0xB4D, 0xC4D, 0xD4D].contains(x) { k += 96 }
  return k
}
var out = ""; var last = -1; var n = 0
for c in UInt32(0)...0x10FFFF {
  let k = (0xD800...0xDFFF).contains(c) ? 3 : cls(c)
  if k != last { out += String(c, radix: 16) + ":" + String(k) + " "; last = k; n += 1 }
}
print(out)

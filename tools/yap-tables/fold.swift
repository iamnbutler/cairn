// The tables in lean/Examples/Yap/Fold.lean, from the ICU that runs Yap's fixes: where
// `[\w-]` (case-insensitive) matches (`wordText`), and each code point's full case folding by
// `u_strFoldCase` (`foldText`). Compared as scalars: Swift's `==` would call ΐ and its
// decomposition equal. `swiftc -O fold.swift && ./fold`; docs/yap-parity.md.
import Foundation
let r = try! NSRegularExpression(pattern: "[\\w-]", options: .caseInsensitive)
var out = ""; var last = false; var first = true
for v in UInt32(0)...0x10FFFF {
  var w = false
  if let s = Unicode.Scalar(v) { let t = String(Character(s)); w = r.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil }
  else { w = last }  // surrogates: keep the run going
  if first || w != last { out += String(v, radix: 16) + ":" + (w ? "1" : "0") + " "; last = w; first = false }
}
print("word:", out)
let h = dlopen(nil, RTLD_NOW)
typealias Fold = @convention(c) (UnsafeMutablePointer<UInt16>, Int32, UnsafePointer<UInt16>, Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
let fold = unsafeBitCast(dlsym(h, "u_strFoldCase")!, to: Fold.self)
var f = ""
var n = 0
for v in UInt32(0)...0x10FFFF {
  guard let s = Unicode.Scalar(v) else { continue }
  let src = Array(String(s).utf16)
  var dst = [UInt16](repeating: 0, count: 8); var err: Int32 = 0
  let len = fold(&dst, 8, src, Int32(src.count), 0, &err)
  let res = String(decoding: dst[0..<Int(len)], as: UTF16.self)
  if Array(res.unicodeScalars) != [s] { f += String(v, radix: 16) + ":" + res.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ".") + " "; n += 1 }
}
print("fold:", f)

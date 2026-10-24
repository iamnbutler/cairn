// cmp a.png b.png [out.png] [--raw] [--px x,y ...] [--region name:x0,y0,x1,y1 ...]
// Both images drawn into sRGB premultiplied RGBA (ColorSync-matched from their profiles, or raw
// with --raw), then compared per channel. out.png: a | b | |a-b|×4 over a checkerboard-free black.
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
var args = Array(CommandLine.arguments.dropFirst())
let raw = args.contains("--raw"); args.removeAll { $0 == "--raw" }
var pxs: [(Int, Int)] = [], regions: [(String, Int, Int, Int, Int)] = []
var plain: [String] = []
var i = 0
while i < args.count {
    if args[i] == "--px" { i += 1; while i < args.count, !args[i].hasPrefix("--") { let v = args[i].split(separator: ",").map { Int($0)! }; pxs.append((v[0], v[1])); i += 1 }; continue }
    if args[i] == "--region" { i += 1; while i < args.count, !args[i].hasPrefix("--") { let p = args[i].split(separator: ":"); let v = p[1].split(separator: ",").map { Int($0)! }; regions.append((String(p[0]), v[0], v[1], v[2], v[3])); i += 1 }; continue }
    plain.append(args[i]); i += 1
}
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func load(_ p: String) -> (Int, Int, [UInt8]) {
    let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, 0, nil)!
    let w = img.width, h = img.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let src = raw ? img.copy(colorSpace: srgb)! : img
    b.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setBlendMode(.copy)
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, b)
}
let (w, h, a) = load(plain[0]), (w2, h2, b) = load(plain[1])
guard w == w2, h == h2 else { print("size differs \(w)x\(h) vs \(w2)x\(h2)"); exit(1) }
func stats(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> String {
    var n = 0, n2 = 0, n8 = 0, n32 = 0, mx = 0, sum = 0
    for y in max(0, y0)..<min(h, y1) { for x in max(0, x0)..<min(w, x1) {
        let o = (y * w + x) * 4; var d = 0
        for c in 0..<4 { d = max(d, abs(Int(a[o + c]) - Int(b[o + c]))) }
        n += 1; sum += d; mx = max(mx, d); if d > 2 { n2 += 1 }; if d > 8 { n8 += 1 }; if d > 32 { n32 += 1 }
    }}
    return String(format: "px %d  >2: %d (%.2f%%)  >8: %d (%.2f%%)  >32: %d  max %d  mean %.3f", n, n2, 100 * Double(n2) / Double(max(n, 1)), n8, 100 * Double(n8) / Double(max(n, 1)), n32, mx, Double(sum) / Double(max(n, 1)))
}
print("all     " + stats(0, 0, w, h))
for r in regions { print(r.0.padding(toLength: 8, withPad: " ", startingAt: 0) + stats(r.1, r.2, r.3, r.4)) }
for (x, y) in pxs { let o = (y * w + x) * 4; print("(\(x),\(y)) a \(Array(a[o..<o+4])) b \(Array(b[o..<o+4]))") }
if plain.count > 2 {
    let ow = w * 3 + 16
    var o = [UInt8](repeating: 255, count: ow * h * 4)
    for y in 0..<h { for x in 0..<w { for c in 0..<4 {
        let s = (y * w + x) * 4 + c
        o[(y * ow + x) * 4 + c] = a[s]; o[(y * ow + x + w + 8) * 4 + c] = b[s]
        o[(y * ow + x + 2 * w + 16) * 4 + c] = c == 3 ? 255 : UInt8(min(255, abs(Int(a[s]) - Int(b[s])) * 4))
    }}}
    // a and b over white, so the shadow shows.
    for y in 0..<h { for x in 0..<(2 * w + 8) { let s = (y * ow + x) * 4; let al = 255 - Int(o[s + 3]); for c in 0..<3 { o[s + c] = UInt8(min(255, Int(o[s + c]) + al)) }; o[s + 3] = 255 } }
    let ctx = CGContext(data: &o, width: ow, height: h, bitsPerComponent: 8, bytesPerRow: ow * 4, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: plain[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
}

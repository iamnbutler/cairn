// strip out.png refdir oursdir frame... : rows of (reference | Cairn) per frame, at half size, over grey.
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
func load(_ p: String) -> CGImage { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!, 0, nil)! }
let a = CommandLine.arguments
let frames = Array(a[4...])
let imgs = frames.map { (load(a[2] + "/" + $0), load(a[3] + "/" + $0)) }
let w = imgs.map { $0.0.width }.max()!, gap = 8
let rowH = imgs.map { max($0.0.height, $0.1.height) }
let W = (2 * w + gap) / 2, H = (rowH.reduce(0, +) + gap * (frames.count - 1)) / 2
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
ctx.interpolationQuality = .high
var y = H * 2
for (i, (r, o)) in imgs.enumerated() {
    y -= rowH[i]
    ctx.draw(r, in: CGRect(x: 0, y: y / 2, width: r.width / 2, height: r.height / 2))
    ctx.draw(o, in: CGRect(x: (w + gap) / 2, y: y / 2, width: o.width / 2, height: o.height / 2))
    y -= gap
}
let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)

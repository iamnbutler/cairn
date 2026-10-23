import CairnFrame
@testable import CairnRender
import Foundation
import Testing

/// One renderer for the whole test run. `Renderer` is single-threaded and Swift Testing runs
/// tests in parallel, so every use goes through `withRenderer`.
nonisolated(unsafe) private let sharedRenderer = try! Renderer()
private let rendererLock = NSLock()

func withRenderer<T>(_ body: (Renderer) throws -> T) rethrows -> T {
    rendererLock.lock(); defer { rendererLock.unlock() }
    return try body(sharedRenderer)
}

func render(_ frame: Frame, scale: Float = 2) throws -> Image {
    try withRenderer { try $0.image(frame, scale: scale) }
}

// Shorthands for hand-made frames.
func rgb(_ hex: UInt32, _ a: UInt8 = 255) -> Color {
    Color(r: UInt8(hex >> 16 & 0xff), g: UInt8(hex >> 8 & 0xff), b: UInt8(hex & 0xff), a: a)
}
func R(_ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32) -> Rect { Rect(x: x, y: y, w: w, h: h) }
func P(_ x: Int32, _ y: Int32) -> Point { Point(x: x, y: y) }
func rect(_ r: Rect, _ fill: Color?, radius: UInt32 = 0, border: Border? = nil) -> Draw {
    .rect(r, fill: fill, radius: radius, border: border)
}
func text(_ x: Int32, _ y: Int32, _ s: String, font: Font = Font(), color: Color = rgb(0x111111)) -> Draw {
    .text(origin: P(x, y), font: font, color: color, string: s)
}
func frame(_ w: Int32, _ h: Int32, _ draws: [Draw]) -> Frame { Frame(size: Size(w: w, h: h), draws: draws) }

/// Where rendered images go for a person to look at: $CAIRN_RENDER_OUT, or a temp directory.
let outputDir: URL = {
    if let p = ProcessInfo.processInfo.environment["CAIRN_RENDER_OUT"] { return URL(fileURLWithPath: p) }
    return FileManager.default.temporaryDirectory.appendingPathComponent("cairn-render")
}()

let goldenDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Goldens")

/// How far an image may drift from its golden: a channel may differ by up to `channel`
/// everywhere, and by more in at most `fraction` of pixels (glyph rasterisation can move by an
/// antialiasing step between OS releases; geometry should not move at all).
struct Tolerance { var channel = 8; var fraction = 0.002 }

struct Diff { var badPixels = 0; var maxDelta = 0; var total = 0 }

func diff(_ a: Image, _ b: Image, channel: Int) -> Diff {
    var d = Diff(total: a.width * a.height)
    for i in stride(from: 0, to: a.bgra.count, by: 4) {
        var m = 0
        for c in 0..<4 { m = max(m, abs(Int(a.bgra[i + c]) - Int(b.bgra[i + c]))) }
        d.maxDelta = max(d.maxDelta, m)
        if m > channel { d.badPixels += 1 }
    }
    return d
}

/// Compares a render with `Goldens/<name>.png`. With CAIRN_UPDATE_GOLDENS=1 it rewrites the
/// golden instead. The render is always written to `outputDir` for inspection.
func expectGolden(_ name: String, _ f: Frame, scale: Float = 2, tolerance: Tolerance = Tolerance(),
                  sourceLocation: SourceLocation = #_sourceLocation) throws {
    let img = try render(f, scale: scale)
    try img.writePNG(to: outputDir.appendingPathComponent("\(name).png"))
    let golden = goldenDir.appendingPathComponent("\(name).png")
    if ProcessInfo.processInfo.environment["CAIRN_UPDATE_GOLDENS"] == "1" {
        try img.writePNG(to: golden)
        return
    }
    guard let want = Image.readPNG(from: golden) else {
        Issue.record("missing golden \(golden.path); run with CAIRN_UPDATE_GOLDENS=1", sourceLocation: sourceLocation)
        return
    }
    #expect(want.width == img.width && want.height == img.height, "\(name): size", sourceLocation: sourceLocation)
    guard want.width == img.width, want.height == img.height else { return }
    let d = diff(img, want, channel: tolerance.channel)
    let ok = Double(d.badPixels) <= tolerance.fraction * Double(d.total)
    if !ok { try? want.writePNG(to: outputDir.appendingPathComponent("\(name).golden.png")) }
    #expect(ok, "\(name): \(d.badPixels) of \(d.total) pixels differ by more than \(tolerance.channel) (max \(d.maxDelta)); see \(outputDir.path)",
            sourceLocation: sourceLocation)
}

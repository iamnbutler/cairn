import CairnFrame
@testable import CairnRender
import Foundation
import Testing

let white = rgb(0xffffff)
let red = rgb(0xff0000)
let blue = rgb(0x0000ff)

@Suite struct ProbeTests {
    @Test(arguments: [Float(1), 1.5, 2, 3]) func fillIsExactInsideAndAbsentOutside(_ scale: Float) throws {
        let f = frame(40, 40, [rect(R(10, 10, 20, 10), red)])
        let img = try render(f, scale: scale)
        let px = PixelRect.covering(R(10, 10, 20, 10), scale: scale)
        // Edges snap to whole device pixels, so coverage is all or nothing: no blended fringe.
        for y in 0..<img.height {
            for x in 0..<img.width {
                let inside = x >= px.x0 && x < px.x1 && y >= px.y0 && y < px.y1
                #expect(img.pixel(x, y) == (inside ? red : white), "(\(x), \(y)) @\(scale)x")
                if img.pixel(x, y) != (inside ? red : white) { return }
            }
        }
    }

    @Test func probeReadsTheControlBox() throws {
        let f = frame(100, 60, [rect(R(0, 0, 100, 60), rgb(0xf6f5f2)),
                                rect(R(10, 10, 40, 20), rgb(0x3d7dd9), radius: 6),
                                text(14, 25, "OK", color: white)])
        try withRenderer { (r: Renderer) throws in
            #expect(try r.probe(f, at: P(40, 13)) == rgb(0x3d7dd9))   // inside the box, off the label
            #expect(try r.probe(f, at: P(70, 40)) == rgb(0xf6f5f2))
            #expect(try r.probe(f, at: P(10, 10)) != rgb(0x3d7dd9))   // rounded corner: not fully painted
            #expect(try r.probe(f, at: [P(40, 13), P(70, 40)], scale: 1) == [rgb(0x3d7dd9), rgb(0xf6f5f2)])
        }
    }

    @Test func translucentBlendsOver() throws {
        let f = frame(10, 10, [rect(R(0, 0, 10, 10), red, radius: 0), rect(R(0, 0, 10, 10), rgb(0x0000ff, 128))])
        let c = try withRenderer { try $0.probe(f, at: P(5, 5)) }
        #expect(abs(Int(c.r) - 127) <= 1 && c.g == 0 && abs(Int(c.b) - 128) <= 1 && c.a == 255, "\(c)")
    }

    /// Borders are inside the rect, `width × scale` device pixels thick, over the fill.
    @Test(arguments: [Float(1), 2]) func borderInside(_ scale: Float) throws {
        let f = frame(40, 40, [rect(R(10, 10, 20, 20), white, border: Border(width: 2, color: blue))])
        let img = try render(f, scale: scale)
        let s = Int(scale)
        #expect(img.pixel(10 * s - 1, 20 * s) == white)          // outside: background
        #expect(img.pixel(10 * s, 20 * s) == blue)               // first border pixel
        #expect(img.pixel(12 * s - 1, 20 * s) == blue)           // last border pixel
        #expect(img.pixel(12 * s, 20 * s) == white)              // fill
        #expect(img.pixel(30 * s - 1, 20 * s) == blue)
        #expect(img.pixel(20 * s, 30 * s - 1) == blue)
        #expect(img.pixel(20 * s, 20 * s) == white)
    }

    /// A 1 pt border at 1.5x is 1 device pixel (rounded half down), never 0.
    @Test func thinBorderNeverVanishes() throws {
        let f = frame(20, 20, [rect(R(2, 2, 16, 16), white, border: Border(width: 1, color: blue))])
        let img = try render(f, scale: 1.5)
        let x0 = PixelRect.covering(R(2, 2, 16, 16), scale: 1.5).x0
        #expect(img.pixel(x0, 15) == blue)
        #expect(img.pixel(x0 + 1, 15) == white)
        #expect(Renderer.edgeLength(1, 0.5) == 0)  // the clamp to 1 px happens at the call site
    }

    /// The SDF works in device pixels: across a circle's edge the antialiasing ramp is about one
    /// device pixel wide at any scale (the spike's was two at 2x).
    @Test(arguments: [Float(1), 2, 3]) func antialiasingIsOneDevicePixel(_ scale: Float) throws {
        let f = frame(60, 60, [rect(R(10, 10, 40, 40), rgb(0x000000), radius: 20)])
        let img = try render(f, scale: scale)
        let y = Int(30 * scale)          // the circle's equator: its edge is vertical here
        let partial = (0..<img.width).filter { x in
            let c = img.pixel(x, y).r
            return c > 8 && c < 247
        }
        #expect(partial.count <= 2, "partial pixels at the equator: \(partial)")  // one per side
        // Along a diagonal the edge is at 45°; its ramp spans ~1.4 device px per side.
        var diag = 0
        for i in 0..<img.width {
            let c = img.pixel(i, i).r
            if c > 8 && c < 247 { diag += 1 }
        }
        #expect(diag <= 4, "partial pixels on the diagonal: \(diag)")
    }

    /// Shared logical edges stay shared at 1.5x: tiled boxes leave no background showing.
    @Test func noSeamsAtFractionalScale() throws {
        let img = try render(Scenes.tiles, scale: 1.5)
        for y in 0..<img.height {
            for x in 0..<img.width {
                let c = img.pixel(x, y)
                #expect(c == rgb(0x3d7dd9) || c == rgb(0x2a5aa0), "(\(x), \(y)) = \(c)")
                if c != rgb(0x3d7dd9) && c != rgb(0x2a5aa0) { return }
            }
        }
    }

    @Test func clipsNestAndPop() throws {
        let f = frame(100, 100, [
            .pushClip(R(10, 10, 60, 60)),
            .pushClip(R(40, 40, 60, 60)),          // intersects to 40,40 30x30
            rect(R(0, 0, 100, 100), red),
            .popClip,
            rect(R(0, 0, 20, 20), blue),           // outer clip only: 10..20
            .popClip,
            rect(R(90, 0, 10, 10), blue),          // unclipped
        ])
        let img = try render(f, scale: 2)
        func at(_ x: Int, _ y: Int) -> Color { img.pixel(x * 2, y * 2) }
        #expect(at(40, 40) == red && at(69, 69) == red)
        #expect(at(39, 50) == white && at(70, 50) == white && at(50, 39) == white && at(50, 70) == white)
        #expect(at(10, 10) == blue && at(19, 19) == blue && at(9, 9) == white && at(20, 15) == white)
        #expect(at(95, 5) == blue)
    }

    @Test func emptyClipDrawsNothingAndUnbalancedPopIsIgnored() throws {
        let f = frame(20, 20, [
            .pushClip(R(5, 5, 0, 10)), rect(R(0, 0, 20, 20), red), text(2, 15, "x"), .popClip,
            .popClip, .popClip,
            rect(R(0, 0, 5, 5), blue),
        ])
        let (img, stats) = try withRenderer { r in (try r.image(f, scale: 1), r.lastStats) }
        #expect(img.pixel(10, 10) == white)
        #expect(img.pixel(2, 2) == blue)
        #expect(stats.unbalancedPops == 2)
        #expect(stats.skipped == 2)
        #expect(stats.rects == 1)
    }

    /// Clips snap with the same rule as fills, so a clip equal to a rect admits exactly its pixels.
    @Test(arguments: [Float(1), 1.25, 1.5, 2]) func clipMatchesFill(_ scale: Float) throws {
        let r = R(3, 7, 13, 9)
        let a = try render(frame(30, 30, [rect(r, red)]), scale: scale)
        let b = try render(frame(30, 30, [.pushClip(r), rect(R(0, 0, 30, 30), red), .popClip]), scale: scale)
        #expect(a.bgra == b.bgra)
    }

    @Test func pixelRectCovering() {
        #expect(PixelRect.covering(R(1, 1, 1, 1), scale: 1.5) == PixelRect(x0: 1, y0: 1, x1: 3, y1: 3))  // centres 1.5 and 2.5 px lie in [1, 2) pt
        #expect(PixelRect.covering(R(1, 1, 2, 2), scale: 1.5) == PixelRect(x0: 1, y0: 1, x1: 4, y1: 4))
        #expect(PixelRect.covering(R(-3, 0, 2, 0), scale: 2) == PixelRect(x0: -6, y0: 0, x1: -2, y1: 0))
        #expect(PixelRect.covering(R(0, 0, -5, 4), scale: 2).isEmpty)
    }

    /// Later draws are on top, across kinds, and kinds interleave as separate batches.
    @Test func paintOrderAndBatching() throws {
        let label = text(5, 20, "████", font: Font(size: 20), color: red)
        let over = frame(60, 30, [label, rect(R(0, 0, 60, 30), blue)])
        let under = frame(60, 30, [rect(R(0, 0, 60, 30), blue), label])
        let p = P(12, 12)
        try withRenderer { (r: Renderer) throws in
            #expect(try r.probe(over, at: p) == blue)
            #expect(try r.probe(under, at: p) == red)
            #expect(r.lastStats.rectBatches == 1 && r.lastStats.glyphBatches == 1)

            var draws: [Draw] = (0..<1000).map { i in rect(R(Int32(i % 50), Int32(i / 50), 1, 1), red) }
            _ = try r.image(frame(60, 30, draws), scale: 1)
            #expect(r.lastStats.rectBatches == 1 && r.lastStats.rects == 1000)

            draws = [rect(R(0, 0, 5, 5), red), text(0, 10, "a"), rect(R(0, 0, 5, 5), red), text(0, 10, "b"),
                     .pushClip(R(0, 0, 10, 10)), rect(R(0, 0, 5, 5), red), .popClip, rect(R(0, 0, 5, 5), red)]
            _ = try r.image(frame(60, 30, draws), scale: 1)
            #expect(r.lastStats.rectBatches == 4 && r.lastStats.glyphBatches == 2)
        }
    }

    /// Glyphs from fallback fonts (emoji in colour, CJK) paint, and emoji keep their colour
    /// whatever the text colour.
    @Test func colourEmojiIgnoreTextColour() throws {
        let f = frame(40, 40, [text(4, 30, "🟥", font: Font(size: 28), color: rgb(0x00ff00))])
        let c = try withRenderer { try $0.probe(f, at: P(17, 19)) }
        #expect(c.r > 180 && c.g < 120, "\(c)")
    }

    /// Filling the atlas past its page budget resets it between frames and keeps drawing correctly.
    @Test func atlasResetsWhenFull() throws {
        // ~2,500 distinct large CJK glyphs fill more than `maxPages` pages at 2x.
        let chars = (0x4E00..<(0x4E00 + 2600)).map { String(UnicodeScalar($0)!) }.joined()
        let big = Font(size: 64)
        try withRenderer { (r: Renderer) throws in
            var draws: [Draw] = []
            for (i, chunk) in stride(from: 0, to: chars.count, by: 100).enumerated() {
                let start = chars.index(chars.startIndex, offsetBy: chunk)
                let end = chars.index(start, offsetBy: min(100, chars.count - chunk))
                draws.append(text(0, Int32(64 + i * 70), String(chars[start..<end]), font: big))
            }
            _ = try r.image(frame(400, 400, draws), scale: 2)
            #expect(r.atlas.pageCount > GlyphAtlas.maxPages, "pages: \(r.atlas.pageCount)")
            let probe = frame(40, 40, [rect(R(0, 0, 40, 40), white), rect(R(10, 10, 20, 20), red), text(2, 30, "x")])
            #expect(try r.probe(probe, at: P(20, 15)) == red)
            #expect(r.atlas.pageCount <= 2, "atlas was reset: \(r.atlas.pageCount) pages")
        }
    }
}

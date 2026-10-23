import CairnFrame
@testable import CairnRender
import Testing

/// The fixed set of frames whose renders are checked into Goldens/. Each is small, exercises one
/// feature, and is rendered at 2x (the common backing scale); a few also at 1x and 1.5x.
enum Scenes {
    static let bg = rgb(0xf6f5f2)

    static let rects = frame(240, 160, [
        rect(R(0, 0, 240, 160), bg),
        rect(R(10, 10, 60, 40), rgb(0xd94f3d)),
        rect(R(80, 10, 60, 40), rgb(0x3d7dd9), radius: 6),
        rect(R(150, 10, 80, 40), rgb(0x3daa5c), radius: 20),           // pill: radius clamps to h/2
        rect(R(10, 60, 40, 40), rgb(0x8a3dd9), radius: 100),           // circle
        rect(R(60, 60, 60, 40), rgb(0xd94f3d, 128), radius: 4),        // translucent over…
        rect(R(90, 80, 60, 40), rgb(0x3d7dd9, 128), radius: 4),        // …translucent
        rect(R(160, 60, 1, 60), rgb(0x111111)),                         // hairlines
        rect(R(165, 60, 60, 1), rgb(0x111111)),
        rect(R(170, 70, 50, 50), rgb(0xe0a030), radius: 3),
        rect(R(10, 130, 220, 20), rgb(0x222222), radius: 10),
    ])

    static let borders = frame(240, 160, [
        rect(R(0, 0, 240, 160), bg),
        rect(R(10, 10, 60, 40), rgb(0xffffff), border: Border(width: 1, color: rgb(0x999999))),
        rect(R(80, 10, 60, 40), rgb(0xffffff), radius: 6, border: Border(width: 2, color: rgb(0x3d7dd9))),
        rect(R(150, 10, 80, 40), nil, radius: 20, border: Border(width: 4, color: rgb(0xd94f3d))),
        rect(R(10, 60, 40, 40), rgb(0xe0a030), radius: 20, border: Border(width: 3, color: rgb(0x222222))),
        rect(R(60, 60, 60, 40), rgb(0x3daa5c), radius: 8, border: Border(width: 6, color: rgb(0x000000, 96))),
        rect(R(130, 60, 40, 40), rgb(0xffffff), border: Border(width: 30, color: rgb(0x8a3dd9))),  // border fills it
        rect(R(180, 60, 50, 40), nil, radius: 12, border: Border(width: 1, color: rgb(0x111111))),
        rect(R(10, 110, 220, 40), rgb(0xffffff), radius: 4, border: Border(width: 1, color: rgb(0xcccccc))),
        rect(R(14, 114, 100, 32), rgb(0xeeeeee), radius: 3),
    ])

    static let clips = frame(240, 160, [
        rect(R(0, 0, 240, 160), bg),
        .pushClip(R(20, 20, 120, 100)),
        rect(R(0, 0, 240, 160), rgb(0xdde6f5)),                          // fills only the clip
        .pushClip(R(60, 40, 140, 60)),                                    // nested: intersects to 60,40 80x60
        rect(R(0, 0, 240, 160), rgb(0x3d7dd9)),
        text(50, 75, "clipped text runs past", color: rgb(0xffffff)),
        .popClip,
        rect(R(10, 100, 60, 40), rgb(0xd94f3d), radius: 8),               // clipped by outer only
        .pushClip(R(200, 0, 40, 40)),                                     // disjoint: nothing shows
        rect(R(0, 0, 240, 160), rgb(0x000000)),
        .popClip,
        .popClip,
        rect(R(150, 110, 80, 40), rgb(0x3daa5c), radius: 6),              // after all pops: unclipped
        .pushClip(R(150, 20, 80, 0)),                                     // empty clip
        rect(R(150, 20, 80, 40), rgb(0x000000)),
        .popClip,
    ])

    static let fonts = frame(320, 200, [
        rect(R(0, 0, 320, 200), rgb(0xffffff)),
        text(10, 20, "System 13 regular: Sphinx of black quartz"),
        text(10, 40, "System 13 bold: judge my vow", font: Font(weight: 700)),
        text(10, 62, "System 17 semibold italic", font: Font(size: 17, weight: 600, italic: true)),
        text(10, 82, "Mono 13: let x = f(0) // 0O1lI", font: Font(family: 1)),
        text(10, 100, "System 11 light, grey", font: Font(size: 11, weight: 300), color: rgb(0x777777)),
        text(10, 132, "Heavy 24 AVATAR", font: Font(size: 24, weight: 800)),
        rect(R(10, 145, 300, 45), rgb(0x1d2330), radius: 6),
        text(20, 166, "Light on dark: 0123456789", color: rgb(0xf0f0f0)),
        text(20, 182, "Mono bold italic on dark", font: Font(family: 1, weight: 700, italic: true), color: rgb(0x8fd18f)),
    ])

    static let scripts = frame(320, 140, [
        rect(R(0, 0, 320, 140), rgb(0xffffff)),
        text(10, 24, "Emoji: 😀 🎉 👍🏽 👨‍👩‍👧 ✅"),
        text(10, 52, "CJK: 你好世界 こんにちは 한국어", font: Font(size: 15)),
        text(10, 80, "Accents: café naïve e\u{301}x Ångström"),
        text(10, 110, "Big emoji 🌍🚀", font: Font(size: 26)),
        text(200, 110, "混合 mixed ✨", color: rgb(0xd94f3d)),
    ])

    /// Paint order: later draws are on top, across rects and text.
    static let order = frame(240, 120, [
        rect(R(0, 0, 240, 120), bg),
        text(10, 30, "under the box", font: Font(size: 17, weight: 700)),
        rect(R(40, 10, 60, 30), rgb(0x3d7dd9, 200), radius: 4),
        text(60, 30, "over", font: Font(size: 17, weight: 700), color: rgb(0xffffff)),
        rect(R(10, 60, 100, 50), rgb(0xd94f3d)),
        rect(R(30, 70, 100, 50), rgb(0x3daa5c)),
        text(40, 95, "top", font: Font(size: 20, weight: 700)),
        rect(R(150, 60, 80, 50), rgb(0x222222), radius: 25),
        text(165, 90, "pill", color: rgb(0xffffff)),
    ])

    /// Boxes that tile with shared edges: no seams at any scale.
    static let tiles: Frame = {
        var d: [Draw] = [rect(R(0, 0, 120, 60), rgb(0xffffff))]
        for i in 0..<12 {
            for j in 0..<6 {
                d.append(rect(R(Int32(i * 10), Int32(j * 10), 10, 10), (i + j) % 2 == 0 ? rgb(0x3d7dd9) : rgb(0x2a5aa0)))
            }
        }
        return frame(120, 60, d)
    }()
}

@Suite struct GoldenTests {
    @Test func rects() throws { try expectGolden("rects@2x", Scenes.rects) }
    @Test func rects1x() throws { try expectGolden("rects@1x", Scenes.rects, scale: 1) }
    @Test func rects15x() throws { try expectGolden("rects@1.5x", Scenes.rects, scale: 1.5) }
    @Test func borders() throws { try expectGolden("borders@2x", Scenes.borders) }
    @Test func borders15x() throws { try expectGolden("borders@1.5x", Scenes.borders, scale: 1.5) }
    @Test func clips() throws { try expectGolden("clips@2x", Scenes.clips) }
    @Test func clips15x() throws { try expectGolden("clips@1.5x", Scenes.clips, scale: 1.5) }
    @Test func fonts() throws { try expectGolden("fonts@2x", Scenes.fonts, tolerance: Tolerance(channel: 24, fraction: 0.01)) }
    @Test func fonts1x() throws { try expectGolden("fonts@1x", Scenes.fonts, scale: 1, tolerance: Tolerance(channel: 24, fraction: 0.01)) }
    @Test func scripts() throws { try expectGolden("scripts@2x", Scenes.scripts, tolerance: Tolerance(channel: 24, fraction: 0.01)) }
    @Test func order() throws { try expectGolden("order@2x", Scenes.order, tolerance: Tolerance(channel: 24, fraction: 0.01)) }
    @Test func tiles15x() throws { try expectGolden("tiles@1.5x", Scenes.tiles, scale: 1.5) }
}

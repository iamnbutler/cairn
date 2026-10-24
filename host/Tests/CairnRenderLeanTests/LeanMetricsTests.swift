import CairnFrame
@testable import CairnRender
import CairnLeanText
import Testing

/// End to end: Lean's `TextMetrics.host` (through the extern, the C glue, and the
/// `cairn_text_metrics` export) returns exactly the metrics the renderer draws with.
@Suite struct LeanMetricsTests {
    func lean(_ f: Font, _ s: String) -> [Int32] {
        var bytes = Array(s.utf8)
        var out = [Int32](repeating: 0, count: s.unicodeScalars.count + 3 + 1)
        let n = cairn_text_test_lean_metrics(f.family, f.size, f.weight, f.style, f.tracking,
                                             &bytes, bytes.count, &out, out.count)
        return Array(out.prefix(n))
    }

    @Test func leanSeesWhatTheRendererDraws() {
        cairn_text_test_init()
        let fonts = [Font(), Font(weight: 700), Font(size: 17, weight: 600, italic: true),
                     Font(family: 1), Font(size: 24, weight: 800),
                     Font(size: 10, weight: 600, width: .expanded, tracking: 140),
                     Font(size: 22, weight: 200, width: .expanded, tabular: true),
                     Font(size: 15, width: .condensed, tracking: -50, tabular: true)]
        let strings = ["", "Hello, world", "AVATAR", "café", "e\u{301}x", "a👨‍👩‍👧b", "你好世界",
                       "👍🏽 ok", "abאבc", "tab\there", "\u{FEFF}bom"]
        for f in fonts {
            for s in strings {
                let line = TextSystem.shared.shape(f, s)
                let got = lean(f, s)
                #expect(got.first == 1, "the Swift host's cairn_text_metrics is linked, not the weak stand-in")
                #expect(Array(got.dropFirst()) == [line.ascent, line.descent] + line.offsets,
                        "\(f) \(s.debugDescription)")
            }
        }
    }
}

import AppKit
import CairnFrame
import CoreText

/// The one mapping from a frame's `Font` to a Core Text font. Drawing and metrics both go through
/// it, so they can never disagree about which font a run uses.
enum Fonts {
    /// Sizes outside this range are clamped (a size of 0 would make Core Text pick 12 pt).
    static let sizeRange: ClosedRange<UInt32> = 1...1024

    /// CSS weight (100–900, rounded to the nearest hundred and clamped) to an AppKit weight.
    static func weight(_ w: UInt32) -> NSFont.Weight {
        let hundred = min(max((Int(w) + 50) / 100, 1), 9)
        switch hundred {
        case 1: return .ultraLight
        case 2: return .thin
        case 3: return .light
        case 4: return .regular
        case 5: return .medium
        case 6: return .semibold
        case 7: return .bold
        case 8: return .heavy
        default: return .black
        }
    }

    /// family 1 is the system monospaced font; every other family is the system UI font.
    /// Italic applies the symbolic trait; if the face has no italic, the upright face is used.
    static func make(_ font: Font) -> CTFont {
        let size = CGFloat(min(max(font.size, sizeRange.lowerBound), sizeRange.upperBound))
        let w = weight(font.weight)
        let ns = font.family == 1
            ? NSFont.monospacedSystemFont(ofSize: size, weight: w)
            : NSFont.systemFont(ofSize: size, weight: w)
        let base = ns as CTFont
        guard font.italic else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, 0, nil, .traitItalic, .traitItalic) ?? base
    }
}

/// A CTFont usable as a dictionary key (Core Foundation equality and hash).
struct FontKey: Hashable, @unchecked Sendable {
    let font: CTFont
    static func == (a: FontKey, b: FontKey) -> Bool { CFEqual(a.font, b.font) }
    func hash(into h: inout Hasher) { h.combine(CFHash(font)) }
}

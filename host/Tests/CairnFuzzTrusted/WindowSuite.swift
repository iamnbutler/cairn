import AppKit
import CairnFrame
import CairnHost
import Foundation

/// The window's minimum size (^1010, `WindowSizer` in host/Sources/CairnHost/WindowSize.swift).
/// Each case makes a resizable window (never shown) with the host's sizer as its delegate, then
/// runs a random sequence of new minimums (some negative, some larger than the window) and live
/// resizes, each proposed to the delegate as AppKit proposes a drag and then applied with
/// `setFrame`, as AppKit does. After every step:
///
/// - `window.min-size`: `contentMinSize` is the latest minimum (negative taken as 0), the
///   window's content is at least that big, and so is the size the host would tell Lean (its
///   content view's bounds, rounded down to whole points); a minimum the window already meets
///   leaves its frame alone, and growing to a larger one keeps the window's top-left corner; a
///   live resize to a size at or above the minimum is left as proposed.
final class WindowSuite: Suite {
    let name = "window"
    let crashCheck = "window.min-size"
    let checks: [String: CheckInfo] = [
        "window.min-size": CheckInfo(
            title: "The window is never smaller than the app's minimum size",
            trusted: ["host/Sources/CairnHost/WindowSize.swift (WindowSizer)", "host/Sources/CairnHost/CairnApp.swift",
                      "AppKit (NSWindow.contentMinSize, windowWillResize)"],
            oracle: "the latest minimum the frames asked for"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 10) }
    func setUp() {}

    enum Step: CustomStringConvertible {
        case minimum(Size)
        case drag(NSSize)
        var description: String {
            switch self {
            case let .minimum(s): "minimum \(s.w)×\(s.h)"
            case let .drag(s): "drag to \(Int(s.width))×\(Int(s.height))"
            }
        }
    }

    static func size(_ g: inout SplitMix) -> Int32 {
        switch g.below(6) {
        case 0: Int32(-g.range(1, 100))
        case 1: 0
        default: Int32(g.range(1, 2400))
        }
    }

    static func plan(_ g: inout SplitMix) -> (NSSize, [Step]) {
        let start = NSSize(width: g.range(1, 2000), height: g.range(1, 1400))
        var steps: [Step] = []
        for _ in 0..<g.range(1, 12) {
            if g.chance(1, 3) {
                steps.append(.minimum(Size(w: size(&g), h: size(&g))))
            } else {
                steps.append(.drag(NSSize(width: g.range(1, 2600), height: g.range(1, 1600))))
            }
        }
        return (start, steps)
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        MainActor.assumeIsolated { runMain(&g, r) }
    }

    @MainActor
    func runMain(_ g: inout SplitMix, _ r: Recorder) {
        let (start, steps) = Self.plan(&g)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: start),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(origin: .zero, size: start))
        window.contentView = view
        let sizer = WindowSizer()
        window.delegate = sizer
        var min = NSSize.zero
        func check(_ what: Step) {
            r.ran("window.min-size")
            let content = window.contentRect(forFrameRect: window.frame).size
            if window.contentMinSize != min {
                r.fail("window.min-size", "after \(what): contentMinSize \(window.contentMinSize), want \(min)")
            }
            if content.width < min.width || content.height < min.height {
                r.fail("window.min-size", "after \(what): content \(content) under the minimum \(min)")
            }
            let told = (view.bounds.width.rounded(.down), view.bounds.height.rounded(.down))
            if told.0 < min.width || told.1 < min.height {
                r.fail("window.min-size", "after \(what): the view's size \(told) under the minimum \(min)")
            }
        }
        for step in steps {
            switch step {
            case let .minimum(s):
                let before = window.frame
                let content = window.contentRect(forFrameRect: before).size
                min = NSSize(width: CGFloat(max(0, s.w)), height: CGFloat(max(0, s.h)))
                sizer.apply(s, to: window)
                if content.width >= min.width && content.height >= min.height {
                    if window.frame != before { r.fail("window.min-size", "\(step) moved a window that met it: \(before) → \(window.frame)") }
                    r.count("window.min-size", "met")
                } else {
                    if window.frame.minX != before.minX || window.frame.maxY != before.maxY {
                        r.fail("window.min-size", "\(step) grew the window off its top-left: \(before) → \(window.frame)")
                    }
                    r.count("window.min-size", "grown")
                }
            case let .drag(content):
                let proposed = window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
                let answer = sizer.windowWillResize(window, to: proposed)
                if content.width >= min.width && content.height >= min.height && answer != proposed {
                    r.fail("window.min-size", "\(step) at or above the minimum \(min) was changed to \(answer)")
                }
                r.count("window.min-size", answer == proposed ? "drags" : "drags clamped")
                window.setFrame(NSRect(origin: window.frame.origin, size: answer), display: false)
            }
            check(step)
        }
        window.close()
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let (start, steps) = Self.plan(&g)
        return "window \(Int(start.width))×\(Int(start.height)), then " + steps.map(\.description).joined(separator: ", ")
    }
}

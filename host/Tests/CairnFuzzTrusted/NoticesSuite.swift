import AppKit
import CairnFrame
import CairnHost
import Foundation

/// A core whose next frame carries the effects the suite gives it, once.
final class EffectsCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Effect] = []
    func set(_ e: [Effect]) { lock.withLock { pending = e } }
    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) {}
    func frame() throws -> Frame {
        lock.withLock {
            defer { pending = [] }
            return Frame(size: Size(w: 10, h: 10), draws: [], effects: pending)
        }
    }
}

/// `badge` and `announce` (^1030, ^1031; `Notices`, `HostView.run`). Each case sends one to
/// three frames whose effects mix `badge` (labels empty, short, long, any Unicode, or none) and
/// `announce` (any text, either priority) with effects the host leaves alone (`scrollTo`,
/// `focus`), through a real `HostView` in a window that is never shown, as the engine hands
/// them over:
///
/// - `dock.badge`: after each frame, `NSApp.dockTile.badgeLabel`, read back from AppKit, is
///   exactly the label of the last `badge` so far, or nil when that was `badge none`; a frame
///   with no `badge` leaves it as it was. The case ends with the badge cleared, and reads nil.
/// - `ax.announce`: the poster (a recorder standing in for `NSAccessibility.post`) is called
///   once per `announce`, in order, for the window, with `announcementRequested`'s user info
///   holding exactly the text and the priority's level (`low` 10, `high` 90), and never for
///   anything else.
final class NoticesSuite: Suite {
    let name = "notices"
    let crashCheck = "dock.badge"
    let checks: [String: CheckInfo] = [
        "dock.badge": CheckInfo(
            title: "The Dock badge is exactly the last `badge` effect's label, or none",
            trusted: ["host/Sources/CairnHost/NoticeEffects.swift (Notices.badge)",
                      "host/Sources/CairnHost/HostView.swift (run)", "NSDockTile.badgeLabel"],
            oracle: "the labels sent, against NSApp.dockTile.badgeLabel read back"),
        "ax.announce": CheckInfo(
            title: "An announcement is posted once, with exactly its text and priority",
            trusted: ["host/Sources/CairnHost/NoticeEffects.swift (Notices.announce)",
                      "host/Sources/CairnHost/HostView.swift (run)", "NSAccessibility.post"],
            oracle: "the texts and priorities sent, against a recorder in place of NSAccessibility.post"),
    ]

    func cases(for n: Int) -> Int { max(8, n / 2) }

    var view: HostView!
    var window: NSWindow!
    var engine: Engine!
    let core = EffectsCore()
    struct Posted { var element: AnyObject?; var text: String?; var level: Int? }
    let posted = Locked<[Posted]>([])

    func setUp() {
        MainActor.assumeIsolated {
            let core = self.core
            engine = Engine(size: Size(w: 10, h: 10), scalePercent: 200, clock: false) { core }
            view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: 10, height: 10))
            let posted = self.posted
            view.notices = NoticeSystem(setBadge: NoticeSystem.live.setBadge, post: { element, info in
                posted.update {
                    $0.append(Posted(element: element as AnyObject,
                                     text: info[.announcement] as? String,
                                     level: (info[.priority] as? NSNumber)?.intValue))
                }
            })
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = view
            engine.start()
            _ = engine.wait(through: 0)
            view.applyLatestFrame()
        }
    }

    static func label(_ g: inout SplitMix) -> String? {
        switch g.below(6) {
        case 0: nil
        case 1: ""
        case 2: String(g.below(1000))
        case 3: "99+"
        case 4: String(repeating: "9", count: 1 + g.below(40))
        default: TextPool.string(&g, maxParts: 4)
        }
    }

    static func plan(_ g: inout SplitMix) -> [[Effect]] {
        (0..<(1 + g.below(3))).map { _ in
            (0..<g.below(5)).map { _ in
                switch g.below(5) {
                case 0, 1: .badge(label(&g))
                case 2, 3: .announce(TextPool.string(&g, maxParts: 6), priority: g.bool() ? .high : .low)
                default: g.bool() ? .scrollTo(ControlRef(claim: 14), .start) : .focus(ControlRef(claim: 2))
                }
            }
        }
    }

    func send(_ effects: [Effect]) {
        core.set(effects)
        let seq = engine.send([.pointerMove(Point(x: 0, y: 0))])
        _ = engine.wait(through: seq)
        MainActor.assumeIsolated { view.applyLatestFrame() }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let frames = Self.plan(&g)
        var badge: String? = MainActor.assumeIsolated { NSApp.dockTile.badgeLabel }
        var said: [(String, Int)] = []
        posted.update { $0 = [] }
        for effects in frames {
            send(effects)
            for e in effects {
                if case .badge(let l) = e { badge = l }
                if case let .announce(t, p) = e { said.append((t, p == .high ? 90 : 10)) }
            }
            let shown = MainActor.assumeIsolated { NSApp.dockTile.badgeLabel }
            r.expect("dock.badge", shown == badge,
                     "after \(effects): the badge reads \(String(describing: shown)), want \(String(describing: badge))")
            let got = posted.value
            let win = MainActor.assumeIsolated { window as AnyObject }
            r.expect("ax.announce", got.count == said.count
                        && zip(got, said).allSatisfy { $0.element === win && $0.text == $1.0 && $0.level == $1.1 },
                     "after \(effects): posted \(got.map { ($0.text ?? "nil", $0.level ?? -1) }), want \(said)")
        }
        r.count("ax.announce", said.isEmpty ? "none" : "announced")
        send([.badge(nil)])
        let cleared = MainActor.assumeIsolated { NSApp.dockTile.badgeLabel }
        r.expect("dock.badge", cleared == nil, "badge none leaves \(String(describing: cleared))")
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "frames of effects: \(Self.plan(&g))"
    }
}

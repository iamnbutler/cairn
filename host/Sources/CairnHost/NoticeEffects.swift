import AppKit
import CairnFrame

// `badge` and `announce` (docs/effects.md). Trusted: claims ^1030 and ^1031 in docs/trusted.md.
// Each is one AppKit call with no policy here: the label and the text are Lean's, as they are.
// The calls go through a small struct of functions so the trusted-base fuzzer can record the
// announcements it posts instead of speaking them.

/// What `badge` and `announce` reach.
public struct NoticeSystem: Sendable {
    /// Sets `NSApp.dockTile.badgeLabel`.
    public var setBadge: @MainActor @Sendable (String?) -> Void
    /// `NSAccessibility.post(element:notification:userInfo:)` with `.announcementRequested`.
    public var post: @MainActor @Sendable (_ element: Any, _ userInfo: [NSAccessibility.NotificationUserInfoKey: Any]) -> Void

    public init(setBadge: @escaping @MainActor @Sendable (String?) -> Void,
                post: @escaping @MainActor @Sendable (Any, [NSAccessibility.NotificationUserInfoKey: Any]) -> Void) {
        self.setBadge = setBadge
        self.post = post
    }

    public static let live = NoticeSystem(
        setBadge: { NSApp.dockTile.badgeLabel = $0 },
        post: { NSAccessibility.post(element: $0, notification: .announcementRequested, userInfo: $1) })
}

public enum Notices {
    /// `badge label`: the Dock tile shows exactly `label`; `nil` clears it.
    @MainActor public static func badge(_ label: String?, _ sys: NoticeSystem = .live) {
        sys.setBadge(label)
    }

    /// The AppKit level for a priority: `low` waits for speech in progress, `high` interrupts it.
    public static func level(_ p: Priority) -> NSAccessibilityPriorityLevel {
        switch p {
        case .low: .low
        case .high: .high
        }
    }

    /// The `userInfo` an announcement of `text` at `priority` is posted with.
    public static func userInfo(_ text: String, _ priority: Priority) -> [NSAccessibility.NotificationUserInfoKey: Any] {
        [.announcement: text, .priority: NSNumber(value: level(priority).rawValue)]
    }

    /// `announce text priority`: one `announcementRequested` notification carrying exactly
    /// `text`, posted for `element` (the window, or the app when there is none).
    @MainActor public static func announce(_ text: String, _ priority: Priority, element: Any,
                                           _ sys: NoticeSystem = .live) {
        sys.post(element, userInfo(text, priority))
    }
}

import AppKit
import CairnFrame

/// Keeps the app's window at least the content size the app asks for (`App.minSize`, carried
/// by the frame's window record): trusted claim ^1010, docs/trusted.md. AppKit's
/// `contentMinSize` stops a person dragging the window smaller; as the window's delegate this
/// also clamps every live resize AppKit proposes, and a window already smaller than a new
/// minimum grows to it, keeping its top-left corner where it was.
@MainActor
public final class WindowSizer: NSObject, NSWindowDelegate {
    /// The minimum last applied, in points (negative sizes are taken as 0).
    public private(set) var minimum = NSSize.zero

    override public init() {}

    static func clamp(_ s: Size) -> NSSize { NSSize(width: CGFloat(max(0, s.w)), height: CGFloat(max(0, s.h))) }

    /// Takes the window record's minimum: sets `contentMinSize` and grows the window if its
    /// content is smaller. Does nothing when neither changes.
    public func apply(_ min: Size, to window: NSWindow) {
        let m = Self.clamp(min)
        if window.contentMinSize != m { window.contentMinSize = m }
        minimum = m
        let content = window.contentRect(forFrameRect: window.frame)
        guard content.width < m.width || content.height < m.height else { return }
        let size = NSSize(width: max(content.width, m.width), height: max(content.height, m.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: content.origin, size: size))
        frame.origin.y = window.frame.maxY - frame.height  // keep the top edge (AppKit's y is up)
        window.setFrame(frame, display: window.isVisible)
    }

    /// A live resize: the proposed frame size, grown so the content is at least the minimum.
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard content.width < minimum.width || content.height < minimum.height else { return frameSize }
        let size = NSSize(width: max(content.width, minimum.width), height: max(content.height, minimum.height))
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }
}

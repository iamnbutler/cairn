import AppKit
import CairnFrame
import QuartzCore

/// The window's only view. It turns AppKit input into `Event`s for the engine, hosts the Metal
/// layer the render thread paints, and answers AppKit (text input, accessibility, cursor) from
/// the last published frame. It never calls Lean and never waits for it.
public final class HostView: NSView {
    public let engine: Engine
    let metalLayer = CAMetalLayer()
    private let renderLoop: RenderLoop
    let mirror = AXMirror()
    private let hop = MainHop()

    /// The last frame the main thread has applied (AX, cursor, text input).
    public private(set) var shown: Published?
    /// The focused field as the input system sees it, ahead of Lean by the edits in flight.
    public internal(set) var textShadow = TextInputShadow()
    /// Every time the shadow's prediction disagreed with Lean (most recent last, capped).
    public private(set) var shadowDivergences: [ShadowDivergence] = []
    /// Runs before each effect; returning true means it was handled and the host's own handling is
    /// skipped. The debug socket uses it to record effects and keep them off the user's clipboard
    /// and speakers (docs/conformance.md).
    public var effectHook: ((Effect) -> Bool)?
    /// The pasteboard `setClipboard` writes and Paste reads: the general one, or a private one
    /// under the debug socket.
    public var pasteboard: NSPasteboard = .general
    /// Runs after each applied frame, with it: the app's other surfaces follow it (`SurfaceHost`).
    public var onApply: ((Frame) -> Void)?
    private var scroll = ScrollAccumulator()
    private var cursor: Cursor = .arrow
    private var tracking: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []

    public init(engine: Engine, renderer: FrameRenderer, size: NSSize) {
        self.engine = engine
        renderLoop = RenderLoop(engine: engine, renderer: renderer, layer: metalLayer,
                                viewport: Viewport(size: size, scale: 2))
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        renderer.configure(metalLayer)
        metalLayer.contentsGravity = .topLeft  // a stale drawable during live resize isn't stretched
        metalLayer.isOpaque = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)  // frame colours are sRGB
        let hop = self.hop
        engine.onPublish = { [weak self] _ in
            hop.request { self?.applyLatestFrame() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { renderLoop.stop() }

    public override var isFlipped: Bool { true }
    public override func makeBackingLayer() -> CALayer { metalLayer }
    public override var acceptsFirstResponder: Bool { true }
    public override var isOpaque: Bool { true }

    // MARK: Window, size and scale

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        updateViewport()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.send([.windowFocus(true)]) }
        })
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.send([.windowFocus(false)]) }
        })
        renderLoop.start(link: displayLink(target: renderLoop, selector: #selector(RenderLoop.tick)))
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let old = logicalSize
        super.setFrameSize(newSize)
        if logicalSize != old {
            updateViewport(seq: send([.resize(logicalSize)]))
        }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateViewport(seq: send([.scale(percent: Self.percent(window?.backingScaleFactor ?? 2))]))
    }

    static func percent(_ scale: CGFloat) -> UInt32 { UInt32((scale * 100).rounded()) }

    var logicalSize: Size { Size(w: Int32(bounds.width.rounded(.down)), h: Int32(bounds.height.rounded(.down))) }

    /// `seq`: the event that tells Lean about this size; frames before it are drawn only if
    /// the wait gets long (the live-resize policy in docs/host.md).
    private func updateViewport(seq: UInt64? = nil) {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        renderLoop.setViewport(Viewport(size: bounds.size, scale: scale), seq: seq)
    }

    // MARK: Sending

    /// Enqueues events for Lean; returns the last one's sequence number.
    @discardableResult
    func send(_ events: [Event], time: Double = hostNow()) -> UInt64 {
        engine.send(events, time: time)
    }

    /// Sends events that may change the focused field in ways the shadow doesn't model.
    @discardableResult
    func sendEditing(_ events: [Event], time: Double = hostNow()) -> UInt64 {
        let seq = engine.send(events, time: time)
        textShadow.taint(seq: seq)
        return seq
    }

    func recordDivergence(_ d: ShadowDivergence) {
        shadowDivergences.append(d)
        if shadowDivergences.count > 100 { shadowDivergences.removeFirst() }
        FileHandle.standardError.write("cairn: text input shadow diverged \(d)\n".data(using: .utf8)!)
    }

    private func point(_ e: NSEvent) -> Point { point(convert(e.locationInWindow, from: nil)) }
    private func point(_ p: NSPoint) -> Point { Point(x: Int32(p.x.rounded(.down)), y: Int32(p.y.rounded(.down))) }

    /// AppKit stamps events with seconds since boot, the same clock as `hostNow()`.
    private func time(_ e: NSEvent) -> Double { e.timestamp > 0 ? min(e.timestamp, hostNow()) : hostNow() }

    // MARK: Pointer

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    /// While composing, the input method sees mouse events first (a click can commit or close
    /// the composition). Only then: Korean IMEs swallow every click otherwise.
    private func imeTakes(_ e: NSEvent) -> Bool {
        hasMarkedText() && inputContext?.handleEvent(e) == true
    }

    // Each press is preceded by a move to its point, so Lean's hover is right even when no
    // mouseMoved arrived first (entering from another window, a click-through).
    public override func mouseDown(with e: NSEvent) {
        if imeTakes(e) { return }
        let p = point(e)
        sendEditing([.pointerMove(p), .pointerDown(p, .primary, clicks: UInt32(max(1, e.clickCount)), KeyMapping.mods(e.modifierFlags))], time: time(e))
    }
    public override func mouseUp(with e: NSEvent) {
        if imeTakes(e) { return }
        sendEditing([.pointerUp(point(e), .primary, KeyMapping.mods(e.modifierFlags))], time: time(e))
    }
    public override func rightMouseDown(with e: NSEvent) {
        let p = point(e)
        sendEditing([.pointerMove(p), .pointerDown(p, .secondary, clicks: UInt32(max(1, e.clickCount)), KeyMapping.mods(e.modifierFlags))], time: time(e))
    }
    public override func rightMouseUp(with e: NSEvent) {
        sendEditing([.pointerUp(point(e), .secondary, KeyMapping.mods(e.modifierFlags))], time: time(e))
    }
    public override func mouseMoved(with e: NSEvent) { send([.pointerMove(point(e))], time: time(e)) }
    public override func mouseDragged(with e: NSEvent) {
        if imeTakes(e) { return }
        sendEditing([.pointerMove(point(e))], time: time(e))  // a drag can select text
    }
    public override func flagsChanged(with e: NSEvent) {
        if hasMarkedText() { _ = inputContext?.handleEvent(e) }  // some IMEs commit on a modifier
        super.flagsChanged(with: e)
    }
    public override func rightMouseDragged(with e: NSEvent) { send([.pointerMove(point(e))], time: time(e)) }
    public override func mouseEntered(with e: NSEvent) { send([.pointerMove(point(e))], time: time(e)) }
    public override func mouseExited(with e: NSEvent) { send([.pointerExit], time: time(e)) }

    public override func scrollWheel(with e: NSEvent) {
        if e.phase == .began || e.phase == .mayBegin { scroll.reset() }
        guard let d = scroll.add(deltaX: e.scrollingDeltaX, deltaY: e.scrollingDeltaY, precise: e.hasPreciseScrollingDeltas)
        else { return }
        send([.scroll(point(e), dx: d.dx, dy: d.dy)], time: time(e))
    }

    /// A click at a node's centre, for accessibility presses: it goes through Lean's hit testing
    /// like any other click. The pointer is then put back where the mouse really is.
    func click(at rect: Rect) {
        let c = Point(x: rect.x + rect.w / 2, y: rect.y + rect.h / 2)
        var events: [Event] = [.pointerMove(c), .pointerDown(c, .primary, clicks: 1, Mods()), .pointerUp(c, .primary, Mods())]
        if let w = window {
            let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
            events.append(bounds.contains(p) ? .pointerMove(point(p)) : .pointerExit)
        }
        sendEditing(events)
    }

    // MARK: Cursor

    public override func resetCursorRects() { addCursorRect(bounds, cursor: Self.nsCursor(cursor)) }
    public override func cursorUpdate(with event: NSEvent) { Self.nsCursor(cursor).set() }

    static func nsCursor(_ c: Cursor) -> NSCursor {
        switch c {
        case .arrow: .arrow
        case .pointer: .pointingHand
        case .text: .iBeam
        }
    }

    private func setCursor(_ c: Cursor) {
        guard c != cursor else { return }
        cursor = c
        window?.invalidateCursorRects(for: self)
        if let w = window, bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) {
            Self.nsCursor(c).set()
        }
    }

    // MARK: Keys

    /// Whether keys go through the input system: the shadow has a focused field (it leads the
    /// frame while edits are in flight).
    var textActive: Bool { textShadow.state != nil }

    public override var inputContext: NSTextInputContext? { textActive ? super.inputContext : nil }

    public override func keyDown(with e: NSEvent) {
        // A shortcut the main menu owns arrives here only when its item didn't take it (say,
        // Paste with nothing to paste); it was the menu's, so it isn't also a key for Lean.
        if Self.menuOwns(e) { return }
        if textActive {
            currentKeyEvent = e  // the original event: rebuilt ones break Korean input
            interpretKeyEvents([e])
            currentKeyEvent = nil
        } else {
            // Every character, not just the first: a synthesized event can carry a whole string.
            let evs = KeyMapping.keys(keyCode: e.keyCode, charactersIgnoringModifiers: e.charactersIgnoringModifiers,
                                      mods: KeyMapping.mods(e.modifierFlags))
            if !evs.isEmpty { sendEditing(evs, time: time(e)) }
        }
    }

    var currentKeyEvent: NSEvent?

    /// Whether a main-menu item has this key equivalent (with these modifiers).
    static func menuOwns(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods.contains(.command) || mods.contains(.control), let menu = NSApp.mainMenu,
              let key = e.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return false }
        func search(_ m: NSMenu) -> Bool {
            m.items.contains { item in
                if let sub = item.submenu, search(sub) { return true }
                return item.keyEquivalent.lowercased() == key
                    && item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                        .subtracting(.shift) == mods.subtracting(.shift)
            }
        }
        return search(menu)
    }

    // MARK: Edit menu

    // Always enabled: the frame says nothing about what can be copied or undone, so Lean ignores
    // what doesn't apply (docs/trusted.md).
    @objc func copy(_ sender: Any?) { sendEditing([.copy]) }
    @objc func cut(_ sender: Any?) { sendEditing([.cut]) }
    @objc func paste(_ sender: Any?) {
        sendEditing([.paste(pasteboard.string(forType: .string) ?? "")])
    }
    public override func selectAll(_ sender: Any?) { sendEditing([.selectAll]) }
    @objc func undo(_ sender: Any?) { sendEditing([.undo]) }
    @objc func redo(_ sender: Any?) { sendEditing([.redo]) }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(paste(_:)), #selector(copy(_:)), #selector(cut(_:)), #selector(selectAll(_:)),
             #selector(undo(_:)), #selector(redo(_:)): true
        default: true
        }
    }

    // MARK: Frames

    /// On the main thread, after one or more frames were published. Tools and tests that run
    /// without a run loop call it directly.
    public func applyLatestFrame() {
        guard let p = engine.latest else { return }
        let previous = shown
        shown = p
        for effect in engine.takeEffects() { run(effect) }
        setCursor(p.frame.cursor)
        textInputDidChange(p, previousFrame: previous?.frame.textInput)
        mirror.update(p.frame, host: self)
        onApply?(p.frame)
    }

    private func run(_ effect: Effect) {
        if effectHook?(effect) == true { return }
        switch effect {
        case .setClipboard(let s):
            pasteboard.clearContents()
            pasteboard.setString(s, forType: .string)
        case .beep:
            NSSound.beep()
        case .focus:
            break  // Lean's runtime already moved the focus (docs/runtime.md)
        case .setTimer, .cancelTimer:
            break  // Lean's runtime keeps the timers; the frame's `wake` drives the clock
        case .request, .cancelRequest:
            break  // the engine's World already ran it (docs/effects.md)
        case .quit:
            NSApp.terminate(nil)
        }
    }

    // MARK: Accessibility

    public override func isAccessibilityElement() -> Bool { false }
    public override func accessibilityChildren() -> [Any]? { onMain(nil) { mirror.roots } }
    public override var accessibilityFocusedUIElement: Any? { onMain(self) { mirror.focused ?? self } }
    public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        onMain(nil) { mirror.hitTest(screenPoint: point) } ?? super.accessibilityHitTest(point)
    }

    /// A rect in this view's logical points, in screen coordinates (y up), for AX and IME.
    func screenRect(_ r: CGRect) -> CGRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(r, to: nil))
    }
}

/// Hops from the Lean thread to the main thread at most once per run-loop turn, however many
/// frames are published meanwhile (the main thread always reads the newest).
final class MainHop: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled = false

    func request(_ body: @escaping @MainActor () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [self] in
            lock.lock()
            scheduled = false
            lock.unlock()
            MainActor.assumeIsolated { body() }
        }
    }
}

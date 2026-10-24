import AppKit
import CairnFrame
import QuartzCore

/// The app's surfaces other than its window (docs/surfaces.md): menu bar status items with
/// native menus, and overlay panels drawn by Metal. Each frame's surface records are applied
/// here, matched by place claim, on the main thread (`HostView.onApply`).
///
/// The host decides nothing about the app: a menu shows exactly the frame's records, a chosen
/// item is reported with its ref whether or not it is enabled (Lean's runtime ignores a stale
/// choice, `Runtime.menu_select_stale`), and a panel is placed where its anchor says. What it
/// trusts AppKit for is listed in docs/trusted.md (^940–^944).
@MainActor
public final class SurfaceHost {
    public enum Mode: Sendable {
        /// Status items in the menu bar, panels on screen.
        case live
        /// Nothing reaches the screen: menus are built but not attached to a status item, and
        /// panels are made but never ordered front. For the debug socket, self tests and the
        /// trusted-base fuzzer, which drive the menus through the same objects.
        case detached
    }

    public let mode: Mode
    private let send: ([Event]) -> UInt64
    private let makeRenderer: () -> FrameRenderer
    private let engine: Engine?
    public private(set) var statuses: [UInt32: StatusHost] = [:]
    public private(set) var panels: [UInt32: PanelHost] = [:]
    /// The surfaces of the last applied frame, in the app's order.
    public private(set) var surfaces: [Surface] = []

    /// `send` enqueues events for Lean and returns the last one's sequence number.
    public init(mode: Mode, engine: Engine?, send: @escaping ([Event]) -> UInt64,
                makeRenderer: @escaping () -> FrameRenderer) {
        self.mode = mode
        self.engine = engine
        self.send = send
        self.makeRenderer = makeRenderer
    }

    public convenience init(engine: Engine, mode: Mode, makeRenderer: @escaping () -> FrameRenderer) {
        self.init(mode: mode, engine: engine, send: { engine.send($0) }, makeRenderer: makeRenderer)
    }

    public func apply(_ frame: Frame) {
        surfaces = frame.surfaces
        for s in frame.surfaces {
            switch s.kind {
            case .window:
                break  // HostView's
            case .statusItem:
                let h = statuses[s.place] ?? {
                    let h = StatusHost(place: s.place, live: mode == .live, send: send)
                    statuses[s.place] = h
                    return h
                }()
                h.update(s)
            case .panel:
                let h = panels[s.place] ?? {
                    let h = PanelHost(place: s.place, live: mode == .live, engine: engine, makeRenderer: makeRenderer)
                    panels[s.place] = h
                    return h
                }()
                h.update(s)
            }
        }
    }

    /// The menu of the status item at `place`, or of the first status item.
    public func menu(_ place: UInt32? = nil) -> MenuHost? {
        if let place { return statuses[place]?.menu }
        return surfaces.first { $0.kind == .statusItem }.flatMap { statuses[$0.place]?.menu }
    }
}

// MARK: Menus

/// A chosen item's ref, carried by its `NSMenuItem`.
final class RefBox: NSObject {
    let ref: ControlRef
    init(_ ref: ControlRef) { self.ref = ref }
}

/// One native menu tree, built from a status item's menu records (`Frame.ofMenu`: flattened,
/// parents first) and updated in place: a menu whose items keep their kinds keeps its
/// `NSMenuItem`s (so an open menu updates under the pointer); one whose shape changed is rebuilt.
@MainActor
public final class MenuHost: NSObject, NSMenuDelegate {
    public let place: UInt32
    public let root = NSMenu()
    private let send: ([Event]) -> UInt64
    public private(set) var records: [MenuRecord] = []
    /// How many menus (the root or a submenu) were rebuilt rather than updated in place.
    public private(set) var rebuilds = 0
    /// The sequence number of the last event this menu sent.
    public private(set) var lastSeq: UInt64 = 0

    public init(place: UInt32, send: @escaping ([Event]) -> UInt64) {
        self.place = place
        self.send = send
        super.init()
        root.autoenablesItems = false
        root.delegate = self
    }

    public func update(_ records: [MenuRecord]) {
        self.records = records
        var kids: [Int?: [Int]] = [:]
        for (i, r) in records.enumerated() { kids[r.parent, default: []].append(i) }
        sync(root, kids[nil] ?? [], kids)
    }

    private enum Shape { case separator, submenu, item }
    private static func shape(_ r: MenuRecord) -> Shape {
        switch r.kind {
        case .separator: .separator
        case .submenu: .submenu
        case .item, .info: .item
        }
    }
    private static func shape(_ item: NSMenuItem) -> Shape {
        item.isSeparatorItem ? .separator : item.submenu != nil ? .submenu : .item
    }

    private func sync(_ menu: NSMenu, _ idxs: [Int], _ kids: [Int?: [Int]]) {
        let same = menu.items.count == idxs.count
            && zip(menu.items, idxs).allSatisfy { Self.shape($0) == Self.shape(records[$1]) }
        if !same {
            menu.removeAllItems()
            for i in idxs { menu.addItem(records[i].kind == .separator ? .separator() : NSMenuItem()) }
            rebuilds += 1
        }
        for (item, i) in zip(menu.items, idxs) { configure(item, i, kids) }
    }

    private func configure(_ item: NSMenuItem, _ i: Int, _ kids: [Int?: [Int]]) {
        let r = records[i]
        if r.kind == .separator { return }
        if item.title != r.label { item.title = r.label }
        switch r.kind {
        case .item where r.control != nil:
            let ref = r.control!
            item.target = self
            item.action = #selector(choose(_:))
            if (item.representedObject as? RefBox)?.ref != ref { item.representedObject = RefBox(ref) }
            item.identifier = NSUserInterfaceItemIdentifier(ref.label)
            item.isEnabled = r.enabled
            item.state = r.checked == true ? .on : .off
            let (key, mask) = r.shortcut.map(Self.keyEquivalent) ?? ("", [])
            if item.keyEquivalent != key { item.keyEquivalent = key }
            item.keyEquivalentModifierMask = mask
        case .submenu:
            let sub = item.submenu ?? {
                let m = NSMenu(title: r.label)
                m.autoenablesItems = false
                item.submenu = m
                return m
            }()
            sub.title = r.label
            item.identifier = r.place.map { NSUserInterfaceItemIdentifier("^\($0)") }
            item.isEnabled = r.enabled
            sync(sub, kids[i] ?? [], kids)
        default:
            // A status line (or an item without a control, which Lean never makes): shown, not
            // actionable.
            item.target = nil
            item.action = nil
            item.representedObject = nil
            item.identifier = nil
            item.isEnabled = false
            item.state = .off
            item.keyEquivalent = ""
        }
    }

    /// An item was chosen: report its ref. Lean checks it against the menu it is showing.
    @objc public func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? RefBox else { return }
        lastSeq = send([.menuSelect(place: place, box.ref)])
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === root else { return }
        lastSeq = send([.menuOpen(place: place)])
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === root else { return }
        lastSeq = send([.menuClose(place: place)])
    }

    /// The menu item `id` (a ref's label, `^N` or `^N#K`, or a submenu's `^P`) and its menu.
    public func find(_ id: String) -> (NSMenu, Int)? {
        func go(_ m: NSMenu) -> (NSMenu, Int)? {
            for (i, item) in m.items.enumerated() {
                if item.identifier?.rawValue == id { return (m, i) }
                if let sub = item.submenu, let hit = go(sub) { return hit }
            }
            return nil
        }
        return go(root)
    }

    /// A shortcut as a key equivalent: the character AppKit matches and the modifier mask.
    public static func keyEquivalent(_ s: Shortcut) -> (String, NSEvent.ModifierFlags) {
        func fn(_ k: Int) -> String { String(Character(Unicode.Scalar(UInt32(k))!)) }
        let key: String = switch s.key {
        case .enter: "\r"
        case .escape: "\u{1b}"
        case .tab: "\t"
        case .backspace: "\u{8}"
        case .delete: fn(NSDeleteFunctionKey)
        case .left: fn(NSLeftArrowFunctionKey)
        case .right: fn(NSRightArrowFunctionKey)
        case .up: fn(NSUpArrowFunctionKey)
        case .down: fn(NSDownArrowFunctionKey)
        case .home: fn(NSHomeFunctionKey)
        case .finish: fn(NSEndFunctionKey)
        case .pageUp: fn(NSPageUpFunctionKey)
        case .pageDown: fn(NSPageDownFunctionKey)
        case let .char(c): String(c).lowercased()
        }
        var mask: NSEvent.ModifierFlags = []
        if s.mods.command { mask.insert(.command) }
        if s.mods.shift { mask.insert(.shift) }
        if s.mods.option { mask.insert(.option) }
        if s.mods.control { mask.insert(.control) }
        return (key, mask)
    }
}

/// A status item: its button in the menu bar (when live) and its menu.
@MainActor
public final class StatusHost {
    public let place: UInt32
    public let menu: MenuHost
    public private(set) var item: NSStatusItem?
    public private(set) var status = StatusFrame()
    public private(set) var shown = false
    private let live: Bool
    private var missingSymbol: String?

    init(place: UInt32, live: Bool, send: @escaping ([Event]) -> UInt64) {
        self.place = place
        self.live = live
        menu = MenuHost(place: place, send: send)
    }

    func update(_ s: Surface) {
        shown = s.shown
        menu.update(s.status.menu)
        let old = status
        status = s.status
        guard live else { return }
        if item == nil {
            let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            it.menu = menu.root
            item = it
        }
        guard let item, let button = item.button else { return }
        // Every write below, even of an unchanged value, makes AppKit redraw the status item's
        // replicants in the menu bar (-[NSStatusItem _updateReplicants]); frames arrive at up to
        // 50 a second while recording, so write only what changed (yap-cairn's bench/yap-instruments.md).
        if item.isVisible != s.shown { item.isVisible = s.shown }
        if old.symbol != status.symbol || button.image == nil && !status.symbol.isEmpty {
            let image = status.symbol.isEmpty ? nil
                : NSImage(systemSymbolName: status.symbol, accessibilityDescription: status.label)
            image?.isTemplate = true
            if image == nil, !status.symbol.isEmpty, missingSymbol != status.symbol {
                missingSymbol = status.symbol
                FileHandle.standardError.write("cairn: no SF Symbol named \(status.symbol)\n".data(using: .utf8)!)
            }
            button.image = image
        }
        if button.title != status.title { button.title = status.title }
        let position: NSControl.ImagePosition = status.title.isEmpty ? .imageOnly : .imageLeading
        if button.imagePosition != position { button.imagePosition = position }
        if button.accessibilityLabel() != status.label { button.setAccessibilityLabel(status.label) }
        let id = NSUserInterfaceItemIdentifier(status.control.label)
        if button.identifier != id { button.identifier = id }
    }
}

// MARK: Panels

/// A panel that never becomes key or main: AppKit never gives it the keyboard, so showing it
/// never takes focus from the app the person is using.
public final class OverlayPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// One overlay panel (docs/surfaces.md, "Overlay panel"): non-activating, never key,
/// click-through, at status-bar level, on every Space and over full-screen apps; drawn by Metal
/// from the panel's canvas with a transparent clear colour. Hiding fades it out (a host-only
/// look, decision 6).
@MainActor
public final class PanelHost {
    public let place: UInt32
    public let panel: OverlayPanel
    /// Whether the frame says the panel is shown (what Lean asked for, ahead of any fade).
    public private(set) var visible = false
    public private(set) var canvas: Canvas = .empty
    public private(set) var anchor: Anchor = .bottomCenter(offset: 0)
    /// The screen's visible frame the panel was placed in when it was shown.
    public private(set) var screenFrame: CGRect?
    private let live: Bool
    private let content: PanelContentView?
    static let fade = 0.18

    public static let behavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    init(place: UInt32, live: Bool, engine: Engine?, makeRenderer: () -> FrameRenderer) {
        self.place = place
        self.live = live
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false  // explicitly: an accessory app is never active
        panel.collectionBehavior = Self.behavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityRole(.group)
        if live, let engine {
            let v = PanelContentView(engine: engine, place: place, renderer: makeRenderer())
            panel.contentView = v
            content = v
        } else {
            content = nil
        }
    }

    /// Where a panel of `size` goes in a screen's visible frame (y up): horizontally centred,
    /// `offset` points above its bottom, on whole points.
    public static func placement(visible vf: CGRect, size: Size, anchor: Anchor) -> CGRect {
        let w = CGFloat(max(0, size.w)), h = CGFloat(max(0, size.h))
        switch anchor {
        case let .bottomCenter(offset):
            return CGRect(x: (vf.midX - w / 2).rounded(.down), y: (vf.minY + CGFloat(offset)).rounded(.down),
                          width: w, height: h)
        }
    }

    /// Benchmarks only (yap-cairn's tools/bench/): put every panel on `NSScreen.screens[i]` whatever the
    /// frame chose, so runs compared with each other draw on the same display.
    public static var benchScreen: Int?

    /// The screen a panel shown now goes on.
    static func screen(_ choice: ScreenChoice) -> NSScreen? {
        if let i = benchScreen, NSScreen.screens.indices.contains(i) { return NSScreen.screens[i] }
        switch choice {
        case .pointer:
            let p = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
        case .main:
            return NSScreen.main
        }
    }

    func update(_ s: Surface) {
        let want = s.shown && s.canvas.size.w > 0 && s.canvas.size.h > 0
        let resized = s.canvas.size != canvas.size || s.anchor != anchor
        canvas = s.canvas
        anchor = s.anchor
        panel.title = s.title
        panel.setAccessibilityLabel(s.title)
        if want {
            if !visible {
                visible = true
                // The screen is chosen when the panel appears and kept until it is hidden.
                screenFrame = Self.screen(s.screen)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
                reposition()
                if live {
                    panel.alphaValue = 1
                    panel.orderFrontRegardless()
                }
            } else if resized {
                reposition()
            }
            content?.update(size: s.canvas.size)
        } else if visible {
            visible = false
            screenFrame = nil
            guard live else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.fade
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.visible else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    private func reposition() {
        guard let vf = screenFrame else { return }
        let r = Self.placement(visible: vf, size: canvas.size, anchor: anchor)
        if panel.frame != r { panel.setFrame(r, display: false) }
    }
}

/// A panel's content: a Metal layer painted by its own render thread from the panel's canvas.
final class PanelContentView: NSView {
    let metalLayer = CAMetalLayer()
    private let renderLoop: RenderLoop
    private var started = false

    init(engine: Engine, place: UInt32, renderer: FrameRenderer) {
        renderLoop = RenderLoop(engine: engine, renderer: renderer, layer: metalLayer,
                                viewport: Viewport(size: CGSize(width: 1, height: 1), scale: 2),
                                reportsPresented: false) { p in
            guard let s = p.frame.surfaces.first(where: { $0.place == place && $0.kind == .panel }), s.shown
            else { return nil }
            return Frame(size: s.canvas.size, draws: s.canvas.draws)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        renderer.configure(metalLayer)
        metalLayer.isOpaque = false  // the clear colour is transparent; blending is premultiplied
        metalLayer.contentsGravity = .topLeft
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { renderLoop.stop() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func makeBackingLayer() -> CALayer { metalLayer }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !started else { return }
        started = true
        renderLoop.start(link: displayLink(target: renderLoop, selector: #selector(RenderLoop.tick)),
                         maxFps: Self.maxFps)
    }

    /// A panel draws at most 60 frames a second, as the original Yap's overlay does (its
    /// `MTKView.preferredFramesPerSecond = 60`, App/Overlay.swift): on a 120 Hz display an
    /// animated `paint` would otherwise draw every refresh and queue up behind its own
    /// drawables (yap-cairn's bench/yap-instruments.md, "120 Hz").
    static let maxFps: Float = 60

    func update(size: Size) {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        renderLoop.setViewport(Viewport(size: CGSize(width: CGFloat(size.w), height: CGFloat(size.h)), scale: scale), seq: nil)
    }
}

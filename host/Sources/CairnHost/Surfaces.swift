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
    /// The app's own menus in the menu bar, if it has any (`Surface.menuBar`).
    public private(set) var bar: MenuBarHost?
    /// The main menu the bar's menus go in: `NSApp.mainMenu` when live (none for an accessory
    /// app), else a copy of the host's main menu that never reaches the screen.
    public var mainMenu: NSMenu?
    /// The surfaces of the last applied frame, in the app's order.
    public private(set) var surfaces: [Surface] = []

    /// `send` enqueues events for Lean and returns the last one's sequence number.
    public init(mode: Mode, engine: Engine?, send: @escaping ([Event]) -> UInt64,
                makeRenderer: @escaping () -> FrameRenderer) {
        self.mode = mode
        self.engine = engine
        self.send = send
        self.makeRenderer = makeRenderer
        if mode == .detached { mainMenu = CairnApp.menu(title: "App", install: false) }
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
            case .menuBar:
                let main = mode == .live ? NSApp.mainMenu : mainMenu
                guard let main else { continue }  // an accessory app has no main menu
                if bar == nil || bar!.place != s.place || bar!.main !== main {
                    bar?.remove()
                    bar = MenuBarHost(place: s.place, main: main, send: send)
                }
                bar!.update(s.status.menu)
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
    /// The record's enabled flag, for menus that validate their items (`validateMenuItem`).
    var enabled = true
    init(_ ref: ControlRef) { self.ref = ref }
}

/// One native menu tree, built from a status item's menu records (`Frame.ofMenu`: flattened,
/// parents first) and updated in place: a menu whose items keep their kinds keeps its
/// `NSMenuItem`s (so an open menu updates under the pointer); one whose shape changed is rebuilt.
@MainActor
public class MenuHost: NSObject, NSMenuDelegate, NSMenuItemValidation {
    public let place: UInt32
    public let root = NSMenu()
    private let send: ([Event]) -> UInt64
    public private(set) var records: [MenuRecord] = []
    /// How many menus (the root or a submenu) were rebuilt rather than updated in place.
    public private(set) var rebuilds = 0
    /// The sequence number of the last event this menu sent.
    public private(set) var lastSeq: UInt64 = 0
    /// Whether opening and closing the root is reported (`menuOpen`, `menuClose`): a status
    /// item's menu does; a control's menu reports its close itself (`ControlMenuHost`), and the
    /// menu bar's menus report neither.
    let reportsOpenClose: Bool

    public init(place: UInt32, reportsOpenClose: Bool = true, send: @escaping ([Event]) -> UInt64) {
        self.place = place
        self.send = send
        self.reportsOpenClose = reportsOpenClose
        super.init()
        root.autoenablesItems = false
        root.delegate = self
    }

    public func update(_ records: [MenuRecord]) {
        self.records = records
        let kids = Self.children(records)
        sync(root, kids[nil] ?? [], kids)
    }

    func setRecords(_ records: [MenuRecord]) { self.records = records }

    static func children(_ records: [MenuRecord]) -> [Int?: [Int]] {
        var kids: [Int?: [Int]] = [:]
        for (i, r) in records.enumerated() { kids[r.parent, default: []].append(i) }
        return kids
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
        sync(menu, at: 0, replacing: menu.items.count, idxs, kids)
    }

    /// Syncs the `count` items of `menu` from `start` with the records `idxs` (the rest of the
    /// menu is someone else's: the host's own items in the app menu and the menu bar).
    func sync(_ menu: NSMenu, at start: Int, replacing count: Int, _ idxs: [Int], _ kids: [Int?: [Int]]) {
        let old = Array(menu.items[start..<start + count])
        let same = old.count == idxs.count
            && zip(old, idxs).allSatisfy { Self.shape($0) == Self.shape(records[$1]) }
        if !same {
            for _ in 0..<count { menu.removeItem(at: start) }
            for (k, i) in idxs.enumerated() {
                menu.insertItem(records[i].kind == .separator ? .separator() : NSMenuItem(), at: start + k)
            }
            rebuilds += 1
        }
        for (k, i) in idxs.enumerated() { configure(menu.items[start + k], i, kids) }
    }

    func configure(_ item: NSMenuItem, _ i: Int, _ kids: [Int?: [Int]]) {
        let r = records[i]
        if r.kind == .separator { return }
        if item.title != r.label { item.title = r.label }
        switch r.kind {
        case .item where r.control != nil:
            let ref = r.control!
            item.target = self
            item.action = #selector(choose(_:))
            if (item.representedObject as? RefBox)?.ref != ref { item.representedObject = RefBox(ref) }
            (item.representedObject as? RefBox)?.enabled = r.enabled
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

    /// An item in a menu that validates its items (the host's app menu, where the app's own
    /// items go, has `autoenablesItems` on) is enabled as its record says, not because this host
    /// answers its action (found by cairn-fuzz-trusted, `menubar.select`: a greyed item's key
    /// equivalent was performed).
    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        (item.representedObject as? RefBox)?.enabled ?? false
    }

    /// An item was chosen: report its ref. Lean checks it against the menu it is showing.
    @objc public func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? RefBox else { return }
        lastSeq = send([.menuSelect(place: place, box.ref)])
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard reportsOpenClose, menu === root else { return }
        lastSeq = send([.menuOpen(place: place)])
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard reportsOpenClose, menu === root else { return }
        lastSeq = send([.menuClose(place: place)])
    }

    /// The menu item `id` (a ref's label, `^N` or `^N#K`, or a submenu's `^P`) and its menu.
    public func find(_ id: String) -> (NSMenu, Int)? { Self.find(id, in: root) }

    public static func find(_ id: String, in m: NSMenu) -> (NSMenu, Int)? {
        for (i, item) in m.items.enumerated() {
            if item.identifier?.rawValue == id { return (m, i) }
            if let sub = item.submenu, let hit = find(id, in: sub) { return hit }
        }
        return nil
    }

    /// A shortcut as a key equivalent: the character AppKit matches and the modifier mask. A
    /// letter with shift is the capital: AppKit matches a key equivalent against the event's
    /// `charactersIgnoringModifiers`, which keeps shift (⇧⌘A gives "A"), so a lower-case "a" with
    /// the shift mask never matches (found by cairn-fuzz-trusted, `menubar.select`).
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
        case let .char(c): s.mods.shift && c.isLetter ? String(c).uppercased() : String(c).lowercased()
        case .menu: fn(NSF10FunctionKey)
        }
        var mask: NSEvent.ModifierFlags = []
        if s.mods.command { mask.insert(.command) }
        if s.mods.shift { mask.insert(.shift) }
        if s.mods.option { mask.insert(.option) }
        if s.mods.control { mask.insert(.control) }
        return (key, mask)
    }
}

/// The app's own menus (docs/surfaces.md, "The app's menus"), from a `menuBar` surface's items:
/// each top-level submenu is a menu in the menu bar, before the host's Window menu; every other
/// top-level entry goes in the app menu, above the host's Hide and Quit, with a separator after
/// them. The host's own items stay the host's. Chosen items, by click or key equivalent, are
/// reported as `menuSelect(place, ref)`, as a status item's are.
@MainActor
public final class MenuBarHost: MenuHost {
    /// The main menu the items go in.
    public private(set) weak var main: NSMenu?
    /// How many items this host put at the top of the app menu (and whether a separator follows).
    public private(set) var appCount = 0
    private var appSeparator = false
    /// How many menus this host put in the menu bar.
    public private(set) var barCount = 0

    init(place: UInt32, main: NSMenu, send: @escaping ([Event]) -> UInt64) {
        self.main = main
        super.init(place: place, reportsOpenClose: false, send: send)
    }

    /// The app menu: the main menu's first item's submenu.
    var appMenu: NSMenu? { main?.items.first?.submenu }

    /// Where the bar's menus start: before the Window menu, else at the end.
    private func barStart(_ main: NSMenu) -> Int {
        let window = main.items.firstIndex { $0.submenu != nil && $0.submenu?.title == "Window" }
        return (window ?? main.items.count) - barCount
    }

    public override func update(_ records: [MenuRecord]) {
        guard let main, let app = appMenu else { return }
        let kids = Self.children(records)
        setRecords(records)
        let top = kids[nil] ?? []
        let menus = top.filter { records[$0].kind == .submenu }
        let items = top.filter { records[$0].kind != .submenu }
        if appSeparator { app.removeItem(at: appCount); appSeparator = false }
        sync(app, at: 0, replacing: appCount, items, kids)
        appCount = items.count
        if appCount > 0 { app.insertItem(.separator(), at: appCount); appSeparator = true }
        sync(main, at: barStart(main), replacing: barCount, menus, kids)
        barCount = menus.count
    }

    /// This host's items in the main menu: those at the top of the app menu, and its menus in the
    /// menu bar, in order.
    public var own: (app: [NSMenuItem], menus: [NSMenuItem]) {
        guard let main, let app = appMenu else { return ([], []) }
        let start = barStart(main)
        return (Array(app.items.prefix(appCount)), Array(main.items[start..<(start + barCount)]))
    }

    /// Takes this host's items out of the main menu.
    func remove() {
        guard let main, let app = appMenu else { return }
        for _ in 0..<(appCount + (appSeparator ? 1 : 0)) { app.removeItem(at: 0) }
        let start = barStart(main)
        for _ in 0..<barCount { main.removeItem(at: start) }
        appCount = 0; barCount = 0; appSeparator = false
    }

    /// The bar's item `id` (a ref's label or a submenu's `^P`) and its menu, in the main menu.
    public override func find(_ id: String) -> (NSMenu, Int)? {
        guard let main else { return nil }
        return Self.find(id, in: main)
    }
}

/// A control's menu (docs/surfaces.md, "Menus on controls"): when the window's frame says a
/// control's menu is open (the window surface's `status`: the owner and its items), the host
/// pops up a native menu at the control; a chosen item is reported as `menuSelect(window, ref)`
/// and the menu closing, after it, as `menuClose(window)`. When the frame stops showing it (the
/// control or its menu went away) an open menu is dismissed. Lean decides what is open; the
/// host only shows it, and ignores frames from before its own close reached Lean.
@MainActor
public final class ControlMenuHost {
    private let send: ([Event]) -> UInt64
    /// False under the debug socket and in tests: the menu is built but never popped up (it
    /// would block the main thread); a driver chooses items and closes it.
    public var live: Bool
    /// The open menu (its place is the window's), if the last frame shows one.
    public private(set) var menu: MenuHost?
    /// The control whose menu is open.
    public private(set) var owner: ControlRef?
    /// Whether AppKit is tracking the popped-up menu now.
    public private(set) var tracking = false
    /// The point a secondary click opened the menu at, if it did: the menu pops up there.
    var clickPoint: Point?
    /// How many times a menu was popped up (tests).
    public private(set) var popUps = 0
    private var closedThrough: UInt64 = 0
    private var pending = false

    public init(live: Bool, send: @escaping ([Event]) -> UInt64) {
        self.live = live
        self.send = send
    }

    /// The window's surface record from a frame that accounts for events through `seq`.
    public func update(_ window: Surface?, through seq: UInt64, view: HostView?) {
        guard let window, !window.status.menu.isEmpty else {
            if tracking { menu?.root.cancelTracking() }
            owner = nil
            return
        }
        guard seq >= closedThrough else { return }  // still open only because Lean hasn't heard
        if menu == nil || menu!.place != window.place {
            menu = MenuHost(place: window.place, reportsOpenClose: false, send: send)
        }
        if tracking, owner != window.status.control { menu!.root.cancelTracking() }
        menu!.update(window.status.menu)
        owner = window.status.control
        guard live, let view, !tracking, !pending else { return }
        pending = true
        // Not inside the frame's apply: tracking a menu runs a nested event loop.
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view else { return }
            self.pending = false
            self.popUp(in: view)
        }
    }

    private func popUp(in view: HostView) {
        guard let owner, let menu, !tracking, view.window != nil,
              let node = view.shown?.frame.ax.first(where: { $0.control == owner }) else { return }
        let r = node.rect
        let at: NSPoint
        if let p = clickPoint, r.x <= p.x, p.x < r.x + r.w, r.y <= p.y, p.y < r.y + r.h {
            at = NSPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        } else {
            at = NSPoint(x: CGFloat(r.x), y: CGFloat(r.y + r.h) + 4)  // below the control (flipped view)
        }
        clickPoint = nil
        tracking = true
        popUps += 1
        // A chosen item's action is sent before this returns, so the selection reaches Lean
        // before the close.
        menu.root.popUp(positioning: nil, at: at, in: view)
        tracking = false
        close()
    }

    /// The menu closed: tell Lean, and show no open menu from frames before it heard.
    @discardableResult
    public func close() -> UInt64 {
        guard let menu else { return 0 }
        let seq = send([.menuClose(place: menu.place)])
        closedThrough = seq
        owner = nil
        return seq
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

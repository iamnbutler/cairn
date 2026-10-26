import AppKit
import CairnFrame
import CairnHost
import Foundation

/// A core that shows whatever frame the suite gives it and records every event it is stepped
/// with.
final class RecordingCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Frame(size: Size(w: 10, h: 10), draws: [])
    private var seen: [Event] = []
    func set(_ f: Frame) { lock.withLock { current = f } }
    func take() -> [Event] { lock.withLock { defer { seen = [] }; return seen } }
    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) { lock.withLock { seen.append(contentsOf: events) } }
    func frame() throws -> Frame { lock.withLock { current } }
}

/// Menus on controls and the app's own menus in the menu bar (docs/surfaces.md, "Menus on
/// controls" and "The app's menus"; ^945–^950). Each case:
///
/// - applies one to four frames whose window record shows a random control menu (random
///   records, as `SurfacesSuite.menu` makes them) for a random owner, or none, to a real
///   `HostView` in a window that is never shown, with its control menu built but not popped up
///   (`ControlMenuHost.live == false`, as under the debug socket);
/// - drives a detached `ControlMenuHost` through frames that account for events before and after
///   its own close;
/// - gives the view random AX nodes, some with menus, and performs `AXShowMenu` on them;
/// - applies one to four frames with a random `menuBar` surface to a detached `SurfaceHost`,
///   whose main menu is a copy of the host's (`CairnApp.menu`) that never reaches the screen,
///   and chooses its items by `performActionForItem(at:)` and by key equivalent
///   (`NSMenu.performKeyEquivalent(with:)`).
///
/// Checks:
/// - `control-menu.render`: the native menu is the window record's menu records (the
///   `SurfacesSuite` oracle), for the record's owner; no records, no menu.
/// - `control-menu.select`: choosing an item sends exactly `menuSelect(window, ref)`, and the
///   close that follows exactly `menuClose(window)`, in that order; a status line, separator or
///   submenu sends nothing but the close.
/// - `control-menu.dismiss`: after the host closes a menu, a frame from before Lean heard (its
///   events through a lower sequence number) never shows it open again, one from after does; a
///   frame without a menu leaves none open.
/// - `ax.show-menu`: `AXShowMenu` is allowed on exactly the controls with a menu, and performing
///   it sends a secondary click at the node's centre (move, down, up), then puts the pointer
///   back; a menu button is an `AXMenuButton`.
/// - `menubar.render`: the main menu holds the records' top-level submenus as menus before the
///   Window menu and the other top-level entries at the top of the app menu, then a separator,
///   then the host's Hide and Quit, unchanged, with Edit and Window in place.
/// - `menubar.select`: choosing an item by `performActionForItem` or by its key equivalent sends
///   exactly `menuSelect(place, ref)`; the key equivalent of a greyed item sends nothing.
final class MenusSuite: Suite {
    let name = "menus"
    let crashCheck = "control-menu.render"
    let checks: [String: CheckInfo] = [
        "control-menu.render": CheckInfo(
            title: "A control's menu shows exactly the frame's menu records",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (ControlMenuHost, MenuHost)", "AppKit (NSMenu)"],
            oracle: "the window record's menu records, as a tree, and its owner"),
        "control-menu.select": CheckInfo(
            title: "Choosing a control menu's item reports its ref, then the close",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (ControlMenuHost, MenuHost)",
                      "AppKit (NSMenu.performActionForItem)"],
            oracle: "the record each item was built from, and the window's place"),
        "control-menu.dismiss": CheckInfo(
            title: "The host shows a control menu only while Lean has it open",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (ControlMenuHost)"],
            oracle: "the sequence number of the host's close and of each frame"),
        "ax.show-menu": CheckInfo(
            title: "AXShowMenu opens a control's menu as a right click does",
            trusted: ["host/Sources/CairnHost/AXMirror.swift (accessibilityPerformShowMenu, role)",
                      "host/Sources/CairnHost/HostView.swift (secondaryClick)"],
            oracle: "the frame's AX nodes: which have a menu, their rects"),
        "menubar.render": CheckInfo(
            title: "The menu bar shows the app's menu items",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (MenuBarHost, MenuHost)", "AppKit (NSMenu)"],
            oracle: "the menuBar record's items, split into menus and app-menu items, and the host's own menu"),
        "menubar.select": CheckInfo(
            title: "A menu bar item or its key equivalent reports that item's ref",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (MenuBarHost, MenuHost)",
                      "AppKit (NSMenu.performActionForItem, NSMenu.performKeyEquivalent)"],
            oracle: "the record each item was built from"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 10) }

    var view: HostView!
    var window: NSWindow!
    var engine: Engine!
    let core = RecordingCore()

    func setUp() {
        MainActor.assumeIsolated {
            let core = self.core
            engine = Engine(size: Size(w: 400, h: 300), scalePercent: 200, clock: false) { core }
            view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: 400, height: 300))
            view.effectHook = { _ in true }
            view.controlMenu.live = false
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = view
            engine.start()
        }
    }

    /// Shows `f` and returns the events the core was stepped with meanwhile (the suite's own
    /// pointer move among them).
    @discardableResult
    func apply(_ f: Frame) -> [Event] {
        core.set(f)
        let seq = engine.send([.pointerMove(Point(x: 0, y: 0))])
        _ = engine.wait(through: seq)
        MainActor.assumeIsolated { view.applyLatestFrame() }
        return core.take()
    }

    /// Waits until the core has stepped every event sent so far and returns them.
    func drain() -> [Event] {
        _ = engine.wait(through: engine.lastSeq)
        return core.take()
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        controlMenus(&g, r)
        dismiss(&g, r)
        showMenu(&g, r)
        MainActor.assumeIsolated { menuBar(&g, r) }
    }

    // MARK: Control menus

    func controlMenus(_ g: inout SplitMix, _ r: Recorder) {
        let place = UInt32(g.range(1, 999))
        _ = drain()
        for _ in 0..<g.range(1, 4) {
            let records = g.chance(1, 5) ? [] : SurfacesSuite.menu(&g)
            let owner = ControlRef(claim: UInt32(g.range(1, 999)), key: UInt32(g.range(0, 3)))
            let ax = [AxNode(control: owner, role: .button, rect: Rect(x: 10, y: 10, w: 40, h: 20), label: "More",
                             menu: true)]
            let f = Frame(surfaces: [Surface(kind: .window, place: place,
                                             canvas: Canvas(size: Size(w: 400, h: 300), draws: [], ax: ax),
                                             status: StatusFrame(control: owner, menu: records))])
            apply(f)
            var chosen: (NSMenu, Int, MenuRecord, Bool)?
            let ok: Bool = MainActor.assumeIsolated {
                let c = view.controlMenu
                r.ran("control-menu.render")
                if records.isEmpty {
                    return r.expect("control-menu.render", c.owner == nil, "no records, but \(String(describing: c.owner)) has a menu open")
                }
                guard r.expect("control-menu.render", c.owner == owner, "owner \(String(describing: c.owner)), record \(owner.label)"),
                      let m = c.menu else { return false }
                r.expect("control-menu.render", m.place == place, "menu place \(m.place), window \(place)")
                if let d = SurfacesSuite.compare(m.root, records, parent: nil, path: "root") {
                    r.fail("control-menu.render", d)
                    return false
                }
                r.count("control-menu.render", "records", records.count)
                var all: [(NSMenu, Int, MenuRecord, Bool)] = []
                func walk(_ menu: NSMenu, _ parent: Int?, _ within: Bool) {
                    let idxs = records.indices.filter { records[$0].parent == parent }
                    for (j, i) in idxs.enumerated() {
                        let rec = records[i]
                        if rec.kind == .submenu, let sub = menu.items[j].submenu { walk(sub, i, within && rec.enabled); continue }
                        all.append((menu, j, rec, within))
                    }
                }
                walk(m.root, nil, true)
                if !all.isEmpty { chosen = all[g.below(all.count)] }
                return true
            }
            guard ok, !records.isEmpty else { continue }
            // Choose an item (or none: Escape), then the menu closes, as a popped-up menu does.
            r.ran("control-menu.select")
            let pick = g.chance(3, 4) ? chosen : nil
            MainActor.assumeIsolated {
                if let (m, j, _, _) = pick { m.performActionForItem(at: j) }
                view.controlMenu.close()
            }
            let sent = drain()
            let close = Event.menuClose(place: place)
            if let (_, _, rec, within) = pick {
                if rec.kind == .item, let ref = rec.control {
                    if within && rec.enabled {
                        r.expect("control-menu.select", sent == [.menuSelect(place: place, ref), close],
                                 "choosing \(ref.label) sent \(sent)")
                        r.count("control-menu.select", "chosen")
                    } else {
                        r.expect("control-menu.select", sent == [close] || sent == [.menuSelect(place: place, ref), close],
                                 "a disabled \(ref.label) sent \(sent)")
                        r.count("control-menu.select", sent == [close] ? "disabledNotSent" : "disabledSent")
                    }
                } else {
                    r.expect("control-menu.select", sent == [close], "a \(rec.kind) item sent \(sent)")
                    r.count("control-menu.select", "inert")
                }
            } else {
                r.expect("control-menu.select", sent == [close], "closing sent \(sent)")
                r.count("control-menu.select", "dismissed")
            }
        }
        // The window shows no menu: none is open.
        apply(Frame(surfaces: [Surface(kind: .window, place: place, canvas: Canvas(size: Size(w: 400, h: 300), draws: []))]))
        MainActor.assumeIsolated {
            r.ran("control-menu.render")
            r.expect("control-menu.render", view.controlMenu.owner == nil, "a menu is open with no records")
        }
    }

    func dismiss(_ g: inout SplitMix, _ r: Recorder) {
        MainActor.assumeIsolated {
            var sent: [Event] = []
            let host = ControlMenuHost(live: false) { sent.append(contentsOf: $0); return UInt64(sent.count) + 100 }
            let place = UInt32(g.range(1, 999))
            var through: UInt64 = 0
            var closed: UInt64 = 0
            for _ in 0..<g.range(2, 10) {
                let owner = ControlRef(claim: UInt32(g.range(1, 99)))
                let shows = g.chance(2, 3)
                let records = shows ? [MenuRecord(kind: .item, label: "A", control: ControlRef(claim: 900))] : []
                let w = Surface(kind: .window, place: place, status: StatusFrame(control: owner, menu: records))
                if g.chance(1, 3), host.owner != nil { closed = host.close() }
                // Frames come in order; some account for the close, some don't yet.
                through = max(through, g.chance(1, 2) ? closed : (closed > 0 ? closed - 1 : 0))
                let windowless = g.chance(1, 8)
                host.update(windowless ? nil : w, through: through, view: nil)
                r.ran("control-menu.dismiss")
                let open = !windowless && shows && through >= closed
                r.expect("control-menu.dismiss", (host.owner != nil) == open,
                         "frame through \(through), closed at \(closed), shows \(shows): open \(host.owner != nil)")
                if host.owner != nil { r.expect("control-menu.dismiss", host.owner == owner, "the owner is \(String(describing: host.owner))") }
                r.count("control-menu.dismiss", open ? "open" : shows && !windowless ? "stale" : "none")
            }
        }
    }

    // MARK: AXShowMenu

    func showMenu(_ g: inout SplitMix, _ r: Recorder) {
        var nodes: [AxNode] = []
        let roles: [Role] = [.button, .button, .checkbox, .textField, .listItem, .text, .group]
        for i in 0..<g.range(1, 8) {
            let role = g.elem(roles)
            let control: ControlRef? = role == .text || role == .group ? nil : ControlRef(claim: UInt32(500 + i))
            let menu: Bool? = control == nil ? nil : g.chance(1, 3) ? nil : g.bool()
            let rect = Rect(x: Int32(g.range(0, 300)), y: Int32(g.range(0, 250)), w: Int32(g.range(2, 90)), h: Int32(g.range(2, 40)))
            nodes.append(AxNode(control: control, role: role, rect: rect, label: "n\(i)", menu: menu))
        }
        let f = Frame(surfaces: [Surface(kind: .window, place: 1,
                                         canvas: Canvas(size: Size(w: 400, h: 300), draws: [], ax: nodes))])
        apply(f)
        let perform: [(String, Rect)] = MainActor.assumeIsolated {
            var out: [(String, Rect)] = []
            let els = (view.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
            r.ran("ax.show-menu")
            r.expect("ax.show-menu", els.count == nodes.count, "\(els.count) elements for \(nodes.count) nodes")
            for (el, n) in zip(els, nodes) {
                let allowed = el.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformShowMenu))
                let want = n.control != nil && n.menu != nil
                r.expect("ax.show-menu", allowed == want, "\(n.label) (menu \(String(describing: n.menu))): AXShowMenu allowed \(allowed)")
                let menuButton = el.accessibilityRole() == .menuButton
                r.expect("ax.show-menu", menuButton == (n.menu == true && n.role == .button),
                         "\(n.label) (\(n.role), menu \(String(describing: n.menu))): role \(String(describing: el.accessibilityRole()))")
                if want { out.append((n.control!.label, n.rect)) }
                else { r.expect("ax.show-menu", !el.accessibilityPerformShowMenu(), "\(n.label) performed AXShowMenu without a menu") }
            }
            return out
        }
        _ = drain()
        for (label, rect) in perform {
            let done: Bool = MainActor.assumeIsolated {
                let els = (view.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityElement }
                guard let el = els.first(where: { $0.accessibilityIdentifier() == label }) else { return false }
                return el.accessibilityPerformShowMenu()
            }
            r.expect("ax.show-menu", done, "AXShowMenu on \(label) was not performed")
            let sent = drain()
            let c = Point(x: rect.x + rect.w / 2, y: rect.y + rect.h / 2)
            let click: [Event] = [.pointerMove(c), .pointerDown(c, .secondary, clicks: 1, Mods()), .pointerUp(c, .secondary, Mods())]
            let back: Bool = sent.count == 4 && {
                switch sent[3] { case .pointerMove, .pointerExit: return true; default: return false }
            }()
            r.expect("ax.show-menu", Array(sent.prefix(3)) == click && back,
                     "AXShowMenu on \(label) at \(rect) sent \(sent)")
            r.count("ax.show-menu", "performed")
        }
    }

    // MARK: The menu bar

    /// Virtual key codes of the letters (kVK_ANSI_*).
    static let letterCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
    ]

    /// Every item of `menu` and its submenus.
    static func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }

    @MainActor
    func menuBar(_ g: inout SplitMix, _ r: Recorder) {
        var sent: [Event] = []
        let host = SurfaceHost(mode: .detached, engine: nil, send: { sent.append(contentsOf: $0); return UInt64(sent.count) },
                               makeRenderer: { fatalError("a detached host makes no renderer") })
        guard let main = host.mainMenu else { r.fail("menubar.render", "a detached host has no main menu"); return }
        let place = UInt32(g.range(1, 999))
        let hostTitles = ["Hide App", "", "Quit App"]
        for _ in 0..<g.range(1, 4) {
            let records = SurfacesSuite.menu(&g)
            host.apply(Frame(surfaces: [Surface(kind: .menuBar, place: place, status: StatusFrame(menu: records))]))
            r.ran("menubar.render")
            let top = records.indices.filter { records[$0].parent == nil }
            let menus = top.filter { records[$0].kind == .submenu }
            let items = top.filter { records[$0].kind != .submenu }
            guard let app = main.items.first?.submenu else { r.fail("menubar.render", "no app menu"); return }
            let k = items.count
            if let d = SurfacesSuite.compare(Array(app.items.prefix(k)), items, records, path: "app") {
                r.fail("menubar.render", d)
                continue
            }
            let rest = Array(app.items.dropFirst(k == 0 ? 0 : k + 1))
            r.expect("menubar.render", k == 0 || app.items[k].isSeparatorItem, "no separator after the app's items")
            r.expect("menubar.render", rest.map { $0.isSeparatorItem ? "" : $0.title } == hostTitles,
                     "the host's app menu items are \(rest.map(\.title))")
            r.expect("menubar.render", rest.first?.action == #selector(NSApplication.hide(_:))
                     && rest.last?.action == #selector(NSApplication.terminate(_:)), "Hide or Quit lost its action")
            let titles = main.items.map { $0.submenu?.title ?? "" }
            let bar = Array(main.items.dropFirst(2).prefix(menus.count))
            r.expect("menubar.render", main.items.count == 3 + menus.count && titles[1] == "Edit" && titles.last == "Window",
                     "the main menu's menus are \(titles)")
            if let d = SurfacesSuite.compare(bar, menus, records, path: "bar") { r.fail("menubar.render", d); continue }
            r.count("menubar.render", "menus", menus.count)
            r.count("menubar.render", "appItems", k)

            // Leaves: (menu, index, record, effectively enabled).
            var leaves: [(NSMenu, Int, MenuRecord, Bool)] = []
            func walk(_ menu: NSMenu, _ idxs: [Int], offset: Int, _ within: Bool) {
                for (j, i) in idxs.enumerated() {
                    let rec = records[i]
                    let item = menu.items[offset + j]
                    if rec.kind == .submenu, let sub = item.submenu {
                        walk(sub, records.indices.filter { records[$0].parent == i }, offset: 0, within && rec.enabled)
                        continue
                    }
                    if rec.kind == .item, rec.control != nil { leaves.append((menu, offset + j, rec, within)) }
                }
            }
            walk(app, items, offset: 0, true)
            walk(main, menus, offset: 2, true)
            guard !leaves.isEmpty else { continue }

            // By click (sampled: AppKit's highlight takes about 60 ms).
            if g.chance(1, 3) {
                let (m, j, rec, within) = leaves[g.below(leaves.count)]
                r.ran("menubar.select")
                sent = []
                m.performActionForItem(at: j)
                if within && rec.enabled {
                    r.expect("menubar.select", sent == [.menuSelect(place: place, rec.control!)], "choosing \(rec.control!.label) sent \(sent)")
                    r.count("menubar.select", "chosen")
                } else {
                    r.expect("menubar.select", sent.isEmpty || sent == [.menuSelect(place: place, rec.control!)],
                             "a disabled \(rec.control!.label) sent \(sent)")
                }
            }

            // By key equivalent: a letter no other item in the main menu has with those modifiers.
            let every = Self.allItems(main)
            let mask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            for (m, j, rec, within) in leaves {
                let item = m.items[j]
                guard let s = rec.shortcut, case let .char(c) = s.key, let code = Self.letterCodes[c] else { continue }
                let flags = item.keyEquivalentModifierMask.intersection(mask)
                let same = every.filter {
                    $0.keyEquivalent.lowercased() == item.keyEquivalent.lowercased()
                        && $0.keyEquivalentModifierMask.intersection(mask) == flags
                }
                guard same.count == 1, flags.contains(.command) || flags.contains(.control) else {
                    r.count("menubar.select", "keyAmbiguous")
                    continue
                }
                // As a keyboard gives it: `charactersIgnoringModifiers` keeps shift.
                let shifted = flags.contains(.shift) ? String(c).uppercased() : String(c)
                guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
                                               context: nil, characters: shifted, charactersIgnoringModifiers: shifted,
                                               isARepeat: false, keyCode: code)
                else { continue }
                r.ran("menubar.select")
                sent = []
                let handled = main.performKeyEquivalent(with: e)
                if within && rec.enabled {
                    r.expect("menubar.select", handled && sent == [.menuSelect(place: place, rec.control!)],
                             "\(DebugKey.describe(flags, c)) for \(rec.control!.label): handled \(handled), sent \(sent)")
                    r.count("menubar.select", "key")
                } else if !rec.enabled {
                    r.expect("menubar.select", sent.isEmpty,
                             "\(DebugKey.describe(flags, c)) for a greyed \(rec.control!.label) sent \(sent)")
                    r.count("menubar.select", "keyGreyed")
                } else {
                    // An enabled item in a greyed submenu (Lean never greys a submenu): AppKit
                    // still performs its key equivalent; the ref is the item's, and Lean decides.
                    r.expect("menubar.select", sent.isEmpty || sent == [.menuSelect(place: place, rec.control!)],
                             "\(DebugKey.describe(flags, c)) in a greyed submenu sent \(sent)")
                    r.count("menubar.select", sent.isEmpty ? "keyInGreyedSubmenuNotSent" : "keyInGreyedSubmenuSent")
                }
            }
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let records = SurfacesSuite.menu(&g)
        return "control menus and a menu bar like: \(records.count) menu records"
    }
}

enum DebugKey {
    static func describe(_ f: NSEvent.ModifierFlags, _ c: Character) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "") + (f.contains(.shift) ? "⇧" : "")
            + (f.contains(.command) ? "⌘" : "") + String(c).uppercased()
    }
}

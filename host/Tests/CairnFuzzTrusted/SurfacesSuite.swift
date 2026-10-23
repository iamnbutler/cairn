import AppKit
import CairnFrame
import CairnHost
import Foundation

/// The host's surfaces (`SurfaceHost`, host/Sources/CairnHost/Surfaces.swift) against the
/// frame's surface records (docs/surfaces.md). Each case applies a random run of frames, each
/// with a status item (a random menu) and an overlay panel (randomly shown, sized and anchored),
/// to a detached host (nothing reaches the menu bar or the screen) and checks after every frame:
///
/// - `menu.render`: the NSMenu tree is the records, item by item (titles, enabled, checkmarks,
///   key equivalents, refs, separators, submenus, status lines not actionable).
/// - `menu.select`: performing each item's action (`NSMenu.performActionForItem(at:)`) sends
///   exactly one `menuSelect` with the place and that item's ref; non-actionable items send
///   nothing.
/// - `menu.open-close`: the root menu's delegate sends one `menuOpen`, one `menuClose`.
/// - `panel.inert`: the panel's window properties.
/// - `panel.place`: the panel's frame against the anchor, computed here.
final class SurfacesSuite: Suite {
    let name = "surfaces"
    let crashCheck = "menu.render"
    let checks: [String: CheckInfo] = [
        "menu.render": CheckInfo(
            title: "The native menu shows exactly the frame's menu records",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (MenuHost)", "AppKit (NSMenu)"],
            oracle: "the menu records, as a tree"),
        "menu.select": CheckInfo(
            title: "Choosing a menu item reports that item's ref",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (MenuHost)", "AppKit (NSMenu.performActionForItem)"],
            oracle: "the record each item was built from"),
        "menu.open-close": CheckInfo(
            title: "Opening and closing the menu are reported once each",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (MenuHost)"],
            oracle: "the status item's place"),
        "panel.inert": CheckInfo(
            title: "An overlay panel never takes focus or clicks",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (PanelHost, OverlayPanel)", "AppKit (NSPanel)"],
            oracle: "docs/surfaces.md, \"Overlay panel\""),
        "panel.place": CheckInfo(
            title: "An overlay panel is where its anchor says",
            trusted: ["host/Sources/CairnHost/Surfaces.swift (PanelHost)", "AppKit (NSWindow.setFrame)"],
            oracle: "the anchor's arithmetic on the chosen screen's visible frame"),
    ]

    func cases(for n: Int) -> Int { max(4, n / 10) }
    func setUp() {}

    // MARK: Generators

    static func shortcut(_ g: inout SplitMix) -> Shortcut? {
        guard g.chance(1, 3) else { return nil }
        let named: [Key] = [.enter, .escape, .tab, .backspace, .delete, .left, .right, .up, .down, .home,
                            .finish, .pageUp, .pageDown]
        let key: Key = g.chance(2, 3)
            ? .char(Character(Unicode.Scalar(UInt32(g.elem(Array("abcdefghijklmnopqrstuvwxyz0123456789,.;/".unicodeScalars)).value))!))
            : g.elem(named)
        return Shortcut(key: key, mods: Mods(shift: g.bool(), command: g.chance(3, 4), option: g.chance(1, 4),
                                             control: g.chance(1, 6)))
    }

    /// A flattened menu (parents before children; a parent is always a submenu).
    static func menu(_ g: inout SplitMix) -> [MenuRecord] {
        var out: [MenuRecord] = []
        var submenus: [Int] = []
        for _ in 0..<g.range(0, 14) {
            let parent: Int? = submenus.isEmpty || g.chance(1, 2) ? nil : g.elem(submenus)
            let label = g.chance(1, 4) ? TextPool.string(&g, maxParts: 6) : g.elem(["Show", "Hide", "Item", "Recent", "Quit", "None yet", ""])
            switch g.below(10) {
            case 0, 1:
                out.append(MenuRecord(kind: .separator, parent: parent))
            case 2:
                out.append(MenuRecord(kind: .info, label: label, parent: parent, enabled: false))
            case 3:
                submenus.append(out.count)
                out.append(MenuRecord(kind: .submenu, label: label, place: g.bool() ? UInt32(g.range(1, 999)) : nil,
                                      parent: parent, enabled: g.chance(4, 5)))
            default:
                let ref = ControlRef(claim: UInt32(g.range(1, 999)), key: g.chance(1, 3) ? UInt32(g.range(0, 9)) : 0)
                out.append(MenuRecord(kind: .item, label: label, control: ref, parent: parent, enabled: g.chance(3, 4),
                                      checked: g.chance(1, 3) ? g.bool() : nil, shortcut: shortcut(&g)))
            }
        }
        return out
    }

    static func frame(_ g: inout SplitMix, status: UInt32, panel: UInt32) -> Frame {
        let st = StatusFrame(control: ControlRef(claim: status + 1), symbol: g.elem(["tray", "tray.full", ""]),
                             title: g.chance(1, 3) ? "Tray" : "", label: "Tray", menu: menu(&g))
        let size = Size(w: Int32(g.range(0, 900)), h: Int32(g.range(0, 300)))
        let panelSurface = Surface(kind: .panel, place: panel, shown: g.chance(2, 3), title: "Overlay",
                                   anchor: .bottomCenter(offset: UInt32(g.range(0, 200))),
                                   screen: g.bool() ? .pointer : .main,
                                   canvas: Canvas(size: size, draws: []))
        return Frame(surfaces: [Surface(kind: .statusItem, place: status, status: st), panelSurface])
    }

    // MARK: Oracle

    static func keyEquivalent(_ s: Shortcut?) -> (String, NSEvent.ModifierFlags) {
        guard let s else { return ("", []) }
        func fn(_ k: Int) -> String { String(UnicodeScalarType(UInt32(k)).map { Character($0) } ?? " ") }
        let key: String
        switch s.key {
        case .enter: key = "\r"
        case .escape: key = "\u{1b}"
        case .tab: key = "\t"
        case .backspace: key = "\u{8}"
        case .delete: key = fn(0xF728)
        case .left: key = fn(0xF702)
        case .right: key = fn(0xF703)
        case .up: key = fn(0xF700)
        case .down: key = fn(0xF701)
        case .home: key = fn(0xF729)
        case .finish: key = fn(0xF72B)
        case .pageUp: key = fn(0xF72C)
        case .pageDown: key = fn(0xF72D)
        case let .char(c): key = String(c).lowercased()
        }
        var m: NSEvent.ModifierFlags = []
        if s.mods.command { m.insert(.command) }
        if s.mods.shift { m.insert(.shift) }
        if s.mods.option { m.insert(.option) }
        if s.mods.control { m.insert(.control) }
        return (key, m)
    }
    typealias UnicodeScalarType = Unicode.Scalar

    /// Compares `menu` with the records whose parent is `parent`; returns the first difference.
    /// AppKit greys out everything in a disabled submenu, so an item is enabled when it and every
    /// enclosing submenu are (Lean's submenus are always enabled; the format allows otherwise).
    static func compare(_ menu: NSMenu, _ records: [MenuRecord], parent: Int?, path: String,
                        within: Bool = true) -> String? {
        let idxs = records.indices.filter { records[$0].parent == parent }
        guard menu.items.count == idxs.count else {
            return "\(path): \(menu.items.count) items, \(idxs.count) records"
        }
        for (item, i) in zip(menu.items, idxs) {
            let r = records[i]
            let at = "\(path)[\(i)]"
            if item.isSeparatorItem != (r.kind == .separator) { return "\(at): separator \(item.isSeparatorItem), record \(r.kind)" }
            if r.kind == .separator { continue }
            if item.title != r.label { return "\(at): title \(item.title.debugDescription), label \(r.label.debugDescription)" }
            switch r.kind {
            case .submenu:
                guard let sub = item.submenu else { return "\(at): no submenu" }
                if item.isEnabled != (within && r.enabled) { return "\(at): submenu enabled \(item.isEnabled)" }
                if item.identifier?.rawValue != r.place.map({ "^\($0)" }) { return "\(at): submenu id \(String(describing: item.identifier))" }
                if let d = compare(sub, records, parent: i, path: at, within: within && r.enabled) { return d }
            case .item where r.control != nil:
                if item.action == nil { return "\(at): no action" }
                if item.submenu != nil { return "\(at): an item with a submenu" }
                if item.isEnabled != (within && r.enabled) { return "\(at): enabled \(item.isEnabled), record \(r.enabled)" }
                if (item.state == .on) != (r.checked == true) || item.state == .mixed { return "\(at): state \(item.state.rawValue), checked \(String(describing: r.checked))" }
                if item.identifier?.rawValue != r.control!.label { return "\(at): id \(String(describing: item.identifier)), ref \(r.control!.label)" }
                let (k, m) = keyEquivalent(r.shortcut)
                if item.keyEquivalent != k { return "\(at): key \(item.keyEquivalent.debugDescription), expected \(k.debugDescription)" }
                if !k.isEmpty, item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) != m {
                    return "\(at): mods \(item.keyEquivalentModifierMask.rawValue), expected \(m.rawValue)"
                }
            default:
                if item.action != nil || item.isEnabled || item.submenu != nil { return "\(at): a status line is actionable" }
            }
        }
        return nil
    }

    // MARK: Run

    func run(_ g: inout SplitMix, _ r: Recorder) {
        MainActor.assumeIsolated { runMain(&g, r) }
    }

    @MainActor
    func runMain(_ g: inout SplitMix, _ r: Recorder) {
        var sent: [Event] = []
        let host = SurfaceHost(mode: .detached, engine: nil, send: { sent.append(contentsOf: $0); return UInt64(sent.count) },
                               makeRenderer: { fatalError("a detached host makes no renderer") })
        let status = UInt32(g.range(1, 999)), panelPlace = status + 2
        var wasShown = false
        var screen: CGRect?
        for _ in 0..<g.range(1, 6) {
            let f = Self.frame(&g, status: status, panel: panelPlace)
            host.apply(f)
            let records = f.surfaces[0].status.menu
            guard let menu = host.menu(status) else { r.fail("menu.render", "no menu for ^\(status)"); return }

            r.ran("menu.render")
            if let d = Self.compare(menu.root, records, parent: nil, path: "root") {
                r.fail("menu.render", d)
            }
            r.count("menu.render", "records", records.count)

            // Choose an item in a third of the frames: AppKit's performActionForItem takes about
            // 60 ms (its highlight), so this check gets fewer cases than the others.
            var all: [(NSMenu, Int, MenuRecord, Bool)] = []
            func walk(_ m: NSMenu, _ parent: Int?, _ within: Bool) {
                let idxs = records.indices.filter { records[$0].parent == parent }
                guard m.items.count == idxs.count else { return }
                for (j, i) in idxs.enumerated() {
                    let rec = records[i]
                    if rec.kind == .submenu, let sub = m.items[j].submenu { walk(sub, i, within && rec.enabled); continue }
                    all.append((m, j, rec, within))
                }
            }
            walk(menu.root, nil, true)
            for _ in 0..<(g.chance(1, 3) ? min(1, all.count) : 0) {
                r.ran("menu.select")
                let (m, j, rec, within) = all.remove(at: g.below(all.count))
                sent = []
                m.performActionForItem(at: j)
                if rec.kind == .item, let ref = rec.control {
                    if within && rec.enabled {
                        r.expect("menu.select", sent == [.menuSelect(place: status, ref)],
                                 "choosing \(ref.label) sent \(sent)")
                        r.count("menu.select", "chosen")
                    } else {
                        // AppKit may or may not perform a disabled item; if it does, the ref is
                        // still the item's (Lean ignores it).
                        r.expect("menu.select", sent.isEmpty || sent == [.menuSelect(place: status, ref)],
                                 "a disabled \(ref.label) sent \(sent)")
                        r.count("menu.select", sent.isEmpty ? "disabledNotSent" : "disabledSent")
                    }
                } else {
                    r.expect("menu.select", sent.isEmpty, "a \(rec.kind) item sent \(sent)")
                    r.count("menu.select", "inert")
                }
            }

            r.ran("menu.open-close")
            sent = []
            menu.menuWillOpen(menu.root)
            for item in menu.root.items { if let sub = item.submenu { menu.menuWillOpen(sub); menu.menuDidClose(sub) } }
            menu.menuDidClose(menu.root)
            r.expect("menu.open-close", sent == [.menuOpen(place: status), .menuClose(place: status)],
                     "open and close sent \(sent)")

            guard let ph = host.panels[panelPlace] else { r.fail("panel.inert", "no panel for ^\(panelPlace)"); return }
            let p = ph.panel
            r.ran("panel.inert")
            r.expect("panel.inert", !p.canBecomeKey && !p.canBecomeMain, "the panel can become key or main")
            r.expect("panel.inert", p.styleMask.contains(.nonactivatingPanel), "the panel is not non-activating")
            r.expect("panel.inert", p.ignoresMouseEvents, "the panel takes the mouse")
            r.expect("panel.inert", !p.hidesOnDeactivate, "the panel hides on deactivate")
            r.expect("panel.inert", p.level == .statusBar, "the panel's level is \(p.level.rawValue)")
            r.expect("panel.inert", p.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary])
                     && !p.collectionBehavior.contains(.moveToActiveSpace), "collection behaviour \(p.collectionBehavior.rawValue)")
            r.expect("panel.inert", !p.isOpaque && p.backgroundColor == .clear, "the panel is opaque")
            r.expect("panel.inert", !p.isVisible && !p.isKeyWindow, "a detached panel is on screen or key")

            let ps = f.surfaces[1]
            let want = ps.shown && ps.canvas.size.w > 0 && ps.canvas.size.h > 0
            r.ran("panel.place")
            r.expect("panel.place", ph.visible == want, "visible \(ph.visible), shown \(want)")
            if want {
                guard let vf = ph.screenFrame else { r.fail("panel.place", "a shown panel has no screen"); continue }
                if wasShown { r.expect("panel.place", vf == screen, "the screen changed while shown: \(String(describing: screen)) → \(vf)") }
                screen = vf
                let w = CGFloat(ps.canvas.size.w), h = CGFloat(ps.canvas.size.h)
                let expect = CGRect(x: (vf.midX - w / 2).rounded(.down), y: (vf.minY + CGFloat(ps.anchor.offset)).rounded(.down),
                                    width: w, height: h)
                r.expect("panel.place", p.frame == expect, "panel at \(p.frame), expected \(expect) in \(vf)")
                r.count("panel.place", "shown")
            } else {
                r.expect("panel.place", ph.screenFrame == nil, "a hidden panel keeps its screen")
                screen = nil
            }
            wasShown = want
        }
        r.count("menu.render", "rebuilds", host.menu(status)?.rebuilds ?? 0)
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        let f = Self.frame(&g, status: 1, panel: 3)
        return "frames like: \(f.surfaces[0].status.menu.count) menu records, panel \(f.surfaces[1].canvas.size)"
    }
}

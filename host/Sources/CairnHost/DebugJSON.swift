import AppKit
import CairnFrame

/// The debug socket's JSON (docs/conformance.md). A frame is written in exactly the shape the
/// conformance generator writes the model's frame (`Conformance.jframe` in
/// tools/conformance/lean/Conformance/Gen.lean), so the driver compares the two as values.
public enum DebugJSON {
    static func rect(_ r: Rect) -> [Any] { [Int(r.x), Int(r.y), Int(r.w), Int(r.h)] }
    static func point(_ p: Point) -> [Any] { [Int(p.x), Int(p.y)] }
    static func color(_ c: Color) -> [Any] { [Int(c.r), Int(c.g), Int(c.b), Int(c.a)] }
    static func opt<T>(_ v: T?, _ f: (T) -> Any) -> Any { v.map(f) ?? NSNull() }

    static func draw(_ d: Draw) -> [String: Any] {
        switch d {
        case let .rect(r, fill, radius, border):
            ["rect": rect(r), "fill": opt(fill, color), "radius": Int(radius),
             "border": opt(border) { ["width": Int($0.width), "color": color($0.color)] }]
        case let .text(origin, font, c, s):
            ["text": s, "at": point(origin),
             "font": [Int(font.family), Int(font.size), Int(font.weight), font.italic,
                      Int(font.width.rawValue), Int(font.tracking), font.tabular] as [Any],
             "color": color(c)]
        case let .pushClip(r): ["push": rect(r)]
        case .popClip: ["pop": true]
        case let .shape(r, fill, radius, border, corner, shadow):
            ["shape": rect(r), "fill": opt(fill, color), "radius": Int(radius),
             "border": opt(border) { ["width": Int($0.width), "color": color($0.color)] },
             "continuous": corner == .continuous,
             "shadow": opt(shadow) { ["color": color($0.color), "radius": Int($0.radius),
                                      "offset": [Int($0.x), Int($0.y)]] }]
        case let .paint(r, p):
            ["paint": rect(r), "shader": p.shader, "origin": Int(p.origin),
             "scalars": p.scalars.map { Int($0) }, "arrays": p.arrays.map { $0.map { Int($0) } }]
        case let .image(r, dest, source):
            ["image": rect(r), "dest": rect(dest), "source": source]
        }
    }

    static func roleName(_ r: Role) -> String {
        switch r {
        case .group: "group"
        case .button: "button"
        case .checkbox: "checkbox"
        case .text: "text"
        case .textField: "textField"
        case .link: "link"
        case .list: "list"
        case .listItem: "listItem"
        case .heading: "heading"
        case .tab: "tab"
        case .scrollArea: "scrollArea"
        }
    }

    static func ax(_ n: AxNode) -> [String: Any] {
        ["role": roleName(n.role), "control": opt(n.control) { $0.label }, "parent": opt(n.parent) { $0 },
         "rect": rect(n.rect), "label": n.label, "value": n.value, "focused": n.focused,
         "selected": n.selected, "checked": opt(n.checked) { $0 }, "secure": n.secure]
    }

    static func textInput(_ t: TextInput) -> [String: Any] {
        ["control": t.control.label, "rect": rect(t.rect), "caret": rect(t.caret), "text": t.text,
         "selection": [Int(t.selection.start), Int(t.selection.end)],
         "marked": opt(t.marked) { [Int($0.start), Int($0.end)] }, "origin": point(t.textOrigin),
         "secure": t.secure]
    }

    static func cursorName(_ c: Cursor) -> String {
        switch c {
        case .arrow: "arrow"
        case .pointer: "pointer"
        case .text: "text"
        }
    }

    static func frame(_ f: Frame) -> [String: Any] {
        ["size": [Int(f.size.w), Int(f.size.h)], "draws": f.draws.map(draw), "ax": f.ax.map(ax),
         "textInput": opt(f.textInput, textInput), "cursor": cursorName(f.cursor)]
    }

    static func effect(_ e: Effect) -> [String: Any] {
        switch e {
        case .setClipboard(let s): ["clipboard": s]
        case .beep: ["beep": true]
        case .focus(let c): ["focus": c.label]
        case let .setTimer(n, ms): ["setTimer": n, "ms": Int(ms)]
        case .cancelTimer(let n): ["cancelTimer": n]
        case let .request(id, r): ["request": Int(id), "kind": request(r)]
        case .quit: ["quit": true]
        case let .cancelRequest(id): ["cancelRequest": Int(id)]
        }
    }

    /// How the debug socket describes a request (public for the trusted fuzzer, which checks
    /// that no secret or typed text shows up in it).
    public static func describe(_ r: Request) -> String { request(r) }

    static func request(_ r: Request) -> String {
        switch r {
        case .readFile(let p): "readFile \(p)"
        case let .writeFile(p, d): "writeFile \(p) (\(d.count) bytes)"
        case .playSound(let n): "playSound \(n)"
        // Never the secret's value nor a captured one: the header's name and how many fields.
        // A redacted request (a secure field's text) shows no URL.
        case let .http(m, u, _, _, _, s, cap, red):
            "http \(m) \(red ? "<redacted>" : u)\(s.map { " secret \($0.header)" } ?? "")\(cap.isEmpty ? "" : " capture \(cap.count)")"
        case let .appendFile(p, d): "appendFile \(p) (\(d.count) bytes)"
        case .listDir(let p): "listDir \(p)"
        case .deleteFile(let p): "deleteFile \(p)"
        case .frontmostApp: "frontmostApp"
        case let .permission(p, prompt): "permission \(p)\(prompt ? " prompt" : "")"
        // The typed text is what the person dictated: its length only.
        case let .typeText(pid, t, ret): "typeText \(pid) (\(t.utf8.count) bytes)\(ret ? " return" : "")"
        // Never the secret's value (the host reads it only when sending) nor the body.
        case let .upload(m, u, _, s, body, _): "upload \(m) \(u) (\(body.count) parts)\(s.map { " secret \($0.header)" } ?? "")"
        case .forgetClip(let c): "forgetClip \(c)"
        case .openItem(let t): "open \(t)"
        case .appRunning(let b): "appRunning \(b)"
        case let .readDefault(d, k): "readDefault \(d) \(k)"
        case .makeDir(let p): "makeDir \(p)"
        case let .loadImage(s, reload): "loadImage \(s)\(reload ? " reload" : "")"
        case .forgetSecret(let a): "forgetSecret \(a)"
        }
    }

    /// The accessibility tree as an assistive app reads it: every element under the view, depth
    /// first, through the public `NSAccessibility` methods, with frames converted from screen
    /// coordinates back to the view's logical points (y down).
    @MainActor
    static func axTree(_ view: HostView) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func rounded(_ r: NSRect) -> [Any] {
            guard let w = view.window else { return [0, 0, 0, 0] }
            let v = view.convert(w.convertFromScreen(r), from: nil)
            return [Int(v.minX.rounded()), Int(v.minY.rounded()), Int(v.width.rounded()), Int(v.height.rounded())]
        }
        func value(_ v: Any?) -> Any {
            switch v {
            case let s as String: s
            case let n as NSNumber: n.intValue
            default: NSNull()
            }
        }
        func walk(_ xs: [Any]?, parent: Int?) {
            for case let e as NSAccessibilityElement in xs ?? [] {
                var d: [String: Any] = [
                    "id": e.accessibilityIdentifier(),
                    "role": e.accessibilityRole()?.rawValue ?? NSNull(),
                    "subrole": e.accessibilitySubrole()?.rawValue ?? NSNull(),
                    "roleDescription": e.accessibilityRoleDescription() ?? NSNull(),
                    "label": e.accessibilityLabel() ?? NSNull(),
                    "title": e.accessibilityTitle() ?? NSNull(),
                    "value": value(e.accessibilityValue()),
                    "focused": e.isAccessibilityFocused(),
                    "selected": e.isAccessibilitySelected(),
                    "enabled": e.isAccessibilityEnabled(),
                    "frame": rounded(e.accessibilityFrame()),
                    "parent": parent ?? NSNull(),
                ]
                if e.accessibilityRole() == .textField {
                    let r = e.accessibilitySelectedTextRange()
                    d["selection"] = [r.location, r.length]
                    d["characters"] = e.accessibilityNumberOfCharacters()
                }
                let index = out.count
                out.append(d)
                walk(e.accessibilityChildren(), parent: index)
            }
        }
        walk(view.accessibilityChildren(), parent: nil)
        return out
    }

    // MARK: Surfaces

    /// A native menu as AppKit holds it.
    @MainActor
    static func menu(_ m: NSMenu) -> [[String: Any]] {
        m.items.map { item in
            if item.isSeparatorItem { return ["kind": "separator"] }
            var o: [String: Any] = [
                "kind": item.submenu != nil ? "submenu" : item.action != nil ? "item" : "info",
                "title": item.title, "enabled": item.isEnabled,
                "state": item.state == .on ? "on" : item.state == .mixed ? "mixed" : "off",
                "id": item.identifier?.rawValue ?? NSNull(),
                "key": item.keyEquivalent,
                // The mask defaults to ⌘ with no key; it means something only with a key.
                "mods": item.keyEquivalent.isEmpty ? [] : modNames(item.keyEquivalentModifierMask),
            ]
            if let sub = item.submenu { o["items"] = menu(sub) }
            return o
        }
    }

    static func modNames(_ f: NSEvent.ModifierFlags) -> [String] {
        var out: [String] = []
        if f.contains(.command) { out.append("command") }
        if f.contains(.shift) { out.append("shift") }
        if f.contains(.option) { out.append("option") }
        if f.contains(.control) { out.append("control") }
        return out
    }

    static func kindName(_ k: SurfaceKind) -> String {
        switch k {
        case .window: "window"
        case .panel: "panel"
        case .statusItem: "statusItem"
        }
    }

    static func cg(_ r: CGRect) -> [Any] { [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)] }

    /// The app's surfaces: what the frame says and what AppKit has.
    @MainActor
    static func surfaces(_ host: SurfaceHost?, view: HostView) -> [String: Any] {
        let policy: String = switch NSApp.activationPolicy() {
        case .regular: "regular"
        case .accessory: "accessory"
        case .prohibited: "prohibited"
        @unknown default: "unknown"
        }
        let frame = view.shown?.frame
        var list: [[String: Any]] = []
        for s in frame?.surfaces ?? [] {
            var o: [String: Any] = ["kind": kindName(s.kind), "place": Int(s.place), "shown": s.shown, "title": s.title]
            switch s.kind {
            case .window:
                o["size"] = [Int(s.canvas.size.w), Int(s.canvas.size.h)]
                o["minSize"] = [Int(s.minSize.w), Int(s.minSize.h)]
                if let w = view.window {
                    o["window"] = ["number": w.windowNumber, "key": w.isKeyWindow, "visible": w.isVisible]
                }
            case .statusItem:
                o["symbol"] = s.status.symbol
                o["statusTitle"] = s.status.title
                o["label"] = s.status.label
                o["control"] = s.status.control.label
                if let h = host?.statuses[s.place] {
                    o["inMenuBar"] = h.item != nil
                    o["rebuilds"] = h.menu.rebuilds
                }
            case .panel:
                o["size"] = [Int(s.canvas.size.w), Int(s.canvas.size.h)]
                o["anchor"] = ["bottomCenter": Int(s.anchor.offset)]
                o["screen"] = s.screen == .pointer ? "pointer" : "main"
                o["draws"] = s.canvas.draws.count
                o["texts"] = s.canvas.draws.compactMap { if case let .text(_, _, _, t) = $0 { t } else { nil } }
                if let h = host?.panels[s.place] { o["panel"] = panel(h) }
            }
            list.append(o)
        }
        return [
            "policy": policy, "active": NSApp.isActive,
            "keyWindow": NSApp.keyWindow?.windowNumber ?? NSNull(),
            "mainMenu": NSApp.mainMenu != nil,
            "detached": host?.mode == .detached,
            "surfaces": list,
        ]
    }

    @MainActor
    static func panel(_ h: PanelHost) -> [String: Any] {
        let p = h.panel
        let b = p.collectionBehavior
        var behavior: [String] = []
        if b.contains(.canJoinAllSpaces) { behavior.append("canJoinAllSpaces") }
        if b.contains(.fullScreenAuxiliary) { behavior.append("fullScreenAuxiliary") }
        if b.contains(.stationary) { behavior.append("stationary") }
        if b.contains(.ignoresCycle) { behavior.append("ignoresCycle") }
        if b.contains(.moveToActiveSpace) { behavior.append("moveToActiveSpace") }
        return [
            "visible": h.visible, "onScreen": p.isVisible,
            "canBecomeKey": p.canBecomeKey, "canBecomeMain": p.canBecomeMain, "key": p.isKeyWindow,
            "nonactivating": p.styleMask.contains(.nonactivatingPanel),
            "ignoresMouse": p.ignoresMouseEvents, "hidesOnDeactivate": p.hidesOnDeactivate,
            "level": p.level.rawValue, "statusBarLevel": NSWindow.Level.statusBar.rawValue,
            "behavior": behavior, "opaque": p.isOpaque,
            "frame": cg(p.frame), "screenFrame": h.screenFrame.map(cg) ?? NSNull(),
        ]
    }
}

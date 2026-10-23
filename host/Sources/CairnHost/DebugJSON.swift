import AppKit
import CairnFrame

/// The debug socket's JSON (docs/conformance.md). A frame is written in exactly the shape the
/// conformance generator writes the model's frame (`Conformance.jframe` in
/// tools/conformance/lean/Conformance/Gen.lean), so the driver compares the two as values.
enum DebugJSON {
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
             "font": [Int(font.family), Int(font.size), Int(font.weight), font.italic], "color": color(c)]
        case let .pushClip(r): ["push": rect(r)]
        case .popClip: ["pop": true]
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
        }
    }

    static func ax(_ n: AxNode) -> [String: Any] {
        ["role": roleName(n.role), "control": opt(n.control) { $0.label }, "parent": opt(n.parent) { $0 },
         "rect": rect(n.rect), "label": n.label, "value": n.value, "focused": n.focused,
         "selected": n.selected, "checked": opt(n.checked) { $0 }]
    }

    static func textInput(_ t: TextInput) -> [String: Any] {
        ["control": t.control.label, "rect": rect(t.rect), "caret": rect(t.caret), "text": t.text,
         "selection": [Int(t.selection.start), Int(t.selection.end)],
         "marked": opt(t.marked) { [Int($0.start), Int($0.end)] }, "origin": point(t.textOrigin)]
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
        }
    }

    static func request(_ r: Request) -> String {
        switch r {
        case .readFile(let p): "readFile \(p)"
        case let .writeFile(p, d): "writeFile \(p) (\(d.count) bytes)"
        case .playSound(let n): "playSound \(n)"
        case let .http(m, u, _, _, _): "http \(m) \(u)"
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
}

import AppKit
import CairnFrame
import CairnHost
import Foundation

/// A core that shows whatever frame the suite gives it, whatever events arrive.
final class FrameCore: AppCore, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Frame(size: Size(w: 10, h: 10), draws: [])
    func set(_ f: Frame) { lock.withLock { current = f } }
    func start(size: Size, scalePercent: UInt32) {}
    func step(_ events: [Event]) {}
    func frame() throws -> Frame { lock.withLock { current } }
}

/// The accessibility mirror under scroll areas and on secure fields (^1021, ^1022;
/// `AXMirror`, `AXNodeElement`, `DebugJSON.describe`). Each case builds a random tree of AX
/// nodes as Lean's frames list them (a parent before its children), with scroll areas nested
/// anywhere and nodes under them given an empty rect (scrolled out) or a visible one, text fields
/// plain and secure, one node focused or none, and applies one to four frames of it to a real
/// `HostView` in a window that is never shown, scrolling between them (the rects change, the
/// tree doesn't). After each frame it walks the view's accessibility tree through AppKit's
/// public API (`accessibilityChildren`, `accessibilityParent`, `accessibilityHitTest`, the
/// attribute getters), as an assistive app does:
///
/// - `ax.scroll`: the elements reached from the view are exactly the nodes that are not
///   scrolled out, each once, under its frame parent, in frame order, with that parent as its
///   `accessibilityParent` (the view for a root); a node is scrolled out when it, or a node
///   above it, has an empty rect and a scroll area somewhere above that. A scroll area is an
///   `AXScrollArea`. A hit test anywhere in the view answers the view or an element reached from
///   it whose frame contains the point. The focused element is the last focused node's, scrolled
///   out or not, or the view when there is none. The oracle walks each node's parents itself.
/// - `ax.secure`: a secure field is an `AXTextField` with subrole `AXSecureTextField` whose
///   value is nil, with no characters, no selected text, an empty selected range and an empty
///   string for any range; the text planted in it (in the node's value, and in the frame's text
///   input when it is focused) is in no attribute of any element. A plain field's value is its
///   text, so the check can see a value that leaks. `DebugJSON.describe` (the debug socket's
///   log of requests) of an `http` request shows no header value, body or secret, and no URL
///   when the request is `redact`.
final class AXSuite: Suite {
    let name = "ax"
    let crashCheck = "ax.scroll"
    let checks: [String: CheckInfo] = [
        "ax.scroll": CheckInfo(
            title: "Assistive apps reach only what a scroll area shows",
            trusted: ["host/Sources/CairnHost/AXMirror.swift (AXMirror.update, hidden, hitTest)",
                      "host/Sources/CairnHost/HostView.swift (accessibilityChildren, accessibilityFocusedUIElement, accessibilityHitTest)"],
            oracle: "the frame's AX nodes: each node's parent chain walked here, empty rects under a scroll area"),
        "ax.secure": CheckInfo(
            title: "A secure field shows assistive apps nothing typed",
            trusted: ["host/Sources/CairnHost/AXMirror.swift (AXNodeElement: subrole, value, text, selection)",
                      "host/Sources/CairnHost/DebugJSON.swift (describe of http)"],
            oracle: "text planted in the frame's secure nodes, text input and requests, looked for in every attribute"),
    ]

    func cases(for n: Int) -> Int { max(8, n / 2) }

    var view: HostView!
    var window: NSWindow!
    var engine: Engine!
    let core = FrameCore()

    func setUp() {
        MainActor.assumeIsolated {
            let core = self.core
            engine = Engine(size: Size(w: 400, h: 300), scalePercent: 200, clock: false) { core }
            view = HostView(engine: engine, renderer: NullRenderer(), size: NSSize(width: 400, height: 300))
            view.effectHook = { _ in true }
            window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = view
            engine.start()
        }
    }

    static let roles: [Role] = [.group, .button, .checkbox, .text, .textField, .link, .list, .listItem,
                                .heading, .tab, .scrollArea]

    struct Spec {
        var role: Role
        var parent: Int?
        var control: Bool
        var secure: Bool
    }

    struct Plan: CustomStringConvertible {
        var specs: [Spec]
        var marker: String
        /// Per frame: each node's rect, and the focused node.
        var frames: [(rects: [Rect], focused: Int?)]
        var description: String {
            "\(specs.count) nodes ("
                + specs.enumerated().map { i, s in
                    "\(i):\(s.role)\(s.secure ? " secure" : "")\(s.parent.map { "<\($0)" } ?? "")"
                }.joined(separator: " ")
                + "), \(frames.count) frames, focus \(frames.map { $0.focused.map(String.init) ?? "-" })"
        }
    }

    static func plan(_ g: inout SplitMix) -> Plan {
        let n = g.range(1, 40)
        var specs: [Spec] = []
        for i in 0..<n {
            let role: Role = g.weighted([(3, { _ in .scrollArea }), (3, { _ in .textField }), (6, { g in g.elem(roles) })])
            let parent: Int? = i == 0 || g.chance(1, 6) ? nil : g.below(i)
            specs.append(Spec(role: role, parent: parent, control: g.chance(2, 3),
                              secure: role == .textField && g.chance(1, 2)))
        }
        // Under a scroll area somewhere above: those can be scrolled out.
        func underScroll(_ i: Int) -> Bool {
            var p = specs[i].parent
            while let q = p { if specs[q].role == .scrollArea { return true }; p = specs[q].parent }
            return false
        }
        var frames: [(rects: [Rect], focused: Int?)] = []
        for _ in 0..<g.range(1, 4) {
            var rects: [Rect] = []
            for i in 0..<n {
                let out = (underScroll(i) || g.chance(1, 20)) && g.chance(2, 5)
                let x = Int32(g.range(0, 390)), y = Int32(g.range(0, 290))
                rects.append(out
                    ? g.elem([Rect(x: x, y: y, w: 0, h: 0), Rect(x: x, y: y, w: Int32(g.range(1, 40)), h: 0),
                              Rect(x: x, y: y, w: 0, h: Int32(g.range(1, 40)))])
                    : Rect(x: x, y: y, w: Int32(g.range(1, 400 - Int(x))), h: Int32(g.range(1, 300 - Int(y)))))
            }
            let fields = specs.indices.filter { specs[$0].role == .textField && specs[$0].control }
            let focused: Int? = g.chance(1, 4) ? nil : g.chance(3, 4) && !fields.isEmpty ? g.elem(fields) : g.below(n)
            frames.append((rects, focused))
        }
        let marker = "pw-" + String(g.next(), radix: 36)
        return Plan(specs: specs, marker: marker, frames: frames)
    }

    static func label(_ i: Int) -> String { "n\(i)" }

    static func frame(_ p: Plan, _ k: Int) -> Frame {
        let (rects, focused) = p.frames[k]
        var ax: [AxNode] = []
        var input: TextInput?
        for (i, s) in p.specs.enumerated() {
            let control = s.control ? ControlRef(claim: UInt32(100 + i)) : nil
            // A plain field's value is its own text; a secure one's is the planted text (Lean's
            // frame would hold bullets; the host must not show even the plant).
            let value = s.role == .textField ? (s.secure ? p.marker : "plain\(i)") : (s.role == .text ? "text\(i)" : "")
            ax.append(AxNode(control: control, role: s.role, rect: rects[i], label: label(i), value: value,
                             parent: s.parent, focused: focused == i, secure: s.secure))
            if focused == i, s.role == .textField, let c = control {
                let t = s.secure ? p.marker + "!" : "typed\(i)"
                let u = UInt32(t.unicodeScalars.count)
                input = TextInput(control: c, rect: rects[i], caret: Rect(x: rects[i].x, y: rects[i].y, w: 1, h: 16),
                                  text: t, selection: (0, u), marked: nil, secure: s.secure)
            }
        }
        return Frame(size: Size(w: 400, h: 300), draws: [], ax: ax, textInput: input)
    }

    /// Whether node `i` is scrolled out, by walking its parents (not the host's one pass).
    static func hidden(_ p: Plan, _ rects: [Rect], _ i: Int) -> Bool {
        var j: Int? = i
        while let a = j {
            var q = p.specs[a].parent, scrolled = false
            while let b = q { if p.specs[b].role == .scrollArea { scrolled = true; break }; q = p.specs[b].parent }
            if scrolled && (rects[a].w <= 0 || rects[a].h <= 0) { return true }
            j = p.specs[a].parent
        }
        return false
    }

    func apply(_ f: Frame) {
        core.set(f)
        let seq = engine.send([.pointerMove(Point(x: 0, y: 0))])
        _ = engine.wait(through: seq)
        MainActor.assumeIsolated { view.applyLatestFrame() }
    }

    func run(_ g: inout SplitMix, _ r: Recorder) {
        let p = Self.plan(&g)
        r.ran("ax.scroll")
        r.ran("ax.secure")
        for k in p.frames.indices {
            apply(Self.frame(p, k))
            let ok = MainActor.assumeIsolated { check(p, k, &g, r) }
            if !ok { return }
        }
        requests(&g, r)
    }

    /// One frame's tree, as an assistive app reads it.
    @MainActor
    func check(_ p: Plan, _ k: Int, _ g: inout SplitMix, _ r: Recorder) -> Bool {
        let (rects, focused) = p.frames[k]
        let n = p.specs.count
        let at = "frame \(k)"
        // The tree.
        var seen: [Int: NSAccessibilityElement] = [:]
        var order: [Int] = []
        var parentOf: [Int: Int?] = [:]
        var childrenOf: [Int?: [Int]] = [:]
        var ok = true
        func walk(_ els: [Any], under: Int?) {
            for case let el as NSAccessibilityElement in els {
                guard let lab = el.accessibilityLabel(), lab.hasPrefix("n"), let i = Int(lab.dropFirst()), i < n else {
                    r.fail("ax.scroll", "\(at): an element with label \(el.accessibilityLabel() ?? "nil") is no node")
                    ok = false
                    return
                }
                if seen[i] != nil {
                    r.fail("ax.scroll", "\(at): node \(i) is reached twice")
                    ok = false
                    return
                }
                seen[i] = el
                order.append(i)
                parentOf[i] = under
                childrenOf[under, default: []].append(i)
                let parent = el.accessibilityParent()
                let parentOK = under.map { u in (parent as? NSAccessibilityElement) === seen[u] } ?? ((parent as? NSView) === view)
                if !parentOK {
                    r.fail("ax.scroll", "\(at): node \(i)'s accessibilityParent is not \(under.map { "node \($0)" } ?? "the view")")
                    ok = false
                    return
                }
                walk(el.accessibilityChildren() ?? [], under: i)
            }
        }
        walk(view.accessibilityChildren() ?? [], under: nil)
        guard ok else { return false }
        let want = Set((0..<n).filter { !Self.hidden(p, rects, $0) })
        if Set(seen.keys) != want {
            let extra = Set(seen.keys).subtracting(want).sorted(), missing = want.subtracting(seen.keys).sorted()
            r.fail("ax.scroll", "\(at): reached \(extra.isEmpty ? "" : "scrolled-out nodes \(extra)")\(missing.isEmpty ? "" : " but not visible nodes \(missing)")")
            return false
        }
        for i in want {
            let fp = p.specs[i].parent
            if parentOf[i]! != fp {
                r.fail("ax.scroll", "\(at): node \(i) is under \(parentOf[i]!.map { "node \($0)" } ?? "the view"), its frame parent is \(fp.map { "node \($0)" } ?? "none")")
                return false
            }
            if p.specs[i].role == .scrollArea, seen[i]!.accessibilityRole() != .scrollArea {
                r.fail("ax.scroll", "\(at): scroll area node \(i) has role \(seen[i]!.accessibilityRole()?.rawValue ?? "nil")")
                return false
            }
        }
        for (parent, kids) in childrenOf where kids != kids.sorted() {
            r.fail("ax.scroll", "\(at): \(parent.map { "node \($0)" } ?? "the view")'s children \(kids) are out of frame order")
            return false
        }
        r.count("ax.scroll", "nodes reached", want.count)
        r.count("ax.scroll", "nodes scrolled out", n - want.count)
        // Focus: the last focused node's element, reached or not.
        let fe = view.accessibilityFocusedUIElement
        if let f = focused {
            let lab = (fe as? NSAccessibilityElement)?.accessibilityLabel()
            if lab != Self.label(f) {
                r.fail("ax.scroll", "\(at): node \(f) is focused but the focused element is \(lab ?? String(describing: fe))")
                return false
            }
            if !want.contains(f) { r.count("ax.scroll", "focused and scrolled out") }
        } else if (fe as? NSView) !== view {
            r.fail("ax.scroll", "\(at): no node is focused but the focused element is \(String(describing: fe))")
            return false
        }
        // Hit tests at random points of the view.
        for _ in 0..<8 {
            let pt = NSPoint(x: Double(g.range(0, 3999)) / 10, y: Double(g.range(0, 2999)) / 10)
            let screen = window.convertPoint(toScreen: view.convert(pt, to: nil))
            let hit = view.accessibilityHitTest(screen)
            if let el = hit as? NSAccessibilityElement {
                guard let lab = el.accessibilityLabel(), let i = Int(lab.dropFirst()), seen[i] === el else {
                    r.fail("ax.scroll", "\(at): a hit test at \(pt) answers \(el.accessibilityLabel() ?? "an element") the tree doesn't reach")
                    return false
                }
                if !el.accessibilityFrame().contains(screen) {
                    r.fail("ax.scroll", "\(at): a hit test at \(pt) answers node \(i), whose frame doesn't contain it")
                    return false
                }
                r.count("ax.scroll", "hits on a node")
            }
        }
        // Secure fields.
        var leak: String?
        func look(_ what: String, _ s: String?) { if leak == nil, let s, s.contains(p.marker) { leak = what } }
        for (i, el) in seen.sorted(by: { $0.key < $1.key }) {
            let s = p.specs[i]
            look("node \(i)'s label", el.accessibilityLabel())
            look("node \(i)'s title", el.accessibilityTitle())
            look("node \(i)'s value", el.accessibilityValue().map { "\($0)" })
            look("node \(i)'s identifier", el.accessibilityIdentifier())
            look("node \(i)'s selected text", el.accessibilitySelectedText())
            look("node \(i)'s string", el.accessibilityString(for: NSRange(location: 0, length: 1000)))
            if s.secure {
                r.count("ax.secure", "secure fields")
                let sel = el.accessibilitySelectedTextRange(), vis = el.accessibilityVisibleCharacterRange()
                let str = el.accessibilityString(for: NSRange(location: 0, length: 1000)) ?? ""
                guard r.expect("ax.secure", el.accessibilityRole() == .textField && el.accessibilitySubrole() == .secureTextField,
                               "\(at): secure node \(i) is \(el.accessibilityRole()?.rawValue ?? "nil")/\(el.accessibilitySubrole()?.rawValue ?? "nil")"),
                      r.expect("ax.secure", el.accessibilityValue() == nil, "\(at): secure node \(i) has a value"),
                      r.expect("ax.secure", el.accessibilityNumberOfCharacters() == 0 && (el.accessibilitySelectedText() ?? "").isEmpty
                                  && sel.length == 0 && vis.length == 0 && str.isEmpty,
                               "\(at): secure node \(i) shows text: \(el.accessibilityNumberOfCharacters()) characters, selection \(sel), visible \(vis)")
                else { return false }
            } else if s.role == .textField {
                let text = focused == i && s.control ? "typed\(i)" : "plain\(i)"
                guard r.expect("ax.secure", el.accessibilityValue() as? String == text && el.accessibilitySubrole() != .secureTextField,
                               "\(at): plain field \(i)'s value is \(el.accessibilityValue().map { "\($0)" } ?? "nil"), want \(text)")
                else { return false }
                r.count("ax.secure", "plain fields")
            }
        }
        if let fe = fe as? NSAccessibilityElement {
            look("the focused element's value", fe.accessibilityValue().map { "\($0)" })
            look("the focused element's selected text", fe.accessibilitySelectedText())
            look("the focused element's string", fe.accessibilityString(for: NSRange(location: 0, length: 1000)))
        }
        if let leak {
            r.fail("ax.secure", "\(at): the planted text is in \(leak)")
            return false
        }
        return true
    }

    /// `DebugJSON.describe` of `http` requests with planted headers, bodies and (when `redact`)
    /// URLs.
    func requests(_ g: inout SplitMix, _ r: Recorder) {
        for _ in 0..<4 {
            let m = "rq-" + String(g.next(), radix: 36)
            let redact = g.bool()
            let url = redact ? "https://example.test/x?password=\(m)" : "https://example.test/\(g.below(1000))"
            let secret: Secret? = g.bool()
                ? Secret(header: "Authorization", scheme: "Bearer ", source: .keychain(account: "acct"))
                : nil
            let req = Request.http(method: g.elem(["GET", "POST"]), url: url,
                                   headers: [Header("X-Plant", m)], body: Array(m.utf8), timeoutMs: 1000,
                                   secret: secret, capture: g.bool() ? [Capture("accessJwt", "a")] : [],
                                   redact: redact)
            let d = DebugJSON.describe(req)
            guard r.expect("ax.secure", !d.contains(m), "DebugJSON.describe shows a planted header, body or redacted URL: \(d)"),
                  r.expect("ax.secure", redact || d.contains(url), "DebugJSON.describe of a request that isn't redact lost its URL: \(d)")
            else { return }
            r.count("ax.secure", redact ? "redacted requests" : "plain requests")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        Self.plan(&g).description
    }
}

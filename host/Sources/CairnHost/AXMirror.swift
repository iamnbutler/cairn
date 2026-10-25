import AppKit
import CairnFrame

/// Mirrors each frame's `ax` nodes as `NSAccessibilityElement`s.
///
/// Elements are reused across frames by a stable key, so VoiceOver's cursor stays on the same
/// element while its properties change: a node with a control is keyed by its `ControlRef`
/// (`^5#12`), and a node without one by its parent's key, its role and its position among
/// siblings of that role. Every property is answered from the element's current node; screen
/// frames are computed on demand from the view, so they stay right when the window moves.
///
/// AppKit asks accessibility questions on the main thread, but its methods aren't annotated
/// that way, so the elements hop into the main actor with `onMain` (and answer empty if ever
/// asked from another thread).
@MainActor
final class AXMirror {
    private(set) var roots: [AXNodeElement] = []
    private(set) var byKey: [String: AXNodeElement] = [:]
    private(set) var ordered: [AXNodeElement] = []
    private(set) var focused: AXNodeElement?

    /// Applies a frame and posts notifications for what changed.
    func update(_ frame: Frame, host: HostView) {
        let nodes = frame.ax
        let keys = Self.keys(nodes)
        var next: [String: AXNodeElement] = [:]
        var created: [AXNodeElement] = []
        var textChanged: [AXNodeElement] = []
        var titleChanged: [AXNodeElement] = []
        var valueChanged: [AXNodeElement] = []
        var elements: [AXNodeElement] = []
        elements.reserveCapacity(nodes.count)
        let field = frame.textInput

        for (i, node) in nodes.enumerated() {
            let key = keys[i]
            let fieldText = node.control != nil && node.control == field?.control ? field : nil
            if let el = byKey[key], next[key] == nil {
                if node.role == .textField {
                    if (el.field?.text ?? el.node.value) != (fieldText?.text ?? node.value) { textChanged.append(el) }
                } else if el.node.value != node.value || el.node.checked != node.checked || el.node.selected != node.selected {
                    valueChanged.append(el)
                }
                if el.node.label != node.label { titleChanged.append(el) }
                el.node = node
                el.field = fieldText
                el.children = []
                next[key] = el
                elements.append(el)
            } else {
                let el = AXNodeElement(key: key, node: node, host: host)
                el.field = fieldText
                // A duplicate key (two nodes with the same control) still gets an element.
                if next[key] == nil { next[key] = el }
                created.append(el)
                elements.append(el)
            }
        }
        var newRoots: [AXNodeElement] = []
        let hidden = Self.hidden(nodes)
        for (i, node) in nodes.enumerated() {
            let el = elements[i]
            if hidden[i] {
                // Scrolled out of view: kept (so its element survives scrolling back) but exposed
                // nowhere.
                el.parentElement = nil
            } else if let p = node.parent, p >= 0, p < nodes.count, p != i, !Self.cycles(nodes, from: i) {
                el.parentElement = elements[p]
                elements[p].children.append(el)
            } else {
                el.parentElement = nil
                newRoots.append(el)
            }
        }
        let removed = byKey.values.filter { next[$0.key] !== $0 }
        let oldFocused = focused
        let oldSelection = oldFocused?.field.map { ($0.selection.start, $0.selection.end) }
        byKey = next
        ordered = elements
        roots = newRoots
        focused = elements.last { $0.node.focused }

        for el in removed { el.dead = true }

        // Posting on an element that isn't in a window hangs AppKit (Chromium), so a windowless
        // host (tests, before the window is up) updates silently. Order follows AccessKit: text
        // changes before selection changes, focus last; no per-frame layoutChanged.
        guard host.window != nil else { return }
        for el in removed { NSAccessibility.post(element: el, notification: .uiElementDestroyed) }
        if !created.isEmpty || !removed.isEmpty {
            NSAccessibility.post(element: host, notification: .layoutChanged,
                                 userInfo: created.isEmpty ? nil : [.uiElements: created])
        }
        for el in textChanged { NSAccessibility.post(element: el, notification: .valueChanged) }
        if let f = focused, f === oldFocused, let s = f.field, let o = oldSelection,
           o.0 != s.selection.start || o.1 != s.selection.end {
            NSAccessibility.post(element: f, notification: .selectedTextChanged)
        }
        for el in titleChanged { NSAccessibility.post(element: el, notification: .titleChanged) }
        // The focused node's value change goes last among value changes, so VoiceOver reads it.
        for el in valueChanged where el !== focused { NSAccessibility.post(element: el, notification: .valueChanged) }
        if let f = focused, valueChanged.contains(where: { $0 === f }) {
            NSAccessibility.post(element: f, notification: .valueChanged)
        }
        if focused !== oldFocused, let f = focused {
            NSAccessibility.post(element: f, notification: .focusedUIElementChanged)
        }
    }

    /// Stable keys for a frame's nodes (see the type's comment).
    static func keys(_ nodes: [AxNode]) -> [String] {
        var keys = [String?](repeating: nil, count: nodes.count)
        var ordinals: [String: Int] = [:]
        func key(_ i: Int, depth: Int) -> String {
            if let k = keys[i] { return k }
            let n = nodes[i]
            let k: String
            if let c = n.control {
                k = c.label
            } else {
                let parent = n.parent.flatMap { $0 >= 0 && $0 < nodes.count && $0 != i && depth < nodes.count ? key($0, depth: depth + 1) : nil } ?? ""
                let prefix = "\(parent)/\(n.role)"
                let o = ordinals[prefix, default: 0]
                ordinals[prefix] = o + 1
                k = "\(prefix).\(o)"
            }
            keys[i] = k
            return k
        }
        return nodes.indices.map { key($0, depth: 0) }
    }

    /// Which nodes are scrolled out of view: under a scroll area, with an empty rect (the frame
    /// gives each node its visible rect), or under such a node. A frame lists a parent before its
    /// children, so one pass in order sees every parent first; a parent that comes later is
    /// ignored here.
    static func hidden(_ nodes: [AxNode]) -> [Bool] {
        var hidden = [Bool](repeating: false, count: nodes.count)
        var scrolled = [Bool](repeating: false, count: nodes.count)
        for (i, n) in nodes.enumerated() {
            guard let p = n.parent, p >= 0, p < i else { continue }
            scrolled[i] = scrolled[p] || nodes[p].role == .scrollArea
            hidden[i] = hidden[p] || (scrolled[i] && (n.rect.w <= 0 || n.rect.h <= 0))
        }
        return hidden
    }

    /// Whether following parents from `i` loops (a malformed frame); such nodes become roots.
    static func cycles(_ nodes: [AxNode], from i: Int) -> Bool {
        var seen = Set<Int>()
        var j: Int? = i
        while let k = j {
            if !seen.insert(k).inserted { return true }
            j = nodes[k].parent.flatMap { $0 >= 0 && $0 < nodes.count ? $0 : nil }
        }
        return false
    }

    /// The deepest element whose frame contains a screen point.
    func hitTest(screenPoint p: NSPoint) -> AXNodeElement? {
        func search(_ els: [AXNodeElement]) -> AXNodeElement? {
            for el in els.reversed() where el.accessibilityFrame().contains(p) {
                return search(el.children) ?? el
            }
            return nil
        }
        return search(roots)
    }
}

/// One accessibility node. Used only on the main thread (AppKit's accessibility thread).
final class AXNodeElement: NSAccessibilityElement, @unchecked Sendable {
    let key: String
    var node: AxNode
    /// The frame's text input, when this node is the focused field.
    var field: TextInput?
    var children: [AXNodeElement] = []
    weak var parentElement: AXNodeElement?
    weak var host: HostView?
    /// The node left the frame. A client may still hold the element; it answers empty.
    var dead = false {
        didSet { if dead { children = []; parentElement = nil } }
    }

    init(key: String, node: AxNode, host: HostView) {
        self.key = key
        self.node = node
        self.host = host
        super.init()
    }

    override func isAccessibilityElement() -> Bool { !dead }
    override func accessibilityParent() -> Any? { dead ? nil : parentElement ?? host }
    override func accessibilityChildren() -> [Any]? { children }
    override func accessibilityIdentifier() -> String { node.control?.label ?? "" }
    override func isAccessibilityEnabled() -> Bool { true }
    override func isAccessibilityFocused() -> Bool { node.focused }
    override func isAccessibilitySelected() -> Bool { node.selected }

    override func accessibilityFrame() -> NSRect {
        // Computed from the view rather than set in parent space: the parent of a nested node
        // is another element, and parent space is y-up even under a flipped view
        // (docs/spike-boundary.md).
        guard !dead, let host else { return .zero }
        let r = node.rect.cg
        return onMain(.zero) { host.screenRect(r) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { Self.role(node.role) }

    /// A secure field is an `AXSecureTextField`, as `NSSecureTextField` is.
    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        if node.secure { return .secureTextField }
        return node.role == .tab ? NSAccessibility.Subrole(rawValue: "AXTabButton") : nil
    }

    override func accessibilityRoleDescription() -> String? {
        switch node.role {
        case .listItem: "list item"
        case .heading: "heading"
        default: NSAccessibility.Role.description(for: self)
        }
    }

    static func role(_ r: Role) -> NSAccessibility.Role {
        switch r {
        case .group, .listItem: .group
        case .button: .button
        case .checkbox: .checkBox
        case .text: .staticText
        case .textField: .textField
        case .link: .link
        case .list: .list
        case .heading: NSAccessibility.Role(rawValue: "AXHeading")
        case .tab: .radioButton
        case .scrollArea: .scrollArea
        }
    }

    override func accessibilityLabel() -> String? { node.label.isEmpty ? nil : node.label }
    override func accessibilityTitle() -> String? { node.role == .button || node.role == .heading ? node.label : nil }

    /// A secure field exposes no value, no text and no selection: not even its bullets.
    override func accessibilityValue() -> Any? {
        if node.secure { return nil }
        return switch node.role {
        case .checkbox, .tab: (node.checked ?? node.selected) ? 1 : 0
        case .textField: field?.text ?? node.value
        case .text: node.value.isEmpty ? node.label : node.value
        default: node.value.isEmpty ? nil : node.value
        }
    }

    override func accessibilityOrientation() -> NSAccessibilityOrientation {
        node.role == .list ? .vertical : .unknown
    }

    // MARK: Text fields (the focused one answers from the frame's text input)

    private var text: String { node.secure ? "" : field?.text ?? node.value }

    override func accessibilityNumberOfCharacters() -> Int { text.utf16.count }

    override func accessibilitySelectedTextRange() -> NSRange {
        guard !node.secure, let f = field else { return NSRange(location: text.utf16.count, length: 0) }
        return TextIndex(f.text).nsRange(scalars: Int(f.selection.start), Int(f.selection.end))
    }

    override func accessibilitySelectedText() -> String? {
        let r = accessibilitySelectedTextRange()
        return (text as NSString).substring(with: r)
    }

    override func accessibilityVisibleCharacterRange() -> NSRange { NSRange(location: 0, length: text.utf16.count) }
    override func accessibilityInsertionPointLineNumber() -> Int { 0 }

    override func accessibilityString(for range: NSRange) -> String? {
        let n = text.utf16.count
        guard range.location <= n else { return nil }
        return (text as NSString).substring(with: NSRange(location: range.location, length: min(range.length, n - range.location)))
    }

    // MARK: Actions

    /// A press is a real click at the node's centre, so it goes through Lean's hit testing.
    override func accessibilityPerformPress() -> Bool {
        guard !dead, node.control != nil, let host else { return false }
        let rect = node.rect
        return onMain(false) { host.click(at: rect); return true }
    }

    /// Focusing a field from an assistive app is a click on it, like a person would do.
    override func setAccessibilityFocused(_ focused: Bool) {
        guard !dead, focused, node.role == .textField, node.control != nil, !node.focused else { return }
        let rect = node.rect
        guard let host else { return }
        onMain(()) { host.click(at: rect) }
    }

    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformPress) { return node.control != nil }
        if selector == #selector(setAccessibilityFocused(_:)) { return node.role == .textField && node.control != nil }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}

/// Runs `body` on the main actor if this is the main thread, else returns `fallback`.
func onMain<T>(_ fallback: T, _ body: @MainActor () -> T) -> T {
    guard Thread.isMainThread else { return fallback }
    nonisolated(unsafe) var result = fallback
    MainActor.assumeIsolated { result = body() }
    return result
}

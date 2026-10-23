// The Swift mirror of lean/Cairn/Frame.lean and lean/Cairn/Input.lean. The decoder and event
// encoder (Decode.swift, Encode.swift) are generated against docs/frame.md; these types are
// the contract the renderer and host code against. Initializers are public so other modules
// (host, renderer, tests) can build values.

public struct Point: Equatable, Sendable {
    public var x, y: Int32
    public init(x: Int32, y: Int32) { self.x = x; self.y = y }
}
public struct Size: Equatable, Sendable {
    public var w, h: Int32
    public init(w: Int32, h: Int32) { self.w = w; self.h = h }
}
public struct Rect: Equatable, Sendable {
    public var x, y, w, h: Int32
    public init(x: Int32, y: Int32, w: Int32, h: Int32) { self.x = x; self.y = y; self.w = w; self.h = h }
}
public struct Color: Equatable, Sendable {
    public var r, g, b, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) { self.r = r; self.g = g; self.b = b; self.a = a }
}
public struct Border: Equatable, Sendable {
    public var width: UInt32; public var color: Color
    public init(width: UInt32, color: Color) { self.width = width; self.color = color }
}

public struct Font: Hashable, Sendable {
    public var family: UInt32  // 0 system UI, 1 system monospaced
    public var size: UInt32    // points
    public var weight: UInt32  // 100–900
    public var italic: Bool
    public init(family: UInt32 = 0, size: UInt32 = 13, weight: UInt32 = 400, italic: Bool = false) {
        self.family = family; self.size = size; self.weight = weight; self.italic = italic
    }
}

public enum Draw: Equatable, Sendable {
    case rect(Rect, fill: Color?, radius: UInt32, border: Border?)
    case text(origin: Point, font: Font, color: Color, string: String)  // origin: baseline left
    case pushClip(Rect)
    case popClip
}

public enum Role: UInt8, Sendable {
    case group, button, checkbox, text, textField, link, list, listItem, heading, tab
}

public struct ControlRef: Hashable, Sendable {
    public var claim: UInt32
    public var key: UInt32
    public init(claim: UInt32, key: UInt32 = 0) { self.claim = claim; self.key = key }
    /// `^5`, or `^5#12` for one instance of a repeated control.
    public var label: String { key == 0 ? "^\(claim)" : "^\(claim)#\(key)" }
}

public struct AxNode: Equatable, Sendable {
    public var control: ControlRef?
    public var role: Role
    public var rect: Rect
    public var label: String
    public var value: String
    public var parent: Int?
    public var focused: Bool
    public var selected: Bool
    public var checked: Bool?
    public init(control: ControlRef?, role: Role, rect: Rect, label: String, value: String = "",
                parent: Int? = nil, focused: Bool = false, selected: Bool = false, checked: Bool? = nil) {
        self.control = control; self.role = role; self.rect = rect; self.label = label; self.value = value
        self.parent = parent; self.focused = focused; self.selected = selected; self.checked = checked
    }
}

public struct TextInput: Equatable, Sendable {
    public var control: ControlRef
    public var rect: Rect
    public var caret: Rect
    public var text: String
    public var selection: (start: UInt32, end: UInt32)
    public var marked: (start: UInt32, end: UInt32)?
    public init(control: ControlRef, rect: Rect, caret: Rect, text: String,
                selection: (start: UInt32, end: UInt32), marked: (start: UInt32, end: UInt32)?) {
        self.control = control; self.rect = rect; self.caret = caret; self.text = text
        self.selection = selection; self.marked = marked
    }

    public static func == (a: TextInput, b: TextInput) -> Bool {
        a.control == b.control && a.rect == b.rect && a.caret == b.caret && a.text == b.text
            && a.selection == b.selection && a.marked?.start == b.marked?.start
            && a.marked?.end == b.marked?.end
    }
}

public enum Cursor: UInt8, Sendable { case arrow, pointer, text }

public enum Effect: Equatable, Sendable {
    case setClipboard(String)
    case beep
}

public struct Frame: Equatable, Sendable {
    public var size: Size
    public var draws: [Draw]
    public var ax: [AxNode]
    public var textInput: TextInput?
    public var cursor: Cursor
    public var effects: [Effect]
    public init(size: Size, draws: [Draw], ax: [AxNode] = [], textInput: TextInput? = nil,
                cursor: Cursor = .arrow, effects: [Effect] = []) {
        self.size = size; self.draws = draws; self.ax = ax; self.textInput = textInput
        self.cursor = cursor; self.effects = effects
    }
}

public struct Mods: Equatable, Sendable {
    public var shift = false, command = false, option = false, control = false
    public init(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift; self.command = command; self.option = option; self.control = control
    }
}

/// `[start, end)` in Unicode scalar indices into a field's text (Lean's `Nat × Nat`).
public struct ScalarRange: Equatable, Hashable, Sendable {
    public var start, end: UInt32
    public init(start: UInt32, end: UInt32) { self.start = start; self.end = end }
}

public enum Button: UInt8, Sendable { case primary, secondary }

public enum Key: Equatable, Sendable {
    case enter, escape, tab, backspace, delete
    case left, right, up, down, home, finish, pageUp, pageDown
    case char(Character)
}

public enum Event: Equatable, Sendable {
    case pointerMove(Point)
    case pointerDown(Point, Button, clicks: UInt32, Mods)
    case pointerUp(Point, Button, Mods)
    case pointerExit
    case scroll(Point, dx: Int32, dy: Int32)
    case key(Key, Mods)
    /// Committed text. Replaces `replacing` when given, else the marked text, else the selection.
    case insertText(String, replacing: ScalarRange? = nil)
    /// Composition: marked text with a selection inside it (scalar offsets into `s`), replacing
    /// `replacing`, else the marked text, else the selection. Empty `s` ends the composition.
    case setMarked(String, selStart: UInt32, selLen: UInt32, replacing: ScalarRange? = nil)
    case unmark
    case copy, cut, selectAll, undo, redo
    case paste(String)
    case resize(Size)
    case scale(percent: UInt32)
    case windowFocus(Bool)
}


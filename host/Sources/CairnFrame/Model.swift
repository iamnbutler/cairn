// The Swift mirror of lean/Cairn/Frame.lean and lean/Cairn/Input.lean. The decoder and event
// encoder (Decode.swift, Encode.swift) are generated against docs/frame.md; these types are
// the contract the renderer and host code against.

public struct Point: Equatable, Sendable { public var x, y: Int32 }
public struct Size: Equatable, Sendable { public var w, h: Int32 }
public struct Rect: Equatable, Sendable { public var x, y, w, h: Int32 }
public struct Color: Equatable, Sendable { public var r, g, b, a: UInt8 }
public struct Border: Equatable, Sendable { public var width: UInt32; public var color: Color }

public struct Font: Hashable, Sendable {
    public var family: UInt32  // 0 system UI, 1 system monospaced
    public var size: UInt32    // points
    public var weight: UInt32  // 100–900
    public var italic: Bool
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
}

public struct TextInput: Equatable, Sendable {
    public var control: ControlRef
    public var rect: Rect
    public var caret: Rect
    public var text: String
    public var selection: (start: UInt32, end: UInt32)
    public var marked: (start: UInt32, end: UInt32)?

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
}

public struct Mods: Equatable, Sendable {
    public var shift = false, command = false, option = false, control = false
    public init(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift; self.command = command; self.option = option; self.control = control
    }
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
    case insertText(String)
    case setMarked(String, selStart: UInt32, selLen: UInt32)
    case unmark
    case copy, cut, selectAll, undo, redo
    case paste(String)
    case resize(Size)
    case scale(percent: UInt32)
    case windowFocus(Bool)
}

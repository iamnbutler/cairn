import AppKit
import CairnFrame

/// How AppKit's key handling becomes `Event`s. Two paths:
///
/// - With a focused text field, keys go through `interpretKeyEvents`, so the input system (key
///   bindings, IME, dead keys) decides what they mean. Text arrives as `insertText`; everything
///   else arrives as a command selector, which `KeyMapping.command` names as a key by meaning.
/// - Without one, `KeyMapping.key` maps the raw key: named keys by key code, anything else as
///   `.char` with its modifiers (so a focused button can see Space, and shortcuts reach Lean).
///
/// The meaning of a modifier on a key is the Mac's: option moves by word, command by line
/// (`home`/`finish`) or document (command + `home`/`finish`), shift extends the selection. The
/// runtime turns these into `TextOp`s; the table is in docs/host.md.
public enum KeyMapping {
    /// The event for a text command selector, or nil if the host doesn't forward it.
    public static func command(_ selector: String) -> Event? {
        if let e = edits[selector] { return e }
        guard let (key, mods) = keys[selector] else { return nil }
        return .key(key, mods)
    }

    private static let shift = Mods(shift: true)
    private static let option = Mods(option: true)
    private static let optionShift = Mods(shift: true, option: true)
    private static let command = Mods(command: true)
    private static let commandShift = Mods(shift: true, command: true)
    private static let none = Mods()

    private static let edits: [String: Event] = [
        "selectAll:": .selectAll,
        "copy:": .copy, "cut:": .cut,
        "undo:": .undo, "redo:": .redo,
    ]

    private static let keys: [String: (Key, Mods)] = [
        "moveLeft:": (.left, none), "moveRight:": (.right, none),
        "moveUp:": (.up, none), "moveDown:": (.down, none),
        "moveBackward:": (.left, none), "moveForward:": (.right, none),
        "moveLeftAndModifySelection:": (.left, shift), "moveRightAndModifySelection:": (.right, shift),
        "moveUpAndModifySelection:": (.up, shift), "moveDownAndModifySelection:": (.down, shift),
        "moveBackwardAndModifySelection:": (.left, shift), "moveForwardAndModifySelection:": (.right, shift),

        "moveWordLeft:": (.left, option), "moveWordRight:": (.right, option),
        "moveWordBackward:": (.left, option), "moveWordForward:": (.right, option),
        "moveWordLeftAndModifySelection:": (.left, optionShift),
        "moveWordRightAndModifySelection:": (.right, optionShift),
        "moveWordBackwardAndModifySelection:": (.left, optionShift),
        "moveWordForwardAndModifySelection:": (.right, optionShift),

        "moveToBeginningOfLine:": (.home, none), "moveToEndOfLine:": (.finish, none),
        "moveToLeftEndOfLine:": (.home, none), "moveToRightEndOfLine:": (.finish, none),
        "moveToBeginningOfParagraph:": (.home, none), "moveToEndOfParagraph:": (.finish, none),
        "moveToBeginningOfLineAndModifySelection:": (.home, shift),
        "moveToEndOfLineAndModifySelection:": (.finish, shift),
        "moveToLeftEndOfLineAndModifySelection:": (.home, shift),
        "moveToRightEndOfLineAndModifySelection:": (.finish, shift),
        "moveToBeginningOfParagraphAndModifySelection:": (.home, shift),
        "moveToEndOfParagraphAndModifySelection:": (.finish, shift),
        "moveParagraphBackwardAndModifySelection:": (.home, shift),
        "moveParagraphForwardAndModifySelection:": (.finish, shift),

        "moveToBeginningOfDocument:": (.home, command), "moveToEndOfDocument:": (.finish, command),
        "moveToBeginningOfDocumentAndModifySelection:": (.home, commandShift),
        "moveToEndOfDocumentAndModifySelection:": (.finish, commandShift),
        "scrollToBeginningOfDocument:": (.home, command), "scrollToEndOfDocument:": (.finish, command),
        "pageUp:": (.pageUp, none), "pageDown:": (.pageDown, none),
        "scrollPageUp:": (.pageUp, none), "scrollPageDown:": (.pageDown, none),
        "pageUpAndModifySelection:": (.pageUp, shift), "pageDownAndModifySelection:": (.pageDown, shift),

        "deleteBackward:": (.backspace, none), "deleteForward:": (.delete, none),
        "deleteBackwardByDecomposingPreviousCharacter:": (.backspace, none),
        "deleteWordBackward:": (.backspace, option), "deleteWordForward:": (.delete, option),
        "deleteToBeginningOfLine:": (.backspace, command), "deleteToEndOfLine:": (.delete, command),
        "deleteToBeginningOfParagraph:": (.backspace, command), "deleteToEndOfParagraph:": (.delete, command),

        "insertNewline:": (.enter, none), "insertLineBreak:": (.enter, shift),
        "insertNewlineIgnoringFieldEditor:": (.enter, option),
        "insertParagraphSeparator:": (.enter, none),
        "insertTab:": (.tab, none), "insertBacktab:": (.tab, shift),
        "insertTabIgnoringFieldEditor:": (.tab, option),
        "cancelOperation:": (.escape, none),
    ]

    /// Every selector `command` forwards (for docs and tests).
    public static var forwardedSelectors: [String] { Array(keys.keys) + Array(edits.keys) }

    /// Named keys by virtual key code (kVK_* in Carbon's Events.h).
    public static func namedKey(keyCode: UInt16) -> Key? {
        switch keyCode {
        case 36, 76: .enter      // Return, keypad Enter
        case 53: .escape
        case 48: .tab
        case 51: .backspace
        case 117: .delete        // forward delete
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        case 115: .home
        case 119: .finish
        case 116: .pageUp
        case 121: .pageDown
        default: nil
        }
    }

    /// A key press outside a text field: a named key, or the character the key produces without
    /// modifiers (so command-K is `.char("k")` with `command`).
    public static func key(keyCode: UInt16, charactersIgnoringModifiers: String?, mods: Mods) -> Event? {
        keys(keyCode: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers, mods: mods).first
    }

    /// Every key one key event stands for. Synthesized events (accessibility tools, remote
    /// input) can carry several characters at once; each one is a key, in order, as if typed.
    public static func keys(keyCode: UInt16, charactersIgnoringModifiers: String?, mods: Mods) -> [Event] {
        if let k = namedKey(keyCode: keyCode) { return [.key(k, mods)] }
        return (charactersIgnoringModifiers ?? "").compactMap { c in
            guard !(c.unicodeScalars.first.map { (0xF700...0xF8FF).contains($0.value) } ?? true)  // function keys
            else { return nil }
            return .key(.char(Character(c.lowercased())), mods)
        }
    }

    /// The context-menu key: Shift-F10 (`.menu`, the shift is the key's own), or the Menu key of
    /// a PC keyboard (kVK_ContextualMenu) with its modifiers.
    public static func menuKey(keyCode: UInt16, mods: Mods) -> Event? {
        switch keyCode {
        case 109 where mods.shift && !mods.command && !mods.option && !mods.control:  // F10
            .key(.menu, Mods())
        case 110: .key(.menu, mods)
        default: nil
        }
    }

    public static func mods(_ flags: NSEvent.ModifierFlags) -> Mods {
        Mods(shift: flags.contains(.shift), command: flags.contains(.command),
             option: flags.contains(.option), control: flags.contains(.control))
    }
}

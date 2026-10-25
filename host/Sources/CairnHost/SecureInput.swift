import Carbon.HIToolbox
import CairnFrame

/// Secure event input while a secure field has focus, as `NSSecureTextField` does: with it on,
/// other processes can't read the keystrokes (an event tap or a global monitor sees none), so a
/// password typed into a Cairn app is as private as one typed into a system field.
///
/// It is on exactly while the view is live, its window is key, and the last applied frame's
/// text input is a secure field (`TextInput.secure`). The calls are counted by the system, so
/// the gate turns it on and off in pairs and never twice in a row (^1020, fuzzed by
/// `text.secure-input`; docs/trusted.md).
public struct SecureInputGate: Sendable {
    /// Turns the system's secure input on (`true`) or off.
    public typealias Toggle = @Sendable (Bool) -> Void
    public private(set) var on = false
    private let toggle: Toggle

    public init(toggle: @escaping Toggle = SecureInputGate.system) { self.toggle = toggle }

    /// `EnableSecureEventInput` and `DisableSecureEventInput`.
    public static let system: Toggle = { on in
        if on { _ = EnableSecureEventInput() } else { _ = DisableSecureEventInput() }
    }

    /// Whether the system says secure input is on (for this process or any other).
    public static var systemEnabled: Bool { IsSecureEventInputEnabled() }

    /// Whether secure input should be on.
    public static func wanted(textInput: TextInput?, windowKey: Bool, live: Bool) -> Bool {
        live && windowKey && textInput?.secure == true
    }

    /// Turns it on or off when that changes.
    public mutating func set(_ want: Bool) {
        guard want != on else { return }
        on = want
        toggle(want)
    }
}

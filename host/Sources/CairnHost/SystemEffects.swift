import AppKit
@preconcurrency import AVFoundation
import ApplicationServices
import CairnFrame

// `frontmostApp` and `permission` (docs/effects.md). Trusted: claims ^964 and ^965 in
// docs/trusted.md. Both read the system through a small struct of functions so the trusted-base
// fuzzer can check the logic against stubs: it never prompts the person.

/// The app in front, as the system reports it.
public enum Apps {
    /// `(pid, name)` of the frontmost app, or nil when there is none.
    public typealias Source = @Sendable () -> (pid: Int32, name: String?)?

    public static let live: Source = {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return (app.processIdentifier, app.localizedName)
    }

    /// `app pid name` (name "" when the app has none), or `failed notFound`.
    public static func frontmost(_ source: Source = live) -> Reply {
        guard let (pid, name) = source() else { return .failed(.notFound, "no app is in front") }
        guard pid > 0 else { return .failed(.other, "the app in front has no process id") }
        return .app(pid: UInt32(pid), name: name ?? "")
    }
}

/// The TCC calls behind `permission`.
public struct PermissionSystem: Sendable {
    /// `AXIsProcessTrustedWithOptions`, prompting when asked.
    public var accessibility: @Sendable (_ prompt: Bool) -> Bool
    public var microphone: @Sendable () -> AVAuthorizationStatus
    /// Asks the person for the microphone; answers whether it was granted.
    public var requestMicrophone: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void

    public init(accessibility: @escaping @Sendable (Bool) -> Bool,
                microphone: @escaping @Sendable () -> AVAuthorizationStatus,
                requestMicrophone: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void) {
        self.accessibility = accessibility
        self.microphone = microphone
        self.requestMicrophone = requestMicrophone
    }

    public static let live = PermissionSystem(
        // The kAXTrustedCheckOptionPrompt global is not concurrency-safe under Swift 6; its
        // value is this literal (as in Yap's PushToTalk).
        accessibility: { prompt in AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary) },
        microphone: { AVCaptureDevice.authorizationStatus(for: .audio) },
        requestMicrophone: { done in AVCaptureDevice.requestAccess(for: .audio) { done($0) } })
}

public enum Permissions {
    /// `flag granted`. With `prompt`: Accessibility shows the system's prompt (which opens
    /// System Settings) and answers at once with the current state; the microphone asks only
    /// while undecided and answers with the person's choice. A refused permission can't be
    /// asked for again; the person changes it in System Settings.
    public static func check(_ p: Permission, prompt: Bool, _ sys: PermissionSystem = .live,
                             _ reply: @escaping @Sendable (Reply) -> Void) {
        switch p {
        case .accessibility:
            reply(.flag(sys.accessibility(prompt)))
        case .microphone:
            switch sys.microphone() {
            case .authorized: reply(.flag(true))
            case .notDetermined where prompt: sys.requestMicrophone { reply(.flag($0)) }
            default: reply(.flag(false))
            }
        }
    }
}

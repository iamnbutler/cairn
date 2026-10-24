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

// `openItem`, `appRunning` and `readDefault` (docs/effects.md). Trusted: claims ^1000–^1002 in
// docs/trusted.md. Each reads the system through a small struct of functions, so the trusted-base
// fuzzer checks the logic against stubs: it never opens anything or reads real defaults.

/// What `openItem`, `appRunning` and `readDefault` reach.
public struct Workspace: Sendable {
    /// `NSWorkspace.open`: whether the system took the URL.
    public var open: @Sendable (URL) -> Bool
    /// Whether a file exists at the path.
    public var exists: @Sendable (String) -> Bool
    /// The running apps with this bundle identifier, not counting ones that have terminated.
    public var running: @Sendable (String) -> Int
    /// `CFPreferencesCopyAppValue(key, domain)`.
    public var value: @Sendable (_ key: String, _ domain: String) -> Any?

    public init(open: @escaping @Sendable (URL) -> Bool, exists: @escaping @Sendable (String) -> Bool,
                running: @escaping @Sendable (String) -> Int,
                value: @escaping @Sendable (String, String) -> Any?) {
        self.open = open; self.exists = exists; self.running = running; self.value = value
    }

    public static let live = Workspace(
        open: { url in NSWorkspace.shared.open(url) },
        exists: { FileManager.default.fileExists(atPath: $0) },
        running: { id in
            NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }.count
        },
        value: { key, domain in CFPreferencesCopyAppValue(key as CFString, domain as CFString) })

    /// Opens nothing, runs nothing, has no defaults. For tests.
    public static let inert = Workspace(open: { _ in false }, exists: { _ in false }, running: { _ in 0 },
                                        value: { _, _ in nil })
}

public enum Opening {
    /// A target with a URL scheme (`x-apple.systempreferences:…`, `https://…`), as opposed to a
    /// path: letters, digits, `+`, `-` or `.` before the first `:`, starting with a letter, and
    /// not starting with `/` or `~`.
    static func scheme(_ t: String) -> Bool {
        guard let colon = t.firstIndex(of: ":"), colon != t.startIndex else { return false }
        let s = t[..<colon]
        guard let f = s.first, f.isASCII, f.isLetter else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }

    /// `done` once the system took the target; a path that doesn't exist is `notFound`, an
    /// empty target or one with NUL `invalid`, and one the system refused `failed other`.
    public static func open(_ target: String, _ ws: Workspace = .live) -> Reply {
        if target.isEmpty { return .failed(.invalid, "empty target") }
        if target.utf8.contains(0) { return .failed(.invalid, "NUL in target") }
        let url: URL
        if scheme(target) {
            guard let u = URL(string: target) else { return .failed(.invalid, "not a URL") }
            url = u
        } else {
            let path = Files.expand(target)
            guard ws.exists(path) else { return .failed(.notFound, "no such file") }
            url = URL(fileURLWithPath: path)
        }
        return ws.open(url) ? .done : .failed(.other, "the system would not open it")
    }

    /// `flag running`; an empty identifier is `invalid`.
    public static func running(_ bundleId: String, _ ws: Workspace = .live) -> Reply {
        if bundleId.isEmpty || bundleId.utf8.contains(0) { return .failed(.invalid, "empty bundle identifier") }
        return .flag(ws.running(bundleId) > 0)
    }

    /// `bytes` of the value as UTF-8 text: a string as it is, a boolean as `1` or `0`, a number
    /// as its decimal text. Missing is `notFound`; any other type (data, arrays, dates) `invalid`.
    public static func readDefault(_ domain: String, _ key: String, _ ws: Workspace = .live) -> Reply {
        if domain.isEmpty || key.isEmpty || domain.utf8.contains(0) || key.utf8.contains(0) {
            return .failed(.invalid, "empty domain or key")
        }
        guard let v = ws.value(key, domain) else { return .failed(.notFound, "no such default") }
        if let s = v as? String { return .bytes(Array(s.utf8)) }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bytes(Array((n.boolValue ? "1" : "0").utf8)) }
            return .bytes(Array(n.stringValue.utf8))
        }
        return .failed(.invalid, "not a string, number or boolean")
    }
}

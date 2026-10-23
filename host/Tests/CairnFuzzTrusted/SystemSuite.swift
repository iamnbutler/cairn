@preconcurrency import AVFoundation
import AppKit
import CairnFrame
import CairnHost
import Foundation

/// `frontmostApp`, `permission`, `openItem`, `appRunning` and `readDefault`, without prompting
/// anyone, opening anything or reading real defaults:
///
/// - `effects.frontmost-app`: against stubbed sources, the pid and name come back exactly (any
///   name, none, no app at all is `notFound`); the live answer names a running process whose
///   name is its `NSRunningApplication`'s.
/// - `effects.permission`: against a stubbed system, every status and prompt flag gives the
///   answer docs/effects.md describes, the system is asked to prompt exactly when `prompt` is
///   set (the microphone only while undecided), and each request is answered once; the live
///   answers without a prompt equal `AXIsProcessTrusted` and the microphone's status.
/// - `effects.open-item`: against a stubbed workspace, a target with a scheme is opened as that
///   URL, a path (`~/` expanded) as a file URL only when it exists, and the answer is done exactly
///   when the stub took it; empty and NUL targets are invalid and nothing is opened.
/// - `effects.app-running`: the flag is whether the stub counts a running app with that id; live,
///   it agrees with `NSRunningApplication` for the Finder and for an id no app has.
/// - `effects.read-default`: strings come back as their UTF-8, booleans as 1 or 0, numbers as
///   their decimal text, missing as notFound and other types as invalid, read from the domain
///   and key asked for.
final class SystemSuite: Suite {
    let name = "system"
    let crashCheck = "effects.permission"
    let checks: [String: CheckInfo] = [
        "effects.frontmost-app": CheckInfo(
            title: "`frontmostApp` answers the app in front's pid and name",
            trusted: ["host/Sources/CairnHost/SystemEffects.swift (Apps)", "NSWorkspace"],
            oracle: "the stub's answer; NSRunningApplication and kill(pid, 0) for the live one"),
        "effects.permission": CheckInfo(
            title: "`permission` answers whether the app holds it, and prompts only when asked",
            trusted: ["host/Sources/CairnHost/SystemEffects.swift (Permissions)", "TCC"],
            oracle: "a stubbed TCC: its statuses and the calls made; AXIsProcessTrusted and AVCaptureDevice for live"),
        "effects.open-item": CheckInfo(
            title: "`openItem` opens exactly the URL or existing file it names",
            trusted: ["host/Sources/CairnHost/SystemEffects.swift (Opening.open)", "NSWorkspace.open"],
            oracle: "a stubbed workspace: the URLs it was asked to open and its answers"),
        "effects.app-running": CheckInfo(
            title: "`appRunning` answers whether an app with that bundle id runs",
            trusted: ["host/Sources/CairnHost/SystemEffects.swift (Opening.running)", "NSRunningApplication"],
            oracle: "a stubbed workspace; NSRunningApplication for the live Finder"),
        "effects.read-default": CheckInfo(
            title: "`readDefault` answers the default's value as text",
            trusted: ["host/Sources/CairnHost/SystemEffects.swift (Opening.readDefault)", "CFPreferences"],
            oracle: "a stubbed defaults store and the value's own text"),
    ]

    func cases(for n: Int) -> Int { max(2, n / 4) }
    func setUp() {}

    func run(_ g: inout SplitMix, _ r: Recorder) {
        frontmost(&g, r)
        permission(&g, r)
        openItem(&g, r)
        appRunning(&g, r)
        readDefault(&g, r)
    }

    func openItem(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.open-item"
        let exists = g.bool(), takes = g.bool()
        let opened = Locked<[URL]>([])
        let ws = Workspace(open: { u in opened.update { $0.append(u) }; return takes },
                           exists: { _ in exists }, running: { _ in 0 }, value: { _, _ in nil })
        let target: String
        let want: URL?
        switch g.below(5) {
        case 0:
            target = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            want = URL(string: target)
        case 1:
            target = "https://example.com/" + String(g.below(1000))
            want = URL(string: target)
        case 2:
            let name = "yap " + String(g.below(100)) + ".txt"
            target = "~/Library/Application Support/yap/" + name
            want = exists ? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/yap/" + name) : nil
        case 3:
            target = "/tmp/" + String(g.below(100))
            want = exists ? URL(fileURLWithPath: target) : nil
        default:
            target = g.bool() ? "" : "a\u{0}b"
            want = nil
        }
        let got = Opening.open(target, ws)
        r.expect(c, opened.value == (want.map { [$0] } ?? []), "open \(target): opened \(opened.value), want \(String(describing: want))")
        if target.isEmpty || target.contains("\u{0}") {
            if case .failed(.invalid, _) = got { r.ran(c) } else { r.fail(c, "open \(target.debugDescription) is \(got)") }
        } else if want == nil {
            if case .failed(.notFound, _) = got { r.ran(c) } else { r.fail(c, "open missing \(target) is \(got)") }
        } else if takes {
            r.expect(c, got == .done, "open \(target) taken: \(got)")
        } else if case .failed(.other, _) = got { r.ran(c) } else { r.fail(c, "open \(target) refused: \(got)") }
        r.count(c, want == nil ? "refused" : "opened")
    }

    func appRunning(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.app-running"
        let n = g.below(3)
        let id = g.elem(["dev.yap.Yap", "com.apple.finder", TextPool.string(&g)])
        let asked = Locked<[String]>([])
        let ws = Workspace(open: { _ in false }, exists: { _ in false },
                           running: { b in asked.update { $0.append(b) }; return n }, value: { _, _ in nil })
        let got = Opening.running(id, ws)
        if id.isEmpty || id.utf8.contains(0) {
            if case .failed(.invalid, _) = got { r.ran(c) } else { r.fail(c, "appRunning \(id.debugDescription) is \(got)") }
            r.expect(c, asked.value.isEmpty, "the system was asked about an invalid id")
        } else {
            r.expect(c, got == .flag(n > 0) && asked.value == [id], "appRunning \(id) with \(n) running: \(got), asked \(asked.value)")
        }
        if g.chance(1, 8) {
            let finder = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty
            r.expect(c, Opening.running("com.apple.finder") == .flag(finder), "live Finder")
            r.expect(c, Opening.running("dev.cairn.no-such-app") == .flag(false), "live: an id no app has is running")
            r.count(c, "live")
        }
    }

    func readDefault(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.read-default"
        let domain = g.elem(["dev.yap.Yap", "NSGlobalDomain", ""]), key = g.elem(["model", "enabled", "submits", ""])
        let s = TextPool.string(&g)
        let i = Int(truncatingIfNeeded: g.next() % 1_000_000) - 500_000
        let choice = g.below(6)
        let values: [Any?] = [s, NSNumber(value: g.bool()), NSNumber(value: i), nil, Data([1, 2]), [1, 2] as NSArray]
        let value = values[choice]
        let asked = Locked<[String]>([])
        let ws = Workspace(open: { _ in false }, exists: { _ in false }, running: { _ in 0 },
                           value: { k, d in asked.update { $0.append(d + " " + k) }; return value })
        let got = Opening.readDefault(domain, key, ws)
        if domain.isEmpty || key.isEmpty {
            if case .failed(.invalid, _) = got { r.ran(c) } else { r.fail(c, "readDefault '\(domain)' '\(key)' is \(got)") }
            return
        }
        r.expect(c, asked.value == [domain + " " + key], "asked \(asked.value)")
        switch value {
        case let v as String: r.expect(c, got == .bytes(Array(v.utf8)), "string \(v.debugDescription): \(got)")
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
            r.expect(c, got == .bytes(Array((n.boolValue ? "1" : "0").utf8)), "bool \(n): \(got)")
        case let n as NSNumber: r.expect(c, got == .bytes(Array(String(n.intValue).utf8)), "number \(n): \(got)")
        case nil:
            if case .failed(.notFound, _) = got { r.ran(c) } else { r.fail(c, "missing is \(got)") }
        default:
            if case .failed(.invalid, _) = got { r.ran(c) } else { r.fail(c, "other type is \(got)") }
        }
        r.count(c, ["string", "bool", "number", "missing", "data", "array"][choice])
    }

    func frontmost(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.frontmost-app"
        let pid = Int32(g.elem([1, 2, 99, 65535, Int(Int32.max)]))
        let name: String? = g.chance(1, 4) ? nil : TextPool.string(&g)
        let got = Apps.frontmost { (pid, name) }
        r.expect(c, got == .app(pid: UInt32(pid), name: name ?? ""), "frontmost of (\(pid), \(String(describing: name))) is \(got)")
        let none = Apps.frontmost { nil }
        if case .failed(.notFound, _) = none { r.ran(c) } else { r.fail(c, "no app in front is \(none)") }
        if case .failed = Apps.frontmost({ (0, "x") }) { r.ran(c) } else { r.fail(c, "pid 0 is not failed") }
        if case .failed = Apps.frontmost({ (-1, "x") }) { r.ran(c) } else { r.fail(c, "pid -1 is not failed") }
        if g.chance(1, 8) {
            switch Apps.frontmost() {
            case let .app(pid, name):
                let app = NSRunningApplication(processIdentifier: pid_t(pid))
                r.expect(c, kill(pid_t(pid), 0) == 0 || errno == EPERM, "the live frontmost pid \(pid) is not a process")
                r.expect(c, app != nil && (app?.localizedName ?? "") == name, "live frontmost \(pid) \(name) vs \(String(describing: app?.localizedName))")
                r.count(c, "live")
            case .failed(.notFound, _): r.count(c, "liveNone")
            case let other: r.fail(c, "live frontmost: \(other)")
            }
        }
    }

    func permission(_ g: inout SplitMix, _ r: Recorder) {
        let c = "effects.permission"
        let trusted = g.bool()
        let status = g.elem([AVAuthorizationStatus.notDetermined, .restricted, .denied, .authorized])
        let grant = g.bool()
        let prompt = g.bool()
        let p = g.elem([Permission.accessibility, .microphone])
        let delay = g.below(3)
        let calls = Locked<[String]>([])
        let sys = PermissionSystem(
            accessibility: { pr in calls.update { $0.append("ax \(pr)") }; return trusted },
            microphone: { calls.update { $0.append("mic") }; return status },
            requestMicrophone: { done in
                calls.update { $0.append("ask") }
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delay)) { done(grant) }
            })
        let replies = Locked<[Reply]>([])
        let sem = DispatchSemaphore(value: 0)
        Permissions.check(p, prompt: prompt, sys) { rep in replies.update { $0.append(rep) }; sem.signal() }
        guard sem.wait(timeout: .now() + 2) == .success else { r.fail(c, "no answer for \(p) prompt=\(prompt)"); return }
        usleep(5000)
        let want: Bool, wantCalls: [String]
        switch p {
        case .accessibility:
            want = trusted; wantCalls = ["ax \(prompt)"]
        case .microphone:
            let ask = status == .notDetermined && prompt
            want = status == .authorized || (ask && grant)
            wantCalls = ask ? ["mic", "ask"] : ["mic"]
        }
        r.expect(c, replies.value == [.flag(want)], "\(p) status=\(status.rawValue) trusted=\(trusted) prompt=\(prompt) grant=\(grant): \(replies.value), want \(want)")
        r.expect(c, calls.value == wantCalls, "\(p) prompt=\(prompt): the system was called \(calls.value), want \(wantCalls)")
        r.count(c, prompt ? "prompted" : "quiet")

        // The live system, never prompting.
        if g.chance(1, 8) {
            let live = Locked<Reply?>(nil)
            let s2 = DispatchSemaphore(value: 0)
            Permissions.check(.accessibility, prompt: false) { live.value = $0; s2.signal() }
            s2.wait()
            r.expect(c, live.value == .flag(AXIsProcessTrusted()), "live accessibility \(String(describing: live.value))")
            Permissions.check(.microphone, prompt: false) { live.value = $0; s2.signal() }
            s2.wait()
            r.expect(c, live.value == .flag(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized),
                     "live microphone \(String(describing: live.value))")
            r.count(c, "live")
        }
    }

    func describe(_ g: inout SplitMix, reproDir: URL, caseIndex: Int) -> String {
        "frontmostApp, permission, openItem, appRunning and readDefault against stubs (and, sometimes, the live system without prompts)"
    }
}

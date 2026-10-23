@preconcurrency import AVFoundation
import AppKit
import CairnFrame
import CairnHost
import Foundation

/// `frontmostApp` and `permission`, without prompting anyone:
///
/// - `effects.frontmost-app`: against stubbed sources, the pid and name come back exactly (any
///   name, none, no app at all is `notFound`); the live answer names a running process whose
///   name is its `NSRunningApplication`'s.
/// - `effects.permission`: against a stubbed system, every status and prompt flag gives the
///   answer docs/effects.md describes, the system is asked to prompt exactly when `prompt` is
///   set (the microphone only while undecided), and each request is answered once; the live
///   answers without a prompt equal `AXIsProcessTrusted` and the microphone's status.
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
    ]

    func cases(for n: Int) -> Int { max(2, n / 4) }
    func setUp() {}

    func run(_ g: inout SplitMix, _ r: Recorder) {
        frontmost(&g, r)
        permission(&g, r)
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
        "frontmostApp and permission against stubs (and, sometimes, the live system without prompts)"
    }
}

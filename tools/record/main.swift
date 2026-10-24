// Records one window, and nothing else on screen, to a .mov file.
//
//   record --pid <pid> [--title <substring>] --out <file.mov> [--seconds N]
//   record --pid <pid> --window <id> [--wait S] [--size WxH] --out <file.mov> [--seconds N]
//
// Without --window it takes the app's first normal (layer 0) window. --window takes that one
// window by its CGWindowID, at any layer (a non-activating panel, like Yap's overlay), and only
// if it belongs to <pid>. --wait polls up to S seconds for it to come on screen. --size sets the
// output in points (default: the window's size when recording starts), for a window that grows.
//
// Recording stops after N seconds, on SIGINT/SIGTERM, or when the window closes.
// ScreenCaptureKit's desktop-independent window filter captures only that window's
// pixels, so other apps never end up in a recording.

import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

var pid: pid_t?
var title: String?
var out: String?
var seconds: Double?
var windowID: CGWindowID?
var waitSeconds = 0.0
var size: CGSize?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--pid": pid = args.next().flatMap { pid_t($0) }
    case "--title": title = args.next()
    case "--out": out = args.next()
    case "--seconds": seconds = args.next().flatMap { Double($0) }
    case "--window": windowID = args.next().flatMap { CGWindowID($0) }
    case "--wait": waitSeconds = args.next().flatMap { Double($0) } ?? 0
    case "--size":
        let wh = (args.next() ?? "").split(separator: "x").compactMap { Double($0) }
        guard wh.count == 2 else { fail("--size takes WxH in points") }
        size = CGSize(width: wh[0], height: wh[1])
    default: fail("unknown argument \(arg)")
    }
}
guard let pidArg = pid, let outArg = out else {
    fail("usage: record --pid <pid> [--title <s> | --window <id> [--wait S]] [--size WxH] --out <file.mov> [--seconds N]")
}

final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    let pid: pid_t
    let title: String?
    let out: String
    var stream: SCStream?
    var done: (() -> Void)?

    init(pid: pid_t, title: String?, out: String) {
        self.pid = pid
        self.title = title
        self.out = out
    }

    func find() async throws -> SCWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // Always the one window, and always one that <pid> owns.
        return content.windows.first { w in
            guard w.owningApplication?.processID == pid else { return false }
            if let id = windowID { return w.windowID == id }
            return w.windowLayer == 0 && (title == nil || (w.title ?? "").contains(title!))
        }
    }

    func start() async throws {
        let deadline = Date(timeIntervalSinceNow: waitSeconds)
        var found = try await find()
        while found == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            found = try await find()
        }
        guard let window = found else { fail("no on-screen window for pid \(pid)") }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let points = size ?? window.frame.size
        config.width = Int(points.width * scale)
        config.height = Int(points.height * scale)
        config.scalesToFit = false  // a window that grows keeps its scale (top left), not squeezed
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false  // the real pointer sits wherever the person left it; it is never part of the demo
        config.capturesAudio = false

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = URL(fileURLWithPath: out)
        recording.outputFileType = .mov
        recording.videoCodecType = .hevc
        let output = SCRecordingOutput(configuration: recording, delegate: self)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        self.stream = stream
        FileHandle.standardError.write("recording window \(window.windowID) \(config.width)x\(config.height) to \(out)\n".data(using: .utf8)!)
    }

    func stop() async {
        try? await stream?.stopCapture()
    }

    func finish() {
        DispatchQueue.main.async { self.done?(); self.done = nil }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finish() }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        fail("recording failed: \(error)")
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The window closed or capture was interrupted; the file is finalised either way.
        finish()
    }
}

_ = NSApplication.shared
let recorder = Recorder(pid: pidArg, title: title, out: outArg)
let stopSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { Task { await recorder.stop() } }
    source.resume()
    return source
}

Task {
    do { try await recorder.start() } catch { fail("could not start: \(error)") }
    if let seconds {
        try? await Task.sleep(for: .seconds(seconds))
        await recorder.stop()
    }
}
recorder.done = { exit(0) }
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

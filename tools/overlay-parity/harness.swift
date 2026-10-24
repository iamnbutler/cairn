// yapref: reference captures of Yap's overlay (the real OverlayView and
// WaveRenderer from a patched copy of Overlay.swift), for pixel comparison.
//
//   yapref <scene.json> [--out <dir>]          one PNG + JSON per state
//   yapref --motion <script.json> --out <dir>  real-time timeline, 60 fps SCStream frames
//
// Only this process's own window is ever captured: ScreenCaptureKit's
// desktop-independent window filter on the panel's window id, owned by our pid.
//
// Scene: {"levelsRecipe"?: str, "states": [{"name", "phase": listening|handsFree|transcribing|typed|failed,
//   "text", "clockSeconds", "time", "elapsed", "levels": [120 floats, oldest first], "cuts": [seconds],
//   "levelsRecipe"?: str}]}. active and tint follow from phase via the original Overlay.update().
//
// Motion script: {"initial": <state without name>, "waveform": "frozen"|"advance", "lead": s before
//   the first event (default 0.3), "duration": s after the first event, "captureHeight": pt (default 420),
//   "events": [{"at": s, "phase"?: str, "text"?: str, "hide"?: true}]}.
//   frozen: the waveform is drawn with the initial values (and redrawn on phase events for tint/active).
//   advance: on every 60 Hz display-link frame, time = initial.time + (targetTimestamp - scheduled first
//   event) and elapsed += frame interval while the phase is active; levels and cuts stay as given.
//   The clock text is always frozen at clockSeconds. Output: frame-NNNNN.png + index.json.

import AppKit
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("yapref: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

/// mach host time in seconds; the clock SCStream presentation timestamps use.
func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

// MARK: - Input

struct State: Decodable {
    var name: String?
    var phase: String
    var text: String?
    var clockSeconds: Double?
    var time: Float?
    var elapsed: Float?
    var levels: [Float]
    var cuts: [Float]?
    /// Optional free-form description of how `levels` was made; echoed to the output JSON.
    var levelsRecipe: String?
}

struct Scene: Decodable {
    var states: [State]
    var levelsRecipe: String?
}

struct MotionEvent: Decodable {
    var at: Double
    var phase: String?
    var text: String?
    var hide: Bool?
}

struct MotionScript: Decodable {
    /// The state shown before the first event (its `name` is ignored).
    var initial: State
    /// "frozen": waveform drawn once with `initial`'s values. "advance": every
    /// display frame (60 Hz) sets time = initial.time + t and advances elapsed
    /// by the frame interval while the phase is active, t measured from the first event.
    var waveform: String?
    /// Seconds of capture before the first event.
    var lead: Double?
    /// Seconds of capture after the first event.
    var duration: Double
    /// Height of the capture buffer in points (the window can grow to this).
    var captureHeight: Double?
    var events: [MotionEvent]
    var levelsRecipe: String?
}

func phase(_ name: String) -> OverlayModel.Phase {
    switch name {
    case "listening": .listening
    case "handsFree": .handsFree
    case "transcribing": .transcribing
    case "typed": .typed
    case "failed": .failed
    default: fail("unknown phase \(name)")
    }
}

// MARK: - Harness

@MainActor
final class Harness {
    let overlay = Overlay(level: { 0 })
    var renderer: WaveRenderer { overlay.renderer }
    var panel: NSPanel { overlay.panel! }
    private var lastPresented = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init() {
        renderer.presented = { [weak self] frame in self?.didPresent(frame) }
        // The real begin(): makes the panel exactly as makePanel() does and shows
        // it at the bottom centre of the screen the pointer is on, as place() does.
        overlay.begin(1)
    }

    private func didPresent(_ frame: Int) {
        lastPresented = max(lastPresented, frame)
        let ready = waiters.filter { $0.0 <= lastPresented }
        waiters.removeAll { $0.0 <= lastPresented }
        for (_, c) in ready { c.resume() }
    }

    /// Sets everything a state says, through the original's own update() where it can.
    func apply(_ s: State) {
        guard s.levels.count == 120 else { fail("\(s.name ?? "state"): levels must have 120 entries, has \(s.levels.count)") }
        overlay.update(1, phase: phase(s.phase), text: s.text ?? "")
        setClock(s.clockSeconds ?? 0)
        renderer.time = s.time ?? 0
        renderer.elapsed = s.elapsed ?? 0
        renderer.levels = s.levels
        renderer.cuts = s.cuts ?? []
    }

    /// The clock shows Int(stopped - started): both fixed, exactly representable.
    func setClock(_ seconds: Double) {
        overlay.model.started = Date(timeIntervalSinceReferenceDate: 0)
        overlay.model.stopped = Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Draws the waveform once and waits until that frame has been presented.
    func drawAndWait() async {
        guard let view = renderer.view else { fail("no MTKView") }
        let before = renderer.frameCount
        view.draw()
        let target = renderer.frameCount
        if target == before { fail("waveform did not draw (no drawable or pipeline)") }
        if lastPresented >= target { return }
        await withCheckedContinuation { c in waiters.append((target, c)) }
    }

    /// Waits until the panel's frame has not changed for `quiet` seconds.
    func settle(quiet: Double = 0.35, timeout: Double = 3) async {
        var last = panel.frame
        var stableSince = hostNow()
        let start = hostNow()
        while hostNow() - start < timeout {
            try? await Task.sleep(for: .milliseconds(16))
            if panel.frame != last { last = panel.frame; stableSince = hostNow() }
            if hostNow() - stableSince >= quiet { return }
        }
    }

    func scWindow() async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = CGWindowID(panel.windowNumber)
        guard let w = content.windows.first(where: { $0.windowID == id && $0.owningApplication?.processID == getpid() })
        else { fail("own window \(id) not in shareable content") }
        return w
    }

    /// Geometry of the waveform, in window points (both origins given).
    func geometry() -> [String: Any] {
        let scale = panel.backingScaleFactor
        var info: [String: Any] = [
            "windowSizePoints": ["width": panel.frame.width, "height": panel.frame.height],
            "windowFrameOnScreenPoints": rect(panel.frame),
            "backingScale": scale,
            "screen": panel.screen?.localizedName ?? "",
        ]
        if let view = renderer.view {
            let r = view.convert(view.bounds, to: nil)  // window coords, origin bottom-left
            var top = r
            top.origin.y = panel.frame.height - r.maxY
            info["waveformFrameWindowPointsBottomLeftOrigin"] = rect(r)
            info["waveformFrameWindowPointsTopLeftOrigin"] = rect(top)
            info["waveformDrawableSizePixels"] = ["width": view.drawableSize.width, "height": view.drawableSize.height]
            info["waveformColorPixelFormat"] = "bgra8Unorm"
            info["waveformLayerColorspace"] = (view.layer as? CAMetalLayer)?.colorspace?.name as String? ?? "nil (uncorrected)"
        }
        return info
    }
}

func rect(_ r: CGRect) -> [String: Double] {
    ["x": r.origin.x, "y": r.origin.y, "width": r.width, "height": r.height]
}

extension WaveRenderer {
    var frameCount: Int { frames }
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { fail("cannot write \(url.path)") }
}

func writeJSON(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

func alphaName(_ info: CGImageAlphaInfo) -> String {
    switch info {
    case .premultipliedFirst: "premultipliedFirst"
    case .premultipliedLast: "premultipliedLast"
    case .first: "first"
    case .last: "last"
    case .noneSkipFirst: "noneSkipFirst"
    case .noneSkipLast: "noneSkipLast"
    case .none: "none"
    default: "other(\(info.rawValue))"
    }
}

func captureConfig(width: Double, height: Double, scale: Double) -> SCStreamConfiguration {
    let config = SCStreamConfiguration()
    config.width = Int((width * scale).rounded())
    config.height = Int((height * scale).rounded())
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = false
    config.capturesAudio = false
    config.ignoreShadowsSingleWindow = true  // the panel has no window shadow anyway (hasShadow = false)
    config.shouldBeOpaque = false
    config.scalesToFit = false
    config.captureResolution = .best
    return config
}

// MARK: - Stills

@MainActor
func runScene(_ scene: Scene, out: URL) async {
    let h = Harness()
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (index, s) in scene.states.enumerated() {
        let name = s.name ?? "state-\(index)"
        h.apply(s)
        await h.settle()  // text animation (0.15 s) and the panel's resize
        await h.drawAndWait()
        try? await Task.sleep(for: .milliseconds(100))  // let the window server composite it
        await h.drawAndWait()  // same values again: guards against a resize-triggered redraw in between
        try? await Task.sleep(for: .milliseconds(100))
        do {
            let window = try await h.scWindow()
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = Double(filter.pointPixelScale)
            let config = captureConfig(width: window.frame.width, height: window.frame.height, scale: scale)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            writePNG(image, to: out.appendingPathComponent("\(name).png"))
            var info = h.geometry()
            info["name"] = name
            info["imagePixels"] = ["width": image.width, "height": image.height]
            info["imageAlpha"] = alphaName(image.alphaInfo)
            info["imageColorspace"] = image.colorSpace.map { String(describing: $0) } ?? ""
            info["capturePointPixelScale"] = scale
            info["scWindowFramePoints"] = rect(window.frame)
            info["input"] = [
                "phase": s.phase, "text": s.text ?? "", "clockSeconds": s.clockSeconds ?? 0,
                "time": s.time ?? 0, "elapsed": s.elapsed ?? 0, "cuts": s.cuts ?? [],
                "active": h.renderer.active, "levels": s.levels,
                "levelsRecipe": s.levelsRecipe ?? scene.levelsRecipe ?? "",
            ] as [String: Any]
            writeJSON(info, to: out.appendingPathComponent("\(name).json"))
            log("\(name): window \(Int(h.panel.frame.width))x\(Int(h.panel.frame.height)) pt, \(image.width)x\(image.height) px")
        } catch {
            fail("capture failed (Screen Recording permission?): \(error)")
        }
    }
}

// MARK: - Motion

/// Receives the stream's frames. Copies each into memory and writes PNGs on a background queue.
final class FrameSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let out: URL
    let lock = NSLock()
    var records: [[String: Any]] = []
    var index = 0
    let writers = DispatchQueue(label: "writers", attributes: .concurrent)
    let group = DispatchGroup()
    var error: Error?

    init(out: URL) { self.out = out }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let a = attachments.first
        else { return }
        let statusRaw = a[.status] as? Int ?? -1
        let status = SCFrameStatus(rawValue: statusRaw)
        let pts = sample.presentationTimeStamp.seconds
        var record: [String: Any] = ["ptsHost": pts, "status": statusName(status)]
        if let d = a[.contentRect] { record["contentRect"] = rectDict(d) }
        if let s = a[.scaleFactor] as? Double { record["scaleFactor"] = s }
        if let s = a[.contentScale] as? Double { record["contentScale"] = s }
        if let d = a[.boundingRect] { record["boundingRect"] = rectDict(d) }
        guard status == .complete, let pixels = sample.imageBuffer else {
            lock.withLock { records.append(record) }
            return
        }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        let w = CVPixelBufferGetWidth(pixels), hgt = CVPixelBufferGetHeight(pixels)
        let bpr = CVPixelBufferGetBytesPerRow(pixels)
        let data = Data(bytes: CVPixelBufferGetBaseAddress(pixels)!, count: bpr * hgt)
        CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        let colorspace = CVImageBufferGetColorSpace(pixels)?.takeUnretainedValue() ?? CGColorSpace(name: CGColorSpace.sRGB)!
        // Crop to the window's content rect (pixels): the buffer is sized for the largest window.
        var crop = CGRect(x: 0, y: 0, width: w, height: hgt)
        if let d = a[.contentRect], let r = CGRect(dictionaryRepresentation: d as! CFDictionary) {
            let scale = (a[.scaleFactor] as? Double ?? 2) / (a[.contentScale] as? Double ?? 1)
            crop = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
                .intersection(crop)
        }
        let n: Int = lock.withLock { index += 1; return index }
        let file = String(format: "frame-%05d.png", n)
        record["file"] = file
        record["bufferPixels"] = ["width": w, "height": hgt]
        record["cropPixels"] = rect(crop)
        lock.withLock { records.append(record) }
        let url = out.appendingPathComponent(file)
        let cropRect = crop
        writers.async(group: group) {
            let provider = CGDataProvider(data: data as CFData)!
            let full = CGImage(
                width: w, height: hgt, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: colorspace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            writePNG(full.cropping(to: cropRect) ?? full, to: url)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { self.error = error }
    }

    func statusName(_ s: SCFrameStatus?) -> String {
        switch s {
        case .complete: "complete"
        case .idle: "idle"
        case .blank: "blank"
        case .suspended: "suspended"
        case .started: "started"
        case .stopped: "stopped"
        default: "unknown"
        }
    }

    func rectDict(_ d: Any) -> [String: Double] {
        guard let r = CGRect(dictionaryRepresentation: d as! CFDictionary) else { return [:] }
        return rect(r)
    }
}

@MainActor
final class Sizes: Sendable { nonisolated(unsafe) var rows: [[String: Any]] = [] }

@MainActor
final class Ticker: NSObject {
    var tick: (CADisplayLink) -> Void = { _ in }
    @objc func step(_ link: CADisplayLink) { tick(link) }
}

/// Sleeps until host time `when`: coarse sleep, then 1 ms steps, so events land within ~1-2 ms.
@MainActor
func sleepUntil(_ when: Double) async {
    let coarse = when - hostNow() - 0.004
    if coarse > 0 { try? await Task.sleep(for: .seconds(coarse), tolerance: .milliseconds(1)) }
    while hostNow() < when { try? await Task.sleep(for: .microseconds(500), tolerance: .microseconds(100)) }
}

@MainActor
func runMotion(_ script: MotionScript, out: URL) async {
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let h = Harness()
    h.apply(script.initial)
    await h.settle()
    await h.drawAndWait()

    // Panel size changes, as the window reports them.
    let sizes = Sizes()
    sizes.rows = [["host": hostNow(), "width": h.panel.frame.width, "height": h.panel.frame.height]]
    let observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: h.panel, queue: .main) { _ in
        MainActor.assumeIsolated {
            sizes.rows.append(["host": hostNow(), "width": h.panel.frame.width, "height": h.panel.frame.height])
        }
    }

    let sink = FrameSink(out: out)
    let stream: SCStream
    let window: SCWindow
    do {
        window = try await h.scWindow()
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let config = captureConfig(
            width: window.frame.width, height: max(script.captureHeight ?? 420, window.frame.height), scale: scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 8
        stream = SCStream(filter: filter, configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
        try await stream.startCapture()
        log("streaming window \(window.windowID) into \(config.width)x\(config.height) px")
    } catch {
        fail("capture failed (Screen Recording permission?): \(error)")
    }

    let events = script.events.sorted { $0.at < $1.at }
    guard let first = events.first else { fail("no events") }
    let lead = script.lead ?? 0.3
    let t0 = hostNow() + lead  // host time of the first event
    var fired: [[String: Any]] = []

    // Waveform: frozen, or advanced every display frame.
    let advance = script.waveform == "advance"
    var draws: [[String: Any]] = []
    let ticker = Ticker()
    var lastTarget: Double?
    let startTime = script.initial.time ?? 0
    var link: CADisplayLink?
    if advance {
        ticker.tick = { link in
            let target = link.targetTimestamp  // when this frame will be on screen (host seconds)
            let dt = lastTarget.map { target - $0 } ?? 0
            lastTarget = target
            h.renderer.time = startTime + Float(target - t0)
            if h.renderer.active { h.renderer.elapsed += Float(dt) }
            h.renderer.view?.draw()
            draws.append([
                "host": hostNow(), "targetHost": target, "t": target - t0,
                "time": Double(h.renderer.time), "elapsed": Double(h.renderer.elapsed),
            ])
        }
        let l = h.panel.screen!.displayLink(target: ticker, selector: #selector(Ticker.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    for event in events {
        let when = t0 + (event.at - first.at)
        await sleepUntil(when)
        let now = hostNow()
        if let p = event.phase { h.overlay.update(1, phase: phase(p)) }
        if let text = event.text { h.overlay.update(1, text: text) }
        if event.hide == true { h.overlay.hide(1) }
        if !advance { h.renderer.view?.draw() }  // phase may change tint/active
        var record: [String: Any] = ["at": event.at, "host": now, "t": now - t0]
        if let p = event.phase { record["phase"] = p }
        if let text = event.text { record["text"] = text }
        if event.hide == true { record["hide"] = true }
        fired.append(record)
    }
    let end = t0 + script.duration
    await sleepUntil(end)
    link?.invalidate()
    try? await stream.stopCapture()
    NotificationCenter.default.removeObserver(observer)
    let resizes = sizes.rows
    await withCheckedContinuation { c in sink.group.notify(queue: .main) { c.resume() } }
    if let error = sink.error { log("stream stopped with error: \(error)") }

    let actualT0 = (fired.first?["host"] as? Double) ?? t0
    var frames = sink.lock.withLock { sink.records }
    for i in frames.indices {
        if let pts = frames[i]["ptsHost"] as? Double {
            frames[i]["t"] = pts - actualT0
            // The size of the window in this frame, from the stream (contentRect is in window points).
            if let r = frames[i]["contentRect"] as? [String: Double] {
                frames[i]["windowSizePoints"] = ["width": r["width"]!, "height": r["height"]!]
            }
            // The panel size last reported by didResize at or before the PTS (can lead the pixels by a frame).
            if let size = resizes.last(where: { ($0["host"] as! Double) <= pts }) {
                frames[i]["panelSizeByDidResize"] = ["width": size["width"]!, "height": size["height"]!]
            }
        }
    }
    func rel(_ rows: [[String: Any]], _ key: String) -> [[String: Any]] {
        rows.map { var r = $0; if let h = r[key] as? Double { r["t"] = h - actualT0 }; return r }
    }
    writeJSON([
        "note": "t is seconds relative to the first event's actual dispatch (host clock = CMClockGetHostTimeClock; SCStream PTS are on it too). Frames with status idle mean nothing changed since the previous complete frame. The stream buffer is sized for captureHeight points; each PNG is cropped to the frame's contentRect * scaleFactor / contentScale, i.e. exactly the window. windowSizePoints comes from that contentRect (the size of the window in those pixels); panelSizeByDidResize is the NSWindow frame size last reported by didResize at or before the PTS, which can run a frame ahead of the pixels. events[].at is the scripted time, events[].t the actual dispatch.",
        "firstEventHost": actualT0,
        "scheduledFirstEventHost": t0,
        "backingScale": h.panel.backingScaleFactor,
        "waveform": advance ? "advance" : "frozen",
        "events": rel(fired, "host"),
        "resizes": rel(resizes, "host"),
        "draws": rel(draws, "host"),
        "frames": frames,
        "initial": [
            "phase": script.initial.phase, "text": script.initial.text ?? "",
            "clockSeconds": script.initial.clockSeconds ?? 0, "time": script.initial.time ?? 0,
            "elapsed": script.initial.elapsed ?? 0, "cuts": script.initial.cuts ?? [],
            "levels": script.initial.levels, "levelsRecipe": script.initial.levelsRecipe ?? script.levelsRecipe ?? "",
        ] as [String: Any],
        "geometryAtEnd": h.geometry(),
    ], to: out.appendingPathComponent("index.json"))
    let complete = frames.filter { $0["file"] != nil }.count
    log("motion: \(complete) complete frames, \(frames.count - complete) idle/other, \(resizes.count) sizes, \(draws.count) waveform draws -> \(out.path)")
}

// MARK: - Main

var args = Array(CommandLine.arguments.dropFirst())
var motion: String?
var outPath: String?
var scenePath: String?
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--motion": motion = args.isEmpty ? nil : args.removeFirst()
    case "--out": outPath = args.isEmpty ? nil : args.removeFirst()
    default: scenePath = a
    }
}
let usage = "usage: yapref <scene.json> [--out dir] | yapref --motion <script.json> --out <dir>"

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    if let motion {
        guard let outPath else { fail(usage) }
        let data = (try? Data(contentsOf: URL(fileURLWithPath: motion))) ?? { fail("cannot read \(motion)") }()
        let script = (try? JSONDecoder().decode(MotionScript.self, from: data)) ?? { fail("bad motion script") }()
        await runMotion(script, out: URL(fileURLWithPath: outPath))
    } else {
        guard let scenePath else { fail(usage) }
        let data = (try? Data(contentsOf: URL(fileURLWithPath: scenePath))) ?? { fail("cannot read \(scenePath)") }()
        let scene: Scene
        do { scene = try JSONDecoder().decode(Scene.self, from: data) } catch { fail("bad scene: \(error)") }
        await runScene(scene, out: URL(fileURLWithPath: outPath ?? "/tmp/yo-ref/out"))
    }
    exit(0)
}
NSApplication.shared.run()

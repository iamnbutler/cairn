@preconcurrency import AVFoundation
import CairnFrame
import Foundation

// The `record` subscription, `forgetClip` and the `wav` parts of `upload` (docs/effects.md).
// Trusted: claims ^966–^968 in docs/trusted.md. The host keeps each clip's samples; Lean sees
// only their levels (20 ms windows of sums of squares and peaks) and asks for a WAV of a range
// of windows, which goes straight into an upload body.

/// Samples per level window: 20 ms at 16 kHz (`Examples.Yap.Chunker.windowSamples`).
public let windowSamples = 320
/// The sample rate the host records at, as Yap's AudioCapture does.
public let sampleRate = 16_000

/// Turns a stream of samples into level windows, carrying a partial window over to the next
/// batch, so the windows don't depend on how the samples were split.
public struct LevelMeter: Sendable {
    private var sumSq: UInt64 = 0
    private var peak: UInt32 = 0
    private var filled = 0

    public init() {}

    /// The magnitude Lean's chunker counts: `|s|`, with `Int16.min` as `Int16.max` (as in Yap).
    @inline(__always) static func magnitude(_ s: Int16) -> UInt32 {
        s == .min ? UInt32(Int16.max) : UInt32(abs(Int32(s)))
    }

    /// The batch's peak and the windows it completes, in order.
    public mutating func feed(_ samples: UnsafeBufferPointer<Int16>) -> (peak: UInt32, windows: [Level]) {
        var batchPeak: UInt32 = 0
        var out: [Level] = []
        out.reserveCapacity((filled + samples.count) / windowSamples)
        for s in samples {
            let m = Self.magnitude(s)
            let v = Int64(s)
            sumSq &+= UInt64(v * v)
            if m > peak { peak = m }
            if m > batchPeak { batchPeak = m }
            filled += 1
            if filled == windowSamples {
                out.append(Level(sumSq: sumSq, peak: peak))
                sumSq = 0; peak = 0; filled = 0
            }
        }
        return (batchPeak, out)
    }

    public mutating func feed(_ samples: [Int16]) -> (peak: UInt32, windows: [Level]) {
        samples.withUnsafeBufferPointer { feed($0) }
    }
}

/// A RIFF/WAVE file around 16 kHz mono 16-bit samples (Yap's `WAV.pcm16`).
public enum WAV {
    public static let headerSize = 44

    public static func header(sampleBytes n: Int) -> [UInt8] {
        var h: [UInt8] = []
        h.reserveCapacity(headerSize)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { h += $0 } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { h += $0 } }
        h += Array("RIFF".utf8); u32(UInt32(36 + n)); h += Array("WAVE".utf8)
        h += Array("fmt ".utf8); u32(16); u16(1); u16(1); u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        h += Array("data".utf8); u32(UInt32(n))
        return h
    }

    /// The file for `samples`, little-endian.
    public static func file(_ samples: ArraySlice<Int16>) -> [UInt8] {
        let n = samples.count * 2
        var out = header(sampleBytes: n)
        out.reserveCapacity(headerSize + n)
        samples.withUnsafeBytes { raw in out.append(contentsOf: raw) }  // arm64 is little-endian
        return out
    }
}

/// Every clip's samples, by Lean's clip id. Recording appends from the audio thread; requests
/// read from any thread.
public final class Clips: @unchecked Sendable {
    /// How many clips are kept: starting another drops the oldest finished one.
    public static let maxClips = 8
    /// The longest clip: 30 minutes (57.6 MB). Recording stops there with a `failed` event.
    public static let maxSamples = 30 * 60 * sampleRate

    struct Clip {
        var samples: [Int16] = []
        var finished = false
        var started: UInt64
    }

    private let cond = NSCondition()
    private var clips: [UInt32: Clip] = [:]
    private var serial: UInt64 = 0

    public init() {}

    /// A new, empty clip under `id`, replacing any clip of that id.
    public func begin(_ id: UInt32) {
        cond.lock()
        defer { cond.unlock() }
        serial += 1
        clips[id] = Clip(started: serial)
        while clips.count > Self.maxClips {
            let old = clips.filter { $0.value.finished }.min { $0.value.started < $1.value.started }
                ?? clips.filter { $0.key != id }.min { $0.value.started < $1.value.started }
            guard let old else { break }
            clips[old.key] = nil
        }
        cond.broadcast()
    }

    /// Appends to a clip that is still recording. False when the clip is full (or gone).
    @discardableResult
    public func append(_ id: UInt32, _ samples: UnsafeBufferPointer<Int16>) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        guard clips[id] != nil, clips[id]!.finished == false else { return false }
        guard clips[id]!.samples.count + samples.count <= Self.maxSamples else { return false }
        clips[id]!.samples.append(contentsOf: samples)
        cond.broadcast()
        return true
    }

    /// The clip has no more samples coming.
    public func finish(_ id: UInt32) {
        cond.lock()
        clips[id]?.finished = true
        cond.broadcast()
        cond.unlock()
    }

    /// Drops a clip's samples. `done`, or `failed notFound`.
    public func forget(_ id: UInt32) -> Reply {
        cond.lock()
        defer { cond.unlock() }
        return clips.removeValue(forKey: id) == nil ? .failed(.notFound, "no clip \(id)") : .done
    }

    public func reset() {
        cond.lock()
        clips.removeAll()
        cond.broadcast()
        cond.unlock()
    }

    /// The ids of the clips kept (tests).
    public var ids: Set<UInt32> {
        cond.lock()
        defer { cond.unlock() }
        return Set(clips.keys)
    }

    /// Windows `start ..< stop` of the clip as a WAV file; `stop` nil is the end of the clip,
    /// with any partial last window. A clip still recording is waited for (up to `wait`
    /// seconds): until it has the windows asked for, or, for the end, until it finishes, as it
    /// does when Lean stops its `record` in the same frame as the upload. After the wait, the
    /// end is what has been recorded so far. Unknown clip: `notFound`; a range past the end or
    /// backwards: `invalid`.
    public func wav(_ id: UInt32, start: UInt32, stop: UInt32?, wait: Double = 1) -> Result<[UInt8], ReplyError> {
        let deadline = Date().addingTimeInterval(wait)
        cond.lock()
        defer { cond.unlock() }
        let lo = Int(start) * windowSamples
        while true {
            guard let c = clips[id] else { return .failure(ReplyError(.notFound, "no clip \(id)")) }
            let ready: Bool
            if let stop { ready = c.finished || c.samples.count >= Int(stop) * windowSamples }
            else { ready = c.finished }
            if ready || !cond.wait(until: deadline) { break }
        }
        guard let c = clips[id] else { return .failure(ReplyError(.notFound, "no clip \(id)")) }
        let hi = stop.map { Int($0) * windowSamples } ?? c.samples.count
        guard lo <= hi, hi <= c.samples.count else {
            return .failure(ReplyError(.invalid, "windows \(start)..<\(stop.map(String.init) ?? "end") of clip \(id), which has \(c.samples.count / windowSamples)"))
        }
        return .success(WAV.file(c.samples[lo..<hi]))
    }
}

/// A failure that becomes a `failed` reply.
public struct ReplyError: Error, Equatable, Sendable {
    public var fault: Fault
    public var message: String
    public init(_ fault: Fault, _ message: String) { self.fault = fault; self.message = message }
    public var reply: Reply { .failed(fault, message) }
}

/// Where samples come from: 16 kHz mono `Int16` buffers, delivered in order on one thread at a
/// time. `start` answers how to stop; after `stop` returns no more buffers are delivered.
public struct Microphone: Sendable {
    public var start: @Sendable (_ onSamples: @escaping @Sendable (UnsafeBufferPointer<Int16>) -> Void) throws(ReplyError) -> @Sendable () -> Void

    public init(start: @escaping @Sendable (@escaping @Sendable (UnsafeBufferPointer<Int16>) -> Void) throws(ReplyError) -> @Sendable () -> Void) {
        self.start = start
    }

    /// The default input device through AVAudioEngine, converted to 16 kHz mono 16-bit as in
    /// Yap's AudioCapture (no voice processing). Not yet asked, starting the engine shows the
    /// system's prompt, as Yap's first recording does. Refused (denied or restricted), it fails
    /// `denied` without starting: Yap records silence then and says "Heard nothing"
    /// (iamnbutler/yap#11). A failure to start is Yap's text, the error's own description.
    public static let live = Microphone { onSamples throws(ReplyError) in
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            throw ReplyError(.denied, "Microphone access is not granted")
        default: break
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw ReplyError(.notFound, "no microphone")
        }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate),
                                             channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw ReplyError(.other, "cannot convert \(inFormat) to 16 kHz mono")
        }
        let box = ConverterBox(converter)
        // About 20 ms of input per buffer; Core Audio may deliver larger buffers.
        let frames = AVAudioFrameCount(max(256, inFormat.sampleRate / 50))
        input.installTap(onBus: 0, bufferSize: frames, format: inFormat) { @Sendable buffer, _ in
            guard let out = box.convert(buffer, to: outFormat), let p = out.int16ChannelData else { return }
            onSamples(UnsafeBufferPointer(start: p[0], count: Int(out.frameLength)))
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw ReplyError(.other, error.localizedDescription)
        }
        let held = EngineBox(engine)
        return { held.stop() }
    }
}

/// The engine, stopped once.
private final class EngineBox: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    init(_ e: AVAudioEngine) { engine = e }
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}

/// One converter, used only from the audio thread (Yap's AudioCapture.convert).
private final class ConverterBox: @unchecked Sendable {
    let converter: AVAudioConverter
    init(_ c: AVAudioConverter) { converter = c }

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

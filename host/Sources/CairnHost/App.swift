import CLean
import CairnFrame
import Foundation

/// The bytes that cross the boundary: events in, frames out. v1 is specified in docs/frame.md
/// and implemented by CairnFrame's decoder and encoder (`FrameV1Codec`), the only codec.
public protocol BoundaryCodec: Sendable {
    func encode(_ events: [Event]) -> [UInt8]
    func decodeFrame(_ bytes: UnsafeRawBufferPointer) throws -> Frame
}

/// The v1 boundary (docs/frame.md): events go out with `encodeEvents`, frames come back with
/// `Frame(decoding:)`. Every app on the `cairn_app_*` ABI uses it.
public struct FrameV1Codec: BoundaryCodec {
    public init() {}
    public func encode(_ events: [Event]) -> [UInt8] { encodeEvents(events) }
    public func decodeFrame(_ bytes: UnsafeRawBufferPointer) throws -> Frame { try Frame(decoding: bytes) }
}

/// What the host runs. Every call happens on the Lean thread, in order: `start` once, then any
/// number of `step` and `frame`.
public protocol AppCore: AnyObject {
    /// Create the state for a window of `size` logical points at backing scale `scalePercent`.
    func start(size: Size, scalePercent: UInt32)
    func step(_ events: [Event])
    func frame() throws -> Frame
}

/// A Lean app: its module initializer and its three exports. Every Lean argument is owned
/// (consumed); see docs/host.md for the ABI.
///
/// A v1 app passes `cairn_app_init`, `cairn_app_step`, `cairn_app_frame` and `FrameV1Codec()`.
/// The closures live in the app's executable, not here: each executable links exactly one app
/// library, so CairnHost must not reference the app symbols itself.
public struct LeanApp: Sendable {
    public var module: cairn_module_init
    public var initialize: @Sendable (_ w: UInt32, _ h: UInt32, _ scalePercent: UInt32) -> OpaquePointer
    public var step: @Sendable (_ state: OpaquePointer, _ events: OpaquePointer) -> OpaquePointer
    public var frame: @Sendable (_ state: OpaquePointer) -> OpaquePointer
    public var codec: BoundaryCodec

    public init(module: cairn_module_init,
                initialize: @escaping @Sendable (UInt32, UInt32, UInt32) -> OpaquePointer,
                step: @escaping @Sendable (OpaquePointer, OpaquePointer) -> OpaquePointer,
                frame: @escaping @Sendable (OpaquePointer) -> OpaquePointer,
                codec: BoundaryCodec) {
        self.module = module
        self.initialize = initialize
        self.step = step
        self.frame = frame
        self.codec = codec
    }
}

/// The Lean runtime, initialized once per process on the first thread that needs it. Every
/// later thread registers itself with `cairn_lean_thread_begin` (docs/spike-boundary.md).
public enum LeanRuntime {
    nonisolated(unsafe) private static var initialized = false
    private static let lock = NSLock()

    /// Call on a thread before it calls into Lean. The first call initializes the runtime, the
    /// framework module (`Cairn`, which text metrics need) and then `module`; later calls
    /// register the thread.
    public static func enter(module: cairn_module_init) {
        lock.lock()
        defer { lock.unlock() }
        if initialized {
            cairn_lean_thread_begin()
        } else {
            #if DEBUG
            let exitOnPanic: UInt8 = 1
            #else
            let exitOnPanic: UInt8 = 0
            #endif
            let inits: [cairn_module_init?] = [initialize_cairn_Cairn, module]
            inits.withUnsafeBufferPointer { cairn_lean_init($0.baseAddress, $0.count, exitOnPanic) }
            initialized = true
        }
    }

    public static func bytes(_ b: [UInt8]) -> OpaquePointer {
        b.withUnsafeBufferPointer { cairn_bytes_new($0.baseAddress, $0.count) }
    }

    /// Reads a Lean byte array in place, then releases it.
    public static func withBytes<T>(_ o: OpaquePointer, _ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        defer { cairn_lean_dec(o) }
        return try body(UnsafeRawBufferPointer(start: cairn_bytes_data(o), count: cairn_bytes_size(o)))
    }
}

/// Runs a `LeanApp`, holding its state. Lives on the Lean thread.
public final class LeanCore: AppCore {
    private let app: LeanApp
    private var state: OpaquePointer?

    public init(_ app: LeanApp) { self.app = app }

    /// Called again by `Engine.restart` (debug socket): the old state is released and the thread,
    /// already registered with Lean, is not registered twice.
    public func start(size: Size, scalePercent: UInt32) {
        if let old = state { cairn_lean_dec(old) } else { LeanRuntime.enter(module: app.module) }
        state = app.initialize(UInt32(max(0, size.w)), UInt32(max(0, size.h)), scalePercent)
    }

    public func step(_ events: [Event]) {
        guard let s = state else { return }
        state = app.step(s, LeanRuntime.bytes(app.codec.encode(events)))
    }

    public func frame() throws -> Frame {
        guard let s = state else { throw CodecError.noState }
        cairn_lean_inc(s)  // frame consumes its argument; keep ours
        return try LeanRuntime.withBytes(app.frame(s)) { try app.codec.decodeFrame($0) }
    }

    deinit { if let s = state { cairn_lean_dec(s) } }
}

public enum CodecError: Error { case noState }

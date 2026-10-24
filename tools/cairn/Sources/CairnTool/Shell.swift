import Foundation

/// Running the tools `cairn` wraps: lake, cairn-link, swift, git, bun, tar.
public struct Shell: Sendable {
    public var environment: [String: String]
    /// Print each command before it runs.
    public var echo = true

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        var env = environment
        // elan's lake, as AGENTS.md says to export it.
        let elan = (env["ELAN_HOME"] ?? (NSHomeDirectory() + "/.elan")) + "/bin"
        let path = env["PATH"] ?? "/usr/bin:/bin"
        if !path.split(separator: ":").contains(Substring(elan)) { env["PATH"] = elan + ":" + path }
        self.environment = env
    }

    public struct Output: Sendable {
        public var status: Int32
        public var stdout: Data
        public var text: String { String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Run a command with its output on the terminal; fail unless it exits 0.
    public func run(_ args: [String], in dir: URL, env extra: [String: String] = [:]) throws(CairnError) {
        let out = try spawn(args, in: dir, env: extra, capture: false, input: nil)
        if out.status != 0 { throw CairnError("`\(args.joined(separator: " "))` failed (exit \(out.status))") }
    }

    /// Run a command and return what it printed; stderr still goes to the terminal.
    public func capture(_ args: [String], in dir: URL, env extra: [String: String] = [:], input: Data? = nil, check: Bool = true) throws(CairnError) -> Output {
        let out = try spawn(args, in: dir, env: extra, capture: true, input: input)
        if check, out.status != 0 { throw CairnError("`\(args.joined(separator: " "))` failed (exit \(out.status))") }
        return out
    }

    /// Whether a command is on PATH.
    public func has(_ tool: String) -> Bool {
        (environment["PATH"] ?? "").split(separator: ":").contains {
            FileManager.default.isExecutableFile(atPath: "\($0)/\(tool)")
        }
    }

    func spawn(_ args: [String], in dir: URL, env extra: [String: String], capture: Bool, input: Data?) throws(CairnError) -> Output {
        if echo, !capture { FileHandle.standardError.write(Data("› \(args.joined(separator: " "))\n".utf8)) }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = dir
        process.environment = environment.merging(extra) { $1 }
        let pipe = Pipe()
        if capture { process.standardOutput = pipe }
        let stdin = Pipe()
        if input != nil { process.standardInput = stdin }
        do { try process.run() } catch { throw CairnError("couldn't run \(args[0]): \(error.localizedDescription)") }
        if let input {
            // Write from another thread so a full stdout pipe can't deadlock us.
            let handle = stdin.fileHandleForWriting
            Thread.detachNewThread {
                handle.write(input)
                try? handle.close()
            }
        }
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, stdout: data)
    }
}

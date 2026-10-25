import CairnTool
import Foundation

let usage = """
    cairn: build, document and publish Cairn packages (docs/cli.md)

      cairn new <name> [--lib|--bin]  start a library or an app: lean/, claims.lock, cairn.toml,
                                      and for an app Package.swift (asks which with neither)
      cairn add [<owner>/]<name>[@<range>]
                                      depend on a package from the registry
      cairn build [--release]         lake cache get, lake build, cairn-link, swift build
      cairn doc [--private] [--open]  the package's docs, in build/doc/<name>/
      cairn publish [--owner <login>] [--dry-run]
                                      publish the version at tag v<version> and its build,
                                      under --owner or else the token's own login
      cairn login                     save a token for publishing (read from stdin)

    Checks, on an app package (docs/cli.md, "Checks"):
      cairn fuzz [<target>…] [--iterations N] [--seed S] [--steps K] [--out DIR] [-v]
                                      claim-driven fuzzing (`lean_exe fuzz`), build/fuzz/
      cairn claims [<module>…] [--out FILE]
                                      every claim as JSON (lake exe claims)
      cairn bench [--product P]       release build, then the app's own --bench
      cairn size [--product P]… [--limit BYTES]
                                      stripped release size, attributed, under a limit
      cairn conformance [--module M] [--product P] [--n N] [--length L] [--seed S]
                                      the Lean model replayed on the running app

    The registry is https://cairn.registry.nexthub.sh, which anyone reads with no login;
    CAIRN_REGISTRY overrides it. CAIRN_TOKEN overrides the saved token.
    """

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()
let commands = Commands()
do {
    switch command {
    case "new": try commands.new(args)
    case "add": try await commands.add(args)
    case "build": try commands.build(args)
    case "doc": try commands.doc(args)
    case "fuzz": try commands.fuzz(args)
    case "claims": try commands.claims(args)
    case "bench": try commands.bench(args)
    case "size": try commands.size(args)
    case "conformance": try commands.conformance(args)
    case "publish": try await commands.publish(args)
    case "login": try await commands.login(args)
    case "help", "-h", "--help": print(usage)
    default:
        FileHandle.standardError.write(Data("cairn: unknown command `\(command)`\n\n\(usage)\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("cairn: \(error.description)\n".utf8))
    exit(1)
}

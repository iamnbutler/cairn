import CairnTool
import Foundation

let usage = """
    cairn: build, document and publish Cairn packages (docs/cli.md)

      cairn new <name> [--lib]        start a package: lean/, claims.lock, cairn.toml, Package.swift
      cairn add <name>[@<range>]      depend on a package from the registry
      cairn build [--release]         lake cache get, lake build, cairn-link, swift build
      cairn doc [--private] [--open]  the package's docs, in build/doc/<name>/
      cairn publish [--no-docs] [--dry-run]
                                      publish the version at tag v<version>, its docs and its build
      cairn login <url>               save a registry token (read from stdin)
      cairn credential get            git credential helper for the registry
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
    case "publish": try await commands.publish(args)
    case "login": try await commands.login(args)
    case "credential": try commands.credential(args)
    case "help", "-h", "--help": print(usage)
    default:
        FileHandle.standardError.write(Data("cairn: unknown command `\(command)`\n\n\(usage)\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("cairn: \(error.description)\n".utf8))
    exit(1)
}

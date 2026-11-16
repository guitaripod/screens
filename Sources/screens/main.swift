import Foundation

let version = "0.2.0"

/// Writes a message to stderr and exits with the given status.
func fail(_ message: String, status: Int32) -> Never {
    fflush(stdout)
    FileHandle.standardError.write(Data("screens: \(message)\n".utf8))
    exit(status)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = Command.parse(arguments) else {
    fail("unexpected arguments \"\(arguments.joined(separator: " "))\"\n\n\(Command.usage)", status: 2)
}

do {
    try Screens().run(command)
} catch {
    fail("\(error)", status: 1)
}

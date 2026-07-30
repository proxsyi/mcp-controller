import Foundation

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
}

enum CommandRunner {
    static func runAsync(executable: String, arguments: [String]) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            try run(executable: executable, arguments: arguments)
        }.value
    }

    static func run(executable: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return CommandResult(output: output, error: error, exitCode: process.terminationStatus)
    }
}

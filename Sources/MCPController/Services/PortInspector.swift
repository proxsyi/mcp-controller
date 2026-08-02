import Foundation

struct ListeningProcess: Equatable, Sendable {
    let pid: Int32
    let command: String
}

enum PortInspector {
    static func listenerAsync(on port: Int) async -> ListeningProcess? {
        await Task.detached(priority: .utility) { listener(on: port) }.value
    }

    static func terminateAsync(_ listener: ListeningProcess) async throws {
        try await Task.detached(priority: .utility) { try terminate(listener) }.value
    }

    static func listener(on port: Int) -> ListeningProcess? {
        guard let result = try? CommandRunner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        ), result.exitCode == 0,
        let firstLine = result.output.split(whereSeparator: \.isNewline).first,
        let pid = Int32(String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let commandResult = try? CommandRunner.run(
            executable: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "command="]
        )
        return ListeningProcess(
            pid: pid,
            command: commandResult?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    static func belongsToProfile(_ listener: ListeningProcess, profile: ServerProfile) -> Bool {
        let command = listener.command.lowercased()
        let quoteCharacters = CharacterSet(charactersIn: "\"'")
        let tokens = command.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: quoteCharacters)
        }

        var markers: [String] = []
        let executablePath = profile.executablePath.lowercased()
        let executableName = URL(fileURLWithPath: executablePath).lastPathComponent
        if !isGenericLauncher(executableName) {
            markers.append(executablePath)
            markers.append(executableName)
        }

        for argument in profile.arguments {
            let expanded = argument.replacingOccurrences(of: "{port}", with: String(profile.localPort)).lowercased()
            if expanded.hasPrefix("/") {
                markers.append(expanded)
                markers.append(URL(fileURLWithPath: expanded).lastPathComponent)
            } else if !expanded.hasPrefix("-"), expanded.count >= 5 {
                markers.append(expanded)
            }
        }

        return markers
            .filter { !$0.isEmpty }
            .contains { marker in
                tokens.contains(marker) ||
                tokens.contains(where: { token in
                    if marker.hasPrefix("/") {
                        return URL(fileURLWithPath: token).standardizedFileURL.path.lowercased() ==
                            URL(fileURLWithPath: marker).standardizedFileURL.path.lowercased()
                    }
                    guard token.hasPrefix("/") else { return false }
                    return URL(fileURLWithPath: token).lastPathComponent.lowercased() == marker
                }) ||
                command.contains("\"\(marker)\"") ||
                command.contains("'\(marker)'")
            }
    }

    private static func isGenericLauncher(_ name: String) -> Bool {
        let generic = ["node", "uv", "uvx", "bun", "npx", "npm", "deno", "java", "ruby", "php"]
        return generic.contains(name) || name == "python" || name.hasPrefix("python3")
    }

    static func terminate(_ listener: ListeningProcess) throws {
        let result = try CommandRunner.run(
            executable: "/bin/kill",
            arguments: ["-TERM", String(listener.pid)]
        )
        guard result.exitCode == 0 else {
            throw ControllerError.commandFailed(result.error.isEmpty ? result.output : result.error)
        }
    }
}

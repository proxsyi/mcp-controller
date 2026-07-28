import Foundation

struct ListeningProcess: Equatable, Sendable {
    let pid: Int32
    let command: String
}

enum PortInspector {
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
        var markers = [URL(fileURLWithPath: profile.executablePath).lastPathComponent.lowercased()]

        for argument in profile.arguments {
            let expanded = argument.replacingOccurrences(of: "{port}", with: String(profile.localPort))
            if expanded.hasPrefix("/") {
                markers.append(expanded.lowercased())
                markers.append(URL(fileURLWithPath: expanded).lastPathComponent.lowercased())
            } else if !expanded.hasPrefix("-"), expanded.count >= 5 {
                markers.append(expanded.lowercased())
            }
        }

        return markers
            .filter { !$0.isEmpty && $0 != "node" && $0 != "uv" && $0 != "bun" }
            .contains { command.contains($0) }
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

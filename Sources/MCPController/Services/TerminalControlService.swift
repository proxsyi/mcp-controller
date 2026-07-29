import Foundation

struct TerminalControlRequest: Codable, Sendable {
    let id: String
    let action: String
    let target: String?
    let arguments: [String: String]
}

struct TerminalControlResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let payload: String?

    static func ok(_ message: String, payload: String? = nil) -> Self { .init(success: true, message: message, payload: payload) }
    static func error(_ message: String) -> Self { .init(success: false, message: message, payload: nil) }
}

final class TerminalControlService: @unchecked Sendable {
    typealias Handler = @Sendable (TerminalControlRequest) async -> TerminalControlResponse
    private let queue = DispatchQueue(label: "com.versyi.mcp-controller.terminal-control")
    private var timer: DispatchSourceTimer?
    private var handler: Handler?

    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MCP Controller/Control", directoryHint: .isDirectory)
    }
    private var requestsURL: URL { baseURL.appending(path: "requests", directoryHint: .isDirectory) }
    private var responsesURL: URL { baseURL.appending(path: "responses", directoryHint: .isDirectory) }

    func start(handler: @escaping Handler) {
        self.handler = handler
        try? FileManager.default.createDirectory(at: requestsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: responsesURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.processRequests() }
        self.timer = timer
        timer.resume()
    }

    private func processRequests() {
        guard let handler else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: requestsURL, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let request = try? JSONDecoder().decode(TerminalControlRequest.self, from: data) else {
                try? FileManager.default.removeItem(at: url); continue
            }
            try? FileManager.default.removeItem(at: url)
            Task {
                let response = await handler(request)
                guard let output = try? JSONEncoder().encode(response) else { return }
                let destination = responsesURL.appending(path: request.id + ".json")
                try? output.write(to: destination, options: .atomic)
            }
        }
    }
}

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
    private var handler: Handler?
    private var isRunning = false
    private var isProcessingBatch = false

    private let activePollInterval: TimeInterval = 0.1
    private let idlePollInterval: TimeInterval = 0.75

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
        guard !isRunning else { return }
        isRunning = true
        scheduleNextPoll(after: 0)
    }

    private func scheduleNextPoll(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollAndReschedule()
        }
    }

    private func pollAndReschedule() {
        guard isRunning else { return }
        let processedAny = processRequests()
        scheduleNextPoll(after: processedAny ? activePollInterval : idlePollInterval)
    }

    @discardableResult
    private func processRequests() -> Bool {
        guard let handler else { return false }
        if isProcessingBatch { return true }

        let urls = sortedRequestURLs()
        guard !urls.isEmpty else { return false }

        var requests: [TerminalControlRequest] = []
        var processedAny = false
        for url in urls where url.pathExtension == "json" {
            defer {
                try? FileManager.default.removeItem(at: url)
            }
            guard let data = try? Data(contentsOf: url),
                  let request = try? JSONDecoder().decode(TerminalControlRequest.self, from: data) else {
                writeErrorResponse("Invalid terminal control request.", for: url)
                processedAny = true
                continue
            }
            requests.append(request)
            processedAny = true
        }
        guard processedAny else { return false }
        guard !requests.isEmpty else { return true }

        isProcessingBatch = true
        Task { [weak self] in
            guard let self else { return }
            for request in requests {
                let response = await handler(request)
                guard let output = try? JSONEncoder().encode(response) else { continue }
                let destination = self.responsesURL.appending(path: request.id + ".json")
                try? output.write(to: destination, options: .atomic)
            }
            self.queue.async { [weak self] in
                self?.isProcessingBatch = false
            }
        }
        return true
    }

    private func writeErrorResponse(_ message: String, for requestURL: URL) {
        let response = TerminalControlResponse.error(message)
        guard let output = try? JSONEncoder().encode(response) else { return }
        let destination = responsesURL.appending(path: requestURL.lastPathComponent)
        try? output.write(to: destination, options: .atomic)
    }

    private func sortedRequestURLs() -> [URL] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .nameKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: requestsURL, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.sorted { lhs, rhs in
            let left = sortKey(for: lhs)
            let right = sortKey(for: rhs)
            if left.date != right.date { return left.date < right.date }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func sortKey(for url: URL) -> (date: Date, name: String) {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .nameKey])
        return (
            values?.creationDate ?? values?.contentModificationDate ?? .distantPast,
            values?.name ?? url.lastPathComponent
        )
    }
}

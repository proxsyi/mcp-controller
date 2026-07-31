import Foundation

struct ProfileStore {
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.versyi.mcp-controller.profile-store")

    var configurationURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "MCP Controller", directoryHint: .isDirectory)
            .appending(path: "servers.json", directoryHint: .notDirectory)
    }

    func load() throws -> [ServerProfile] {
        guard fileManager.fileExists(atPath: configurationURL.path) else { return [] }
        let data = try Data(contentsOf: configurationURL)
        return try JSONDecoder().decode([ServerProfile].self, from: data)
    }

    func save(_ profiles: [ServerProfile]) throws {
        let directory = configurationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: configurationURL, options: .atomic)
    }

    func saveAsync(_ profiles: [ServerProfile], completion: @escaping @Sendable (Error?) -> Void) {
        let url = configurationURL
        let fileManager = self.fileManager
        saveQueue.async {
            do {
                let directory = url.deletingLastPathComponent()
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(profiles).write(to: url, options: .atomic)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
}

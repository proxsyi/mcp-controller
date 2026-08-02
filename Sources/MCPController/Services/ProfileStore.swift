import Foundation

final class ProfileStore: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.versyi.mcp-controller.profile-store")
    private let configurationURLOverride: URL?

    init(configurationURL: URL? = nil) {
        self.configurationURLOverride = configurationURL
    }

    var configurationURL: URL {
        if let configurationURLOverride { return configurationURLOverride }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "MCP Controller", directoryHint: .isDirectory)
            .appending(path: "servers.json", directoryHint: .notDirectory)
    }

    func load() throws -> [ServerProfile] {
        let directory = configurationURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        guard fileManager.fileExists(atPath: configurationURL.path) else { return [] }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
        let data = try Data(contentsOf: configurationURL)
        return try JSONDecoder().decode([ServerProfile].self, from: data)
    }

    func save(_ profiles: [ServerProfile]) throws {
        try saveQueue.sync { [self] in
            try writeProfiles(profiles)
        }
    }

    func saveAsync(_ profiles: [ServerProfile], completion: @escaping @Sendable (Error?) -> Void) {
        saveQueue.async { [self] in
            do {
                try writeProfiles(profiles)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    private func writeProfiles(_ profiles: [ServerProfile]) throws {
        let directory = configurationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: configurationURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
    }
}

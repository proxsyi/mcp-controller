import Foundation
import XCTest
@testable import MCPController

final class ProfileStoreTests: XCTestCase {
    func testImmediateSaveWinsOverPreviouslyQueuedAsyncSnapshot() throws {
        let directory = temporaryDirectory()
        let url = directory.appending(path: "servers.json", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ProfileStore(configurationURL: url)
        var older = ServerProfile()
        older.name = "Older snapshot"
        var newer = older
        newer.name = "Newest state"

        store.saveAsync([older]) { _ in }
        try store.save([newer])

        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.name), ["Newest state"])
    }

    func testSaveRestrictsConfigurationDirectoryAndFilePermissions() throws {
        let directory = temporaryDirectory()
        let url = directory.appending(path: "servers.json", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)

        try ProfileStore(configurationURL: url).save([ServerProfile()])

        XCTAssertEqual(permissions(at: directory), 0o700)
        XCTAssertEqual(permissions(at: url), 0o600)
    }

    func testLoadRepairsPermissiveExistingFilePermissions() throws {
        let directory = temporaryDirectory()
        let url = directory.appending(path: "servers.json", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(configurationURL: url)
        try store.save([ServerProfile()])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        _ = try store.load()

        XCTAssertEqual(permissions(at: directory), 0o700)
        XCTAssertEqual(permissions(at: url), 0o600)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "MCPController-ProfileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func permissions(at url: URL) -> Int? {
        let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return value??.intValue
    }
}

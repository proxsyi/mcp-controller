import Foundation
import XCTest
@testable import MCPController

final class ProfileStoreTests: XCTestCase {
    func testImmediateSaveWinsOverPreviouslyQueuedAsyncSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MCPController-ProfileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
}

import XCTest
@testable import MCPController

final class AutoReleaseAllLoopTests: XCTestCase {
    func testUsesTheRequestedReleaseAllLoopCommand() async {
        let values = await MainActor.run {
            (AutoReleaseAllLoop.shellPath, AutoReleaseAllLoop.command)
        }

        XCTAssertEqual(values.0, "/bin/zsh")
        XCTAssertEqual(
            values.1,
            "while true; do ~/.local/bin/mcpctl release-all; sleep 60; done"
        )
    }
}

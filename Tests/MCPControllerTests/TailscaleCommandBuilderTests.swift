import XCTest
@testable import MCPController

final class TailscaleCommandBuilderTests: XCTestCase {
    func testFunnelEnableUsesOwnedPathAndPort() {
        var profile = ServerProfile()
        profile.localPort = 4123
        profile.publicPort = 8443
        profile.mountPath = "mcp/dev/"
        profile.exposureMode = .funnel

        XCTAssertEqual(
            TailscaleCommandBuilder.enableArguments(for: profile),
            ["funnel", "--bg", "--https=8443", "--set-path=/mcp/dev", "http://127.0.0.1:4123"]
        )
    }

    func testFunnelDisableRemovesOnlyOwnedMount() {
        var profile = ServerProfile()
        profile.publicPort = 443
        profile.mountPath = "/mcp/desktop"
        profile.exposureMode = .funnel

        XCTAssertEqual(
            TailscaleCommandBuilder.disableArguments(for: profile),
            ["funnel", "--https=443", "--set-path=/mcp/desktop", "off"]
        )
    }

    func testLocalOnlyHasNoTailscaleCommands() {
        let profile = ServerProfile()
        XCTAssertNil(TailscaleCommandBuilder.enableArguments(for: profile))
        XCTAssertNil(TailscaleCommandBuilder.disableArguments(for: profile))
    }
}

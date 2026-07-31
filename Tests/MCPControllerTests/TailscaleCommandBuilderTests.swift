import XCTest
@testable import MCPController

final class TailscaleCommandBuilderTests: XCTestCase {
    func testFunnelEnableUsesOwnedPathAndPort() {
        var profile = ServerProfile(); profile.localPort = 4123; profile.publicPort = 8443; profile.mountPath = "mcp/dev/"; profile.exposureMode = .funnel; profile.tailscaleRouteEnabled = true
        XCTAssertEqual(TailscaleCommandBuilder.enableArguments(for: profile), ["funnel", "--bg", "--https=8443", "--set-path=/mcp/dev", "http://127.0.0.1:4123"])
    }

    func testDirectStreamableHTTPRouteTargetsMCPPath() {
        var profile = ServerProfile(); profile.localPort = 4123; profile.arguments = ["--transport", "streamable-http"]; profile.exposureMode = .tailnet; profile.tailscaleRouteEnabled = true
        XCTAssertEqual(TailscaleCommandBuilder.enableArguments(for: profile)?.last, "http://127.0.0.1:4123/mcp")
    }

    func testDirectExplicitRouteTargetsConfiguredEndpointPath() {
        var profile = ServerProfile(); profile.localPort = 4123; profile.arguments = ["--mcp-path=/custom/mcp///"]; profile.exposureMode = .tailnet; profile.tailscaleRouteEnabled = true
        XCTAssertEqual(TailscaleCommandBuilder.enableArguments(for: profile)?.last, "http://127.0.0.1:4123/custom/mcp")
    }

    func testExclusiveGatewayBecomesTailscaleTarget() {
        var profile = ServerProfile(); profile.localPort = 4123; profile.gatewayPort = 39001; profile.arguments = ["--transport", "streamable-http"]; profile.exclusiveGatewayEnabled = true; profile.exposureMode = .funnel; profile.tailscaleRouteEnabled = true
        XCTAssertEqual(TailscaleCommandBuilder.enableArguments(for: profile)?.last, "http://127.0.0.1:39001")
    }

    func testFunnelRemovalTargetsOnlyOwnedMount() {
        var profile = ServerProfile(); profile.publicPort = 443; profile.mountPath = "/mcp/desktop"; profile.exposureMode = .funnel
        XCTAssertEqual(TailscaleCommandBuilder.removeArguments(for: profile), ["funnel", "--https=443", "--set-path=/mcp/desktop", "off"])
    }

    func testStoppingServerDoesNotRemoveIndependentRoute() {
        var profile = ServerProfile(); profile.exposureMode = .funnel; profile.tailscaleRouteEnabled = true
        XCTAssertNil(TailscaleCommandBuilder.disableArguments(for: profile))
    }

    func testConfiguredButDisabledRouteDoesNotStart() {
        var profile = ServerProfile(); profile.exposureMode = .funnel
        XCTAssertNil(TailscaleCommandBuilder.enableArguments(for: profile))
    }
}

import XCTest
@testable import MCPController

final class GatewayRouteMapperTests: XCTestCase {
    func testFunnelRootMapsToConfiguredStreamableHTTPPath() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/remote"
        profile.arguments = ["--streamableHttpPath", "/mcp"]

        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/", profile: profile), "/mcp")
        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/mcp/remote", profile: profile), "/mcp")
    }

    func testExplicitEndpointSuffixIsPreservedAfterMountIsRemoved() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/remote"
        profile.arguments = ["--streamableHttpPath", "/mcp"]

        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/mcp/remote/mcp", profile: profile), "/mcp")
    }

    func testAlreadyStrippedEndpointPassesThrough() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/remote"
        profile.arguments = ["--streamableHttpPath=/mcp"]

        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/mcp", profile: profile), "/mcp")
    }
}

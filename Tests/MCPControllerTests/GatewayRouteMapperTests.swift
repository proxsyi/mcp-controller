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

    func testStreamableHTTPTransportDefaultsToMCPPath() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/macos"
        profile.arguments = ["serve", "--transport", "streamable-http"]

        XCTAssertEqual(profile.streamableHTTPPath, "/mcp")
        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/", profile: profile), "/mcp")
        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/mcp/macos", profile: profile), "/mcp")
    }
    func testCompatibilityRestoresMountAfterProxyStripsPrefix() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/remote"

        XCTAssertEqual(GatewayRouteMapper.publicTarget(for: "/", profile: profile), "/mcp/remote")
        XCTAssertEqual(GatewayRouteMapper.publicTarget(for: "/?probe=1", profile: profile), "/mcp/remote?probe=1")
    }

    func testCompatibilityUsesForwardedPrefixWhenAvailable() {
        var profile = ServerProfile()
        profile.mountPath = "/fallback"

        XCTAssertEqual(
            GatewayRouteMapper.publicTarget(for: "/", forwardedPrefix: "/external/mcp/", profile: profile),
            "/external/mcp"
        )
    }

    func testCompatibilityPreservesCanonicalTarget() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/server"

        XCTAssertEqual(GatewayRouteMapper.publicTarget(for: "/mcp/server", profile: profile), "/mcp/server")
    }

}

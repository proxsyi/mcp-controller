import XCTest
@testable import MCPController

final class GatewayOptionalDiscoveryFallbackTests: XCTestCase {
    func testReturnsEmptyOptionalDiscoveryResultsWhenCapabilityIsMissing() {
        let capabilities: Set<String> = ["logging", "tools"]
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/templates/list", upstreamCapabilities: capabilities))
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/list", upstreamCapabilities: capabilities))
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "prompts/list", upstreamCapabilities: capabilities))
    }

    func testPreservesAdvertisedCapabilities() {
        let capabilities: Set<String> = ["resources", "prompts", "tools"]
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/templates/list", upstreamCapabilities: capabilities))
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/list", upstreamCapabilities: capabilities))
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "prompts/list", upstreamCapabilities: capabilities))
    }
}

import XCTest
@testable import MCPController

final class GatewayOptionalDiscoveryFallbackTests: XCTestCase {
    private var initialized: String { GatewayOptionalDiscoveryFallback.initializedSessionMarker }

    func testRejectsFallbackBeforeARealInitializeResponse() {
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/list", upstreamCapabilities: []))
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "prompts/list", upstreamCapabilities: ["tools"]))
    }

    func testReturnsEmptyOptionalDiscoveryResultsWhenCapabilityIsMissing() {
        let capabilities: Set<String> = [initialized, "logging", "tools"]
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/templates/list", upstreamCapabilities: capabilities))
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/list", upstreamCapabilities: capabilities))
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "prompts/list", upstreamCapabilities: capabilities))
    }

    func testInitializedServerWithNoCapabilitiesStillGetsOptionalFallback() {
        let capabilities: Set<String> = [initialized]
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/list", upstreamCapabilities: capabilities))
        XCTAssertNotNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "prompts/list", upstreamCapabilities: capabilities))
    }

    func testPreservesAdvertisedCapabilities() {
        let capabilities: Set<String> = [initialized, "resources", "prompts", "tools"]
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/templates/list", upstreamCapabilities: capabilities))
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "resources/list", upstreamCapabilities: capabilities))
        XCTAssertNil(GatewayOptionalDiscoveryFallback.emptyResult(for: "prompts/list", upstreamCapabilities: capabilities))
    }
}

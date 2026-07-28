import XCTest
@testable import MCPController

final class GatewayRequestHeaderAdapterTests: XCTestCase {
    func testCompatibilitySuppliesBothRequiredMediaTypes() {
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: "application/json", compatibilityEnabled: true),
            "application/json, text/event-stream"
        )
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: "text/event-stream", compatibilityEnabled: true),
            "application/json, text/event-stream"
        )
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: nil, compatibilityEnabled: true),
            "application/json, text/event-stream"
        )
    }

    func testStrictModePreservesClientHeader() {
        XCTAssertEqual(
            GatewayRequestHeaderAdapter.acceptValue(original: "application/json", compatibilityEnabled: false),
            "application/json"
        )
        XCTAssertNil(GatewayRequestHeaderAdapter.acceptValue(original: nil, compatibilityEnabled: false))
    }
}

import XCTest
@testable import MCPController

final class GatewayRequestDeadlinePolicyTests: XCTestCase {
    func testLongLivedGetStreamsDoNotReceiveRequestDeadline() {
        XCTAssertFalse(GatewayRequestDeadlinePolicy.applies(to: "GET"))
        XCTAssertFalse(GatewayRequestDeadlinePolicy.applies(to: "get"))
    }

    func testBoundedMCPRequestsReceiveRequestDeadline() {
        XCTAssertTrue(GatewayRequestDeadlinePolicy.applies(to: "POST"))
        XCTAssertTrue(GatewayRequestDeadlinePolicy.applies(to: "DELETE"))
    }
}

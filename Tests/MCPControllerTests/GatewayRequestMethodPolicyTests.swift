import XCTest
@testable import MCPController

final class GatewayRequestMethodPolicyTests: XCTestCase {
    func testCoreMCPMethodsAreAlwaysAccepted() {
        for method in ["POST", "GET", "DELETE"] {
            XCTAssertTrue(GatewayRequestMethodPolicy.accepts(method, remoteClientCompatibilityEnabled: false))
        }
    }

    func testHeadProbeRequiresRemoteCompatibility() {
        XCTAssertFalse(GatewayRequestMethodPolicy.accepts("HEAD", remoteClientCompatibilityEnabled: false))
        XCTAssertTrue(GatewayRequestMethodPolicy.accepts("HEAD", remoteClientCompatibilityEnabled: true))
    }

    func testUnsupportedMethodsRemainRejected() {
        XCTAssertFalse(GatewayRequestMethodPolicy.accepts("PUT", remoteClientCompatibilityEnabled: true))
    }
}

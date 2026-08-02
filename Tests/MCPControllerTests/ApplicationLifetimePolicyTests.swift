import XCTest
@testable import MCPController

final class ApplicationLifetimePolicyTests: XCTestCase {
    func testKeepingControllerAvailableDisablesAutomaticTermination() {
        var reasons: [String] = []

        ApplicationLifetimePolicy.keepControllerAvailable { reason in
            reasons.append(reason)
        }

        XCTAssertEqual(reasons, [ApplicationLifetimePolicy.automaticTerminationReason])
    }
}

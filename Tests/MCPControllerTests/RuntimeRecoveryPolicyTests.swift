import XCTest
@testable import MCPController

final class RuntimeRecoveryPolicyTests: XCTestCase {
    func testPersistentServerUsesBoundedBackoff() {
        XCTAssertEqual(RuntimeRecoveryPolicy.retryDelay(autoStart: true, wasUserStopped: false, attempt: 0), 1)
        XCTAssertEqual(RuntimeRecoveryPolicy.retryDelay(autoStart: true, wasUserStopped: false, attempt: 1), 2)
        XCTAssertEqual(RuntimeRecoveryPolicy.retryDelay(autoStart: true, wasUserStopped: false, attempt: 2), 4)
        XCTAssertNil(RuntimeRecoveryPolicy.retryDelay(autoStart: true, wasUserStopped: false, attempt: 3))
        XCTAssertEqual(RuntimeRecoveryPolicy.maximumAttempts, 3)
    }

    func testManualServerDoesNotRestartUnexpectedly() {
        XCTAssertNil(RuntimeRecoveryPolicy.retryDelay(autoStart: false, wasUserStopped: false, attempt: 0))
    }

    func testUserStopNeverRestartsServer() {
        XCTAssertNil(RuntimeRecoveryPolicy.retryDelay(autoStart: true, wasUserStopped: true, attempt: 0))
    }

    func testInvalidAttemptDoesNotRestartServer() {
        XCTAssertNil(RuntimeRecoveryPolicy.retryDelay(autoStart: true, wasUserStopped: false, attempt: -1))
    }
}

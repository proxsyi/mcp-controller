import XCTest
@testable import MCPController

final class ExclusiveLeaseArbiterTests: XCTestCase {
    func testFirstClientGetsLeaseAndSecondWaits() {
        var arbiter = ExclusiveLeaseArbiter(timeout: 900)
        XCTAssertEqual(arbiter.authorize(clientID: "notion", clientName: "Notion"), .allowed)
        XCTAssertEqual(arbiter.authorize(clientID: "cursor", clientName: "Cursor"), .waiting)
        XCTAssertEqual(arbiter.active?.clientID, "notion")
        XCTAssertEqual(arbiter.pending.map(\.clientID), ["cursor"])
    }

    func testApprovalTransfersLease() {
        var arbiter = ExclusiveLeaseArbiter(timeout: 900)
        _ = arbiter.authorize(clientID: "notion", clientName: "Notion")
        _ = arbiter.authorize(clientID: "cursor", clientName: "Cursor")
        arbiter.approve(clientID: "cursor")
        XCTAssertEqual(arbiter.active?.clientID, "cursor")
        XCTAssertTrue(arbiter.pending.isEmpty)
    }

    func testExpiredLeaseCanBeReplaced() {
        let start = Date(timeIntervalSince1970: 100)
        var arbiter = ExclusiveLeaseArbiter(timeout: 60)
        _ = arbiter.authorize(clientID: "notion", clientName: "Notion", now: start)
        XCTAssertEqual(
            arbiter.authorize(clientID: "cursor", clientName: "Cursor", now: start.addingTimeInterval(61)),
            .allowed
        )
        XCTAssertEqual(arbiter.active?.clientID, "cursor")
    }
}

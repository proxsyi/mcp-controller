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

    func testSameClientActivityRefreshesLastSeenWithoutChangingAcquisitionTime() {
        let start = Date(timeIntervalSince1970: 100)
        let refresh = start.addingTimeInterval(45)
        var arbiter = ExclusiveLeaseArbiter(timeout: 60)
        _ = arbiter.authorize(clientID: "notion", clientName: "Notion", now: start)

        XCTAssertEqual(arbiter.authorize(clientID: "notion", clientName: "Notion", now: refresh), .allowed)

        XCTAssertEqual(arbiter.active?.acquiredAt, start)
        XCTAssertEqual(arbiter.active?.lastSeenAt, refresh)
    }

    func testWaitingClientCannotReplaceLeaseKeptAliveBySameClientActivity() {
        let start = Date(timeIntervalSince1970: 100)
        var arbiter = ExclusiveLeaseArbiter(timeout: 60)
        _ = arbiter.authorize(clientID: "notion", clientName: "Notion", now: start)
        _ = arbiter.authorize(clientID: "notion", clientName: "Notion", now: start.addingTimeInterval(45))

        XCTAssertEqual(
            arbiter.authorize(clientID: "cursor", clientName: "Cursor", now: start.addingTimeInterval(75)),
            .waiting
        )
        XCTAssertEqual(arbiter.active?.clientID, "notion")
        XCTAssertEqual(arbiter.pending.map(\.clientID), ["cursor"])
    }

    func testReleaseClearsActiveLeaseWithoutDroppingWaitingClients() {
        var arbiter = ExclusiveLeaseArbiter(timeout: 900)
        _ = arbiter.authorize(clientID: "notion", clientName: "Notion")
        _ = arbiter.authorize(clientID: "cursor", clientName: "Cursor")

        arbiter.release()

        XCTAssertNil(arbiter.active)
        XCTAssertEqual(arbiter.pending.map(\.clientID), ["cursor"])
        XCTAssertEqual(arbiter.authorize(clientID: "cursor", clientName: "Cursor"), .allowed)
        XCTAssertEqual(arbiter.active?.clientID, "cursor")
    }
}

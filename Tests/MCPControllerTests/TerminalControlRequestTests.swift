import XCTest
@testable import MCPController

final class TerminalControlRequestTests: XCTestCase {
    func testQuitIsAcknowledgedBeforeTheHandlerCanTerminateTheApp() {
        let request = TerminalControlRequest(id: "1", action: "QUIT", target: nil, arguments: [:])
        XCTAssertTrue(request.shouldAcknowledgeBeforeHandling)
    }

    func testOrdinaryCommandsWaitForTheirRealHandlerResponse() {
        let request = TerminalControlRequest(id: "1", action: "status", target: nil, arguments: [:])
        XCTAssertFalse(request.shouldAcknowledgeBeforeHandling)
    }
}

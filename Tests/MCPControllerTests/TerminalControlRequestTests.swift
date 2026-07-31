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

    func testOneAIRejectsMissingOrMalformedBooleanValues() {
        XCTAssertEqual(
            TerminalControlRequest(id: "1", action: "one-ai", target: nil, arguments: [:]).validationError,
            "Pass --enabled true or false."
        )
        XCTAssertEqual(
            TerminalControlRequest(id: "1", action: "one-ai", target: nil, arguments: ["enabled": "yes"]).validationError,
            "Pass --enabled true or false."
        )
        XCTAssertNil(
            TerminalControlRequest(id: "1", action: "one-ai", target: nil, arguments: ["enabled": "false"]).validationError
        )
    }

    func testNewServerRejectsInvalidExplicitLocalPorts() {
        XCTAssertEqual(
            TerminalControlRequest(id: "1", action: "new", target: nil, arguments: ["localPort": "80"]).validationError,
            "Pass --local-port with a value from 1024 through 65535."
        )
        XCTAssertEqual(
            TerminalControlRequest(id: "1", action: "new", target: nil, arguments: ["localPort": "not-a-port"]).validationError,
            "Pass --local-port with a value from 1024 through 65535."
        )
        XCTAssertNil(
            TerminalControlRequest(id: "1", action: "new", target: nil, arguments: ["localPort": "4100"]).validationError
        )
    }
}

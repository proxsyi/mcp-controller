import XCTest
@testable import MCPController

final class MCPReadinessProbeTests: XCTestCase {
    func testProbeErrorsDescribeNonSuccessfulHTTPStatus() {
        XCTAssertEqual(
            MCPReadinessProbe.ProbeError.httpStatus(502).errorDescription,
            "The MCP endpoint returned HTTP 502."
        )
    }

}

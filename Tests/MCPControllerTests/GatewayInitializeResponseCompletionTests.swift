import Foundation
import XCTest
@testable import MCPController

final class GatewayInitializeResponseCompletionTests: XCTestCase {
    func testCompleteChunkedInitializeResponseIsMarkedComplete() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = Data("event: message\r\ndata: {\"result\":{\"protocolVersion\":\"2024-11-05\"}}\r\n\r\n".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: session-1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        response.append(HTTPChunkedBodyEncoder.encode(body))
        response.append(Data("0\r\n\r\n".utf8))

        let result = bridge.consume(response)
        XCTAssertEqual(result?.sessionID, "session-1")
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertEqual(result?.responseComplete, true)
    }
}

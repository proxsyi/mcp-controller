import Foundation
import XCTest
@testable import MCPController

final class GatewayInitializeResponseBridgeTests: XCTestCase {
    func testRewritesClientFacingVersionAndCapturesUpstreamSession() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let response = Data(("HTTP/1.1 200 OK\r\nMcp-Session-Id: abc-123\r\nTransfer-Encoding: chunked\r\n\r\n" +
            "data: {\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2024-11-05\"}}\r\n\r\n").utf8)
        let result = bridge.consume(response)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.sessionID, "abc-123")
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("\"protocolVersion\":\"2025-11-25\""))
    }

    func testHandlesVersionMarkerSplitAcrossPackets() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        XCTAssertNil(bridge.consume(Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: s\r\n\r\ndata: {\"protocol".utf8)))
        let result = bridge.consume(Data("Version\":\"2024-11-05\"}\r\n\r\n".utf8))
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("2025-11-25"))
    }

    func testPassesThroughAfterInitialRewrite() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        _ = bridge.consume(Data("HTTP/1.1 200 OK\r\n\r\n{\"protocolVersion\":\"2024-11-05\"}".utf8))
        let later = Data("later".utf8)
        XCTAssertEqual(bridge.consume(later)?.data, later)
    }
}

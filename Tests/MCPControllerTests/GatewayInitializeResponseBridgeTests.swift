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

    func testCapturesAdvertisedCapabilitiesFromSSEInitializeResponse() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = Data("id: first\r\ndata:  \r\n\r\nevent: message\r\nid: second\r\ndata: {\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"logging\":{},\"tools\":{\"listChanged\":true}}}}\r\n\r\n".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: session-caps\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        response.append(HTTPChunkedBodyEncoder.encode(body))
        response.append(Data("0\r\n\r\n".utf8))

        let result = bridge.consume(response)
        XCTAssertEqual(result?.upstreamCapabilities, Set(["logging", "tools", "prompts", "resources"]))
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("\"prompts\":{}"))
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("\"resources\":{}"))
    }

    func testInjectsCompatibilityCapabilitiesIntoRawInitializeJSON() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = "{\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}}}}"
        let response = Data(("HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
        let result = bridge.consume(response)
        XCTAssertEqual(result?.upstreamCapabilities, Set(["tools", "prompts", "resources"]))
        let text = String(decoding: result!.data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"prompts\":{}"))
        XCTAssertTrue(text.contains("\"resources\":{}"))
    }

    func testPassesThroughAfterInitialRewrite() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        _ = bridge.consume(Data("HTTP/1.1 200 OK\r\n\r\n{\"protocolVersion\":\"2024-11-05\"}".utf8))
        let later = Data("later".utf8)
        XCTAssertEqual(bridge.consume(later)?.data, later)
    }
}

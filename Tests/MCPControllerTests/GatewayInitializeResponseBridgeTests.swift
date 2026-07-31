import Foundation
import XCTest
@testable import MCPController

final class GatewayInitializeResponseBridgeTests: XCTestCase {
    private var initialized: String { GatewayOptionalDiscoveryFallback.initializedSessionMarker }

    func testRewritesOpenChunkedInitializeStreamWithoutCorruptingFraming() throws {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = Data("data: {\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2024-11-05\"}}\r\n\r\n".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: abc-123\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        response.append(HTTPChunkedBodyEncoder.encode(body))

        let result = try XCTUnwrap(bridge.consume(response))
        XCTAssertEqual(result.sessionID, "abc-123")
        XCTAssertEqual(result.upstreamVersion, "2024-11-05")
        XCTAssertEqual(result.upstreamCapabilities, Set([initialized]))
        XCTAssertFalse(result.responseComplete)

        let separator = Data("\r\n\r\n".utf8)
        let headerRange = try XCTUnwrap(result.data.range(of: separator))
        let encodedBody = result.data.subdata(in: headerRange.upperBound..<result.data.count)
        let transformed = try XCTUnwrap(HTTPChunkedBodyDecoder.decodeAvailableChunks(encodedBody))
        XCTAssertEqual(transformed.bytesConsumed, encodedBody.count)
        XCTAssertTrue(String(decoding: transformed.body, as: UTF8.self).contains("\"protocolVersion\":\"2025-11-25\""))
    }

    func testHandlesVersionMarkerSplitAcrossPackets() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        XCTAssertNil(bridge.consume(Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: s\r\n\r\ndata: {\"protocol".utf8)))
        let result = bridge.consume(Data("Version\":\"2024-11-05\"}\r\n\r\n".utf8))
        XCTAssertEqual(result?.upstreamVersion, "2024-11-05")
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("2025-11-25"))
    }

    func testCapturesOriginalAdvertisedCapabilitiesFromSSEInitializeResponse() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = Data("id: first\r\ndata:  \r\n\r\nevent: message\r\nid: second\r\ndata: {\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"logging\":{},\"tools\":{\"listChanged\":true}}}}\r\n\r\n".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nMcp-Session-Id: session-caps\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        response.append(HTTPChunkedBodyEncoder.encode(body))
        response.append(Data("0\r\n\r\n".utf8))

        let result = bridge.consume(response)
        XCTAssertEqual(result?.upstreamCapabilities, Set([initialized, "logging", "tools"]))
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("\"prompts\":{}"))
        XCTAssertTrue(String(decoding: result!.data, as: UTF8.self).contains("\"resources\":{}"))
    }

    func testInjectsCompatibilityCapabilitiesIntoRawInitializeJSONWithoutTreatingThemAsUpstream() throws {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        let body = "{\"jsonrpc\":\"2.0\",\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}}}}"
        let response = Data(("HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
        let result = try XCTUnwrap(bridge.consume(response))
        XCTAssertEqual(result.upstreamCapabilities, Set([initialized, "tools"]))
        let text = String(decoding: result.data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"prompts\":{}"))
        XCTAssertTrue(text.contains("\"resources\":{}"))

        let separator = Data("\r\n\r\n".utf8)
        let headerRange = try XCTUnwrap(result.data.range(of: separator))
        let headerText = String(decoding: result.data[..<headerRange.lowerBound], as: UTF8.self)
        let declaredLength = headerText.components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(declaredLength, result.data.count - headerRange.upperBound)
    }

    func testPassesThroughAfterInitialRewrite() {
        let bridge = GatewayInitializeResponseBridge(requestedVersion: "2025-11-25")
        _ = bridge.consume(Data("HTTP/1.1 200 OK\r\n\r\n{\"protocolVersion\":\"2024-11-05\"}".utf8))
        let later = Data("later".utf8)
        XCTAssertEqual(bridge.consume(later)?.data, later)
    }
}

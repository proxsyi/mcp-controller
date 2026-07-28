import Foundation
import XCTest
@testable import MCPController

final class HTTPChunkedBodyEncoderTests: XCTestCase {
    func testFramesSSEPayloadAsHTTPChunk() {
        let payload = Data("event: endpoint\r\ndata: https://example.com/mcp\r\n\r\n".utf8)
        let framed = HTTPChunkedBodyEncoder.encode(payload)
        let expected = String(payload.count, radix: 16) + "\r\n" + String(decoding: payload, as: UTF8.self) + "\r\n"
        XCTAssertEqual(framed, Data(expected.utf8))
    }

    func testUsesByteCountForUnicodePayload() {
        let payload = Data("data: café\r\n\r\n".utf8)
        let framed = String(decoding: HTTPChunkedBodyEncoder.encode(payload), as: UTF8.self)
        XCTAssertTrue(framed.hasPrefix(String(payload.count, radix: 16) + "\r\n"))
    }
}

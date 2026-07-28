import Foundation
import XCTest
@testable import MCPController

final class HTTPChunkedBodyDecoderTests: XCTestCase {
    func testDecodesMultipleChunks() {
        let encoded = Data("4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n".utf8)
        XCTAssertEqual(HTTPChunkedBodyDecoder.decode(encoded), Data("Wikipedia".utf8))
    }

    func testDecodesChunkExtensions() {
        let encoded = Data("B;foo=bar\r\nhello world\r\n0\r\n\r\n".utf8)
        XCTAssertEqual(HTTPChunkedBodyDecoder.decode(encoded), Data("hello world".utf8))
    }

    func testWaitsForCompleteBody() {
        XCTAssertNil(HTTPChunkedBodyDecoder.decode(Data("4\r\nWi".utf8)))
    }
}

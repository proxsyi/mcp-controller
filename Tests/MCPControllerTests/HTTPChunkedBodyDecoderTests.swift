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

    func testRejectsChunkLengthThatWouldOverflowCursorArithmetic() {
        XCTAssertNil(HTTPChunkedBodyDecoder.decode(Data("7fffffffffffffff\r\nx\r\n0\r\n\r\n".utf8)))
    }

    func testReportsOnlyTheConsumedChunkedMessage() {
        let first = Data("1\r\na\r\n0\r\n\r\nnext".utf8)
        let result = HTTPChunkedBodyDecoder.decodeWithConsumed(first)
        XCTAssertEqual(result?.body, Data("a".utf8))
        XCTAssertEqual(result?.bytesConsumed, first.count - 4)
    }

    func testDecodesAvailableChunksWithoutTerminalChunk() {
        let encoded = Data("4\r\nWiki\r\n5\r\npedia\r\n".utf8)
        let result = HTTPChunkedBodyDecoder.decodeAvailableChunks(encoded)
        XCTAssertEqual(result?.body, Data("Wikipedia".utf8))
        XCTAssertEqual(result?.bytesConsumed, encoded.count)
    }

    func testLeavesIncompleteFollowingChunkUnconsumed() {
        let encoded = Data("1\r\na\r\n4\r\nWi".utf8)
        let result = HTTPChunkedBodyDecoder.decodeAvailableChunks(encoded)
        XCTAssertEqual(result?.body, Data("a".utf8))
        XCTAssertEqual(result?.bytesConsumed, 6)
    }
}

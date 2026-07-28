#!/bin/bash
set -euo pipefail

REPO="${HOME}/Projects/Clients/Versyi/MCP-Controller"
cd "${REPO}"

python3 - <<'PY'
from pathlib import Path

profile = Path("Sources/MCPController/Models/ServerProfile.swift")
text = profile.read_text()
old = '''    var streamableHTTPPath: String? {
        if let index = arguments.firstIndex(of: "--streamableHttpPath"), arguments.indices.contains(index + 1) {
            return Self.normalizedEndpointPath(arguments[index + 1])
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--streamableHttpPath=") }) {
            return Self.normalizedEndpointPath(String(argument.dropFirst("--streamableHttpPath=".count)))
        }
        return nil
    }
'''
new = '''    var streamableHTTPPath: String? {
        if let index = arguments.firstIndex(of: "--streamableHttpPath"), arguments.indices.contains(index + 1) {
            return Self.normalizedEndpointPath(arguments[index + 1])
        }
        if let argument = arguments.first(where: { $0.hasPrefix("--streamableHttpPath=") }) {
            return Self.normalizedEndpointPath(String(argument.dropFirst("--streamableHttpPath=".count)))
        }
        if let index = arguments.firstIndex(of: "--transport"), arguments.indices.contains(index + 1) {
            let transport = arguments[index + 1].lowercased()
            if transport == "streamable-http" || transport == "streamablehttp" {
                return "/mcp"
            }
        }
        if arguments.contains(where: {
            let value = $0.lowercased()
            return value == "--transport=streamable-http" || value == "--transport=streamablehttp"
        }) {
            return "/mcp"
        }
        return nil
    }
'''
if old not in text:
    raise SystemExit("ServerProfile.swift did not match the expected pre-fix source")
profile.write_text(text.replace(old, new, 1))

gateway = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
text = gateway.read_text()
old = '''        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { return nil }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return HTTPRequest(method: String(requestParts[0]).uppercased(), target: String(requestParts[1]), headers: headers, body: body)
'''
new = '''        let bodyStart = headerRange.upperBound
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            let encodedBody = data.subdata(in: bodyStart..<data.endIndex)
            guard let body = HTTPChunkedBodyDecoder.decode(encodedBody) else { return nil }
            return HTTPRequest(method: String(requestParts[0]).uppercased(), target: String(requestParts[1]), headers: headers, body: body)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return HTTPRequest(method: String(requestParts[0]).uppercased(), target: String(requestParts[1]), headers: headers, body: body)
'''
if old not in text:
    raise SystemExit("ExclusiveGateway.swift did not match the expected pre-fix source")
gateway.write_text(text.replace(old, new, 1))

tests = Path("Tests/MCPControllerTests/GatewayRouteMapperTests.swift")
text = tests.read_text()
needle = '''    func testAlreadyStrippedEndpointPassesThrough() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/remote"
        profile.arguments = ["--streamableHttpPath=/mcp"]

        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/mcp", profile: profile), "/mcp")
    }
'''
addition = needle + '''
    func testStreamableHTTPTransportDefaultsToMCPPath() {
        var profile = ServerProfile()
        profile.mountPath = "/mcp/macos"
        profile.arguments = ["serve", "--transport", "streamable-http"]

        XCTAssertEqual(profile.streamableHTTPPath, "/mcp")
        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/", profile: profile), "/mcp")
        XCTAssertEqual(GatewayRouteMapper.upstreamTarget(for: "/mcp/macos", profile: profile), "/mcp")
    }
'''
if needle not in text:
    raise SystemExit("GatewayRouteMapperTests.swift did not match the expected source")
tests.write_text(text.replace(needle, addition, 1))
PY

cat > Sources/MCPController/Services/HTTPChunkedBodyDecoder.swift <<'SWIFT'
import Foundation

enum HTTPChunkedBodyDecoder {
    static func decode(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var cursor = 0
        var decoded = Data()

        func firstCRLF(from start: Int) -> Int? {
            guard start < bytes.count else { return nil }
            var index = start
            while index + 1 < bytes.count {
                if bytes[index] == 13 && bytes[index + 1] == 10 { return index }
                index += 1
            }
            return nil
        }

        while true {
            guard let lineEnd = firstCRLF(from: cursor),
                  let line = String(bytes: bytes[cursor..<lineEnd], encoding: .utf8) else { return nil }
            let sizeText = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            guard let size = Int(sizeText, radix: 16), size >= 0 else { return nil }
            cursor = lineEnd + 2

            if size == 0 {
                guard cursor + 1 < bytes.count else { return nil }
                if bytes[cursor] == 13 && bytes[cursor + 1] == 10 { return decoded }
                var index = cursor
                while index + 3 < bytes.count {
                    if bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
                        return decoded
                    }
                    index += 1
                }
                return nil
            }

            guard cursor + size + 1 < bytes.count else { return nil }
            let chunkEnd = cursor + size
            guard bytes[chunkEnd] == 13 && bytes[chunkEnd + 1] == 10 else { return nil }
            decoded.append(contentsOf: bytes[cursor..<chunkEnd])
            cursor = chunkEnd + 2
        }
    }
}
SWIFT

cat > Tests/MCPControllerTests/HTTPChunkedBodyDecoderTests.swift <<'SWIFT'
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
SWIFT

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Models/ServerProfile.swift \
        Sources/MCPController/Services/ExclusiveGateway.swift \
        Sources/MCPController/Services/HTTPChunkedBodyDecoder.swift \
        Tests/MCPControllerTests/GatewayRouteMapperTests.swift \
        Tests/MCPControllerTests/HTTPChunkedBodyDecoderTests.swift
git commit -m "fix(gateway): handle stripped paths and chunked requests"
git push origin main

rm -rf '/Applications/MCP Controller.app.new'
cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'
mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'

echo "Installed fixed build. Resetting its macOS privacy records before relaunch."
tccutil reset All com.versyi.mcp-controller || true
pkill -f '/Applications/MCP Controller.app/Contents/MacOS/MCPController' || true
sleep 3
open -a '/Applications/MCP Controller.app'
sleep 3
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

echo "Done. Re-enable MCP Controller in the opened privacy panes, then rerun the health check."

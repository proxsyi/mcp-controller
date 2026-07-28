#!/bin/bash
set -euo pipefail

REPO="${HOME}/Projects/Clients/Versyi/MCP-Controller"
cd "${REPO}"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path

gateway = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
text = gateway.read_text()
old = '''        let body = "event: endpoint\\r\\ndata: \\(endpoint)\\r\\n\\r\\n" + ": connected\\r\\n\\r\\n"
        let headers = "HTTP/1.1 200 OK\\r\\nContent-Type: text/event-stream\\r\\nCache-Control: no-cache\\r\\nConnection: keep-alive\\r\\n\\r\\n"
        let payload = Data((headers + body).utf8)
        connection.send(content: payload, completion: .contentProcessed { error in
'''
new = '''        let body = Data(("event: endpoint\\r\\ndata: \\(endpoint)\\r\\n\\r\\n" + ": connected\\r\\n\\r\\n").utf8)
        let headers = "HTTP/1.1 200 OK\\r\\nContent-Type: text/event-stream\\r\\nCache-Control: no-cache, no-transform\\r\\nX-Accel-Buffering: no\\r\\nTransfer-Encoding: chunked\\r\\nConnection: keep-alive\\r\\n\\r\\n"
        var payload = Data(headers.utf8)
        payload.append(HTTPChunkedBodyEncoder.encode(body))
        connection.send(content: payload, completion: .contentProcessed { error in
'''
if old not in text:
    raise SystemExit("Compatibility handshake source did not match the expected version")
gateway.write_text(text.replace(old, new, 1))

changelog = Path("CHANGELOG.md")
text = changelog.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.6.8

### Fixed
- Framed compatibility SSE responses with valid HTTP/1.1 chunked transfer encoding.
- Disabled intermediary buffering and response transformation so endpoint events flush immediately through reverse proxies.
- Prevented hosted clients from reporting generic SSE fetch failures after successful authentication and initialization.
"""
if marker not in text:
    raise SystemExit("CHANGELOG marker missing")
changelog.write_text(text.replace(marker, entry, 1))
PY

cat > Sources/MCPController/Services/HTTPChunkedBodyEncoder.swift <<'SWIFT'
import Foundation

enum HTTPChunkedBodyEncoder {
    static func encode(_ body: Data) -> Data {
        var framed = Data(String(body.count, radix: 16).utf8)
        framed.append(Data("\r\n".utf8))
        framed.append(body)
        framed.append(Data("\r\n".utf8))
        return framed
    }
}
SWIFT

cat > Tests/MCPControllerTests/HTTPChunkedBodyEncoderTests.swift <<'SWIFT'
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
SWIFT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.6.8" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 15" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift \
        Sources/MCPController/Services/HTTPChunkedBodyEncoder.swift \
        Tests/MCPControllerTests/HTTPChunkedBodyEncoderTests.swift \
        Resources/Info.plist CHANGELOG.md
git commit -m "fix(gateway): frame compatibility SSE for proxies"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.6.8 >/dev/null 2>&1; then
    echo "Release v0.6.8 already exists."
else
    gh release create v0.6.8 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.6.8"
fi

pkill -f '/MCP Controller.app/Contents/MacOS/MCPController' 2>/dev/null || true
sleep 3
rm -rf '/Applications/MCP Controller.app.new'
cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'
mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'

# Final cleanup: retain only the installed app bundle.
rm -rf 'dist/MCP Controller.app'
rm -f 'dist/MCP-Controller-macOS.zip'
rm -rf "$HOME/Applications/MCP Controller.app"

tccutil reset All com.versyi.mcp-controller || true
open -a '/Applications/MCP Controller.app'
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

echo "v0.6.8 installed. Only /Applications/MCP Controller.app remains. Re-enable permissions, start the server, and retry Notion."

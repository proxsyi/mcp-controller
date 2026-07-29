#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path
p = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
s = p.read_text()

old = '''                    if let error {
                        self.sendError(connection, status: 502, message: "Upstream MCP request failed: \\(error.localizedDescription)", requestID: request.jsonRPCID)
                        upstream.cancel()
                    } else {
                        self.pipeUpstreamResponse(upstream, to: connection, initializeBridge: responseBridge)
                    }
'''
new = '''                    if let error {
                        self.sendError(connection, status: 502, message: "Upstream MCP request failed: \\(error.localizedDescription)", requestID: request.jsonRPCID)
                        upstream.cancel()
                    } else if self.profile.remoteClientCompatibilityEnabled && request.isJSONRPCNotification {
                        self.logHandler("Compatibility acknowledgement: accepted JSON-RPC notification \\(request.jsonRPCMethod ?? "unknown") for upstream delivery.\\n")
                        self.sendAccepted(connection)
                        self.drainUpstreamResponse(upstream)
                    } else {
                        self.pipeUpstreamResponse(upstream, to: connection, initializeBridge: responseBridge)
                    }
'''
if old not in s:
    raise SystemExit("Upstream send completion insertion point missing")
s = s.replace(old, new, 1)

old = '''    private func sendError(
'''
new = '''    private func sendAccepted(_ connection: NWConnection) {
        let response = Data("HTTP/1.1 202 Accepted\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n".utf8)
        send(connection, data: response)
    }

    private func drainUpstreamResponse(_ upstream: NWConnection) {
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
            upstream.cancel()
        }
        queue.asyncAfter(deadline: .now() + 5) { upstream.cancel() }
    }

    private func sendError(
'''
if old not in s:
    raise SystemExit("Gateway response helper insertion point missing")
s = s.replace(old, new, 1)

old = '''    var requestedProtocolVersion: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] as? String == "initialize",
              let params = object["params"] as? [String: Any] else { return nil }
        return params["protocolVersion"] as? String
    }
'''
new = '''    var requestedProtocolVersion: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] as? String == "initialize",
              let params = object["params"] as? [String: Any] else { return nil }
        return params["protocolVersion"] as? String
    }

    var jsonRPCMethod: String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return object["method"] as? String
    }

    var isJSONRPCNotification: Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["method"] is String else { return false }
        return object["id"] == nil
    }
'''
if old not in s:
    raise SystemExit("HTTPRequest notification classifier insertion point missing")
s = s.replace(old, new, 1)
p.write_text(s)

p = Path("scripts/check-notion-validation.sh")
s = p.read_text()
old = '''  sed -E 's/^(authorization:).*/\\1 <redacted>/I' "$headers"
  echo "curl exit: $code"
'''
new = '''  touch "$headers" "$body"
  sed -E 's/^(authorization:).*/\\1 <redacted>/I' "$headers"
  echo "curl exit: $code"
'''
if old in s:
    s = s.replace(old, new, 1)
p.write_text(s)

c = Path("CHANGELOG.md")
s = c.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.7.2

### Fixed
- Added a generic compatibility acknowledgement for JSON-RPC notifications after successful upstream delivery.
- Returned the MCP-required HTTP 202 response immediately instead of allowing proxy timeouts to become HTTP 502 errors.
- Drained the upstream notification response without blocking the remote client.
- Kept the validation report running when a timed-out request produced no body file.
"""
if marker not in s:
    raise SystemExit("CHANGELOG marker missing")
c.write_text(s.replace(marker, entry, 1))
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.7.2" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 19" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift scripts/check-notion-validation.sh Resources/Info.plist CHANGELOG.md
git rm -f scripts/install-v0.7.2.sh
git commit -m "fix(gateway): acknowledge compatibility notifications"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.7.2 >/dev/null 2>&1; then
  echo "Release v0.7.2 already exists."
else
  gh release create v0.7.2 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.7.2"
fi

pkill -f '/MCP Controller.app/Contents/MacOS/MCPController' 2>/dev/null || true
sleep 3
rm -rf '/Applications/MCP Controller.app.new'
cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'
mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'
mkdir -p "$HOME/.local/bin"
cp '/Applications/MCP Controller.app/Contents/Resources/mcpctl' "$HOME/.local/bin/mcpctl"
chmod +x "$HOME/.local/bin/mcpctl"
rm -rf 'dist/MCP Controller.app'
rm -f 'dist/MCP-Controller-macOS.zip'
rm -rf "$HOME/Applications/MCP Controller.app"
tccutil reset All com.versyi.mcp-controller || true
open -a '/Applications/MCP Controller.app'
echo "v0.7.2 installed. Start Remote MacOS Use, rerun validation, then retry Notion."

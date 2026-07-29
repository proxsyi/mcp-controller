#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path
p = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
s = p.read_text()

old = '''        stop(profileID: profile.id)
        let gateway = try ExclusiveGateway(
'''
new = '''        stop(profileID: profile.id)
        for _ in 0..<20 where PortInspector.listener(on: profile.gatewayPort) != nil {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let gateway = try ExclusiveGateway(
'''
if old not in s:
    raise SystemExit("Gateway manager start insertion point missing")
s = s.replace(old, new, 1)

old = '''    private let queue: DispatchQueue
    private let listener: NWListener
'''
new = '''    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let listener: NWListener
'''
if old not in s:
    raise SystemExit("Gateway queue property insertion point missing")
s = s.replace(old, new, 1)

old = '''        self.queue = DispatchQueue(label: "com.versyi.mcp-controller.gateway.\\(profile.id.uuidString)")
        guard let port = NWEndpoint.Port(rawValue: UInt16(profile.gatewayPort)) else {
'''
new = '''        self.queue = DispatchQueue(label: "com.versyi.mcp-controller.gateway.\\(profile.id.uuidString)")
        self.queue.setSpecific(key: queueKey, value: ())
        guard let port = NWEndpoint.Port(rawValue: UInt16(profile.gatewayPort)) else {
'''
if old not in s:
    raise SystemExit("Gateway queue setup insertion point missing")
s = s.replace(old, new, 1)

old = '''    func stop() {
        queue.async { [weak self] in
            self?.listener.cancel()
            self?.arbiter.release()
            self?.publishState()
        }
    }
'''
new = '''    func stop() {
        let shutdown = { [self] in
            listener.cancel()
            arbiter.release()
            publishState()
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            shutdown()
        } else {
            queue.sync(execute: shutdown)
        }
    }
'''
if old not in s:
    raise SystemExit("Gateway stop implementation missing")
s = s.replace(old, new, 1)
p.write_text(s)

c = Path("CHANGELOG.md")
s = c.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.7.1

### Fixed
- Made exclusive gateway shutdown synchronous before a server restart.
- Waited for the old gateway listener to release its port before binding a replacement.
- Prevented rapid stop/start and adopted-listener restarts from failing with `NWError 48: Address already in use`.
"""
if marker not in s:
    raise SystemExit("CHANGELOG marker missing")
c.write_text(s.replace(marker, entry, 1))
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.7.1" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 18" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift Resources/Info.plist CHANGELOG.md
git rm -f scripts/install-v0.7.1.sh
git commit -m "fix(gateway): release listener before restart"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.7.1 >/dev/null 2>&1; then
  echo "Release v0.7.1 already exists."
else
  gh release create v0.7.1 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.7.1"
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
echo "v0.7.1 installed. Start Remote MacOS Use once, then retry Notion."

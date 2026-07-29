#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"
git pull --ff-only

python3 - <<'PY'
from pathlib import Path
p = Path("Sources/MCPController/Services/ExclusiveGateway.swift")
s = p.read_text()
old = '''        headers += "Connection: keep-alive\\r\\n\\r\\n"
'''
new = '''        // Each accepted gateway socket currently carries exactly one HTTP request.
        // Ask the upstream to close after its response so reverse proxies never reuse
        // a backend connection that the gateway is still draining.
        headers += "Connection: close\\r\\n\\r\\n"
'''
if old not in s:
    raise SystemExit("Upstream connection header insertion point missing")
s = s.replace(old, new, 1)
p.write_text(s)

p = Path("Sources/MCPController/AppModel.swift")
s = p.read_text()
old = '''            do { try PortInspector.terminate(listener) }
            catch { fail(profile, "Could not stop adopted PID \\(listener.pid): \\(error.localizedDescription)"); return }
'''
new = '''            do { try PortInspector.terminate(listener) }
            catch {
                if PortInspector.listener(on: profile.localPort)?.pid == listener.pid {
                    fail(profile, "Could not stop adopted PID \\(listener.pid): \\(error.localizedDescription)")
                    return
                }
                appendLog(profile.id, "Adopted PID \\(listener.pid) had already exited; continuing shutdown.\\n")
            }
'''
if old not in s:
    raise SystemExit("Adopted listener shutdown insertion point missing")
s = s.replace(old, new, 1)
p.write_text(s)

c = Path("CHANGELOG.md")
s = c.read_text()
marker = "## Unreleased\n"
entry = """## Unreleased

## v0.7.3

### Fixed
- Closed each upstream HTTP connection after its single proxied MCP response.
- Prevented Tailscale from reusing an initialize backend connection that the gateway was still draining.
- Fixed the first post-initialize request failing with HTTP 502 while the following request opened a fresh connection.
- Treated an already-exited adopted process as a successful stop instead of a failure.
"""
if marker not in s:
    raise SystemExit("CHANGELOG marker missing")
c.write_text(s.replace(marker, entry, 1))
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.7.3" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 20" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController/Services/ExclusiveGateway.swift Sources/MCPController/AppModel.swift Resources/Info.plist CHANGELOG.md
git rm -f scripts/install-v0.7.3.sh
git commit -m "fix(gateway): close one-response proxy connections"
git push origin main

codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
if gh release view v0.7.3 >/dev/null 2>&1; then
  echo "Release v0.7.3 already exists."
else
  gh release create v0.7.3 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.7.3"
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
echo "v0.7.3 installed. Start Remote MacOS Use and rerun validation."

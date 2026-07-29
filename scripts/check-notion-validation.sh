#!/bin/bash
set -euo pipefail

CONFIG="$HOME/Library/Application Support/MCP Controller/servers.json"
REPORT="$HOME/Desktop/notion-mcp-validation-report.txt"
WORK="$(mktemp -d /tmp/notion-mcp-validation.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

python3 - "$CONFIG" "$WORK/profile.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    profiles = json.load(f)
profile = next((p for p in profiles if p.get("name") == "Remote macOS Use"), None)
if not profile:
    raise SystemExit("Remote macOS Use profile not found")
credential = next((c for c in profile.get("clientCredentials", []) if c.get("name") == "Notion"), None)
if not credential:
    credential = (profile.get("clientCredentials") or [None])[0]
if not credential:
    raise SystemExit("No access key exists for Remote macOS Use")
out = {
    "url": "https://cashs-macbook-pro.tail6b12d0.ts.net" + profile.get("mountPath", "/mcp/remote"),
    "token": credential["token"],
    "compatibility": profile.get("remoteClientCompatibilityEnabled"),
    "gatewayPort": profile.get("gatewayPort"),
    "localPort": profile.get("localPort"),
}
with open(sys.argv[2], "w") as f:
    json.dump(out, f)
PY

URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$WORK/profile.json")
TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$WORK/profile.json")
COMPAT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["compatibility"])' "$WORK/profile.json")
GATEWAY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["gatewayPort"])' "$WORK/profile.json")
UPSTREAM=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["localPort"])' "$WORK/profile.json")

exec > >(tee "$REPORT") 2>&1

echo "=== CONFIGURATION ==="
echo "URL: $URL"
echo "Compatibility enabled: $COMPAT"
echo "Gateway port: $GATEWAY"
echo "Upstream port: $UPSTREAM"
echo "Installed version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/MCP Controller.app/Contents/Info.plist' 2>/dev/null || echo missing)"
echo "Installed executable:"
pgrep -fl '/MCP Controller.app/Contents/MacOS/MCPController' || true
echo "App bundles:"
find /Applications "$HOME/Applications" "$HOME/Projects/Clients/Versyi/MCP-Controller/dist" -maxdepth 2 -name 'MCP Controller.app' -print 2>/dev/null || true
echo "Listeners:"
lsof -nP -iTCP:"$GATEWAY" -sTCP:LISTEN || true
lsof -nP -iTCP:"$UPSTREAM" -sTCP:LISTEN || true

request() {
  local name="$1"; shift
  local headers="$WORK/$name.headers"
  local body="$WORK/$name.body"
  echo
  echo "=== $name ==="
  set +e
  curl -sS --no-buffer --max-time 8 -D "$headers" -o "$body" "$@"
  local code=$?
  set -e
  sed -E 's/^(authorization:).*/\1 <redacted>/I' "$headers"
  echo "curl exit: $code"
  echo "body:"
  head -c 3000 "$body"; echo
}

request pre_session_get \
  -X GET \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: text/event-stream" \
  "$URL"

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"notion-validator-emulator","version":"1.0"}}}'
request initialize_json_only \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data "$INIT" \
  "$URL"

SESSION=$(awk 'BEGIN{IGNORECASE=1} /^mcp-session-id:/ {gsub("\r",""); sub(/^[^:]+:[[:space:]]*/,""); print; exit}' "$WORK/initialize_json_only.headers")
VERSION=$(python3 - "$WORK/initialize_json_only.body" <<'PY'
import json, re, sys
text=open(sys.argv[1], errors="replace").read()
match=re.search(r'data:\s*(\{.*\})', text)
if match: text=match.group(1)
try: print(json.loads(text).get("result",{}).get("protocolVersion", "2024-11-05"))
except Exception: print("2024-11-05")
PY
)
echo "Negotiated protocol: $VERSION"
echo "Session received: $([ -n "$SESSION" ] && echo yes || echo no)"

if [ -n "$SESSION" ]; then
  request initialized_notification \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $SESSION" \
    -H "MCP-Protocol-Version: $VERSION" \
    --data '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    "$URL"

  request tools_list \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $SESSION" \
    -H "MCP-Protocol-Version: $VERSION" \
    --data '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
    "$URL"

  request session_get \
    -X GET \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: text/event-stream" \
    -H "Mcp-Session-Id: $SESSION" \
    -H "MCP-Protocol-Version: $VERSION" \
    "$URL"
fi

request options \
  -X OPTIONS \
  -H "Authorization: Bearer $TOKEN" \
  -H "Origin: https://www.notion.so" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization,content-type,mcp-session-id,mcp-protocol-version" \
  "$URL"

echo
echo "Saved report: $REPORT"

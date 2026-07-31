#!/bin/bash
set -euo pipefail

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
CONFIG="${MCP_CONFIG:-$HOME/Library/Application Support/MCP Controller/servers.json}"
REPORT="${MCP_REPORT:-$HOME/Desktop/notion-mcp-validation-report-$TIMESTAMP.txt}"
WORK="$(mktemp -d /tmp/notion-mcp-validation.XXXXXX)"
ORIGIN="${MCP_ORIGIN:-https://www.notion.so}"
trap 'rm -rf "$WORK"' EXIT

python3 - "$CONFIG" "$WORK/profile.json" <<'PY'
import json, os, subprocess, sys

config_path, output_path = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    profiles = [p for p in json.load(f) if p.get("kind", "server") == "server"]
if not profiles:
    raise SystemExit("No server profiles found")

target_name = None
for key in ("MCP_PROFILE", "PROFILE_NAME"):
    value = os.environ.get(key, "").strip()
    if value:
        target_name = value
        break

profile = None
if target_name:
    profile = next((p for p in profiles if p.get("name", "").casefold() == target_name.casefold()), None)
if not profile:
    profile = next((p for p in profiles if p.get("name", "").casefold() == "remote macos use"), None)
if not profile:
    profile = next((p for p in profiles if p.get("mountPath") == "/mcp/remote"), None)
if not profile:
    profile = next((p for p in profiles if p.get("remoteClientCompatibilityEnabled")), None)
if not profile:
    profile = next((p for p in profiles if p.get("tailscaleRouteEnabled")), None)
if not profile:
    raise SystemExit("No suitable remote profile found")

client_name = os.environ.get("MCP_CLIENT", "").strip()
credential = None
if client_name:
    credential = next((c for c in profile.get("clientCredentials", []) if c.get("name", "").casefold() == client_name.casefold()), None)
if not credential:
    credential = next((c for c in profile.get("clientCredentials", []) if c.get("name") == "Notion"), None)
if not credential:
    credential = (profile.get("clientCredentials") or [None])[0]
if not credential:
    raise SystemExit(f"No access key exists for {profile.get('name') or 'selected profile'}")

tailscale_path = profile.get("tailscalePath") or "/opt/homebrew/bin/tailscale"
result = subprocess.run([tailscale_path, "status", "--json"], capture_output=True, text=True, timeout=20, check=True)
dns_name = json.loads(result.stdout)["Self"]["DNSName"].rstrip(".")
mount_path = profile.get("mountPath") or "/mcp/remote"
if not mount_path.startswith("/"):
    mount_path = "/" + mount_path
out = {
    "name": profile.get("name", ""),
    "url": "https://" + dns_name + mount_path,
    "token": credential["token"],
    "compatibility": profile.get("remoteClientCompatibilityEnabled"),
    "gatewayPort": profile.get("gatewayPort"),
    "localPort": profile.get("localPort"),
}
with open(output_path, "w") as f:
    json.dump(out, f)
PY

PROFILE_NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$WORK/profile.json")
URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$WORK/profile.json")
TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$WORK/profile.json")
COMPAT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["compatibility"])' "$WORK/profile.json")
GATEWAY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["gatewayPort"])' "$WORK/profile.json")
UPSTREAM=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["localPort"])' "$WORK/profile.json")

exec > >(tee "$REPORT") 2>&1

echo "=== CONFIGURATION ==="
echo "Profile: $PROFILE_NAME"
echo "URL: $URL"
echo "Origin: $ORIGIN"
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
  touch "$headers" "$body"
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

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"notion-validator-emulator","version":"1.0"}}}'
request initialize_json_only \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  --data "$INIT" \
  "$URL"

SESSION=$(awk 'BEGIN{IGNORECASE=1} /^mcp-session-id:/ {gsub("\r",""); sub(/^[^:]+:[[:space:]]*/,""); print; exit}' "$WORK/initialize_json_only.headers")
VERSION=$(python3 - "$WORK/initialize_json_only.body" <<'PY'
import json, sys
text = open(sys.argv[1], errors="replace").read().replace("\r\n", "\n")
payload = None
for block in text.split("\n\n"):
    data_lines = [line[5:].lstrip() for line in block.split("\n") if line.startswith("data:")]
    if not data_lines:
        continue
    candidate = "\n".join(data_lines).strip()
    if not candidate:
        continue
    try:
            payload = json.loads(candidate)
            break
    except Exception:
        continue
if payload is None:
    payload = json.loads(text)
version = payload.get("result", {}).get("protocolVersion")
if not version:
    raise SystemExit("initialize response missing protocol version")
print(version)
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
  -H "Origin: $ORIGIN" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization,content-type,mcp-session-id,mcp-protocol-version" \
  "$URL"

echo
 echo "Saved report: $REPORT"

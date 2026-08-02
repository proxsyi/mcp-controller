#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MCP Controller.app"
DEST="/Applications/$APP_NAME"
STAGE="/Applications/.MCP Controller.app.installing"

bash "$ROOT/scripts/build-app.sh"
codesign --verify --deep --strict "$ROOT/dist/$APP_NAME"
rm -rf "$STAGE"
ditto "$ROOT/dist/$APP_NAME" "$STAGE"
codesign --verify --deep --strict "$STAGE"

controller_pids() {
  ps -axo pid=,command= | awk '/\/Applications\/MCP Controller\.app\/Contents\/MacOS\/MCPController$/ { print $1 }'
}

# Stop every installed Controller instance before replacing the bundle. Use the
# bundle identifier first so the running app can quit cleanly, then fall back to
# exact installed-process matching instead of pgrep patterns that can miss this
# spaced app path on macOS.
osascript -e 'tell application id "com.versyi.mcp-controller" to quit' >/dev/null 2>&1 || true
for _ in {1..40}; do
  CONTROLLER_PIDS="$(controller_pids)"
  [[ -z "$CONTROLLER_PIDS" ]] && break
  sleep 0.25
done
CONTROLLER_PIDS="$(controller_pids)"
if [[ -n "$CONTROLLER_PIDS" ]]; then
  kill -TERM $CONTROLLER_PIDS 2>/dev/null || true
  for _ in {1..40}; do
    CONTROLLER_PIDS="$(controller_pids)"
    [[ -z "$CONTROLLER_PIDS" ]] && break
    sleep 0.25
  done
  CONTROLLER_PIDS="$(controller_pids)"
  if [[ -n "$CONTROLLER_PIDS" ]]; then
    kill -KILL $CONTROLLER_PIDS 2>/dev/null || true
  fi
fi

rm -rf "$DEST"
mv "$STAGE" "$DEST"
mkdir -p "$HOME/.local/bin"
cp "$DEST/Contents/Resources/mcpctl" "$HOME/.local/bin/mcpctl"
chmod +x "$HOME/.local/bin/mcpctl"
codesign --verify --deep --strict "$DEST"

# Keep only the installed Applications bundle and launch it without forcing a
# second instance. The app itself also rejects duplicate launches.
rm -rf "$ROOT/dist/$APP_NAME"
open "$DEST"
echo "Installed and launched the sole stable-signed app at $DEST"

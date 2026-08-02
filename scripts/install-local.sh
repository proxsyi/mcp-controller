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

# Stop every Controller instance before replacing the installed bundle. This
# prevents a development copy and the Applications copy from running together.
CONTROLLER_PIDS="$(pgrep -f '/MCP Controller\.app/Contents/MacOS/MCPController$' || true)"
if [[ -n "$CONTROLLER_PIDS" ]]; then
  kill -TERM $CONTROLLER_PIDS 2>/dev/null || true
  for _ in {1..40}; do
    pgrep -f '/MCP Controller\.app/Contents/MacOS/MCPController$' >/dev/null || break
    sleep 0.25
  done
  CONTROLLER_PIDS="$(pgrep -f '/MCP Controller\.app/Contents/MacOS/MCPController$' || true)"
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

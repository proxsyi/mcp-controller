#!/bin/bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)/mcp-health-check.py"
TEMP="$(mktemp /tmp/mcp-health-check.XXXXXX.py)"
trap 'rm -f "$TEMP"' EXIT
python3 - "$SOURCE" "$TEMP" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
old = 'if token: cmd[7:7] = ["-H","Authorization: Bearer " + token]'
new = 'if token: cmd += ["-H","Authorization: Bearer " + token]'
if old not in source:
    raise SystemExit("Health checker source did not match the expected version")
Path(sys.argv[2]).write_text(source.replace(old, new, 1))
PY
python3 "$TEMP"

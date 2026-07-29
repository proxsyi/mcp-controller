#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"
git pull --ff-only
python3 - <<'PY'
from pathlib import Path
p = Path("scripts/install-v0.7.0.sh")
lines = p.read_text().splitlines()
lines = [line for line in lines if "s=s.replace('Origin:" not in line]
p.write_text("\n".join(lines) + "\n")
PY
bash scripts/install-v0.7.0.sh

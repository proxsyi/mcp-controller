#!/usr/bin/env python3
"""Live, profile-specific MCP integration tests for MCP Controller."""
from __future__ import annotations
import argparse, json, os, sys, time, urllib.error, urllib.request
from pathlib import Path

PROFILE_SPECS = {
    "DDF597AD-1EC6-4B23-BBF8-4EF2F76E077C": {
        "name": "Mac OS System", "description": "Semantic desktop and shell control.",
        "minimum_tools": 8, "required_any": [{"shell", "Shell"}, {"state", "State"}],
        "safe_calls": [("shell", {"command": "printf mcp-system-ok"}), ("Shell", {"command": "printf mcp-system-ok", "mode": "shell"})],
    },
    "03276892-4D3A-4715-8308-E81E08E6647A": {
        "name": "Mac OS Visual", "description": "Visual desktop automation.",
        "minimum_tools": 18, "required": {"screenshot", "screenInfo", "windowControl", "waitForImage"},
        "safe_calls": [("screenInfo", {})],
    },
    "584031AA-4B48-4583-826E-704AECEBE5FC": {
        "name": "Mac OS Apps", "description": "Structured Apple app access.",
        "minimum_tools": 7, "required": {"applescript.ping", "app.list", "app.get", "app.search"},
        "safe_calls": [("applescript.ping", {})],
    },
    "3C056009-1E43-44F2-B780-E06F726701BA": {
        "name": "Mac OS Remote", "description": "Remote desktop control.",
        "minimum_tools": 8, "required": {"remote_macos_get_screen", "remote_macos_mouse_click", "remote_macos_send_keys"},
        "safe_calls": [("remote_macos_get_screen", {})],
    },
}

def parse_message(text: str) -> dict:
    for line in text.splitlines():
        if line.startswith("data: "):
            return json.loads(line[6:])
    return json.loads(text) if text.strip() else {}

class Client:
    def __init__(self, url: str, token: str, timeout: int):
        self.url, self.token, self.timeout, self.session = url, token, timeout, None
    def post(self, payload: dict) -> tuple[int, dict]:
        headers = {"Authorization": f"Bearer {self.token}", "Accept": "application/json, text/event-stream", "Content-Type": "application/json", "MCP-Protocol-Version": "2025-11-25"}
        if self.session: headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers, method="POST")
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as response:
                    self.session = response.headers.get("Mcp-Session-Id") or self.session
                    return response.status, parse_message(response.read().decode())
            except urllib.error.HTTPError as exc:
                if exc.code not in {502, 503, 504} or attempt == 4:
                    raise
                time.sleep(2 * (attempt + 1))
        raise AssertionError("unreachable")
    def initialize(self) -> None:
        status, body = self.post({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"mcp-controller-tests","version":"1"}}})
        assert status == 200 and body.get("result", {}).get("protocolVersion") == "2025-11-25"
        status, _ = self.post({"jsonrpc":"2.0","method":"notifications/initialized"})
        assert status == 202

def token_for(profile: dict) -> str:
    credentials = profile.get("clientCredentials", [])
    if not credentials: raise AssertionError("No client credentials configured")
    return next((item["token"] for item in credentials if item.get("name", "").lower() == "notion"), credentials[0]["token"])

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="https://cashs-macbook-pro.tail6b12d0.ts.net")
    ap.add_argument("--config", default=str(Path.home()/"Library/Application Support/MCP Controller/servers.json"))
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--skip-tool-calls", action="store_true")
    ap.add_argument("--only", action="append", help="Run one named profile; repeatable")
    ap.add_argument("--local", action="store_true", help="Test local upstream endpoints instead of public routes")
    args = ap.parse_args()
    profiles = {p["id"].upper(): p for p in json.load(open(args.config))}
    failures, report = [], []
    for pid, spec in PROFILE_SPECS.items():
        if args.only and spec["name"] not in args.only:
            continue
        started = time.monotonic()
        row = {"name": spec["name"], "status": "failed"}
        try:
            p = profiles[pid]
            assert p["name"] == spec["name"], f"name is {p['name']!r}"
            assert p.get("description") == spec["description"], f"description is {p.get('description')!r}"
            url = f"http://127.0.0.1:{p['localPort']}/mcp" if args.local else args.base_url.rstrip("/") + p["mountPath"]
            client = Client(url, token_for(p), args.timeout)
            client.initialize()
            status, body = client.post({"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}})
            assert status == 200
            tools = body.get("result", {}).get("tools", [])
            names = {tool["name"] for tool in tools}
            assert len(names) >= spec["minimum_tools"], f"only {len(names)} tools"
            assert spec.get("required", set()) <= names, f"missing {sorted(spec.get('required', set()) - names)}"
            for choices in spec.get("required_any", []): assert choices & names, f"missing one of {sorted(choices)}"
            called = None
            if not args.skip_tool_calls:
                for candidate, tool_args in spec["safe_calls"]:
                    if candidate in names:
                        status, result = client.post({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":candidate,"arguments":tool_args}})
                        assert status == 200 and not result.get("result", {}).get("isError", False), str(result)[:400]
                        called = candidate; break
                assert called, "no representative tool available"
            row.update(status="passed", tool_count=len(names), representative_tool=called)
        except Exception as exc:
            row["error"] = f"{type(exc).__name__}: {exc}"; failures.append(row.copy())
        row["seconds"] = round(time.monotonic() - started, 3); report.append(row)
        print(("PASS" if row["status"] == "passed" else "FAIL"), row["name"], json.dumps(row, sort_keys=True))
    print(json.dumps({"passed": len(report)-len(failures), "failed": len(failures), "profiles": report}, indent=2))
    return 1 if failures else 0
if __name__ == "__main__": raise SystemExit(main())

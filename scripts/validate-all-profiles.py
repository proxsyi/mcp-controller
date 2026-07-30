#!/usr/bin/env python3
"""Non-destructive local-gateway and public-route validation for every profile."""
from __future__ import annotations
import argparse, json, pathlib, subprocess, time, urllib.error, urllib.request

SAFE_CALLS = {
    "MacOS System": [("Shell", {"command": "printf mcp-controller-ok", "mode": "shell"}), ("shell", {"command": "printf mcp-controller-ok"})],
    "MacOS Visual": [("screenInfo", {})],
    "MacOS AppleScript": [("applescript.ping", {})],
    "Chrome DevTools": [("list_pages", {})],
    "ReactBits": [("search_components", {"query": "button"})],
    "Context7": [("resolve-library-id", {"libraryName": "React", "query": "React hooks documentation"}), ("resolve_library_id", {"libraryName": "react"})],
    "Google Stitch": [("list_projects", {})],
    "Supabase": [("list_projects", {})],
    "Cloudflare": [("zones_list", {})],
    "PostHog": [("search", {"query": "projects"})],
    "Sentry": [("find_organizations", {})],
}

class MCPClient:
    def __init__(self, url: str, token: str, timeout: int):
        self.url, self.token, self.timeout, self.session, self.next_id = url, token, timeout, None, 1

    @staticmethod
    def parse(text: str) -> dict:
        for line in text.splitlines():
            if line.startswith("data:"):
                data = line[5:].strip()
                if data:
                    return json.loads(data)
        return json.loads(text) if text.strip() and not ("event:" in text or "data:" in text) else {}

    def post(self, method: str, params: dict | None = None, notification: bool = False) -> tuple[int, dict]:
        payload = {"jsonrpc": "2.0", "method": method}
        if not notification:
            payload["id"] = self.next_id; self.next_id += 1
        if params is not None: payload["params"] = params
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": "2025-11-25",
        }
        if self.session: headers["Mcp-Session-Id"] = self.session
        request = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            self.session = response.headers.get("Mcp-Session-Id") or self.session
            return response.status, self.parse(response.read().decode())

    def validate(self, safe_calls: list[tuple[str, dict]]) -> tuple[int, str | None]:
        status, body = self.post("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "mcp-controller-matrix", "version": "1"}})
        assert status == 200 and body.get("result", {}).get("protocolVersion"), "initialize response missing protocol version"
        try: self.post("notifications/initialized", notification=True)
        except urllib.error.HTTPError as error:
            assert error.code == 202
        status, body = self.post("tools/list", {})
        assert status == 200, f"tools/list returned HTTP {status}"
        tools = body.get("result", {}).get("tools", [])
        names = {tool.get("name") for tool in tools}
        assert names, "tools/list returned no tools"
        called = None
        for name, arguments in safe_calls:
            if name in names:
                status, result = self.post("tools/call", {"name": name, "arguments": arguments})
                assert status == 200 and not result.get("result", {}).get("isError", False), f"safe call {name} failed"
                called = name; break
        return len(names), called

def token_for(profile: dict) -> str:
    credentials = profile.get("clientCredentials") or []
    assert credentials, "no gateway credential configured"
    return next((c["token"] for c in credentials if c.get("name", "").lower() == "notion"), credentials[0]["token"])

def dns_name(profiles: list[dict]) -> str:
    path = next(p["tailscalePath"] for p in profiles if p.get("tailscalePath"))
    result = subprocess.run([path, "status", "--json"], capture_output=True, text=True, timeout=20, check=True)
    return json.loads(result.stdout)["Self"]["DNSName"].rstrip(".")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(pathlib.Path.home()/"Library/Application Support/MCP Controller/servers.json"))
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--catalog-only", action="store_true")
    parser.add_argument("--skip", action="append", default=[], help="Profile name to skip (repeatable)")
    args = parser.parse_args()
    profiles = json.loads(pathlib.Path(args.config).read_text())
    dns = dns_name(profiles)
    report, failures = [], []
    for profile in profiles:
        if profile["name"] in args.skip:
            print(json.dumps({"name": profile["name"], "status": "skipped"}), flush=True)
            continue
        row = {"name": profile["name"], "surfaces": {}}
        token = token_for(profile)
        surfaces = {
            "gateway": f"http://127.0.0.1:{profile['gatewayPort']}/",
            "public": f"https://{dns}{profile['mountPath']}",
        }
        for surface, url in surfaces.items():
            started = time.monotonic()
            try:
                safe = [] if args.catalog_only else SAFE_CALLS.get(profile["name"], [])
                count, called = MCPClient(url, token, args.timeout).validate(safe)
                row["surfaces"][surface] = {"status": "passed", "toolCount": count, "safeTool": called, "seconds": round(time.monotonic()-started, 3)}
            except Exception as error:
                detail = f"{type(error).__name__}: {error}"
                row["surfaces"][surface] = {"status": "failed", "error": detail, "seconds": round(time.monotonic()-started, 3)}
                failures.append({"profile": profile["name"], "surface": surface, "error": detail})
        report.append(row)
        print(json.dumps(row, sort_keys=True), flush=True)
    tested_surfaces = len(report) * 2
    summary = {"passedSurfaces": tested_surfaces-len(failures), "failedSurfaces": len(failures), "skippedProfiles": args.skip, "profiles": report, "failures": failures}
    print(json.dumps(summary, indent=2))
    return 1 if failures else 0

if __name__ == "__main__": raise SystemExit(main())

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
    def __init__(self, url: str, token: str | None, timeout: int):
        self.url, self.token, self.timeout, self.session, self.next_id = url, token, timeout, None, 1

    @staticmethod
    def parse(text: str) -> dict:
        normalized = text.replace("\r\n", "\n")
        for block in normalized.split("\n\n"):
            data_lines = [line[5:].lstrip() for line in block.splitlines() if line.startswith("data:")]
            if not data_lines:
                continue
            candidate = "\n".join(data_lines).strip()
            if not candidate:
                continue
            try:
                return json.loads(candidate)
            except json.JSONDecodeError:
                continue
        return json.loads(normalized) if normalized.strip() and not ("event:" in normalized or "data:" in normalized) else {}

    def post(self, method: str, params: dict | None = None, notification: bool = False) -> tuple[int, dict]:
        payload = {"jsonrpc": "2.0", "method": method}
        if not notification:
            payload["id"] = self.next_id; self.next_id += 1
        if params is not None: payload["params"] = params
        headers = {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
            "MCP-Protocol-Version": "2025-11-25",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        request = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            self.session = response.headers.get("Mcp-Session-Id") or self.session
            return response.status, self.parse(response.read().decode())

    def validate(self, safe_calls: list[tuple[str, dict]]) -> tuple[int, str | None]:
        status, body = self.post("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "mcp-controller-matrix", "version": "1"}})
        assert status == 200 and body.get("result", {}).get("protocolVersion"), "initialize response missing protocol version"
        try:
            status, _ = self.post("notifications/initialized", notification=True)
            assert status in (200, 202, 204), f"initialized notification returned HTTP {status}"
        except urllib.error.HTTPError as error:
            assert error.code in (200, 202, 204), f"initialized notification returned HTTP {error.code}"
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

def token_for(profile: dict, preferred_name: str | None = None) -> str:
    credentials = profile.get("clientCredentials") or []
    assert credentials, "no gateway credential configured"
    if preferred_name:
        selected = next((c for c in credentials if c.get("name", "").casefold() == preferred_name.casefold()), None)
        assert selected, f"credential {preferred_name!r} was not found"
        return selected["token"]
    notion = next((c for c in credentials if c.get("name", "").lower() == "notion"), None)
    return (notion or credentials[0])["token"]

def server_profiles(profiles: list[dict]) -> list[dict]:
    return [profile for profile in profiles if profile.get("kind", "server") == "server"]

def dns_name(profiles: list[dict]) -> str:
    servers = server_profiles(profiles)
    assert servers, "no server profiles found"
    path = next((p.get("tailscalePath") for p in servers if p.get("tailscalePath")), None)
    assert path, "no Tailscale CLI path configured"
    result = subprocess.run([path, "status", "--json"], capture_output=True, text=True, timeout=20, check=True)
    return json.loads(result.stdout)["Self"]["DNSName"].rstrip(".")

def normalized_mount_path(profile: dict) -> str:
    mount_path = (profile.get("mountPath") or "/").strip()
    if not mount_path or mount_path == "/":
        return "/"
    mount_path = mount_path if mount_path.startswith("/") else "/" + mount_path
    return mount_path[:-1] if mount_path.endswith("/") else mount_path

def endpoint_path(profile: dict) -> str:
    args = [str(value) for value in profile.get("arguments", [])]
    for index, argument in enumerate(args):
        if argument == "--streamableHttpPath" and index + 1 < len(args):
            return normalized_mount_path({"mountPath": args[index + 1]})
        if argument.startswith("--streamableHttpPath="):
            return normalized_mount_path({"mountPath": argument.split("=", 1)[1]})
        if argument in ("--path", "--mcp-path") and index + 1 < len(args):
            return normalized_mount_path({"mountPath": args[index + 1]})
    for index, argument in enumerate(args):
        if argument == "--transport" and index + 1 < len(args):
            if args[index + 1].lower() in ("streamable-http", "streamablehttp"):
                return "/mcp"
        if argument.lower() in ("--transport=streamable-http", "--transport=streamablehttp"):
            return "/mcp"
    return "/mcp"

def public_url(dns: str, profile: dict) -> str:
    mount_path = normalized_mount_path(profile)
    public_port = int(profile.get("publicPort", 443) or 443)
    port_suffix = "" if public_port == 443 else f":{public_port}"
    return "https://" + dns + port_suffix + mount_path

def public_surface_enabled(profile: dict) -> bool:
    return bool(profile.get("tailscaleRouteEnabled")) and profile.get("exposureMode") != "disabled"

def gateway_surface_enabled(profile: dict) -> bool:
    return bool(profile.get("exclusiveGatewayEnabled"))

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=str(pathlib.Path.home()/"Library/Application Support/MCP Controller/servers.json"))
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--catalog-only", action="store_true")
    parser.add_argument("--skip", action="append", default=[], help="Profile name to skip (repeatable)")
    parser.add_argument("--credential", help="Credential name to use when a profile has multiple access keys")
    args = parser.parse_args()
    profiles = json.loads(pathlib.Path(args.config).read_text())
    servers = server_profiles(profiles)
    dns = dns_name(servers)
    report, failures = [], []
    for profile in servers:
        if profile["name"] in args.skip:
            print(json.dumps({"name": profile["name"], "status": "skipped"}), flush=True)
            continue
        row = {"name": profile["name"], "surfaces": {}}
        safe = [] if args.catalog_only else SAFE_CALLS.get(profile["name"], [])
        local_url = f"http://127.0.0.1:{profile['localPort']}{endpoint_path(profile)}"
        surfaces: dict[str, tuple[str, str | None]] = {"local": (local_url, None)}
        if gateway_surface_enabled(profile):
            surfaces["gateway"] = (f"http://127.0.0.1:{profile['gatewayPort']}/", token_for(profile, args.credential))
        if public_surface_enabled(profile):
            surfaces["public"] = (public_url(dns, profile), token_for(profile, args.credential))
        for surface, (url, token) in surfaces.items():
            started = time.monotonic()
            try:
                count, called = MCPClient(url, token, args.timeout).validate(safe)
                row["surfaces"][surface] = {"status": "passed", "toolCount": count, "safeTool": called, "seconds": round(time.monotonic()-started, 3)}
            except Exception as error:
                detail = f"{type(error).__name__}: {error}"
                row["surfaces"][surface] = {"status": "failed", "error": detail, "seconds": round(time.monotonic()-started, 3)}
                failures.append({"profile": profile["name"], "surface": surface, "error": detail})
        report.append(row)
        print(json.dumps(row, sort_keys=True), flush=True)
    tested_surfaces = sum(len(row["surfaces"]) for row in report)
    summary = {"passedSurfaces": tested_surfaces-len(failures), "failedSurfaces": len(failures), "skippedProfiles": args.skip, "profiles": report, "failures": failures}
    print(json.dumps(summary, indent=2))
    return 1 if failures else 0

if __name__ == "__main__": raise SystemExit(main())

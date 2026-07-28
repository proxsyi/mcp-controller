#!/bin/bash
set -uo pipefail

REPO_DIR="${HOME}/Projects/Clients/Versyi/MCP-Controller"
CONFIG_PATH="${HOME}/Library/Application Support/MCP Controller/servers.json"
APP_PATH="/Applications/MCP Controller.app"
OUT_PATH="${1:-${HOME}/Desktop/mcp-controller-diagnostics.txt}"

mkdir -p "$(dirname "${OUT_PATH}")"

python3 - "${REPO_DIR}" "${CONFIG_PATH}" "${APP_PATH}" <<'PY' | tee "${OUT_PATH}"
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
config_path = Path(sys.argv[2])
app_path = Path(sys.argv[3])

PAYLOAD = json.dumps({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "mcp-controller-diagnostics", "version": "1.0"},
    },
}, separators=(",", ":"))

results = []

def section(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def run(cmd, timeout=20):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        return subprocess.CompletedProcess(cmd, 124, exc.stdout or "", exc.stderr or "timed out")
    except Exception as exc:
        return subprocess.CompletedProcess(cmd, 125, "", repr(exc))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def normalized_path(value):
    value = (value or "/").strip()
    if not value or value == "/":
        return "/"
    value = value if value.startswith("/") else "/" + value
    return value[:-1] if value.endswith("/") else value


def configured_endpoint(profile):
    args = [str(x) for x in profile.get("arguments", [])]
    for i, arg in enumerate(args):
        if arg == "--streamableHttpPath" and i + 1 < len(args):
            return normalized_path(args[i + 1]), "--streamableHttpPath"
        if arg.startswith("--streamableHttpPath="):
            return normalized_path(arg.split("=", 1)[1]), "--streamableHttpPath="
        if arg in ("--path", "--mcp-path") and i + 1 < len(args):
            return normalized_path(args[i + 1]), arg
    for i, arg in enumerate(args):
        if arg == "--transport" and i + 1 < len(args) and args[i + 1].lower() in ("streamable-http", "streamablehttp"):
            return "/mcp", "streamable-http default"
        if arg.lower() in ("--transport=streamable-http", "--transport=streamablehttp"):
            return "/mcp", "streamable-http default"
    return "/mcp", "diagnostic fallback"


def join_path(base, suffix):
    if suffix == "/":
        return base
    return base.rstrip("/") + suffix


def parse_http(raw):
    status = None
    statuses = re.findall(r"(?m)^HTTP/\S+\s+(\d{3})", raw)
    if statuses:
        status = int(statuses[-1])
    content_type = None
    matches = re.findall(r"(?mi)^content-type:\s*([^\r\n]+)", raw)
    if matches:
        content_type = matches[-1].strip()
    session = bool(re.search(r"(?mi)^mcp-session-id:\s*\S+", raw))
    initialized = '"result"' in raw and ('"serverInfo"' in raw or '"protocolVersion"' in raw)
    auth_error = status in (401, 403)
    return status, content_type, session, initialized, auth_error


def probe(label, url, token, method="POST", timeout=10):
    cmd = [
        "curl", "-sS", "-i", "--no-buffer", "--max-time", str(timeout),
        "-H", "Accept: application/json, text/event-stream",
    ]
    if token:
        cmd += ["-H", "Authorization: Bearer " + token]
    if method == "POST":
        cmd += ["-H", "Content-Type: application/json", "-d", PAYLOAD]
    else:
        cmd += ["-X", method]
    cmd.append(url)
    completed = run(cmd, timeout=timeout + 3)
    raw = completed.stdout or ""
    status, content_type, session, initialized, auth_error = parse_http(raw)

    if status == 200 and initialized:
        verdict = "PASS"
    elif method == "GET" and status == 200 and content_type and "text/event-stream" in content_type:
        verdict = "PASS"
    elif status in (401, 403):
        verdict = "FAIL-AUTH"
    elif status == 404:
        verdict = "FAIL-PATH"
    elif status == 502:
        verdict = "FAIL-UPSTREAM"
    elif status == 200:
        verdict = "WARN-NO-INITIALIZE"
    elif status is None:
        verdict = "FAIL-NO-HTTP"
    else:
        verdict = "FAIL-HTTP"

    results.append((verdict, label, url, status, completed.returncode))
    print(f"[{verdict}] {label}")
    print(f"  URL: {url}")
    print(f"  HTTP: {status} | curl exit: {completed.returncode} | type: {content_type} | session: {session} | initialize: {initialized}")
    if completed.stderr:
        print("  curl:", completed.stderr.strip().replace("\n", " | ")[:400])
    safe = raw.replace(token, "<redacted>") if token else raw
    interesting = []
    for line in safe.splitlines():
        low = line.lower()
        if line.startswith("HTTP/") or low.startswith(("content-type:", "mcp-session-id:", "server:", "event:", "data:")) or line in ("Not Found", "Bad Gateway"):
            interesting.append(line[:700])
    for line in interesting[:12]:
        print("   ", line)


section("MCP CONTROLLER DIAGNOSTICS")
print("Generated:", datetime.datetime.now().astimezone().isoformat())
print("Host:", run(["scutil", "--get", "ComputerName"]).stdout.strip() or "unknown")
print("macOS:", run(["sw_vers", "-productVersion"]).stdout.strip() or "unknown")

section("REPOSITORY AND INSTALLED APP")
if repo.exists():
    print("Repository:", repo)
    print("Branch:", run(["git", "-C", str(repo), "branch", "--show-current"]).stdout.strip())
    print("HEAD:", run(["git", "-C", str(repo), "rev-parse", "HEAD"]).stdout.strip())
    print("Origin main:", run(["git", "-C", str(repo), "rev-parse", "origin/main"]).stdout.strip())
    status = run(["git", "-C", str(repo), "status", "--short"]).stdout.strip()
    print("Working tree:", status or "clean")
else:
    print("[FAIL] Repository missing:", repo)

installed_binary = app_path / "Contents/MacOS/MCPController"
built_binary = repo / "dist/MCP Controller.app/Contents/MacOS/MCPController"
if app_path.exists():
    info_path = app_path / "Contents/Info.plist"
    try:
        with open(info_path, "rb") as f:
            info = plistlib.load(f)
        print("Installed app version:", info.get("CFBundleShortVersionString"), "build", info.get("CFBundleVersion"))
        print("Bundle ID:", info.get("CFBundleIdentifier"))
    except Exception as exc:
        print("[WARN] Could not read installed Info.plist:", exc)
if installed_binary.exists():
    print("Installed binary SHA-256:", sha256(installed_binary))
if built_binary.exists():
    print("Built binary SHA-256:    ", sha256(built_binary))
    print("Binary match:", "PASS" if installed_binary.exists() and sha256(installed_binary) == sha256(built_binary) else "FAIL")

codesign = run(["codesign", "-dv", "--verbose=4", str(app_path)])
print("Code signature:", (codesign.stderr or codesign.stdout).strip()[:1200] or "unavailable")

section("PROCESS AND PORT STATE")
print(run(["pgrep", "-fl", "MCPController|supergateway|macos-mcp|mcp_remote_macos_use|mcp-applescript|automation"]).stdout.strip() or "No matching processes")

if not config_path.exists():
    print("[FATAL] Missing config:", config_path)
    sys.exit(2)
with open(config_path) as f:
    profiles = json.load(f)

for profile in profiles:
    name = profile.get("name", "Unnamed")
    local_port = int(profile.get("localPort", 0))
    gateway_port = int(profile.get("gatewayPort", 0))
    print(f"\n{name}:")
    for kind, port in (("upstream", local_port), ("gateway", gateway_port)):
        listening = run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN"]).stdout.strip()
        print(f"  {kind} {port}:", "PASS" if listening else "FAIL")
        if listening:
            print("   ", listening.splitlines()[-1])

section("TAILSCALE STATE")
tailscale = next((p.get("tailscalePath") for p in profiles if p.get("tailscalePath") and os.path.exists(p.get("tailscalePath"))), None)
if not tailscale:
    tailscale = shutil.which("tailscale")

dns_name = ""
if tailscale:
    status = run([tailscale, "status", "--json"])
    print("tailscale status exit:", status.returncode)
    if status.returncode == 0:
        try:
            obj = json.loads(status.stdout)
            dns_name = ((obj.get("Self") or {}).get("DNSName") or "").rstrip(".")
            print("DNS name:", dns_name or "missing")
            print("Backend state:", obj.get("BackendState", "unknown"))
        except Exception as exc:
            print("[WARN] Could not parse Tailscale status:", exc)
    else:
        print(status.stderr.strip())
    funnel = run([tailscale, "funnel", "status", "--json"])
    print("funnel status exit:", funnel.returncode)
    print((funnel.stdout or funnel.stderr).strip()[:5000])
else:
    print("[FAIL] Tailscale CLI not found")

section("BEST-EFFORT PRIVACY CHECKS")
access = run(["swift", "-e", "import ApplicationServices; print(AXIsProcessTrusted())"], timeout=30)
print("Current diagnostic process Accessibility trust:", access.stdout.strip() or access.stderr.strip())
screen = run(["swift", "-e", "import CoreGraphics; print(CGPreflightScreenCaptureAccess())"], timeout=30)
print("Current diagnostic process Screen Recording trust:", screen.stdout.strip() or screen.stderr.strip())
print("Note: macOS TCC approval is identity-specific; these checks cannot silently grant app permissions.")

section("PROFILE CONFIGURATION")
for profile in profiles:
    endpoint, endpoint_source = configured_endpoint(profile)
    mount = normalized_path(profile.get("mountPath"))
    creds = profile.get("clientCredentials") or []
    print(f"\n{profile.get('name')}:")
    print("  autoStart:", profile.get("autoStart"))
    print("  localPort:", profile.get("localPort"))
    print("  exclusiveGatewayEnabled:", profile.get("exclusiveGatewayEnabled"))
    print("  gatewayPort:", profile.get("gatewayPort"))
    print("  remoteClientCompatibilityEnabled:", profile.get("remoteClientCompatibilityEnabled"))
    print("  tailscaleRouteEnabled:", profile.get("tailscaleRouteEnabled"))
    print("  exposureMode:", profile.get("exposureMode"))
    print("  publicPort:", profile.get("publicPort"))
    print("  mountPath:", mount)
    print("  upstream MCP path:", endpoint, f"({endpoint_source})")
    print("  credential count:", len(creds), "names:", [c.get("name") for c in creds])
    errors = []
    if profile.get("exclusiveGatewayEnabled") and not creds:
        errors.append("exclusive gateway has no credentials")
    if profile.get("tailscaleRouteEnabled") and profile.get("exposureMode") == "disabled":
        errors.append("route enabled but exposure disabled")
    if profile.get("gatewayPort") == profile.get("localPort"):
        errors.append("gateway and upstream use same port")
    print("  static checks:", "PASS" if not errors else "FAIL: " + "; ".join(errors))

section("END-TO-END MCP INITIALIZE PROBES")
for profile in profiles:
    name = profile.get("name", "Unnamed")
    local_port = int(profile.get("localPort", 0))
    gateway_port = int(profile.get("gatewayPort", 0))
    endpoint, endpoint_source = configured_endpoint(profile)
    mount = normalized_path(profile.get("mountPath"))
    token = ((profile.get("clientCredentials") or [{}])[0].get("token") or "")
    public_port = int(profile.get("publicPort", 443))
    port_suffix = "" if public_port == 443 else f":{public_port}"

    print(f"\n--- {name} ---")
    probe("direct upstream endpoint", f"http://127.0.0.1:{local_port}{endpoint}", "")

    if profile.get("exclusiveGatewayEnabled"):
        probe("gateway root (simulates stripped Funnel mount)", f"http://127.0.0.1:{gateway_port}/", token)
        probe("gateway endpoint path", f"http://127.0.0.1:{gateway_port}{endpoint}", token)
        if mount != "/":
            probe("gateway mounted base", f"http://127.0.0.1:{gateway_port}{mount}", token)
            probe("gateway mounted endpoint", f"http://127.0.0.1:{gateway_port}{join_path(mount, endpoint)}", token)
        if profile.get("remoteClientCompatibilityEnabled"):
            probe("gateway compatibility GET", f"http://127.0.0.1:{gateway_port}/", token, method="GET", timeout=5)

    if dns_name and profile.get("tailscaleRouteEnabled") and profile.get("exposureMode") != "disabled":
        base = f"https://{dns_name}{port_suffix}{mount if mount != '/' else ''}"
        probe("public displayed/base URL", base or f"https://{dns_name}{port_suffix}/", token, timeout=15)
        probe("public URL plus upstream endpoint", join_path(base, endpoint), token, timeout=15)

section("SUMMARY")
counts = {}
for verdict, *_ in results:
    counts[verdict] = counts.get(verdict, 0) + 1
for key in sorted(counts):
    print(f"{key}: {counts[key]}")
print("\nInterpretation:")
print("- direct PASS + gateway FAIL means MCP Controller gateway routing/proxying is broken.")
print("- gateway PASS + public FAIL means Tailscale Serve/Funnel routing is broken or stale.")
print("- direct FAIL means the managed MCP process/path itself is broken.")
print("- 404 at gateway root usually means the route was mapped to '/' instead of the server's MCP path.")
print("- 502 at public URL usually means Funnel reached no healthy gateway/upstream response.")
print("- curl exit 28 can be normal for an open SSE stream only when HTTP 200 and initialize data arrived first.")
PY

printf '\nSaved diagnostics to: %s\n' "${OUT_PATH}"

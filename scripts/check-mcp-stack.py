#!/usr/bin/env python3
"""End-to-end diagnostics for every MCP Controller profile. Never prints access tokens."""
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

HOME = Path.home()
REPO = HOME / "Projects/Clients/Versyi/MCP-Controller"
CONFIG = HOME / "Library/Application Support/MCP Controller/servers.json"
APP = Path("/Applications/MCP Controller.app")
OUTPUT = HOME / "Desktop/mcp-controller-diagnostics.txt"
RESULTS = []
PAYLOAD = json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-11-25", "capabilities": {},
               "clientInfo": {"name": "mcp-stack-check", "version": "1.0"}},
}, separators=(",", ":"))


def run(command, timeout=20):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        return subprocess.CompletedProcess(command, 124, error.stdout or "", error.stderr or "timeout")
    except Exception as error:
        return subprocess.CompletedProcess(command, 125, "", repr(error))


def heading(title):
    print("\n" + "=" * 76)
    print(title)
    print("=" * 76)


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize_path(path):
    path = (path or "/").strip()
    if not path or path == "/":
        return "/"
    path = path if path.startswith("/") else "/" + path
    return path[:-1] if path.endswith("/") else path


def join_path(base, suffix):
    return base if suffix == "/" else base.rstrip("/") + suffix


def expected_endpoint(profile):
    args = [str(value) for value in profile.get("arguments", [])]
    for index, argument in enumerate(args):
        if argument == "--streamableHttpPath" and index + 1 < len(args):
            return normalize_path(args[index + 1]), "explicit --streamableHttpPath"
        if argument.startswith("--streamableHttpPath="):
            return normalize_path(argument.split("=", 1)[1]), "explicit --streamableHttpPath="
        if argument in ("--path", "--mcp-path") and index + 1 < len(args):
            return normalize_path(args[index + 1]), "explicit path argument"
    for index, argument in enumerate(args):
        if argument == "--transport" and index + 1 < len(args):
            if args[index + 1].lower() in ("streamable-http", "streamablehttp"):
                return "/mcp", "streamable-http default"
        if argument.lower() in ("--transport=streamable-http", "--transport=streamablehttp"):
            return "/mcp", "streamable-http default"
    return "/mcp", "diagnostic fallback"


def listener(port):
    return run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN"]).stdout.strip()


def probe(label, url, token="", method="POST", timeout=10):
    command = ["curl", "-sS", "-i", "--no-buffer", "--max-time", str(timeout),
               "-H", "Accept: application/json, text/event-stream"]
    if token:
        command += ["-H", "Authorization: Bearer " + token]
    if method == "POST":
        command += ["-H", "Content-Type: application/json", "-d", PAYLOAD]
    else:
        command += ["-X", method]
    command.append(url)
    response = run(command, timeout + 3)
    raw = response.stdout or ""
    statuses = re.findall(r"(?m)^HTTP/\S+\s+(\d{3})", raw)
    status = int(statuses[-1]) if statuses else None
    types = re.findall(r"(?mi)^content-type:\s*([^\r\n]+)", raw)
    content_type = types[-1].strip() if types else None
    initialized = '"result"' in raw and ('"serverInfo"' in raw or '"protocolVersion"' in raw)
    session = bool(re.search(r"(?mi)^mcp-session-id:\s*\S+", raw))

    if status == 200 and (initialized or (method == "GET" and content_type and "text/event-stream" in content_type)):
        verdict = "PASS"
    elif status == 404:
        verdict = "FAIL-PATH"
    elif status == 502:
        verdict = "FAIL-UPSTREAM"
    elif status in (401, 403):
        verdict = "FAIL-AUTH"
    elif status == 200:
        verdict = "WARN-200-NO-INITIALIZE"
    elif status is None:
        verdict = "FAIL-NO-HTTP"
    else:
        verdict = "FAIL-HTTP"

    RESULTS.append((verdict, label, url, status, response.returncode))
    print(f"[{verdict}] {label}")
    print(f"  URL: {url}")
    print(f"  HTTP={status} curl={response.returncode} type={content_type} session={session} initialize={initialized}")
    if response.stderr:
        print("  curl:", response.stderr.strip().replace("\n", " | ")[:300])
    safe = raw.replace(token, "<redacted>") if token else raw
    for line in safe.splitlines():
        lower = line.lower()
        if (line.startswith("HTTP/") or lower.startswith(("server:", "content-type:", "mcp-session-id:", "event:", "data:"))
                or line in ("Not Found", "Bad Gateway")):
            print("   ", line[:600])


def server_profiles(profiles):
    return [profile for profile in profiles if profile.get("kind", "server") == "server"]


def main():
    heading("SYSTEM, SOURCE, AND INSTALLED BUILD")
    print("Generated:", datetime.datetime.now().astimezone().isoformat())
    print("macOS:", run(["sw_vers", "-productVersion"]).stdout.strip())
    print("Repo HEAD:", run(["git", "-C", str(REPO), "rev-parse", "HEAD"]).stdout.strip())
    print("Origin main:", run(["git", "-C", str(REPO), "rev-parse", "origin/main"]).stdout.strip())
    print("Working tree:", run(["git", "-C", str(REPO), "status", "--short"]).stdout.strip() or "clean")

    installed = APP / "Contents/MacOS/MCPController"
    built = REPO / "dist/MCP Controller.app/Contents/MacOS/MCPController"
    if APP.exists():
        with open(APP / "Contents/Info.plist", "rb") as source:
            info = plistlib.load(source)
        print("Installed:", info.get("CFBundleShortVersionString"), "build", info.get("CFBundleVersion"), info.get("CFBundleIdentifier"))
    if installed.exists():
        print("Installed SHA:", sha256(installed))
    if built.exists():
        print("Built SHA:    ", sha256(built))
    if installed.exists() and built.exists():
        print("Binary match:", "PASS" if sha256(installed) == sha256(built) else "FAIL")
    print("Processes:\n" + (run(["pgrep", "-fl", "MCPController|supergateway|macos-mcp|mcp_remote_macos_use|mcp-applescript"]).stdout.strip() or "none"))

    if not CONFIG.exists():
        raise SystemExit(f"Missing config: {CONFIG}")
    with open(CONFIG) as source:
        profiles = server_profiles(json.load(source))

    heading("PROFILE CONFIGURATION AND LISTENERS")
    for profile in profiles:
        endpoint, source = expected_endpoint(profile)
        local_port = int(profile.get("localPort", 0))
        gateway_port = int(profile.get("gatewayPort", 0))
        credentials = profile.get("clientCredentials") or []
        print(f"\n{profile.get('name', 'Unnamed')}")
        print("  upstream", local_port, "LISTEN" if listener(local_port) else "CLOSED")
        print("  gateway ", gateway_port, "LISTEN" if listener(gateway_port) else "CLOSED")
        print("  endpoint", endpoint, f"({source})")
        print("  mount", normalize_path(profile.get("mountPath")), "mode", profile.get("exposureMode"), "route", profile.get("tailscaleRouteEnabled"))
        print("  autoStart", profile.get("autoStart"), "exclusive", profile.get("exclusiveGatewayEnabled"), "compatibility", profile.get("remoteClientCompatibilityEnabled"))
        print("  credentials", len(credentials), [credential.get("name") for credential in credentials])

    heading("TAILSCALE SERVE / FUNNEL")
    tailscale = next((profile.get("tailscalePath") for profile in profiles
                      if profile.get("tailscalePath") and os.path.exists(profile.get("tailscalePath"))), None)
    tailscale = tailscale or shutil.which("tailscale")
    dns_name = ""
    if tailscale:
        status = run([tailscale, "status", "--json"])
        print("tailscale status exit:", status.returncode)
        if status.returncode == 0:
            state = json.loads(status.stdout)
            dns_name = ((state.get("Self") or {}).get("DNSName") or "").rstrip(".")
            print("DNS:", dns_name, "backend:", state.get("BackendState"))
        else:
            print(status.stderr.strip())
        funnel = run([tailscale, "funnel", "status", "--json"])
        print("funnel status exit:", funnel.returncode)
        print((funnel.stdout or funnel.stderr).strip()[:6000])
    else:
        print("FAIL: Tailscale CLI not found")

    heading("BEST-EFFORT MACOS PRIVACY CHECKS")
    accessibility = run(["swift", "-e", "import ApplicationServices; print(AXIsProcessTrusted())"], 30)
    screen = run(["swift", "-e", "import CoreGraphics; print(CGPreflightScreenCaptureAccess())"], 30)
    print("Diagnostic process Accessibility:", accessibility.stdout.strip() or accessibility.stderr.strip())
    print("Diagnostic process Screen Recording:", screen.stdout.strip() or screen.stderr.strip())
    print("These checks are identity-specific; macOS does not permit scripts to silently grant TCC access.")

    heading("END-TO-END MCP INITIALIZE PROBES")
    for profile in profiles:
        name = profile.get("name", "Unnamed")
        local_port = int(profile.get("localPort", 0))
        gateway_port = int(profile.get("gatewayPort", 0))
        endpoint, _ = expected_endpoint(profile)
        mount = normalize_path(profile.get("mountPath"))
        token = ((profile.get("clientCredentials") or [{}])[0].get("token") or "")
        print(f"\n--- {name} ---")
        if not listener(local_port):
            print("[SKIP] Upstream is not running")
            continue
        probe("direct upstream endpoint", f"http://127.0.0.1:{local_port}{endpoint}")
        if profile.get("exclusiveGatewayEnabled") and listener(gateway_port):
            probe("gateway root (Funnel-stripped request)", f"http://127.0.0.1:{gateway_port}/", token)
            probe("gateway endpoint", f"http://127.0.0.1:{gateway_port}{endpoint}", token)
            if mount != "/":
                probe("gateway mounted base", f"http://127.0.0.1:{gateway_port}{mount}", token)
                probe("gateway mounted endpoint", f"http://127.0.0.1:{gateway_port}{join_path(mount, endpoint)}", token)
            if profile.get("remoteClientCompatibilityEnabled"):
                probe("gateway compatibility GET", f"http://127.0.0.1:{gateway_port}/", token, "GET", 5)
        if dns_name and profile.get("tailscaleRouteEnabled") and profile.get("exposureMode") != "disabled":
            port = int(profile.get("publicPort", 443))
            port_suffix = "" if port == 443 else f":{port}"
            public_base = "https://" + dns_name + port_suffix + (mount if mount != "/" else "")
            probe("public displayed/base URL", public_base, token, timeout=15)
            probe("public URL plus endpoint", join_path(public_base, endpoint), token, timeout=15)

    heading("SUMMARY")
    counts = {}
    for verdict, *_ in RESULTS:
        counts[verdict] = counts.get(verdict, 0) + 1
    for verdict in sorted(counts):
        print(verdict + ":", counts[verdict])
    print("\nInterpretation:")
    print("- Direct PASS + gateway FAIL: MCP Controller path mapping or proxy failure.")
    print("- Gateway PASS + public FAIL: stale or broken Tailscale Serve/Funnel route.")
    print("- Direct FAIL: managed MCP process or endpoint failure.")
    print("- Gateway root 404: route root was sent to upstream '/' instead of its MCP path.")
    print("- Public 502: Funnel could not obtain a healthy gateway/upstream response.")
    print("- curl 28 is acceptable only if HTTP 200 and initialize data arrived before the SSE stream remained open.")


if __name__ == "__main__":
    import contextlib
    with open(OUTPUT, "w") as report:
        with contextlib.redirect_stdout(report):
            main()
    print(OUTPUT.read_text())
    print("Saved diagnostics to:", OUTPUT)

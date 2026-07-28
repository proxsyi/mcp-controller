#!/bin/bash
set -uo pipefail

REPO="${HOME}/Projects/Clients/Versyi/MCP-Controller"
CONFIG="${HOME}/Library/Application Support/MCP Controller/servers.json"
APP="/Applications/MCP Controller.app"
OUTPUT="${1:-${HOME}/Desktop/mcp-controller-diagnostics.txt}"
mkdir -p "$(dirname "${OUTPUT}")"

python3 - "${REPO}" "${CONFIG}" "${APP}" <<'PY' | tee "${OUTPUT}"
import datetime, hashlib, json, os, plistlib, re, shutil, subprocess, sys
from pathlib import Path

repo, config_path, app = map(Path, sys.argv[1:4])
checks = []

payload = json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-06-18", "capabilities": {},
               "clientInfo": {"name": "controller-diagnostics", "version": "1.0"}}
}, separators=(",", ":"))

def heading(text):
    print("\n" + "=" * 72 + "\n" + text + "\n" + "=" * 72)

def run(cmd, timeout=20):
    try:
        return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        return subprocess.CompletedProcess(cmd, 124, e.stdout or "", e.stderr or "timeout")
    except Exception as e:
        return subprocess.CompletedProcess(cmd, 125, "", repr(e))

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1048576), b""):
            h.update(block)
    return h.hexdigest()

def norm(path):
    path = (path or "/").strip()
    if not path or path == "/": return "/"
    path = path if path.startswith("/") else "/" + path
    return path[:-1] if path.endswith("/") else path

def endpoint(profile):
    args = [str(a) for a in profile.get("arguments", [])]
    for i, arg in enumerate(args):
        if arg == "--streamableHttpPath" and i + 1 < len(args): return norm(args[i + 1]), "configured"
        if arg.startswith("--streamableHttpPath="): return norm(arg.split("=", 1)[1]), "configured"
        if arg in ("--path", "--mcp-path") and i + 1 < len(args): return norm(args[i + 1]), "configured"
    for i, arg in enumerate(args):
        if arg == "--transport" and i + 1 < len(args) and args[i + 1].lower() in ("streamable-http", "streamablehttp"):
            return "/mcp", "streamable-http default"
        if arg.lower() in ("--transport=streamable-http", "--transport=streamablehttp"):
            return "/mcp", "streamable-http default"
    return "/mcp", "fallback"

def join(base, suffix):
    return base if suffix == "/" else base.rstrip("/") + suffix

def probe(name, url, token="", method="POST", timeout=10):
    cmd = ["curl", "-sS", "-i", "--no-buffer", "--max-time", str(timeout),
           "-H", "Accept: application/json, text/event-stream"]
    if token: cmd += ["-H", "Authorization: Bearer " + token]
    if method == "POST": cmd += ["-H", "Content-Type: application/json", "-d", payload]
    else: cmd += ["-X", method]
    cmd.append(url)
    r = run(cmd, timeout + 3)
    raw = r.stdout or ""
    statuses = re.findall(r"(?m)^HTTP/\S+\s+(\d{3})", raw)
    status = int(statuses[-1]) if statuses else None
    initialized = '"result"' in raw and ('"serverInfo"' in raw or '"protocolVersion"' in raw)
    content_types = re.findall(r"(?mi)^content-type:\s*([^\r\n]+)", raw)
    content_type = content_types[-1].strip() if content_types else None
    if status == 200 and (initialized or (method == "GET" and content_type and "text/event-stream" in content_type)):
        verdict = "PASS"
    elif status == 404: verdict = "FAIL-PATH"
    elif status == 502: verdict = "FAIL-UPSTREAM"
    elif status in (401, 403): verdict = "FAIL-AUTH"
    elif status == 200: verdict = "WARN-200-NO-INITIALIZE"
    elif status is None: verdict = "FAIL-NO-HTTP"
    else: verdict = "FAIL-HTTP"
    checks.append((verdict, name, url, status, r.returncode))
    print(f"[{verdict}] {name}\n  {url}\n  HTTP={status} curl={r.returncode} type={content_type} initialize={initialized}")
    if r.stderr: print("  curl:", r.stderr.strip().replace("\n", " | ")[:300])
    safe = raw.replace(token, "<redacted>") if token else raw
    for line in safe.splitlines():
        low = line.lower()
        if line.startswith("HTTP/") or low.startswith(("server:", "content-type:", "mcp-session-id:", "event:", "data:")) or line in ("Not Found", "Bad Gateway"):
            print("   ", line[:600])

heading("SYSTEM / BUILD")
print("Generated:", datetime.datetime.now().astimezone().isoformat())
print("macOS:", run(["sw_vers", "-productVersion"]).stdout.strip())
print("Repo HEAD:", run(["git", "-C", str(repo), "rev-parse", "HEAD"]).stdout.strip())
print("Origin main:", run(["git", "-C", str(repo), "rev-parse", "origin/main"]).stdout.strip())
print("Git status:\n", run(["git", "-C", str(repo), "status", "--short"]).stdout.strip() or "clean")
installed = app / "Contents/MacOS/MCPController"
built = repo / "dist/MCP Controller.app/Contents/MacOS/MCPController"
if app.exists():
    with open(app / "Contents/Info.plist", "rb") as f: info = plistlib.load(f)
    print("Installed version:", info.get("CFBundleShortVersionString"), "build", info.get("CFBundleVersion"))
    print("Bundle ID:", info.get("CFBundleIdentifier"))
if installed.exists(): print("Installed SHA:", sha(installed))
if built.exists(): print("Built SHA:    ", sha(built))
if installed.exists() and built.exists(): print("Binary match:", "PASS" if sha(installed) == sha(built) else "FAIL")
print("Processes:\n", run(["pgrep", "-fl", "MCPController|supergateway|macos-mcp|mcp_remote_macos_use|mcp-applescript|automation"]).stdout.strip() or "none")

if not config_path.exists():
    print("FATAL: config missing:", config_path)
    sys.exit(2)
with open(config_path) as f: profiles = json.load(f)

heading("PORTS / PROFILE CONFIG")
for p in profiles:
    ep, source = endpoint(p)
    creds = p.get("clientCredentials") or []
    print(f"\n{p.get('name')}")
    print("  upstream:", p.get("localPort"), "LISTEN" if run(["lsof", "-nP", f"-iTCP:{p.get('localPort')}", "-sTCP:LISTEN"]).stdout else "CLOSED")
    print("  gateway: ", p.get("gatewayPort"), "LISTEN" if run(["lsof", "-nP", f"-iTCP:{p.get('gatewayPort')}", "-sTCP:LISTEN"]).stdout else "CLOSED")
    print("  autoStart:", p.get("autoStart"), "exclusive:", p.get("exclusiveGatewayEnabled"), "compat:", p.get("remoteClientCompatibilityEnabled"))
    print("  route:", p.get("tailscaleRouteEnabled"), p.get("exposureMode"), "port", p.get("publicPort"), "mount", norm(p.get("mountPath")))
    print("  expected upstream endpoint:", ep, f"({source})")
    print("  credentials:", len(creds), [c.get("name") for c in creds])

heading("TAILSCALE")
tailscale = next((p.get("tailscalePath") for p in profiles if p.get("tailscalePath") and os.path.exists(p.get("tailscalePath"))), None) or shutil.which("tailscale")
dns = ""
if tailscale:
    ts = run([tailscale, "status", "--json"])
    print("status exit:", ts.returncode)
    if ts.returncode == 0:
        obj = json.loads(ts.stdout)
        dns = ((obj.get("Self") or {}).get("DNSName") or "").rstrip(".")
        print("DNS:", dns, "backend:", obj.get("BackendState"))
    else: print(ts.stderr.strip())
    fs = run([tailscale, "funnel", "status", "--json"])
    print("funnel exit:", fs.returncode)
    print((fs.stdout or fs.stderr).strip()[:6000])
else: print("FAIL: tailscale CLI missing")

heading("BEST-EFFORT PRIVACY")
ax = run(["swift", "-e", "import ApplicationServices; print(AXIsProcessTrusted())"], 30)
sc = run(["swift", "-e", "import CoreGraphics; print(CGPreflightScreenCaptureAccess())"], 30)
print("Diagnostic process Accessibility:", ax.stdout.strip() or ax.stderr.strip())
print("Diagnostic process Screen Recording:", sc.stdout.strip() or sc.stderr.strip())
print("Note: macOS privacy approval is identity-specific and cannot be silently granted.")

heading("END-TO-END INITIALIZE TESTS")
for p in profiles:
    name = p.get("name", "Unnamed")
    local = int(p.get("localPort", 0)); gateway = int(p.get("gatewayPort", 0))
    ep, _ = endpoint(p); mount = norm(p.get("mountPath"))
    token = ((p.get("clientCredentials") or [{}])[0].get("token") or "")
    print(f"\n--- {name} ---")
    probe("direct upstream", f"http://127.0.0.1:{local}{ep}")
    if p.get("exclusiveGatewayEnabled"):
        probe("gateway root (Funnel-stripped request)", f"http://127.0.0.1:{gateway}/", token)
        probe("gateway endpoint", f"http://127.0.0.1:{gateway}{ep}", token)
        if mount != "/":
            probe("gateway mounted base", f"http://127.0.0.1:{gateway}{mount}", token)
            probe("gateway mounted endpoint", f"http://127.0.0.1:{gateway}{join(mount, ep)}", token)
        if p.get("remoteClientCompatibilityEnabled"):
            probe("gateway compatibility GET", f"http://127.0.0.1:{gateway}/", token, "GET", 5)
    if dns and p.get("tailscaleRouteEnabled") and p.get("exposureMode") != "disabled":
        suffix = "" if int(p.get("publicPort", 443)) == 443 else ":" + str(p.get("publicPort"))
        base = f"https://{dns}{suffix}" + (mount if mount != "/" else "")
        probe("public displayed/base URL", base, token, timeout=15)
        probe("public URL plus endpoint", join(base, ep), token, timeout=15)

heading("SUMMARY")
counts = {}
for verdict, *_ in checks: counts[verdict] = counts.get(verdict, 0) + 1
for verdict in sorted(counts): print(verdict + ":", counts[verdict])
print("\nDiagnosis rules:")
print("- Direct PASS + gateway FAIL: controller path mapping or proxy bug.")
print("- Gateway PASS + public FAIL: stale/broken Tailscale Serve or Funnel route.")
print("- Direct FAIL: managed MCP process or its endpoint is broken.")
print("- 404 at gateway root: root was forwarded to upstream '/' instead of its MCP endpoint.")
print("- 502 publicly: Funnel could not obtain a healthy gateway/upstream response.")
print("- curl 28 is acceptable only if HTTP 200 and initialize data arrived before the SSE stream stayed open.")
PY

printf '\nSaved diagnostics to: %s\n' "${OUTPUT}"

#!/usr/bin/env python3
import contextlib, hashlib, json, os, plistlib, re, shutil, subprocess
from pathlib import Path

home = Path.home()
repo = home / "Projects/Clients/Versyi/MCP-Controller"
config = home / "Library/Application Support/MCP Controller/servers.json"
app = Path("/Applications/MCP Controller.app")
report_path = home / "Desktop/mcp-health-report.txt"
results = []
payload = json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"health-check","version":"1.0"}}}, separators=(",", ":"))

def run(cmd, timeout=20):
    try: return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e: return subprocess.CompletedProcess(cmd, 124, e.stdout or "", e.stderr or "timeout")
    except Exception as e: return subprocess.CompletedProcess(cmd, 125, "", repr(e))

def section(name): print("\n" + "="*70 + "\n" + name + "\n" + "="*70)

def listener(port): return bool(run(["lsof","-nP",f"-iTCP:{port}","-sTCP:LISTEN"]).stdout.strip())

def norm(value):
    value = (value or "/").strip()
    if not value or value == "/": return "/"
    value = value if value.startswith("/") else "/" + value
    return value[:-1] if value.endswith("/") else value

def endpoint(profile):
    args = [str(x) for x in profile.get("arguments", [])]
    for i, arg in enumerate(args):
        if arg == "--streamableHttpPath" and i+1 < len(args): return norm(args[i+1]), "explicit"
        if arg.startswith("--streamableHttpPath="): return norm(arg.split("=",1)[1]), "explicit"
        if arg in ("--path","--mcp-path") and i+1 < len(args): return norm(args[i+1]), "explicit"
    for i, arg in enumerate(args):
        if arg == "--transport" and i+1 < len(args) and args[i+1].lower() in ("streamable-http","streamablehttp"): return "/mcp", "streamable-http default"
        if arg.lower() in ("--transport=streamable-http","--transport=streamablehttp"): return "/mcp", "streamable-http default"
    return "/mcp", "fallback"

def join(base, suffix): return base if suffix == "/" else base.rstrip("/") + suffix

def probe(label, url, token="", timeout=10):
    cmd = ["curl","-sS","-i","--no-buffer","--max-time",str(timeout),"-H","Accept: application/json, text/event-stream","-H","Content-Type: application/json","-d",payload]
    if token: cmd += ["-H","Authorization: Bearer " + token]
    cmd.append(url)
    response = run(cmd, timeout+3)
    raw = response.stdout or ""
    statuses = re.findall(r"(?m)^HTTP/\S+\s+(\d{3})", raw)
    status = int(statuses[-1]) if statuses else None
    initialized = '"result"' in raw and ('"serverInfo"' in raw or '"protocolVersion"' in raw)
    if status == 200 and initialized: verdict = "PASS"
    elif status == 404: verdict = "FAIL-PATH"
    elif status == 502: verdict = "FAIL-UPSTREAM"
    elif status in (401,403): verdict = "FAIL-AUTH"
    elif status == 200: verdict = "WARN-200-NO-INITIALIZE"
    elif status is None: verdict = "FAIL-NO-HTTP"
    else: verdict = "FAIL-HTTP"
    results.append((verdict,label,url,status,response.returncode))
    print(f"[{verdict}] {label}\n  {url}\n  HTTP={status} curl={response.returncode} initialize={initialized}")
    if response.stderr: print("  curl:",response.stderr.strip().replace("\n"," | ")[:250])
    safe = raw.replace(token,"<redacted>") if token else raw
    for line in safe.splitlines():
        if line.startswith("HTTP/") or line.lower().startswith(("server:","content-type:","mcp-session-id:","event:","data:")) or line in ("Not Found","Bad Gateway"): print("   ",line[:500])

def sha(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        for block in iter(lambda:f.read(1048576),b""): h.update(block)
    return h.hexdigest()

def main():
    section("BUILD AND PROCESS STATE")
    print("Repo HEAD:",run(["git","-C",str(repo),"rev-parse","HEAD"]).stdout.strip())
    print("Origin main:",run(["git","-C",str(repo),"rev-parse","origin/main"]).stdout.strip())
    print("Git status:",run(["git","-C",str(repo),"status","--short"]).stdout.strip() or "clean")
    installed=app/"Contents/MacOS/MCPController"; built=repo/"dist/MCP Controller.app/Contents/MacOS/MCPController"
    if app.exists():
        with open(app/"Contents/Info.plist","rb") as f: info=plistlib.load(f)
        print("Installed version:",info.get("CFBundleShortVersionString"),"build",info.get("CFBundleVersion"),info.get("CFBundleIdentifier"))
    if installed.exists() and built.exists(): print("Installed/build binary match:","PASS" if sha(installed)==sha(built) else "FAIL")
    print(run(["pgrep","-fl","MCPController|supergateway|macos-mcp|mcp_remote_macos_use|mcp-applescript|automation"]).stdout.strip() or "No matching processes")

    with open(config) as f: profiles=json.load(f)
    section("CONFIGURATION AND PORTS")
    for p in profiles:
        ep,source=endpoint(p); local=int(p.get("localPort",0)); gateway=int(p.get("gatewayPort",0)); creds=p.get("clientCredentials") or []
        print("\n"+p.get("name","Unnamed"))
        print("  upstream",local,"LISTEN" if listener(local) else "CLOSED","gateway",gateway,"LISTEN" if listener(gateway) else "CLOSED")
        print("  endpoint",ep,"("+source+")","mount",norm(p.get("mountPath")))
        print("  autoStart",p.get("autoStart"),"exclusive",p.get("exclusiveGatewayEnabled"),"compatibility",p.get("remoteClientCompatibilityEnabled"))
        print("  route",p.get("tailscaleRouteEnabled"),p.get("exposureMode"),"public port",p.get("publicPort"),"credentials",len(creds))

    section("TAILSCALE")
    tailscale=next((p.get("tailscalePath") for p in profiles if p.get("tailscalePath") and os.path.exists(p.get("tailscalePath"))),None) or shutil.which("tailscale")
    dns=""
    if tailscale:
        state=run([tailscale,"status","--json"])
        print("status exit",state.returncode)
        if state.returncode==0:
            obj=json.loads(state.stdout); dns=((obj.get("Self") or {}).get("DNSName") or "").rstrip("."); print("DNS",dns,"backend",obj.get("BackendState"))
        else: print(state.stderr.strip())
        funnel=run([tailscale,"funnel","status","--json"]); print("funnel exit",funnel.returncode); print((funnel.stdout or funnel.stderr).strip()[:5000])
    else: print("FAIL: Tailscale CLI missing")

    section("BEST-EFFORT PRIVACY")
    ax=run(["swift","-e","import ApplicationServices; print(AXIsProcessTrusted())"],30)
    screen=run(["swift","-e","import CoreGraphics; print(CGPreflightScreenCaptureAccess())"],30)
    print("Accessibility for diagnostic process:",ax.stdout.strip() or ax.stderr.strip())
    print("Screen Recording for diagnostic process:",screen.stdout.strip() or screen.stderr.strip())

    section("END-TO-END INITIALIZE")
    for p in profiles:
        name=p.get("name","Unnamed"); local=int(p.get("localPort",0)); gateway=int(p.get("gatewayPort",0)); ep,_=endpoint(p); mount=norm(p.get("mountPath")); token=((p.get("clientCredentials") or [{}])[0].get("token") or "")
        print("\n--- "+name+" ---")
        if not listener(local): print("[SKIP] upstream is stopped"); continue
        probe("direct upstream", "http://127.0.0.1:"+str(local)+ep)
        if p.get("exclusiveGatewayEnabled") and listener(gateway):
            probe("gateway root /", "http://127.0.0.1:"+str(gateway)+"/", token)
            probe("gateway MCP endpoint", "http://127.0.0.1:"+str(gateway)+ep, token)
            if mount != "/":
                probe("gateway mounted base", "http://127.0.0.1:"+str(gateway)+mount, token)
                probe("gateway mounted endpoint", "http://127.0.0.1:"+str(gateway)+join(mount,ep), token)
        if dns and p.get("tailscaleRouteEnabled") and p.get("exposureMode")!="disabled":
            port=int(p.get("publicPort",443)); suffix="" if port==443 else ":"+str(port)
            public_base="https://"+dns+suffix+(mount if mount!="/" else "")
            probe("public displayed/base URL",public_base,token,15)
            probe("public URL plus MCP endpoint",join(public_base,ep),token,15)

    section("SUMMARY")
    counts={}
    for verdict,*_ in results: counts[verdict]=counts.get(verdict,0)+1
    for key in sorted(counts): print(key,counts[key])
    print("Direct PASS + gateway FAIL = controller routing/proxy bug")
    print("Gateway PASS + public FAIL = Tailscale Serve/Funnel bug")
    print("Direct FAIL = managed server or endpoint bug")
    print("Gateway root 404 = root forwarded to upstream / instead of MCP path")
    print("Public 502 = Funnel could not get a healthy gateway/upstream response")

with open(report_path,"w") as report:
    with contextlib.redirect_stdout(report): main()
print(report_path.read_text())
print("Saved:",report_path)

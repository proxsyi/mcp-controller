#!/usr/bin/env python3
import http.client
import json
import socket
import subprocess
import sys
import threading
import time
from typing import Any, Dict, Optional, Tuple

HOST = "cashs-macbook-pro.tail6b12d0.ts.net"
ROUTE = "/mcp/chrome"
SERVER_NAME = "Chrome DevTools MCP"
TIMEOUT = 20


def load_token() -> str:
    raw = subprocess.check_output([
        "/Users/cashm/.local/bin/mcpctl",
        "--secrets",
        "export",
        SERVER_NAME,
    ])
    profile = json.loads(raw)
    for cred in profile.get("clientCredentials", []):
        if cred.get("name") == "Notion":
            return cred["token"]
    raise RuntimeError("Could not find Notion client credential token")


def headers_to_dict(headers) -> Dict[str, str]:
    return {k.lower(): v for k, v in headers}


def post(payload: Dict[str, Any], token: str, session: Optional[str] = None, timeout: int = TIMEOUT) -> Tuple[int, Dict[str, str], str, float]:
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
    }
    if session:
        headers["Mcp-Session-Id"] = session
        headers["MCP-Protocol-Version"] = "2025-11-25"
    body = json.dumps(payload)
    conn = http.client.HTTPSConnection(HOST, timeout=timeout)
    started = time.time()
    conn.request("POST", ROUTE, body, headers)
    resp = conn.getresponse()
    text = resp.read().decode(errors="replace")
    elapsed = time.time() - started
    hdrs = headers_to_dict(resp.getheaders())
    status = resp.status
    conn.close()
    return status, hdrs, text, elapsed


class GetProbe(threading.Thread):
    def __init__(self, token: str, session: str):
        super().__init__(daemon=True)
        self.token = token
        self.session = session
        self.status = None
        self.headers: Dict[str, str] = {}
        self.first_chunk = ""
        self.error: Optional[str] = None
        self.elapsed = None

    def run(self):
        started = time.time()
        try:
            headers = {
                "Authorization": f"Bearer {self.token}",
                "Accept": "text/event-stream",
                "Mcp-Session-Id": self.session,
                "MCP-Protocol-Version": "2025-11-25",
            }
            conn = http.client.HTTPSConnection(HOST, timeout=TIMEOUT)
            conn.request("GET", ROUTE, headers=headers)
            resp = conn.getresponse()
            self.status = resp.status
            self.headers = headers_to_dict(resp.getheaders())
            try:
                chunk = resp.read(120)
                self.first_chunk = chunk.decode(errors="replace")
            except socket.timeout as e:
                self.error = repr(e)
            self.elapsed = time.time() - started
            try:
                resp.close()
            finally:
                conn.close()
        except Exception as e:
            self.error = repr(e)
            self.elapsed = time.time() - started


def print_step(name: str, ok: bool, detail: str):
    icon = "PASS" if ok else "FAIL"
    print(f"[{icon}] {name}: {detail}")


def main() -> int:
    token = load_token()
    failures = 0

    status, hdrs, body, elapsed = post({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "diagnose-chrome-notion-compat", "version": "1"},
        },
    }, token)
    session = hdrs.get("mcp-session-id")
    init_ok = (
        status == 200
        and hdrs.get("content-type") == "text/event-stream"
        and hdrs.get("transfer-encoding") == "chunked"
        and session
        and '"prompts":{}' in body
        and '"resources":{}' in body
    )
    print_step("initialize", bool(init_ok), f"status={status} session={session} elapsed={elapsed:.3f}s")
    if not init_ok:
        failures += 1

    status, hdrs2, body2, elapsed2 = post({
        "jsonrpc": "2.0",
        "method": "notifications/initialized",
    }, token, session=session)
    ok = status == 202
    print_step("notifications/initialized", ok, f"status={status} elapsed={elapsed2:.3f}s")
    if not ok:
        failures += 1

    get_probe = GetProbe(token, session)
    get_probe.start()
    time.sleep(1.0)

    for idx, method in enumerate([
        "tools/list",
        "resources/templates/list",
        "resources/list",
        "prompts/list",
        "ping",
    ], start=2):
        try:
            status, hdrs_m, body_m, elapsed_m = post({
                "jsonrpc": "2.0",
                "id": idx,
                "method": method,
                "params": {},
            }, token, session=session)
            content_type = hdrs_m.get("content-type")
            transfer = hdrs_m.get("transfer-encoding")
            ok = status == 200 and content_type == "text/event-stream" and transfer == "chunked"
            if method == "resources/templates/list":
                ok = ok and '"resourceTemplates":[]' in body_m
            elif method == "resources/list":
                ok = ok and ('"resources":[]' in body_m or '"Method not found"' in body_m)
            elif method == "prompts/list":
                ok = ok and ('"prompts":[]' in body_m or '"Method not found"' in body_m)
            elif method == "ping":
                ok = ok and '"result":{}' in body_m
            detail = f"status={status} elapsed={elapsed_m:.3f}s ct={content_type} te={transfer} snippet={body_m[:120].replace(chr(10), ' ')}"
        except Exception as e:
            ok = False
            detail = f"exception={repr(e)}"
        print_step(method, ok, detail)
        if not ok:
            failures += 1

    get_probe.join(timeout=3)
    get_ok = get_probe.status == 200 and get_probe.headers.get("content-type") == "text/event-stream" and get_probe.headers.get("transfer-encoding") == "chunked"
    if get_probe.error:
        detail = f"status={get_probe.status} err={get_probe.error} elapsed={get_probe.elapsed}"
    else:
        detail = f"status={get_probe.status} elapsed={get_probe.elapsed:.3f}s snippet={get_probe.first_chunk[:120].replace(chr(10), ' ')}"
    print_step("GET session stream", get_ok, detail)
    if not get_ok:
        failures += 1

    try:
        logs = subprocess.check_output([
            "/Users/cashm/.local/bin/mcpctl",
            "logs",
            SERVER_NAME,
        ], text=True)
        interesting = [
            line for line in logs.splitlines()
            if any(key in line for key in [
                "Gateway request:",
                "Protocol bridge active",
                "Compatibility session stream attached locally",
                "Compatibility fallback",
                "notifications/cancelled",
                "rpc=",
                "cancel=",
            ])
        ]
        print("\n=== Recent relevant logs ===")
        for line in interesting[-25:]:
            print(line)
    except Exception as e:
        print(f"\n[WARN] Could not load logs: {e}")

    print("\n=== Summary ===")
    if failures:
        print(f"Detected {failures} synthetic probe issue(s).")
    else:
        print("Synthetic gateway probe passed.")
    print("If Notion still fails while this script passes, the remaining issue is in live Notion validation behavior rather than basic gateway correctness.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

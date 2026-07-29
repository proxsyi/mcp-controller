#!/bin/bash
set -euo pipefail
cd "$HOME/Projects/Clients/Versyi/MCP-Controller"
git pull --ff-only

cat > Sources/MCPController/Services/TerminalControlService.swift <<'SWIFT'
import Foundation

struct TerminalControlRequest: Codable, Sendable {
    let id: String
    let action: String
    let target: String?
    let arguments: [String: String]
}

struct TerminalControlResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let payload: String?

    static func ok(_ message: String, payload: String? = nil) -> Self { .init(success: true, message: message, payload: payload) }
    static func error(_ message: String) -> Self { .init(success: false, message: message, payload: nil) }
}

final class TerminalControlService: @unchecked Sendable {
    typealias Handler = @Sendable (TerminalControlRequest) async -> TerminalControlResponse
    private let queue = DispatchQueue(label: "com.versyi.mcp-controller.terminal-control")
    private var timer: DispatchSourceTimer?
    private var handler: Handler?

    private var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MCP Controller/Control", directoryHint: .isDirectory)
    }
    private var requestsURL: URL { baseURL.appending(path: "requests", directoryHint: .isDirectory) }
    private var responsesURL: URL { baseURL.appending(path: "responses", directoryHint: .isDirectory) }

    func start(handler: @escaping Handler) {
        self.handler = handler
        try? FileManager.default.createDirectory(at: requestsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: responsesURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.processRequests() }
        self.timer = timer
        timer.resume()
    }

    private func processRequests() {
        guard let handler else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: requestsURL, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let request = try? JSONDecoder().decode(TerminalControlRequest.self, from: data) else {
                try? FileManager.default.removeItem(at: url); continue
            }
            try? FileManager.default.removeItem(at: url)
            Task {
                let response = await handler(request)
                guard let output = try? JSONEncoder().encode(response) else { return }
                let destination = responsesURL.appending(path: request.id + ".json")
                try? output.write(to: destination, options: .atomic)
            }
        }
    }
}
SWIFT

cat > Sources/MCPController/AppModel+TerminalControl.swift <<'SWIFT'
import AppKit
import Foundation

extension AppModel {
    func handleTerminalCommand(_ request: TerminalControlRequest) -> TerminalControlResponse {
        let action = request.action.lowercased()
        switch action {
        case "list", "status":
            let rows = profiles.map { profile in
                ["id": profile.id.uuidString, "name": profile.name, "state": phase(for: profile.id).title,
                 "localPort": String(profile.localPort), "gatewayPort": String(profile.gatewayPort),
                 "remotePath": profile.normalizedMountPath, "compatibility": String(profile.remoteClientCompatibilityEnabled)]
            }
            return .ok("\(rows.count) server(s)", payload: jsonString(rows))
        case "show", "export":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            var visible = profile
            if request.arguments["secrets"] != "true" {
                visible.environment = visible.environment.mapValues { _ in "<redacted>" }
                visible.clientCredentials = visible.clientCredentials.map { .init(id: $0.id, name: $0.name, token: "<redacted>") }
            }
            guard let data = try? JSONEncoder.pretty.encode(visible) else { return .error("Could not encode the server profile.") }
            return .ok(profile.name, payload: String(decoding: data, as: UTF8.self))
        case "import":
            guard let json = request.arguments["json"], let data = json.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(ServerProfile.self, from: data) else { return .error("Pass a complete ServerProfile JSON document.") }
            if profiles.contains(where: { $0.id == profile.id }) { update(profile) } else { add(profile) }
            return .ok("Saved \(profile.name).")
        case "start", "stop", "restart", "duplicate", "remove", "route-start", "route-stop", "lease-release":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            switch action {
            case "start": start(profile)
            case "stop": stop(profile)
            case "restart": stop(profile) { [weak self] in self?.start(profile) }
            case "duplicate": duplicate(profile)
            case "remove": remove(profile)
            case "route-start": if !startTailscaleRoute(profile) { return .error(presentedError ?? "Route could not start.") }
            case "route-stop": if !stopTailscaleRoute(profile) { return .error(presentedError ?? "Route could not stop.") }
            default: releaseLease(profileID: profile.id)
            }
            return .ok("\(action) accepted for \(profile.name).")
        case "start-all": profiles.forEach(start); return .ok("Started all configured servers.")
        case "stop-all": stopAll(); return .ok("Stopped all managed servers.")
        case "logs":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            return .ok(profile.name, payload: logs[profile.id] ?? "")
        case "clear-logs":
            guard let profile = terminalProfile(request.target) else { return .error("Server not found.") }
            clearLog(for: profile.id); return .ok("Cleared logs for \(profile.name).")
        case "funnel-start": startTailscaleFunnel(); return presentedError == nil ? .ok("Funnel routes started.") : .error(presentedError!)
        case "funnel-stop": stopTailscaleFunnel(); return presentedError == nil ? .ok("Funnel routes stopped.") : .error(presentedError!)
        case "funnel-status": return .ok(tailscaleFunnelRunning ? "running" : "stopped")
        case "one-ai":
            let enabled = request.arguments["enabled"] == "true"
            applyGlobalOneAIPolicy(enabled); UserDefaults.standard.set(enabled, forKey: "settings.oneAIOnly")
            return .ok("One-AI policy \(enabled ? "enabled" : "disabled").")
        case "open": NSApplication.shared.activate(ignoringOtherApps: true); return .ok("Opened MCP Controller.")
        case "quit": shutdownForApplicationQuit(); NSApplication.shared.terminate(nil); return .ok("Quitting MCP Controller.")
        default: return .error("Unknown action: \(request.action)")
        }
    }

    private func terminalProfile(_ target: String?) -> ServerProfile? {
        guard let target else { return nil }
        if let id = UUID(uuidString: target), let profile = profiles.first(where: { $0.id == id }) { return profile }
        return profiles.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
    }

    private func jsonString(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
SWIFT

cat > Sources/MCPController/Models/ServerProfile+Diagnostics.swift <<'SWIFT'
import Foundation

extension ServerProfile {
    var startupDiagnosticSummary: String {
        let args = arguments.isEmpty ? "(none)" : arguments.joined(separator: " | ")
        let directory = workingDirectory.isEmpty ? "(inherited)" : workingDirectory
        let environmentSummary = environment.keys.sorted().map { key in
            let lowered = key.lowercased()
            let sensitive = ["password", "token", "secret", "api_key", "apikey"].contains { lowered.contains($0) }
            return "  \(key)=\(sensitive ? "<redacted>" : environment[key] ?? "")"
        }.joined(separator: "\n")
        let origins = allowedOrigins.isEmpty ? "(any/unspecified)" : allowedOrigins.joined(separator: ", ")
        let keyNames = clientCredentials.isEmpty ? "(none)" : clientCredentials.map(\.name).joined(separator: ", ")
        return """
        --- Server configuration ---
        Name: \(name)
        ID: \(id.uuidString)
        Description: \(description.isEmpty ? "(none)" : description)
        Executable: \(executablePath)
        Arguments: \(args)
        Working directory: \(directory)
        Environment:\n\(environmentSummary.isEmpty ? "  (none)" : environmentSummary)
        Local endpoint: 127.0.0.1:\(localPort)\(streamableHTTPPath ?? "")
        Readiness timeout: \(max(15, Int(startupDelaySeconds)))s
        Start at launch: \(autoStart)
        Remote mode: \(exposureMode.title)
        Route enabled: \(tailscaleRouteEnabled)
        Remote path: \(normalizedMountPath)
        Public HTTPS port: \(publicPort)
        Tailscale CLI: \(tailscalePath)
        Gateway enabled: \(exclusiveGatewayEnabled)
        Gateway endpoint: 127.0.0.1:\(gatewayPort)
        Lease timeout: \(leaseTimeoutSeconds)s
        Allowed origins: \(origins)
        Access keys: \(keyNames) (tokens redacted)
        Remote client compatibility: \(remoteClientCompatibilityEnabled)
        ----------------------------
        """ + "\n"
    }
}
SWIFT

cat > Resources/mcpctl <<'PY'
#!/usr/bin/env python3
import argparse, json, os, pathlib, subprocess, sys, time, uuid

base = pathlib.Path.home()/"Library/Application Support/MCP Controller/Control"
reqdir, respdir = base/"requests", base/"responses"

def ensure_app():
    subprocess.run(["open", "-a", "/Applications/MCP Controller.app"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        if reqdir.exists(): return
        time.sleep(.1)

def main():
    parser=argparse.ArgumentParser(prog="mcpctl", description="Control MCP Controller from Terminal")
    parser.add_argument("action", help="list, status, show, export, import, start, stop, restart, start-all, stop-all, logs, clear-logs, route-start, route-stop, funnel-start, funnel-stop, funnel-status, lease-release, duplicate, remove, one-ai, open, quit")
    parser.add_argument("target", nargs="?", help="Server name or UUID")
    parser.add_argument("--secrets", action="store_true", help="Include stored secrets in export")
    parser.add_argument("--file", help="Profile JSON file for import")
    parser.add_argument("--enabled", choices=["true","false"], help="Boolean for one-ai")
    args=parser.parse_args(); ensure_app(); reqdir.mkdir(parents=True, exist_ok=True); respdir.mkdir(parents=True, exist_ok=True)
    ident=str(uuid.uuid4()); extra={"secrets":str(args.secrets).lower()}
    if args.file: extra["json"]=pathlib.Path(args.file).read_text()
    if args.enabled: extra["enabled"]=args.enabled
    request={"id":ident,"action":args.action,"target":args.target,"arguments":extra}
    temp=reqdir/(ident+".tmp"); final=reqdir/(ident+".json")
    temp.write_text(json.dumps(request)); temp.rename(final); response=respdir/(ident+".json")
    for _ in range(150):
        if response.exists():
            result=json.loads(response.read_text()); response.unlink(missing_ok=True)
            if result.get("payload") is not None: print(result["payload"])
            elif result.get("message"): print(result["message"])
            return 0 if result.get("success") else 1
        time.sleep(.1)
    print("MCP Controller did not respond within 15 seconds.", file=sys.stderr); return 2
if __name__ == "__main__": raise SystemExit(main())
PY

python3 - <<'PY'
from pathlib import Path
p=Path('Sources/MCPController/AppModel.swift'); s=p.read_text()
s=s.replace('    private let gatewayManager = ExclusiveGatewayManager()\n', '    private let gatewayManager = ExclusiveGatewayManager()\n    private let terminalControl = TerminalControlService()\n', 1)
old='''        } catch { presentedError = "Could not load server profiles: \\(error.localizedDescription)" }
    }
'''
new='''        } catch { presentedError = "Could not load server profiles: \\(error.localizedDescription)" }
        terminalControl.start { [weak self] request in
            await MainActor.run { self?.handleTerminalCommand(request) ?? .error("MCP Controller is unavailable.") }
        }
    }
'''
if old not in s: raise SystemExit('AppModel init insertion point missing')
s=s.replace(old,new,1)
s=s.replace('''        appendLog(profile.id, "Starting \\(profile.name)…\\n")
''','''        appendLog(profile.id, "Starting \\(profile.name)…\\n")
        appendLog(profile.id, profile.startupDiagnosticSummary)
''',1)
p.write_text(s)

b=Path('scripts/build-app.sh'); s=b.read_text()
s=s.replace('''cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/MCPController"
''','''cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/mcpctl" "$CONTENTS/Resources/mcpctl"
chmod +x "$CONTENTS/MacOS/MCPController" "$CONTENTS/Resources/mcpctl"
''',1); b.write_text(s)

c=Path('CHANGELOG.md'); s=c.read_text(); marker='## Unreleased\n'
entry='''## Unreleased

## v0.7.0

### Added
- Added `mcpctl` terminal control for server lifecycle, profiles, logs, routes, leases, Funnel, and global policy.
- Added complete redacted server configuration snapshots at every start.
- Added gateway protocol and request diagnostics for remote-client validation.

### Fixed
- Made initialize protocol bridging resilient to split and chunked upstream responses.
'''
if marker not in s: raise SystemExit('changelog marker missing')
c.write_text(s.replace(marker,entry,1))
PY

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.7.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 17" Resources/Info.plist

git diff --check
swift test
bash scripts/build-app.sh

git add Sources/MCPController Resources/mcpctl Resources/Info.plist scripts/build-app.sh CHANGELOG.md
git commit -m "feat: add terminal control and startup diagnostics"
git push origin main
codesign --force --deep --sign - --identifier com.versyi.mcp-controller "dist/MCP Controller.app"
codesign --verify --deep --strict --verbose=2 "dist/MCP Controller.app"
ditto -c -k --sequesterRsrc --keepParent "dist/MCP Controller.app" "dist/MCP-Controller-macOS.zip"
gh release create v0.7.0 "dist/MCP-Controller-macOS.zip" --target "$(git rev-parse HEAD)" --generate-notes --title "MCP Controller v0.7.0"
pkill -f '/MCP Controller.app/Contents/MacOS/MCPController' 2>/dev/null || true
sleep 3
rm -rf '/Applications/MCP Controller.app.new'; cp -R 'dist/MCP Controller.app' '/Applications/MCP Controller.app.new'
rm -rf '/Applications/MCP Controller.app'; mv '/Applications/MCP Controller.app.new' '/Applications/MCP Controller.app'
mkdir -p "$HOME/.local/bin"; cp '/Applications/MCP Controller.app/Contents/Resources/mcpctl' "$HOME/.local/bin/mcpctl"; chmod +x "$HOME/.local/bin/mcpctl"
rm -rf 'dist/MCP Controller.app'; rm -f 'dist/MCP-Controller-macOS.zip'; rm -rf "$HOME/Applications/MCP Controller.app"
tccutil reset All com.versyi.mcp-controller || true
open -a '/Applications/MCP Controller.app'
echo "v0.7.0 installed. CLI: $HOME/.local/bin/mcpctl"

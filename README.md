# MCP Controller

MCP Controller is a native macOS app for managing MCP server processes, access gateways, and Tailscale exposure from one place.

Current release: `v0.8.11` (build 38).

## Current operational state — August 3, 2026

- Release `v0.8.11` build 38 includes the Controller lifetime, installer targeting, scoped Tailscale recovery, corrected window architecture, icon/signing, and last-window-close fixes.
- Included fix commits: `347fb0c` keeps the background Controller available, `5ccd928` repairs installed-app relaunch targeting, `558a117` adds Controller-scoped Tailscale recovery, `a6e3c33` separates main/Settings/popover presentation and packages the app icon/signing preference, and `a8d0b8c` keeps the Controller alive after its final window closes.
- Installed app: exactly one `/Applications/MCP Controller.app`, with `AppIcon.icns` and Apple Development signing by team `7JX38C53N8`.
- Tailscale recovery: `tailscale-reset` and `tailscale-reconnect` rebuild only configured Controller-owned route paths. They never run `tailscale funnel reset`, `tailscale serve reset`, or `tailscale down`.
- Terminal aliases: `release-all` maps to `lease-release-all`; `tailscale-reset` and `tailscale-reconnect` map to the same scoped recovery operation.
- Window model: Dock/Finder reopen targets only the real main window; the main window, native Settings scene, and menu-bar popover have distinct identifiers. The toolbar gear/globe and `⌘,` target Settings without surfacing the popover shell.
- Closing the final app window keeps the menu-bar Controller process alive; minimizing continues to retain normal app/Dock presence.
- Runtime verification: the scoped reset reconnected 18 Controller-managed routes, `start-all` returned all 18 profiles to `Running`, and MacOS System, Visual, and AppleScript MCP probes succeeded.
- Test state: 81 Swift tests pass with zero failures, including last-window-close lifecycle coverage.
- Published validation baseline remains 51/51 local, localhost-gateway, and public Funnel surfaces.

The repository intentionally leaves local runtime artifacts untracked: `.playwright-mcp/`, `.serena/`, `mcp-profiles/`, `mcp-server.log`, and `mcp-server-error.log`.

## What it does

- Stores reusable profiles for independently installed local servers and hosted MCP bridges.
- Starts, stops, restarts, adopts, and monitors each managed process independently.
- Queues bulk start and stop actions so each server finishes its transition before the next begins, without blocking the menu bar or main window.
- Supports local-only, tailnet-only, and public Tailscale Funnel exposure.
- Adds and removes only the path-scoped Tailscale route owned by each profile.
- Controls the global Funnel separately while automatically starting it when a configured public profile requires it.
- Optionally places a localhost exclusive-access gateway in front of a server.
- Uses separate Bearer keys and one-client leases for remote AI connections.
- Releases individual leases or every active lease from the menu bar without stopping servers.
- Provides menu-bar controls with a live running-server count, bounded logs, readiness checks, update checks, and terminal control through `mcpctl`.
- Stops managed servers, gateways, routes, leases, and Funnel during the app's managed quit path.
- Persists local configuration under `~/Library/Application Support/MCP Controller/servers.json`.

MCP Controller does not bundle third-party MCP servers. Install or identify each server separately, then create a profile for its executable, local HTTP endpoint, or OAuth-capable remote bridge.

## Local path

```text
~/Projects/Clients/Versyi/MCP-Controller
```

## Requirements

- macOS 14 or newer
- Xcode 26 for native Liquid Glass builds
- Tailscale CLI for tailnet or Funnel exposure
- A Streamable HTTP MCP server, or a stdio/remote bridge such as `mcp-proxy` and `mcp-remote`

## Build and install

```bash
swift test
bash scripts/build-app.sh
bash scripts/install-local.sh
```

GitHub Actions builds a zipped unsigned app bundle. Developer ID signing and notarization remain pending.

## Adding a server

1. Add a profile in the app.
2. Use a clear product name for product-specific servers and a functional name for broad system servers.
3. Enter the absolute executable path.
4. Add one command-line argument per line. `{port}` is replaced with the profile's local port.
5. Set the working directory and required environment values.
6. Allocate a unique local port, exclusive gateway port, and Funnel path.
7. Choose Local only, Tailnet, or Public Funnel.
8. Enable remote-client compatibility when the hosted client requires it.
9. Enable the exclusive gateway and create a separate Bearer key for each remote client.
10. Start the profile and verify local initialization, public initialization, `tools/list`, and one non-destructive tool call.

Keep provider credentials in local environment values or provider-managed OAuth storage. Keep gateway Bearer keys in the local profile store. Do not put live credentials in Git or authored documentation.

## Bridge patterns

### Local stdio server

```text
npx -y mcp-proxy@6.5.4 --host 127.0.0.1 --port {port} --server stream --streamEndpoint / -- <server command>
```

### Hosted OAuth server

```text
npx -y mcp-proxy@6.5.4 --host 127.0.0.1 --port {port} --server stream --streamEndpoint / -- npx -y mcp-remote@0.1.38 <remote MCP URL> <OAuth callback port> --transport http-only --auth-timeout 300
```

`mcp-remote` stores provider OAuth sessions under `~/.mcp-auth`. MCP Controller exposes the local bridge through its separate gateway and Tailscale route.

## Terminal control

The installed command is `~/.local/bin/mcpctl`. Quote names containing spaces. Between `new`, `show --secrets`, `save`, and the lifecycle/access commands below, every app action has a terminal equivalent. Routine terminal commands wake the controller in the background and proceed as soon as the local control queue is available.

```bash
# Inventory and details
~/.local/bin/mcpctl list
~/.local/bin/mcpctl status "Server Name"
~/.local/bin/mcpctl show "Server Name"
~/.local/bin/mcpctl remote-url
~/.local/bin/mcpctl remote-url "Server Name"

# Create and edit profiles
~/.local/bin/mcpctl template > /tmp/server.json
~/.local/bin/mcpctl new --name "Server Name" --executable /absolute/path/to/executable --working-directory /absolute/path --description "What it does" --local-port 4200
~/.local/bin/mcpctl export "Server Name" --secrets > /tmp/server.json
~/.local/bin/mcpctl save --file /tmp/server.json
~/.local/bin/mcpctl save --file /tmp/server.json --restart  # Required when changing a running profile
~/.local/bin/mcpctl import --file /tmp/server.json
~/.local/bin/mcpctl duplicate "Server Name"
~/.local/bin/mcpctl remove "Server Name"

# Lifecycle
~/.local/bin/mcpctl start "Server Name"
~/.local/bin/mcpctl stop "Server Name"
~/.local/bin/mcpctl restart "Server Name"
~/.local/bin/mcpctl start-all
~/.local/bin/mcpctl stop-all

# Logs
~/.local/bin/mcpctl logs "Server Name"
~/.local/bin/mcpctl clear-logs "Server Name"

# Route and Funnel controls
~/.local/bin/mcpctl route-start "Server Name"
~/.local/bin/mcpctl route-stop "Server Name"
~/.local/bin/mcpctl funnel-start
~/.local/bin/mcpctl funnel-stop
~/.local/bin/mcpctl funnel-status
~/.local/bin/mcpctl tailscale-reset
~/.local/bin/mcpctl tailscale-reconnect
~/.local/bin/mcpctl use-default-cli

# Access keys, leases, and approvals
~/.local/bin/mcpctl keys "Server Name"
~/.local/bin/mcpctl key-add "Server Name" --name "Primary AI"
~/.local/bin/mcpctl key-show "Server Name" --key "Primary AI"
~/.local/bin/mcpctl key-remove "Server Name" --key "Primary AI"
~/.local/bin/mcpctl lease
~/.local/bin/mcpctl lease "Server Name"
~/.local/bin/mcpctl lease-release "Server Name"
~/.local/bin/mcpctl lease-release-all
~/.local/bin/mcpctl release-all
~/.local/bin/mcpctl pending
~/.local/bin/mcpctl pending "Server Name"
~/.local/bin/mcpctl approve "Server Name" --client-id CLIENT_ID
~/.local/bin/mcpctl deny "Server Name" --client-id CLIENT_ID
~/.local/bin/mcpctl one-ai --enabled true
~/.local/bin/mcpctl one-ai --enabled false

# App controls
~/.local/bin/mcpctl check-updates
~/.local/bin/mcpctl install-update
~/.local/bin/mcpctl open
~/.local/bin/mcpctl settings
~/.local/bin/mcpctl quit
```

`export --secrets` returns the full saved profile JSON, including environment values and access keys. Edit that file, then apply it with `save --file ...` to change any field that the GUI can edit. Changes to a running profile remain pending until you explicitly confirm **Apply & Restart**. Terminal saves and key changes reject active-profile edits unless `--restart` is passed.

## Exclusive AI access

When exclusive access is enabled, MCP Controller listens on a profile-specific gateway port bound to `127.0.0.1`. Tailscale exposes the gateway instead of the upstream server.

- The first valid Bearer key receives the lease.
- Competing keys receive a retryable JSON-RPC connection-in-use response and appear in the approval queue.
- Approval transfers the lease; the waiting client retries its request.
- Gateway authorization is consumed locally and never forwarded upstream.
- Origin headers are validated against the profile's allowlist only when you explicitly configure origin restrictions; leaving Allowed origins empty keeps origin filtering off.
- Stopping a profile releases its lease and gateway.

Remote-client compatibility can normalize MCP request headers, bridge negotiated protocol versions, acknowledge notifications, and provide empty optional discovery responses when required by strict hosted clients.

## Exposure cleanup

Stopping or removing a profile disables only that profile's configured route. The app intentionally avoids broad commands such as `tailscale serve reset`, `tailscale funnel reset`, and `tailscale down` because they could remove unrelated configuration.

The global Funnel remains independently controllable. Quitting MCP Controller through its managed quit path stops managed processes, gateways, routes, leases, and Funnel.

## Validation

Useful diagnostics include:

```bash
python3 scripts/validate-all-profiles.py
python3 scripts/test-mcp-servers.py
python3 scripts/check-mcp-stack.py
bash scripts/check-notion-validation.sh
bash scripts/run-mcp-health-check.sh
```

`validate-all-profiles.py` detects each profile's configured Streamable HTTP endpoint, including `mcp-proxy` profiles mounted at `/` rather than `/mcp`. It checks configured profiles through local, localhost-gateway, and public Tailscale surfaces, lists tools, and runs only explicitly non-destructive representative calls. Use `--skip "Profile Name"` when a profile already has an active exclusive client lease. The current `v0.8.11` verification retains the established 51/51 tested surfaces with MacOS System skipped for its active lease; all 18 profiles reported Running. The earlier Desktop Commander Copy HTTP 404 was a validator endpoint-detection false positive and is closed.

Validate a new profile locally and publicly before adding its custom MCP URL to another client.

## Performance and lifecycle behavior

Process inspection, readiness polling, gateway startup, route changes, Tailscale DNS lookup, and process termination run away from the main actor. Tailscale DNS is cached, bulk transitions are sequenced by actual runtime phase, and managed shutdown still sends immediate termination signals before app exit. On the fifteen-profile validation machine, terminal control became ready in about 0.54 seconds after launch; cached status calls were typically 0.15–0.26 seconds. Start Everything returned in 0.278 seconds and Stop Everything in 0.172 seconds while the queues continued without freezing the menu bar.

The circular arrow beside a server and Release All are lease-release controls. They disconnect the current AI lease without stopping the MCP server, allowing the same or another authorized client to reconnect.

Protected public routes have a separate request deadline from lease expiry. New and legacy profiles default to a five-minute public request timeout, configurable from 1 to 60 minutes. Requests that have not begun responding receive HTTP 504 at the deadline; already-streaming responses are closed cleanly instead of receiving a second HTTP response. Long-lived compatibility GET streams are exempt from the bounded tool-request deadline and receive 15-second keepalives so Notion sessions remain alive through Funnel.

## Release, installation, and maintenance decisions

- `scripts/publish-release.sh` is the validated manual release path while GitHub Actions is blocked by account billing. It requires a clean tracked tree, verifies that the version tag points to the full current commit, reruns tests and the production build, verifies the signature, creates the ZIP and checksum, pushes `main` and the tag, and publishes with `--verify-tag`.
- `scripts/install-local.sh` is the validated local install path. It stages and verifies the app, stops all Controller processes, atomically replaces `/Applications/MCP Controller.app`, installs `mcpctl`, removes the temporary build app, and launches one Applications copy.
- Tagged GitHub Actions releases require configured Developer ID certificate and signing identity secrets. Local manual artifacts prefer the available Apple Development identity; Developer ID distribution signing is still unavailable.
- GitHub Official remains a direct connection rather than a Controller-managed profile.
- Serena, WCGW, and Desktop Commander remain unrestricted at the macOS capability level by Cash's explicit decision. Controller Bearer authentication, exclusive leases, Origin checks, request deadlines, compatibility handling, and route controls are connection protections, not capability sandboxes.
- Upstream MCP and skill source code is not modified as part of Controller maintenance.
- Gateway-key rotation and Keychain migration are intentionally not tracked as future Controller work.

Deferred work: Developer ID signing/notarization and final distribution choice; OpenPencil live-canvas/font repair; a live intentionally delayed request to verify HTTP 504 behavior; upstream-compatible remediation for the audited Mac OS System, Visual, AppleScript/Apps, Remote, Google Stitch, and Cloudflare dependencies; and pinning `turnstile-spin` persistence to an audited commit before reproducible use.

## Security

Public Funnel endpoints are internet-accessible. Use a unique high-entropy gateway key per client, review waiting connections before approval, and avoid broad provider credentials when narrower scopes are available.

The app and provider OAuth stores contain live credentials locally. Do not commit profile exports, provider token files, logs containing secrets, or Application Support data. Local builds use the available Apple Development identity. Apple Developer ID signing and notarization remain blocked until a Developer ID Application certificate and notary credentials are available; additional security review remains pending.

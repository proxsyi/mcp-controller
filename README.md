# MCP Controller

MCP Controller is a native macOS app for managing MCP server processes, access gateways, and Tailscale exposure from one place.

Current published release: `v0.8.3` (build 30).

> **Development status:** The active work is on `fix/menu-bar-count-and-stability` in draft PR #3. OpenPencil process adoption, the 75-test suite, production build, stable local signing, and installation were verified at `930c096`. Later full-screen menu-popover and sidebar-width fixes are committed but still need to be installed and validated on the MacBook Pro. Do not merge or release this branch yet. See [Development status](docs/DEVELOPMENT_STATUS.md) for the exact verified state, current blockers, and release gates.

## What it does

- Stores reusable profiles for independently installed local servers and hosted MCP bridges.
- Starts, stops, restarts, adopts, and monitors each managed process independently.
- Queues bulk start and stop actions so each transition completes without blocking the menu bar or main window.
- Supports local-only, tailnet-only, and public Tailscale Funnel exposure.
- Adds and removes only the path-scoped Tailscale route owned by each profile.
- Controls the global Funnel separately while automatically starting it when required.
- Optionally places a localhost exclusive-access gateway in front of a server.
- Uses separate Bearer keys and one-client leases for remote AI connections.
- Releases individual leases or every active lease without stopping servers.
- Supports persistent headings, spacers, drag-and-drop organization, and terminal organization commands.
- Provides menu-bar controls with a live running-server count, bounded logs, readiness checks, update checks, and terminal control through `mcpctl`.
- Stops managed servers, gateways, routes, leases, and Funnel during the managed quit path.
- Persists local configuration under `~/Library/Application Support/MCP Controller/servers.json`.

MCP Controller does not bundle third-party MCP servers. Install or identify each server separately, then create a profile for its executable, local HTTP endpoint, or OAuth-capable remote bridge.

## Repository location

The validated repository is on `Cashs-MacBook-Pro`:

```text
/Users/cashm/Projects/Clients/Versyi/MCP-Controller
```

Do not run that path from `Cashs-MacBook-Air` unless the repository has separately been cloned there. A failed `cd ... || exit 1` exits the current shell or SSH session before any fetch, test, build, or install command runs.

## Requirements

- macOS 14 or newer
- Xcode 26 for native Liquid Glass builds
- Tailscale CLI for tailnet or Funnel exposure
- A Streamable HTTP MCP server, or a stdio/remote bridge such as `mcp-proxy` and `mcp-remote`

## Build and install

Run on the MacBook Pro:

```bash
cd "/Users/cashm/Projects/Clients/Versyi/MCP-Controller" || exit 1
git fetch origin
git switch fix/menu-bar-count-and-stability
git pull --ff-only origin fix/menu-bar-count-and-stability
git log -1 --oneline
swift test || exit 1
pkill -f "/Applications/MCP Controller.app/Contents/MacOS/MCPController" 2>/dev/null || true
sleep 2
bash scripts/install-local.sh || exit 1
open -gj -a "/Applications/MCP Controller.app"
sleep 10
"$HOME/.local/bin/mcpctl" list --timeout 15
```

The branch build uses the stable local signing identity when available. Public tagged releases now require configured Developer ID credentials and publish a SHA-256 checksum beside the app archive. Developer ID notarization remains unavailable until valid Apple release credentials are configured.

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

The installed command is `~/.local/bin/mcpctl`. Quote names containing spaces. Routine commands wake the controller in the background and proceed when the local control queue is ready.

```bash
# Inventory
~/.local/bin/mcpctl list
~/.local/bin/mcpctl status "Server Name"
~/.local/bin/mcpctl show "Server Name"
~/.local/bin/mcpctl remote-url "Server Name"

# Create, edit, and organize
~/.local/bin/mcpctl template > /tmp/server.json
~/.local/bin/mcpctl new --name "Server Name" --executable /absolute/path --local-port 4200
~/.local/bin/mcpctl export "Server Name" --secrets > /tmp/server.json
~/.local/bin/mcpctl save --file /tmp/server.json
~/.local/bin/mcpctl save --file /tmp/server.json --restart
~/.local/bin/mcpctl import --file /tmp/server.json
~/.local/bin/mcpctl duplicate "Server Name"
~/.local/bin/mcpctl remove "Server Name"
~/.local/bin/mcpctl heading-add --name "Heading"
~/.local/bin/mcpctl spacer-add
~/.local/bin/mcpctl rename "Old Name" --name "New Name"
~/.local/bin/mcpctl move "Server Name" --index 0

# Lifecycle
~/.local/bin/mcpctl start "Server Name"
~/.local/bin/mcpctl stop "Server Name"
~/.local/bin/mcpctl restart "Server Name"
~/.local/bin/mcpctl start-all
~/.local/bin/mcpctl stop-all

# Logs and routes
~/.local/bin/mcpctl logs "Server Name"
~/.local/bin/mcpctl clear-logs "Server Name"
~/.local/bin/mcpctl route-start "Server Name"
~/.local/bin/mcpctl route-stop "Server Name"
~/.local/bin/mcpctl funnel-start
~/.local/bin/mcpctl funnel-stop
~/.local/bin/mcpctl funnel-status

# Keys, leases, and approvals
~/.local/bin/mcpctl keys "Server Name"
~/.local/bin/mcpctl key-add "Server Name" --name "Primary AI"
~/.local/bin/mcpctl key-show "Server Name" --key "Primary AI"
~/.local/bin/mcpctl key-remove "Server Name" --key "Primary AI"
~/.local/bin/mcpctl lease
~/.local/bin/mcpctl lease-release "Server Name"
~/.local/bin/mcpctl lease-release-all
~/.local/bin/mcpctl pending
~/.local/bin/mcpctl approve "Server Name" --client-id CLIENT_ID
~/.local/bin/mcpctl deny "Server Name" --client-id CLIENT_ID

# App controls
~/.local/bin/mcpctl check-updates
~/.local/bin/mcpctl install-update
~/.local/bin/mcpctl open
~/.local/bin/mcpctl settings
~/.local/bin/mcpctl quit
```

`export --secrets` returns saved profile JSON containing environment values and access keys. Changes to a running profile remain pending until **Apply & Restart** is confirmed. Terminal saves and key changes reject active-profile edits unless `--restart` is passed.

## Exclusive AI access

When exclusive access is enabled, MCP Controller listens on a profile-specific gateway port bound to `127.0.0.1`. Tailscale exposes the gateway instead of the upstream server.

- The first valid Bearer key receives the lease.
- Competing keys receive a retryable JSON-RPC connection-in-use response and appear in the approval queue.
- Approval transfers the lease; the waiting client retries its request.
- Gateway authorization is consumed locally and never forwarded upstream.
- Origin headers are validated only when the profile has an explicit allowlist. Leaving Allowed origins empty disables origin filtering.
- Stopping a profile releases its lease and gateway.

Remote-client compatibility can normalize MCP headers, bridge negotiated protocol versions, acknowledge notifications, and provide empty optional discovery responses when required by strict hosted clients.

## Exposure cleanup

Stopping or removing a profile disables only that profile's configured route. The app intentionally avoids broad commands such as `tailscale serve reset`, `tailscale funnel reset`, and `tailscale down` because they could remove unrelated configuration.

## Validation

```bash
python3 scripts/validate-all-profiles.py
python3 scripts/test-mcp-servers.py
python3 scripts/check-mcp-stack.py
bash scripts/check-notion-validation.sh
bash scripts/run-mcp-health-check.sh
```

`validate-all-profiles.py` checks configured profiles through localhost gateways and public Tailscale routes, lists tools, and runs only explicitly non-destructive representative calls. Use `--skip "Profile Name"` when a profile already has an active exclusive-client lease.

Before release, also prove one uninterrupted Serena session using `tools/list`, `activate_project` for `/Users/cashm/Projects/personal/folder/notion-bridge`, another non-destructive call, and repeated calls without restarting the app, gateway, route, or lease.

## Performance and lifecycle

Process inspection, readiness polling, gateway startup, route changes, Tailscale DNS lookup, and termination run away from the main actor. Tailscale mutations are serialized and bounded. Persistent profiles use bounded recovery after unexpected process or gateway failure. Wrapped npx servers can be adopted by matching the configured command to the actual npm-cache child executable basename.

Protected public routes have a separate request deadline from lease expiry. New and legacy profiles default to a five-minute public timeout. Long-lived compatibility GET streams are exempt from that deadline and receive keepalives so hosted sessions remain alive.

## Security

Public Funnel endpoints are internet-accessible. Use a unique high-entropy gateway key per client, review waiting connections before approval, and avoid broad provider credentials when narrower scopes are available.

Do not commit profile exports, provider token files, logs containing secrets, or Application Support data. Tagged releases must not be published until signing, installed-app validation, the full MCP matrix, Serena session continuity, asset checksum, and released-build retest all pass.

# MCP Controller

MCP Controller is a native macOS app for managing MCP server processes, access gateways, and Tailscale exposure from one place.

Current release: `v0.8.6` (build 33).

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

`validate-all-profiles.py` checks every configured profile through both the localhost gateway and its public Tailscale route, lists tools, and runs only explicitly non-destructive representative calls. Use `--skip "Profile Name"` when a profile already has an active exclusive client lease.

Validate a new profile locally and publicly before adding its custom MCP URL to another client.

## Performance and lifecycle behavior

Process inspection, readiness polling, gateway startup, route changes, Tailscale DNS lookup, and process termination run away from the main actor. Tailscale DNS is cached, bulk transitions are sequenced by actual runtime phase, and managed shutdown still sends immediate termination signals before app exit. On the fifteen-profile validation machine, terminal control became ready in about 0.54 seconds after launch; cached status calls were typically 0.15–0.26 seconds. Start Everything returned in 0.278 seconds and Stop Everything in 0.172 seconds while the queues continued without freezing the menu bar.

The circular arrow beside a server and Release All are lease-release controls. They disconnect the current AI lease without stopping the MCP server, allowing the same or another authorized client to reconnect.

Protected public routes have a separate request deadline from lease expiry. New and legacy profiles default to a five-minute public request timeout, configurable from 1 to 60 minutes. Requests that have not begun responding receive HTTP 504 at the deadline; already-streaming responses are closed cleanly instead of receiving a second HTTP response. Long-lived compatibility GET streams are exempt from the bounded tool-request deadline and receive 15-second keepalives so Notion sessions remain alive through Funnel.

## Security

Public Funnel endpoints are internet-accessible. Use a unique high-entropy gateway key per client, review waiting connections before approval, and avoid broad provider credentials when narrower scopes are available.

The app and provider OAuth stores contain live credentials locally. Do not commit profile exports, provider token files, logs containing secrets, or Application Support data. Local and release artifacts use the available stable local signing identity. Apple Developer ID signing and notarization remain blocked until a Developer ID Application certificate and notary credentials are available; additional security review remains pending.

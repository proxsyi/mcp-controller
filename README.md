# MCP Controller

MCP Controller is a native macOS app for managing local MCP server processes and exposing their HTTP endpoints through Tailscale only when needed.

## What it does

- Add and remove MCP server profiles without hard-coding specific servers.
- Point each profile at an executable, arguments, working directory, environment, and local HTTP port.
- Start and stop each process independently.
- Keep a server local, expose it only to the tailnet, or publish it through Tailscale Funnel.
- Optionally place a built-in exclusive-access gateway between Tailscale and a server.
- Give each AI connection its own Bearer access key.
- Allow only one AI to hold a server lease at a time.
- Queue competing AI connections for approval in the app.
- Remove the exact Tailscale mount owned by a profile when it stops or is deleted.
- Provide a global stop control from the menu bar.
- Persist configuration under `~/Library/Application Support/MCP Controller/servers.json`.

MCP Controller does not install third-party MCP servers. Install each server separately, then point a profile at its executable or HTTP bridge.

## Local path

The intended clone location is:

```text
~/Projects/Clients/Versyi/MCP Controller
```

## Requirements

- macOS 14 or newer
- Xcode 26 for native Liquid Glass builds
- Tailscale CLI for tailnet or Funnel exposure
- An MCP server that listens over Streamable HTTP, or a separate stdio-to-HTTP MCP bridge

## Build

```bash
swift test
bash scripts/build-app.sh
open "dist/MCP Controller.app"
```

GitHub Actions also publishes a zipped unsigned app bundle as a workflow artifact.

## Adding a server

1. Add a profile in the app.
2. Enter the absolute executable path.
3. Add one command-line argument per line. `{port}` is replaced with the configured upstream MCP port.
4. Set the working directory and any environment values.
5. Enter the local HTTP port used by the MCP endpoint or bridge.
6. Choose Local only, Tailnet, or Public Funnel.
7. Choose a unique path such as `/mcp/dev`.
8. Optionally enable exclusive AI access and add one access key for every AI connection.
9. Start the profile.

## Exclusive AI access

When exclusive access is enabled, MCP Controller starts a localhost gateway on the profile's gateway port. Tailscale exposes the gateway instead of the upstream MCP server.

Each AI must use a different generated key as its `Authorization: Bearer` token:

1. The first valid AI key to send a request receives the lease.
2. Requests from that key continue to reach the upstream MCP server.
3. A different key receives HTTP `409 Conflict` with a JSON-RPC implementation error:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32001,
    "message": "Connection in use. Please wait for user confirmation, then retry.",
    "data": {
      "retryable": true,
      "state": "waiting_for_user_confirmation"
    }
  }
}
```

4. The waiting AI appears in MCP Controller with Approve and Deny controls.
5. Approval transfers the lease. The waiting AI must retry its request.
6. The lease can also be released manually, by a successful MCP session DELETE, by inactivity timeout, or when the profile stops.

Gateway Bearer keys are consumed by MCP Controller and are not forwarded to the local upstream server. Requests with an `Origin` header are rejected unless the exact origin is listed in the profile. The listener binds only to `127.0.0.1`.

The gateway forwards Streamable HTTP POST and DELETE requests. It returns `405 Method Not Allowed` for optional SSE GET streams, which is allowed by the MCP Streamable HTTP specification. Server-initiated messages that require a standalone SSE GET stream are not supported in this development build.

## Exposure cleanup

The controller uses path-scoped Tailscale commands. Stopping or deleting a profile runs the matching `off` command for that profile’s HTTPS port and mount path. It intentionally does not run `tailscale serve reset`, `tailscale funnel reset`, or `tailscale down`, because those commands could remove unrelated Tailscale configuration.

Funnel supports public ports `443`, `8443`, and `10000`. Multiple profiles can share an HTTPS port when each uses a unique mount path.

## Security

Public Funnel endpoints are internet-accessible. Enable exclusive access, use a unique high-entropy key per AI, and review every waiting connection before approval.

Access keys currently live in the local profile file in Application Support. Do not commit or paste that file into Notion. Keychain-backed storage, code signing, notarization, health checks, complete SSE proxying, and real-device security testing remain required before the first stable release.

The app is currently unsigned.

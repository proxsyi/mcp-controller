# MCP Controller

MCP Controller is a native macOS app for managing local MCP server processes and exposing their HTTP endpoints through Tailscale only when needed.

## What it does

- Add and remove MCP server profiles without hard-coding specific servers.
- Point each profile at an executable, arguments, working directory, environment, and local HTTP port.
- Start and stop each process independently.
- Keep a server local, expose it only to the tailnet, or publish it through Tailscale Funnel.
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
- Xcode 16 or the matching Swift 6 toolchain
- Tailscale CLI for tailnet or Funnel exposure
- An MCP server that listens over HTTP, or a separate stdio-to-HTTP MCP bridge

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
3. Add one command-line argument per line. `{port}` is replaced with the configured local port.
4. Set the working directory and any environment values.
5. Enter the local HTTP port used by the MCP endpoint or bridge.
6. Choose Local only, Tailnet, or Public Funnel.
7. Choose a unique path such as `/mcp/dev`.
8. Start the profile.

## Exposure cleanup

The controller uses path-scoped Tailscale commands. Stopping or deleting a profile runs the matching `off` command for that profile’s HTTPS port and mount path. It intentionally does not run `tailscale serve reset`, `tailscale funnel reset`, or `tailscale down`, because those commands could remove unrelated Tailscale configuration.

Funnel supports public ports `443`, `8443`, and `10000`. Multiple profiles can share an HTTPS port when each uses a unique mount path.

## Security

Public Funnel endpoints are internet-accessible. Authentication must be enforced by the MCP HTTP server or its bridge. Keep profiles local while configuring them, avoid storing secrets in arguments, and use environment values only on the Mac where the app runs.

The app is currently unsigned. Code signing, notarization, authentication policy, health checks, and a controlled stdio bridge are planned before the first stable release.

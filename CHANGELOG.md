# Changelog

## 0.7.9 — 2026-07-30

- Added a separate five-minute public MCP request timeout, configurable per protected profile from 1 to 60 minutes.
- Added explicit Apply & Restart confirmation for edits to running profiles.
- Added `mcpctl --restart` support for terminal saves and key changes on active profiles.

- Kept running-profile edits as local drafts until restart is confirmed, preventing saved configuration from diverging from the active process.
- Return HTTP 504 when a public request times out before response data starts, and close already-streaming responses cleanly at the deadline.

## 0.7.8 — 2026-07-30

- Moved process inspection, readiness polling, gateway startup, Tailscale routing, and termination work off the main actor.
- Cached Tailscale DNS lookups and removed duplicate route work during individual starts.
- Preserved sequential bulk lifecycle behavior while keeping the menu bar and terminal controller responsive.
- Made restart completion wait for actual process termination and retained immediate managed-quit cleanup.
- Verified individual Release and Release All controls disconnect leases without stopping servers, and verified reconnect after release.
- Added an all-profile gateway/public validation matrix and repaired stale diagnostics.
- Validated all fifteen running profiles; fourteen non-active profiles passed 28 gateway/public surfaces while MacOS System was validated through the active controller connection.
- Recorded that Developer ID notarization remains blocked by missing Apple Developer credentials.

## 0.7.7 — 2026-07-30

- Added a Release All control beside Start Everything.
- Added a per-server circular lease-release control beside Start/Stop.
- Queued bulk start and stop operations so servers transition sequentially.
- Made stop-all wait for each managed process or adopted listener to terminate before continuing.
- Added `mcpctl lease-release-all` and updated bulk lifecycle terminal responses.


All notable changes to MCP Controller are documented here.

## Unreleased

### Fixed
- Prevented routine `mcpctl` commands from activating or focusing the MCP Controller window; explicit `open` and `settings` commands still bring up the requested UI.
- Added 15-second SSE keepalives for compatibility session streams so Notion and Tailscale do not discard healthy idle Mac MCP connections.
- Exempted long-lived GET session streams from the bounded public tool-request deadline.
- Extended the installed Visual, AppleScript, and Remote bridge session timeouts from 10 minutes to 24 hours.

## v0.7.6

### Added
- Expanded `mcpctl` so the terminal can create profiles, print remote URLs, manage access keys, inspect leases and pending requests, approve or deny waiting clients, reset Tailscale CLI paths, open Settings, and trigger update checks or installs.
- Documented the full terminal command surface, including the export-edit-save workflow for editing any profile field from Terminal.

### Fixed
- Corrected the GitHub Actions release workflow so tag builds resolve the tagged commit before publishing a release.
- Limited automatic GitHub release publishing to tag-triggered workflow runs so version bumps on `main` no longer race the release step.

## v0.7.5

### Added
- Added a Start Everything control to the menu bar beside Stop Everything so every configured profile can be launched in one action.

### Documentation
- Refreshed the README with the current clone path, profile workflow, bridge patterns, terminal controls, validation commands, security boundaries, and managed shutdown behavior.
- Expanded the MCP server role guide to cover all fifteen configured profiles and the hosted OAuth bridge pattern.

## v0.7.4

### Fixed
- Closed the public gateway socket immediately after a complete initialize response was flushed.
- Prevented the next request from entering the brief interval between the HTTP response boundary and the upstream TCP close event.
- Allowed `notifications/initialized` to reach a fresh gateway connection instead of receiving a proxy-generated HTTP 502.

## v0.7.3

### Fixed
- Closed each upstream HTTP connection after its single proxied MCP response.
- Prevented Tailscale from reusing an initialize backend connection that the gateway was still draining.
- Fixed the first post-initialize request failing with HTTP 502 while the following request opened a fresh connection.
- Treated an already-exited adopted process as a successful stop instead of a failure.

## v0.7.2

### Fixed
- Added a generic compatibility acknowledgement for JSON-RPC notifications after successful upstream delivery.
- Returned the MCP-required HTTP 202 response immediately instead of allowing proxy timeouts to become HTTP 502 errors.
- Drained the upstream notification response without blocking the remote client.
- Kept the validation report running when a timed-out request produced no body file.

## v0.7.1

### Fixed
- Made exclusive gateway shutdown synchronous before a server restart.
- Waited for the old gateway listener to release its port before binding a replacement.
- Prevented rapid stop/start and adopted-listener restarts from failing with `NWError 48: Address already in use`.

## v0.7.0

### Added
- Added `mcpctl` terminal control for server lifecycle, profiles, logs, routes, leases, Funnel, and global policy.
- Added complete redacted server configuration snapshots at every start.
- Added gateway protocol and request diagnostics for remote-client validation.

### Fixed
- Made initialize protocol bridging resilient to split and chunked upstream responses.

## v0.6.9

### Fixed
- Added a generic per-session MCP protocol bridge for compatibility mode.
- Preserved the upstream protocol version internally while presenting the client-requested dated protocol version to strict hosted clients.
- Rewrote subsequent `MCP-Protocol-Version` headers back to each session’s negotiated upstream version.

## v0.6.8

### Fixed
- Framed compatibility SSE responses with valid HTTP/1.1 chunked transfer encoding.
- Disabled intermediary buffering and response transformation so endpoint events flush immediately through reverse proxies.
- Prevented hosted clients from reporting generic SSE fetch failures after successful authentication and initialization.

## v0.6.7

### Fixed
- Made compatibility mode normalize outbound MCP `Accept` headers to include both `application/json` and `text/event-stream`.
- Adapted strict remote clients without changing upstream MCP servers or weakening strict mode when compatibility is off.

## v0.6.6

### Fixed
- Made compatibility mode reconstruct canonical public endpoints after any path-prefix reverse proxy strips the external mount.
- Added standard `X-Forwarded-Prefix` support with the profile mount path as a safe fallback.
- Preserved query strings and already-canonical paths in compatibility handshakes.

## v0.6.5

### Fixed
- Kept the Remote URL copy button enabled while the shared Tailscale Funnel is running.
- Limited the live-route lock to editable audience, HTTPS port, and route-path controls instead of disabling the entire Remote access grid.

## v0.6.4

### Fixed
- Mapped Tailscale-stripped route roots to each server’s actual Streamable HTTP endpoint.
- Detected the default `/mcp` endpoint used by servers configured with `--transport streamable-http`.
- Added chunked HTTP request decoding so HTTP/2 requests forwarded by Tailscale Funnel validate correctly.
- Replaced buffered SSE forwarding with a raw streaming proxy and kept upstream MCP streams open.
- Preserved canonical public URLs such as `/mcp/macos` and `/mcp/remote` without requiring an extra `/mcp` suffix.

### Added
- Regression tests for explicit and inferred MCP route mapping.
- Tests for chunked request bodies, chunk extensions, and incomplete chunks.
- End-to-end MCP health diagnostics covering processes, ports, routes, Funnel state, authentication, and initialize responses.
- A macOS permission reset helper for rebuilding and reinstalling the controller.

## v0.6.3

### Changed
- Tightened the Setup, Access, and Activity tabs so each one only contains settings that belong there.
- Made Local behavior tiles directly editable and reduced oversized settings blocks.
- Let Remote access directly control each server’s Tailscale route settings.
- Folded gateway-specific advanced controls into Access control and simplified Activity to logs only.
- Updated the top-right server actions to render as separate circular buttons.

## v0.6.2

### Fixed
- Corrected the bundled app version so in-app updates no longer reinstall a 0.6.0 build.
- Added GET handling in the exclusive gateway for remote MCP stream requests.

### Changed
- Condensed Exposure settings into compact cards and removed the oversized remote summary block.

### Added
- Native SwiftUI macOS controller window and menu-bar controls.
- Add, edit, duplicate, start, stop, and remove MCP server profiles.
- Local-only, tailnet-only, and public Funnel exposure modes.
- Exact path-level Tailscale cleanup when stopping or removing a server.
- Persistent local configuration, environment variables, bounded logs, and startup delay.
- macOS packaging script, command-generation tests, and GitHub Actions build artifact.
- Native Liquid Glass controls on macOS 26 with a macOS 14–15 material fallback.
- Clear-glass status surfaces, morphing start/stop actions, fluid section transitions, hover feedback, and running-state motion.
- Reduced Motion support and a simplified process, exposure, and logs workflow.
- Built-in localhost MCP gateway with an exclusive per-server AI lease.
- Unique Bearer access keys for reliably identifying separate AI connections.
- Retryable JSON-RPC connection-in-use responses and an in-app approval queue.
- Manual lease release, denial, automatic inactivity expiry, origin validation, and gateway tests.

### Changed
- Reorganized server configuration into three focused sections.
- Increased spacing and target sizes for a cleaner macOS-native layout.
- Updated the build pipeline to Xcode 26 for Liquid Glass APIs.
- Tailscale routes target the exclusive gateway when it is enabled instead of exposing the upstream MCP server directly.

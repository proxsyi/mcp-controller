# Changelog

All notable changes to MCP Controller are documented here.

## Unreleased

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

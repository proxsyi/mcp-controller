# MCP server roles

Use the narrowest server that directly matches the task. Product-specific servers keep their product names; broad system servers use functional names.

| Name | Main use | Prefer it when |
|---|---|---|
| **MacOS System** | Shell, files, processes, diagnostics, and semantic macOS interaction | The task needs terminal access, source files, logs, processes, or Accessibility elements |
| **MacOS Visual** | Screenshot-driven desktop interaction | The task is visible but lacks reliable semantic UI metadata |
| **MacOS AppleScript** | Structured Apple application automation | The task needs AppleScript access to a supported macOS application |
| **MacOS Remote** | VNC-based remote desktop control | The target is a remote session; do not use it for the active local console |
| **Chrome DevTools** | Browser inspection and debugging | The task needs DOM, network, console, performance, or Chrome runtime information |
| **Lighthouse** | Web quality audits | The task needs performance, accessibility, SEO, or best-practice scoring |
| **Playwright** | Browser testing and automation | The task needs repeatable browser flows, assertions, or cross-page testing |
| **BrowserMCP** | Browser-profile control through its companion extension | The task needs browser automation in a Chrome profile after the extension is installed |
| **ReactBits** | React components and motion references | The task needs implementation-ready React UI or animation patterns |
| **OpenPencil** | Editable interface design automation | The task needs structured visual design artifacts or design-system work |
| **Context7** | Current library documentation | The task needs version-specific API references or current code examples |
| **Google Stitch** | UI generation and design-to-code workflows | The task needs Stitch projects, screens, variants, design systems, or assets |
| **Supabase** | Supabase projects, databases, authentication, and functions | The task needs Supabase schema, SQL, migrations, logs, branches, or Edge Functions |
| **Cloudflare** | Workers and Cloudflare infrastructure | The task needs Workers, Pages, KV, R2, D1, queues, routes, zones, or related services |
| **PostHog** | Product analytics and experimentation | The task needs events, funnels, insights, feature flags, experiments, replay, or PostHog error data |
| **Sentry** | Application errors and debugging | The task needs Sentry organizations, projects, issues, events, traces, or Seer analysis |
| **Serena** | Semantic code navigation and editing | The task needs repository-aware symbol discovery, references, structured edits, or project memories |
| **WCGW** | Shell, file, and coding workflows | The task needs a second general terminal/coding path or redundancy for system operations |
| **Desktop Commander** | Terminal, process, search, and unrestricted file tools | The task needs broad desktop-terminal operations through its explicitly accepted dependency-risk profile |

## Selection order

1. Use a product-specific server when the requested system is named.
2. Use **Context7** for current framework or library documentation.
3. Use **Playwright**, **Chrome DevTools**, or **Lighthouse** according to whether the task is testing, inspection, or auditing.
4. Use **MacOS AppleScript** for supported structured app data.
5. Use **MacOS System** for terminal, files, diagnostics, and semantic desktop interaction.
6. Use **MacOS Visual** only when visual targeting is necessary.
7. Use **Serena** for semantic repository work; use **WCGW** or **Desktop Commander** only when their broader terminal/file capabilities are the direct fit.
8. Use **MacOS Remote** only for an intentional remote/VNC session.

## Remote-service bridge

PostHog and Sentry use their official hosted MCP services through `mcp-remote@0.1.38`. MCP Controller then provides the local process lifecycle, exclusive gateway, Tailscale Funnel route, and client-specific Bearer key.

Provider OAuth sessions remain under `~/.mcp-auth`. They are separate from the Bearer keys used to access MCP Controller's public routes.

## Validation

For every new profile:

1. Confirm the configured process remains running.
2. Initialize against the local endpoint.
3. Initialize against the public Funnel route with the profile's client Bearer key.
4. List tools.
5. Run one non-destructive representative tool.
6. Connect the external client only after all checks pass.

`scripts/test-mcp-servers.py`, `scripts/check-mcp-stack.py`, and the profile-specific diagnostics provide repeatable checks. Never assume a successful process launch proves the public MCP route works.

## Current controller state — August 8, 2026

- Published GitHub release: `v0.8.10` build 37 from `36682ca` / tag `v0.8.10`. Local `main` and `origin/main` are at `387a048`.
- Installed app: one signature-verified `/Applications/MCP Controller.app`, version `0.8.11` build 38.
- All **19 configured profiles** report `Running`; the full Swift suite passed **82 tests with 0 failures**.
- The installed menu-bar **Auto Release** toggle owns a single loop running `while true; do ~/.local/bin/mcpctl release-all; sleep 60; done` until disabled or the managed app quit path stops it. It releases active AI leases and does not stop profiles.
- MacOS System was restored after a local Python environment failure by running `/opt/homebrew/bin/uv sync --reinstall-package macos-mcp` in its server project; the Controller itself did not require a code change.
- BrowserMCP (`@browsermcp/mcp@0.1.3`) and Playwright (`@playwright/mcp@0.0.79`) passed authenticated initialization. BrowserMCP needs its companion Chrome extension for browser-profile control.
- Serena `1.6.1`, WCGW `5.6.4`, and Desktop Commander `0.2.46` remain unrestricted at the operating-system capability level by explicit decision. Controller Bearer authentication, exclusive leases, Origin checks, request deadlines, and route controls remain enabled.
- Desktop Commander's 13 high and 1 moderate audited dependency findings remain an explicitly accepted exception. Serena and WCGW had zero known dependency findings in their audited environments.
- OpenPencil remains deferred pending its reachable advisory and live-canvas/font work.

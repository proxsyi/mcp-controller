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
| **ReactBits** | React components and motion references | The task needs implementation-ready React UI or animation patterns |
| **OpenPencil** | Editable interface design automation | The task needs structured visual design artifacts or design-system work |
| **Context7** | Current library documentation | The task needs version-specific API references or current code examples |
| **Google Stitch** | UI generation and design-to-code workflows | The task needs Stitch projects, screens, variants, design systems, or assets |
| **Supabase** | Supabase projects, databases, authentication, and functions | The task needs Supabase schema, SQL, migrations, logs, branches, or Edge Functions |
| **Cloudflare** | Workers and Cloudflare infrastructure | The task needs Workers, Pages, KV, R2, D1, queues, routes, zones, or related services |
| **PostHog** | Product analytics and experimentation | The task needs events, funnels, insights, feature flags, experiments, replay, or PostHog error data |
| **Sentry** | Application errors and debugging | The task needs Sentry organizations, projects, issues, events, traces, or Seer analysis |

## Selection order

1. Use a product-specific server when the requested system is named.
2. Use **Context7** for current framework or library documentation.
3. Use **Playwright**, **Chrome DevTools**, or **Lighthouse** according to whether the task is testing, inspection, or auditing.
4. Use **MacOS AppleScript** for supported structured app data.
5. Use **MacOS System** for terminal, files, diagnostics, and semantic desktop interaction.
6. Use **MacOS Visual** only when visual targeting is necessary.
7. Use **MacOS Remote** only for an intentional remote/VNC session.

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

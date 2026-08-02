# MCP server roles

Use the narrowest server that directly matches the task. Product-specific servers keep their product names; broad system servers use functional names. MCP Controller manages each process, gateway, route, and lease independently; a running process alone does not prove that its protected public MCP surface works.

For current branch, validation, and release state, see [Development status](DEVELOPMENT_STATUS.md).

## Configured inventory

The current organized inventory contains 18 real server profiles. Headings and spacers are organization records and must not be counted, launched, routed, or validated as servers.

| Name | Main use | Prefer it when |
|---|---|---|
| **MacOS System** | Shell, files, processes, diagnostics, and semantic macOS interaction | The task needs terminal access, source files, logs, processes, or Accessibility elements |
| **MacOS Visual** | Screenshot-driven desktop interaction | The task is visible but lacks reliable semantic UI metadata |
| **MacOS AppleScript** | Structured Apple application automation | The task needs AppleScript access to a supported macOS application |
| **MacOS Remote** | VNC-based remote desktop control | The target is an intentional remote session; do not use it for the active local console |
| **Chrome DevTools** | Browser inspection and debugging | The task needs DOM, network, console, performance, or Chrome runtime information |
| **Lighthouse** | Web quality audits | The task needs performance, accessibility, SEO, or best-practice scoring |
| **Playwright** | Browser testing and automation | The task needs repeatable browser flows, assertions, navigation, or cross-page testing |
| **ReactBits** | React components and motion references | The task needs implementation-ready React UI or animation patterns |
| **OpenPencil** | Editable local design canvas and design-file automation | The task needs structured visual design artifacts or design-system work |
| **Context7** | Current library documentation | The task needs version-specific API references or current code examples |
| **Google Stitch** | UI generation and design-to-code workflows | The task needs Stitch projects, screens, variants, design systems, or assets |
| **Supabase** | Supabase projects, databases, authentication, and functions | The task needs Supabase schema, SQL, migrations, logs, branches, or Edge Functions |
| **Cloudflare** | Workers and Cloudflare infrastructure | The task needs Workers, Pages, KV, R2, D1, queues, routes, zones, or related services |
| **PostHog** | Product analytics and experimentation | The task needs events, funnels, insights, feature flags, experiments, replay, or PostHog error data |
| **Sentry** | Application errors and debugging | The task needs Sentry organizations, projects, issues, events, traces, or Seer analysis |
| **Serena** | Semantic code navigation and project-aware source analysis | The task needs symbol discovery, references, project activation, memory, or non-destructive semantic code inspection |
| **WCGW** | General agent shell and computer-workflow execution | The task needs its isolated command/session model rather than the local macOS semantic bridge |
| **Desktop Commander** | Direct desktop filesystem, process, and command operations | The task needs Desktop Commander's specific execution or file-management surface |

## Selection order

1. Use a named product-specific server when the requested system is explicit.
2. Use **Serena** for project-aware semantic source inspection and symbol navigation.
3. Use **Context7** for current framework or library documentation.
4. Use **Playwright**, **Chrome DevTools**, or **Lighthouse** according to whether the task is testing, inspection, or auditing.
5. Use **MacOS AppleScript** for supported structured Apple-app data.
6. Use **MacOS System** for terminal, local files, diagnostics, and semantic desktop interaction.
7. Use **Desktop Commander** or **WCGW** only when their distinct execution model is required.
8. Use **MacOS Visual** only when visual targeting is necessary.
9. Use **MacOS Remote** only for an intentional remote/VNC session.

## Remote-service bridges

PostHog and Sentry use official hosted MCP services through `mcp-remote@0.1.38`. MCP Controller provides the local bridge lifecycle, exclusive gateway, Tailscale Funnel route, and client-specific Bearer key.

Provider OAuth sessions remain under `~/.mcp-auth`. They are separate from the Bearer keys used to access MCP Controller's protected public routes.

Other profiles may use stdio-to-HTTP bridges, package-manager launchers, or direct Streamable HTTP processes. Wrapped processes can expose a different child command than the configured launcher. MCP Controller therefore identifies a distinctive configured command or script rather than treating generic launchers such as `node`, `npx`, or `python3` as sufficient ownership proof.

## Organization rules

- Headings and spacers persist in the same ordered profile store but are not servers.
- Server counts, ports, routes, lifecycle operations, validation, and diagnostics must filter to `kind == server`.
- The main sidebar and menu-bar list should preserve the same heading, spacer, and server order.
- Drag-and-drop is disabled while search filtering is active so filtered indices cannot corrupt the canonical order.
- The sidebar is bounded to a readable width so names and controls do not collapse into an icon-only strip.

## Validation state

### Verified OpenPencil pass

At branch head `930c096` on the MacBook Pro:

- focused process-adoption tests passed 5/5;
- the full Swift test suite passed 75/75;
- the production app built, used stable local signing, and installed successfully;
- OpenPencil reported `Running`;
- upstream HTTP listened on `127.0.0.1:4114`;
- its WebSocket listened on `127.0.0.1:7601`;
- the protected controller gateway listened on `127.0.0.1:39008`.

This verified that the Controller can adopt the npx-launched OpenPencil child from its generated npm-cache executable path.

### Required validation for every profile

1. Confirm the configured process remains running or is correctly adopted.
2. Confirm its upstream local port is owned by the intended process.
3. Confirm the exclusive gateway is listening on the profile's configured gateway port.
4. Initialize through the local gateway using the intended client Bearer key.
5. Initialize through the public Tailscale route.
6. Send `notifications/initialized` using a semantically valid success path.
7. List tools.
8. Run one explicitly non-destructive representative tool.
9. Release the test lease so the real external client can reconnect.
10. Repeat enough calls to detect session, keepalive, timeout, or reconnect failures.

Useful entrypoints:

```bash
python3 scripts/validate-all-profiles.py
python3 scripts/test-mcp-servers.py
python3 scripts/check-mcp-stack.py
bash scripts/check-notion-validation.sh
bash scripts/run-mcp-health-check.sh
```

Some older diagnostics remain machine-specific or duplicate validation logic. Treat `validate-all-profiles.py` as the primary matrix entrypoint and verify script inputs before relying on older helpers.

## Serena release proof

Before merging or releasing, establish one fresh uninterrupted Serena session:

1. `tools/list`;
2. `activate_project` with `/Users/cashm/Projects/personal/folder/notion-bridge`;
3. one additional non-destructive Serena call;
4. repeated safe calls without restarting MCP Controller, Serena, the gateway, Tailscale route, or lease.

The release proof is incomplete until this sequence and the broader matrix pass on the latest installed build.

## Current release boundary

The source branch includes controller-owned fixes for gateway/session behavior, lifecycle recovery, serialized Tailscale mutations, terminal readiness, optional origins, npx child adoption, full-screen popover behavior, and sidebar width. OpenPencil is verified, but the later full-screen and sidebar fixes still require installation and live validation on the MacBook Pro.

Do not merge PR #3, tag, or publish a release until the latest build passes installed-app UI checks, the complete local/public MCP matrix, Serena continuity, signature/Gatekeeper accounting, packaged-asset checksum verification, and released-build retesting.

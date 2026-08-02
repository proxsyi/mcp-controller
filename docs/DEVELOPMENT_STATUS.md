# MCP Controller development status

Last updated: 2026-08-01

This is the canonical repository status document. Functional code commits and later documentation-only commits are tracked separately so a documentation update does not make the recorded source state stale.

## Release state

- Latest published release: `v0.8.3` (build 30) from `main` at `99e96d02c1c379f4e1803758851e8e7181d6e946`.
- Active branch: `fix/menu-bar-count-and-stability`.
- Latest functional code change: `3f88a0373a84df6292db5e4f55f0c0a0ae5cf4fa` — prevents organized sidebar rows from collapsing.
- Later branch commits update documentation only; use `git log -1 --oneline` for the current branch tip and confirm that history contains `3f88a03`.
- Draft PR: #3. It must remain draft and unmerged until every installed-app and live MCP release gate below passes.
- No new tag or release has been published from this branch.
- Tagged release automation requires configured Developer ID signing and publishes `SHA256SUMS.txt` with the app archive.

## Documentation inventory

All authored project documentation has been audited and synchronized:

- `README.md` — product scope, correct MacBook Pro path, installation, terminal commands, validation, lifecycle, and security/release boundaries.
- `CHANGELOG.md` — verified OpenPencil recovery, current unreleased fixes, pending UI validation, and remaining release gates.
- `docs/DEVELOPMENT_STATUS.md` — this canonical source/validation/release record.
- `docs/MCP-SERVER-ROLES.md` — all 18 configured server roles, organization semantics, validation workflow, OpenPencil evidence, and Serena release proof.
- Draft PR #3 — implementation summary, verified state, pending work, and guardrails.
- Notion page `MCP Controller — Current Development Status` — active workspace status record replacing deleted temporary logs.

The two old temporary Notion pages are already in Trash and remain deleted. The protected `MCP Failure Log` remains untouched.

## Verified in the latest completed local pass

The completed MacBook Pro pass ran at branch head `930c0965c391d05916ff65866722a1ae0427b96b`:

- Focused `PortInspectorTests`: 5/5 passed.
- Full `swift test`: 75/75 passed with zero failures.
- Production build completed.
- The app was signed with the stable local `Session Pinger Signing` identity.
- The app was installed at `/Applications/MCP Controller.app`.
- `mcpctl status OpenPencil` reported `Running`.
- OpenPencil process adoption was verified against the npm-cache executable shape.
- OpenPencil upstream HTTP listened on `127.0.0.1:4114`.
- OpenPencil WebSocket listened on `127.0.0.1:7601`.
- The controller gateway listened on `127.0.0.1:39008`.

This proves the OpenPencil launch failure was Controller process-identification drift, not an OpenPencil package failure. The Controller now recognizes an npx-launched command when the actual child executable appears as a full npm-cache path whose basename matches the configured command.

## Implemented after that verified pass

These functional fixes are committed but still require installation and live validation on the MacBook Pro:

1. `cfa8f2fd2241db9612b3169aedf7f40aed53d006` — promotes the status popover to a popup-level full-screen auxiliary window that can join all Spaces, remain visible while another application is active, and appear over a full-screen application.
2. `3f88a0373a84df6292db5e4f55f0c0a0ae5cf4fa` — gives the main `NavigationSplitView` sidebar a bounded 260–420 point width and balanced split behavior so headings, names, descriptions, links, and action controls do not collapse into an icon-only strip.

The attempted installation of the full-screen fix did not execute. The command was entered on `Cashs-MacBook-Air`, but the repository exists on `Cashs-MacBook-Pro` at `/Users/cashm/Projects/Clients/Versyi/MCP-Controller`. The initial `cd ... || exit 1` failed and closed the SSH session before fetch, tests, build, or installation. Therefore the continued full-screen popover failure does not validate or disprove the patch; that build was never installed on the Pro.

## Broader branch work completed

- Restored the live running-server count beside the menu-bar icon.
- Mirrored headings, spacers, and server ordering in the menu-bar dropdown.
- Added persistent drag-and-drop organization and terminal organization commands.
- Kept routine terminal commands background-only.
- Repaired the background profile-save crash and serialized persistence.
- Preserved real gateway ports when headings and spacers are present.
- Hardened HTTP framing, compatibility initialization, notification handling, optional discovery fallbacks, and session keepalives.
- Moved optional fallbacks behind authentication and lease authorization.
- Added bounded recovery for persistent processes and failed gateway listeners.
- Serialized Tailscale route/Funnel mutations off the main actor with bounded command deadlines and rollback.
- Fixed the bundled `mcpctl` readiness predicate to rely on the control queue rather than a false-negative process probe.
- Changed empty Allowed origins from hidden deny-all behavior to disabled origin filtering, matching the optional UI field.
- Added npm-cache child-process adoption for npx-launched servers.
- Prevented the main sidebar from shrinking below a readable width.
- Added full-screen Space behavior to the menu popover.
- Hardened build/release workflows with versioned artifacts, checksums, and mandatory real signing for tagged releases.

## Configured server inventory

There are 18 real server profiles:

1. MacOS System
2. MacOS Visual
3. MacOS AppleScript
4. MacOS Remote
5. Chrome DevTools
6. Lighthouse
7. Playwright
8. ReactBits
9. OpenPencil
10. Context7
11. Google Stitch
12. Supabase
13. Cloudflare
14. PostHog
15. Sentry
16. Serena
17. WCGW
18. Desktop Commander

Headings and spacers are organization records, not servers. Counts, routes, lifecycle work, validation, and diagnostics must filter to real server profiles.

## Current release blockers

The branch must not be merged or released until all of these pass on the MacBook Pro with the current branch tip:

1. Pull, test, build, install, and launch the branch on the Pro.
2. Confirm the sidebar remains readable at the minimum supported window width and after resizing.
3. Confirm the menu-bar popover opens over full-screen Notion without switching Spaces.
4. Confirm menu-bar running count, headings, spacers, ordering, drag-and-drop, persistence, quit responsiveness, and background terminal behavior.
5. Run the complete MCP profile matrix through local gateways and public Tailscale routes.
6. Prove one uninterrupted Serena session with `tools/list`, `activate_project` for `/Users/cashm/Projects/personal/folder/notion-bridge`, another non-destructive call, and repeated calls without restarting the app, route, gateway, or lease.
7. Recheck the priority profiles: Serena, WCGW, Desktop Commander, Playwright, Supabase, macOS System, OpenPencil, Chrome DevTools, Cloudflare, PostHog, and Sentry.
8. Recheck app signature and account for Gatekeeper assessment. Developer ID/notarization remains unavailable unless valid Apple release credentials are configured.
9. Only after all gates pass: update version/build metadata, merge PR #3, tag, publish the signed archive and checksum, verify the release asset digest, retest the released build, and reconcile status records.

## Validation entrypoints

```bash
python3 scripts/validate-all-profiles.py
python3 scripts/test-mcp-servers.py
python3 scripts/check-mcp-stack.py
bash scripts/check-notion-validation.sh
bash scripts/run-mcp-health-check.sh
```

`validate-all-profiles.py` is the primary matrix entrypoint. Some older diagnostics are machine-specific or duplicate older assumptions; inspect their inputs before treating them as release evidence.

## Correct MacBook Pro install command

Run from a Terminal session on `Cashs-MacBook-Pro`:

```bash
cd "/Users/cashm/Projects/Clients/Versyi/MCP-Controller" || exit 1
git fetch origin
git switch fix/menu-bar-count-and-stability
git pull --ff-only origin fix/menu-bar-count-and-stability
git log -1 --oneline
git log --oneline --all | grep -E '3f88a03|cfa8f2f|930c096'
swift test || exit 1
pkill -f "/Applications/MCP Controller.app/Contents/MacOS/MCPController" 2>/dev/null || true
sleep 2
bash scripts/install-local.sh || exit 1
open -gj -a "/Applications/MCP Controller.app"
sleep 10
"$HOME/.local/bin/mcpctl" list --timeout 15
```

The current branch tip may be a documentation commit. The required functional history must include `930c096`, `cfa8f2f`, and `3f88a03`.

## Record rules

- Keep PR #3 draft and unmerged until every release gate passes.
- Do not restore obsolete temporary Notion logs merely to update them.
- Never edit or delete the protected `MCP Failure Log`.
- Keep the active Notion status page synchronized after each new validation or release milestone.

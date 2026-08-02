# MCP Controller development status

Last updated: 2026-08-01

## Release state

- Latest published release: `v0.8.3` from `main` at `99e96d02c1c379f4e1803758851e8e7181d6e946`.
- Active branch: `fix/menu-bar-count-and-stability`.
- Current documented branch head: `3f88a0373a84df6292db5e4f55f0c0a0ae5cf4fa`.
- Draft PR: #3. It must remain draft and unmerged until the installed-app and live MCP release gates below pass.
- No new tag or release has been published from this branch.
- Tagged release automation now requires configured Developer ID signing and publishes `SHA256SUMS.txt` with the app archive.

## Verified in the latest completed local pass

The local pass completed on the MacBook Pro at branch head `930c0965c391d05916ff65866722a1ae0427b96b`:

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

This proves the OpenPencil launch failure was controller process-identification drift, not an OpenPencil package failure. The controller now recognizes an npx-launched command when the actual child executable appears as a full npm-cache path whose basename matches the configured command.

## Implemented after that verified pass

These fixes are committed but still require installation and live validation on the MacBook Pro:

1. `cfa8f2fd2241db9612b3169aedf7f40aed53d006` — promotes the status popover to a popup-level full-screen auxiliary window that can join all Spaces, remain visible while another application is active, and appear over a full-screen application.
2. `3f88a0373a84df6292db5e4f55f0c0a0ae5cf4fa` — gives the main `NavigationSplitView` sidebar a bounded 260–420 point width and balanced split behavior so headings, names, descriptions, links, and action controls do not collapse into an icon-only strip.

The attempted install of the full-screen fix did not execute: the command was entered on `Cashs-MacBook-Air`, but the repository exists on `Cashs-MacBook-Pro` at `/Users/cashm/Projects/Clients/Versyi/MCP-Controller`. The initial `cd` failed and `exit 1` closed that SSH session. Therefore the continued full-screen popover failure does not disprove the patch; that build was never installed on the Pro.

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
- Changed empty Allowed origins from hidden deny-all behavior to disabled origin filtering, matching the UI's optional field description.
- Added npm-cache child-process adoption for npx-launched servers.
- Hardened build/release workflows with versioned artifacts, checksums, and mandatory real signing for tagged releases.

## Current release blockers

The branch must not be merged or released until all of these pass on the MacBook Pro with the current branch head:

1. Pull, test, build, install, and launch the current branch on the Pro.
2. Confirm the sidebar remains readable at the minimum supported window width and after resizing.
3. Confirm the menu-bar popover opens over full-screen Notion without switching Spaces.
4. Confirm menu-bar running count, headings, spacers, ordering, drag-and-drop, persistence, quit responsiveness, and background terminal behavior.
5. Run the complete MCP profile matrix through local gateways and public Tailscale routes.
6. Prove one uninterrupted Serena session with `tools/list`, `activate_project` for `/Users/cashm/Projects/personal/folder/notion-bridge`, another non-destructive call, and repeated calls without restarting the app, route, gateway, or lease.
7. Recheck the priority profiles: Serena, WCGW, Desktop Commander, Playwright, Supabase, macOS System, OpenPencil, Chrome DevTools, Cloudflare, PostHog, and Sentry.
8. Recheck app signature and account for Gatekeeper assessment. Developer ID/notarization remains unavailable unless valid Apple release credentials are configured.
9. Only after all gates pass: update version/build metadata, merge PR #3, tag, publish the signed archive and checksum, verify the release asset digest, retest the released build, and reconcile the tracking pages.

## Documentation and page rules

- `README.md`, `CHANGELOG.md`, this file, PR #3, the temporary bug ledger, and the temporary SVMG failure log should reflect this state.
- The protected Notion page `MCP Failure Log` must not be edited or deleted.
- The temporary tracking pages must not be deleted until validation and release are complete and deletion is still requested.

## Correct MacBook Pro install command

Run this from a Terminal session on `Cashs-MacBook-Pro`:

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

Expected head at the time this status was written: `3f88a03 fix(sidebar): prevent organized rows from collapsing`.

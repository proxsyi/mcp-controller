# MCP server roles

| Name | Main use | Best at | Prefer over others when |
|---|---|---|---|
| **Mac OS System** | Semantic desktop and shell control. | Terminal work, diagnostics, Accessibility-tree inspection, element-aware interaction | The task needs source, processes, logs, files, or semantic UI elements |
| **Mac OS Visual** | Visual desktop automation. | Screenshots, coordinates, windows, image matching, mouse and keyboard paths | The task is visible but lacks reliable semantic UI metadata |
| **Mac OS Apps** | Structured Apple app access. | Reading and searching supported Apple-app records by container or ID | The task concerns Notes, Calendar, Reminders, or other supported app data |
| **Mac OS Remote** | Remote desktop control. | VNC screenshots and input against a reachable remote Mac | The target Mac is remote or VNC behavior itself must be tested |

## Selection order

1. Use **Mac OS Apps** for structured Apple-app data.
2. Use **Mac OS System** for terminal, diagnostics, files, and semantic UI.
3. Use **Mac OS Visual** for arbitrary visual interaction and image-based targeting.
4. Use **Mac OS Remote** only when the target is a remote/VNC session.

## Test coverage

`scripts/test-mcp-servers.py` independently checks each configured profile's exact name and description, local or public MCP initialization, initialized notification, tool inventory, required capabilities, and one safe representative tool call.

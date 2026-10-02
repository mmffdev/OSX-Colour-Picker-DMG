# MMFFDev Colour Picker

macOS colour picker app. v1 in the root, `v2/`, `v3/` (current work, branch `v3-palettes-projects-sync`). Build: `v3/build.sh`; installers: `v3/make_dmg.sh`, `v3/make_pkg.sh`.

## Vector backlog — the only place this repo's work goes

| | |
|---|---|
| Workspace | `de3bfb2c-9f1b-4c4a-bf75-bc872e32b1bd` |
| Node | `R26GHQXV` (all existing items sit in node id `e51fc096-70b2-4b42-bc06-79c70b1e08bb`) |
| Runway | PR-21 — MMFFDev - Colour Picker |
| Objective | OB-75 — MMFFDev - Colour Picker - OSX |
| Themes | TH-242 Feature List · TH-243 Core Architecture |

Same values as `.mcp.json` (`VECTOR_MCP_REPOSITORY_WORKSPACE` / `_NODE`) — that file is the source of truth; update both together.

### Check before every Vector write

The local Vector connection does NOT read the `.mcp.json` values. It lands in whichever workspace the Platform backend's `.env.dev` names in `MCP_DEV_TRUSTED_WORKSPACE_ID`. So before creating, moving or archiving anything:

1. Search for `PR-21`. It must come back titled "MMFFDev - Colour Picker".
2. If it does not, STOP. You are in another product's workspace (usually Vector's own, `04d19b01-…`, where the runways are PR-7 Vector, PR-9 Orbit, PR-10 Platform). Tell Rick; do not write.

New work goes under OB-75, never under a new runway.

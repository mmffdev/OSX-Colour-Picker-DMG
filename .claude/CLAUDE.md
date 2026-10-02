# MMFFDev Colour Picker

macOS colour picker app. v1 in the root, `v2/`, `v3/` (current work, branch `v3-palettes-projects-sync`). Build: `v3/build.sh`; installers: `v3/make_dmg.sh`, `v3/make_pkg.sh`.

## Vector backlog — the only place this repo's work goes

Since 2026-10-02 this repo's work lives in the workspace the local Vector connection actually reaches (Vector's own), under a runway of its own:

| | |
|---|---|
| Runway | PR-23 — MMFFDev - Colour Picker |
| Objective | OB-80 — Colour Lab (cLab) |
| Themes | TH-260 Colour Lab Tools · TH-261 Colour Lab Foundations · TH-262 Colour Lab Future Ideas |
| Node | `c9b6ca76-522d-44dc-9402-ec797f49ec97` |

A new area of the app gets a new objective under PR-23, never a new runway.

### Check before every Vector write

The local Vector connection does NOT read the `.mcp.json` values. It lands in whichever workspace the Platform backend's `.env.dev` names in `MCP_DEV_TRUSTED_WORKSPACE_ID`. So before creating, moving or archiving anything:

1. Search for `PR-23`. It must come back titled "MMFFDev - Colour Picker".
2. If it does not, STOP. The connection has been pointed at another workspace. Tell Rick; do not write.

Vector refuses titles that look like code ("cLab"), descriptions that do not open "As a …", and anything without "As proven by …" acceptance criteria.

### The original home (not reachable from here)

Earlier items sit in the Colour Picker workspace `de3bfb2c-9f1b-4c4a-bf75-bc872e32b1bd`, node `R26GHQXV` (node id `e51fc096-70b2-4b42-bc06-79c70b1e08bb`): runway PR-21, objective OB-75, themes TH-242 Feature List and TH-243 Core Architecture. `.mcp.json` still names that workspace (`VECTOR_MCP_REPOSITORY_WORKSPACE` / `_NODE`). Nothing has been moved across; if the connection is ever pointed back there, decide with Rick which home wins before writing.

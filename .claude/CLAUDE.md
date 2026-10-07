# MMFFDev Colour Picker

macOS colour picker app (MMFFDev Colour 3). The source is at the repository root; the two earlier apps were removed on 2026-10-02 and live only in git history. Build: `./build.sh` (compiles, runs the self-test, installs); installers: `./make_dmg.sh`, `./make_pkg.sh`. Day to day, open `Colorgain.xcodeproj` at the root in Xcode and Cmd+R: it builds a real signed bundle (Info.plist, icon, Sparkle, the helper, the commit stamped) into DerivedData and runs it, rebuilding only what changed; the installed app still comes from `./build.sh`. The project is generated from `project.yml` by XcodeGen and committed: after adding or removing a `.swift` file, run `xcodegen` at the root and commit the project with the file. `Package.swift` stays the definition `build.sh` compiles. To see the app as a brand-new user, launch it with `--new-user` (in Xcode: Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments, tick it for the run) or run `tools/open.sh new` for the installed app (a throwaway home, never your data; add `permissions` to make macOS ask again); `tools/open.sh me` opens it as you. Xcode's Cmd+R copy is signed with the Developer ID like the installed one, so permissions and chosen folders hold between builds; the scheme carries `--new-user`, `--studio` and `--self-test` unticked under Edit Scheme ▸ Run ▸ Arguments.

## The name is Colorgain

Since 2026-10-07 the app is called **Colorgain**, spelled exactly so: one word, capital C, American "Color". Every new piece of user-facing text says Colorgain. "MMFFDev Colour 3" is the old name; it survives only where renaming is a migration (the bundle and executable names, the Application Support folder, the bundle identifier, the Sparkle feed, the installers, the Store product identifiers) and goes when the rename feature in Vector is done. The rest of the app's own words keep British spelling ("colour"); only the name is American.

## The look is Colorgain's own

Since 2026-10-07 the app is being redesigned in a Swiss style it owns: Helvetica Neue, a 12-column grid, big light type over small dense type, ink on warm paper, no macOS control drawn where the guide draws its own. Before any screen, read `.claude/c_design_guide.md` and only the child it points to for the part in hand; its five laws, baseline justification first, apply to every screen.

## Build after every commit

After every commit, run `./build.sh` so the installed app is the last commit. Commit first, then build: the build stamps the commit's short hash into the app, and the window's footer shows it at the bottom right as "Release v3.0  3f48079". A "+" after the hash means the build was made with uncommitted Swift changes. If Rick cannot see a change, compare that hash with `git log -1` before anything else.

## Vector backlog — the only place this repo's work goes

Since 2026-10-02 this repo's work lives in the workspace the local Vector connection actually reaches (Vector's own), under a runway of its own:

| | |
|---|---|
| Runway | PR-23 — MMFFDev - Colour Picker |
| Objectives | OB-80 Colour Lab (cLab) · OB-81 Colour Tools · OB-82 Export And Handover · First Run And Permissions · Launch And Sales · History And Project Files · Colour Management And Proofing |
| Themes | TH-260 Colour Lab Tools · TH-261 Colour Lab Foundations · TH-262 Colour Lab Future Ideas · TH-263 Contrast And Typography · TH-264 Export Templates (also holds the app-format and Adobe work) · Setup And Permissions · Selling And Licensing · Updates And Health · Launch Page And Help · Project Files · History Rail · History Storage And Settings · Project Overview And Swatch Notes · The Master Colour · Channels And Proofs · Print Conditions And Approved Values · Video, Three-Dimensional Work And Delivery · Image Files, Gamma And Lookup Tables · Palette Pages And Views (under Colour Tools) |
| Node | `c9b6ca76-522d-44dc-9402-ec797f49ec97` |

A new area of the app gets a new objective under PR-23, never a new runway.

### Check before every Vector write

The local Vector connection does NOT read the `.mcp.json` values. It lands in whichever workspace the Platform backend's `.env.dev` names in `MCP_DEV_TRUSTED_WORKSPACE_ID`. So before creating, moving or archiving anything:

1. Search for `PR-23`. It must come back titled "MMFFDev - Colour Picker".
2. If it does not, STOP. The connection has been pointed at another workspace. Tell Rick; do not write.

Vector refuses titles that look like code ("cLab"), descriptions that do not open "As a …", and anything without "As proven by …" acceptance criteria.

### The original home (not reachable from here)

Earlier items sit in the Colour Picker workspace `de3bfb2c-9f1b-4c4a-bf75-bc872e32b1bd`, node `R26GHQXV` (node id `e51fc096-70b2-4b42-bc06-79c70b1e08bb`): runway PR-21, objective OB-75, themes TH-242 Feature List and TH-243 Core Architecture. `.mcp.json` still names that workspace (`VECTOR_MCP_REPOSITORY_WORKSPACE` / `_NODE`). Nothing has been moved across; if the connection is ever pointed back there, decide with Rick which home wins before writing.

## The Studio window (the redesign of the app itself)

`StudioWindow.swift` is the main window on Colorgain's own grid (`Design.App`): header, library rail, context rail, page, history rail, footer, all placed by frame and drawn in the ten text styles. It opens in place of the old window with `--studio` (`tools/open.sh studio`); `--palettes` opens on the palettes view and `--palette "<name>"` on that palette. Built 2026-10-08 for the library and palettes views only; Lab, Contrast and the palette page's options still live in the old window.

## What the product is

A full enterprise colour management and proofing system for 2D, 3D, video, graphic design and print. Hex is never the primary promise. The definition, the master colour design and the reasoning are in `COLOUR-MANAGEMENT.md` at the repository root: read it before any work on colour. The ideas list is `scratch.md`.

## Type scale

`TextSize` in Helpers.swift is the only source of font sizes for UI text: `body` 13 for anything read (notes, names, fields, controls), `caption` 11 for labels over fields and captions, `title` 20 for a page title. Never below 11. Text painted inside swatch tiles is sized to fit and is the one exception. Every UI label starts with a capital.

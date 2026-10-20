# Colorgain checkpoint: linked assets and Lightroom metadata

Saved 17 October 2026 before starting the read-only Lightroom metadata plug-in.

## Installed app

Verified `/Applications/Colorgain.app`: version 3.0, build 357, release `06e4b29+`, built 17 October 2026 at 09:59 BST. `/tmp/colorgain-linked-build.log` records **1,296 passed, 0 failed** and successful installation. Changes are uncommitted. Preserve unrelated work in the dirty working tree; do not reset or commit it implicitly.

The earlier work was implemented, built and installed. Subsequent Lightroom experiments changed sample assets only, not the installed application.

## Implemented in that build

- Rail1 Import panel advertises artefact types; Palettes and ASE are wired. Missing ASE buckets require confirmation and are added only to the chosen branch, not every schema.
- Linked palettes use normal library cards, palette pages and analysis, with link indicators and an orange reference header.
- Edit permission uses a closed/open lock pill. Rename and picker targeting are gated; native palette edits write back to the original with revision checks and transactional rollback.
- Native files carry `header.editControl`; other formats use a sibling `<full filename>.colcar`. A shared `.colguard` coordinates Colorgain claims and writes. Normal termination releases claims; crash recovery is deferred.
- Session memory records rail/panel placement and state. Details and verification status live in [.codex/c_workspace_startup.md](.codex/c_workspace_startup.md).

Implementation contract: [.codex/c_workspace_import.md](.codex/c_workspace_import.md). Main source areas: `WorkspaceImport.swift`, `Projects.swift`, `CatalogueTree.swift`, `PaletteView.swift`, and `FileHandlers/Handler_File_Edit_Access.swift`.

## Outstanding earlier work

- Finish installed-app visual verification of reference cards, orange header, lock/unlock and picker guards. Previous verification was interrupted by concurrent user interaction. Passing automated tests does not establish this UX verification.
- Replace the flattened import destination selector with the familiar workspace tree, filtered by chosen file type, retaining real catalogue identities and supporting multiple destinations. Do not assume fixed client/project structures or expose irrelevant bucket children. Audit the current implementation before resuming because other sessions may have changed it.
- Full revision capture, historical binary storage, history browsing and restore-as-independent-copy are **not implemented**. The history container is a foundation only.
- Restore-as-copy must create a new asset identity with source asset/revision provenance; it must not rewind the shared original.
- Crash/stale-claim recovery, expiry and administrative takeover are deferred. Shared-volume behaviour has not been validated on a real SMB share. Colorgain claims are cooperative, not locks enforced by Lightroom or the OS.
- Non-native palette reference editing needs lossless write adapters; those references remain viewable but cannot be unlocked for unsupported writes.

## Lightroom evidence

Source folder: `/Users/rick/Documents/Trips - Iceland/2018 - Iceland/Snaps`.

1. **0027 external XMP:** Colorgain changed Exposure from +0.25 to +1.25 and added three fields in `urn:colorgain:metadata:1.0:`. Lightroom read the edit and later saved Exposure -1.55. All custom fields survived. CR2 bytes were unchanged.
2. **0028 embedded CR2:** after a full backup, Colorgain updated the existing 8,192-byte XMP allocation at offset 46,600 to Exposure +2.25. Every byte outside that allocation was unchanged. Lightroom read +2.25 successfully.
3. **0028 Lightroom writeback:** Lightroom created an external XMP containing Exposure +1.25 and copied the custom Colorgain fields into it. The CR2 stayed byte-for-byte identical to Colorgain's embedded-write state. Disabling automatic XMP writing does not switch Lightroom to embedded CR2 writes.
4. **0028-Rendered.dng:** the new DNG already contained all three custom fields embedded, with Exposure 0.00 and no external XMP. Colorgain changed embedded Exposure to +2.00, then added `colorgain:colorgain="XXXXX"`. Both edits were backed up and verified to preserve every byte outside XMP and all unrelated XMP properties. Lightroom writeback preservation of this new field is still awaiting verification.

These results apply to the tested files and Lightroom Classic 15.5.1. They do not guarantee arbitrary custom metadata survives every application, export or future version. Preserving unknown XMP does not mean Lightroom understands Colorgain history or locks.

Backups and manifests: `/Users/rick/Pictures/Colorgain_Test/Colorgain Metadata Test/`:

- `20261017-102422`: original and written 0027 sidecars.
- `20261017-103039-embedded-0028`: original CR2, detached original sidecar, written embedded packet, catalogue snapshot and hashes.
- `20261017-103937-dng-0028`: DNG baseline including main image payload hashes.
- `20261017-104044-dng-exposure`: full DNG backup before +2.00.
- `20261017-104152-dng-custom-field`: full DNG backup before XXXXX.

Earlier catalogue investigation lives in `/tmp/colorgain-lightroom-audit-20261017/`. Lightroom stores develop history in its catalogue, not the ordinary XMP current-state recipe. In the examined catalogue, 14 compressed history snapshots totalled 25,535 bytes, not 14 full RAW copies. Temporary audit files are evidence, not durable product storage.

## Next: read-only Colorgain Lightroom plug-in

Rick approved a readable Colorgain view inside Lightroom Classic. At this checkpoint, no plug-in has been created or installed.

First scope: explicitly refresh selected photos, read embedded/sidecar Colorgain XMP, and display friendly fields in Lightroom's Metadata panel. Keep source assets read-only. Lightroom plug-in metadata lives in its catalogue, so the bridge must populate it from file metadata; declaring an XMP namespace alone does not expose fields in Lightroom.

Show the custom value XXXXX, originating application, test ID, test note, actual metadata source and refresh status. Distinguish stale catalogue display values from current file data. Missing files, malformed XMP and unsupported formats need explicit status. Do not imply that proposed asset/revision fields already exist.

Add editing and conflict handling only in a later agreed scope. This plug-in is separate from the Colorgain application build.

References: [Lightroom SDK](https://developer.adobe.com/lightroom-classic), [Adobe metadata behaviour](https://helpx.adobe.com/in/lightroom-classic/desktop/organize-photos-in-lightroom-classic/metadata-basics-actions.html), [Custom Metadata Panel project](https://github.com/adobe-dmeservices/custom-metadata).

## Update: Lightroom plug-in implemented

The read-only prototype has now been created, compiled and installed at `/Users/rick/Library/Application Support/Adobe/Lightroom/Modules/Colorgain.lrplugin`. Source and usage: [tools/lightroom/README.md](tools/lightroom/README.md).

Lightroom 15.5.1 accepted version 0.1.0.1 with no diagnostic messages. A real refresh of 0028.CR2 populated its native Metadata panel with our fields and the external XMP source. The helper reads XXXXX from the test DNG. Dedicated tagset selection and DNG display still need a hands-on check. This separate plug-in build did not rebuild or replace Colorgain build 357. Asset files were not changed by the plug-in work.


## Update: 18 October, import tree and shared menubar

- Import destinations use the shared workspace branch tree after choosing a file type. Command-click/Shift-click supports multiple destinations. Group headings and locked owners cannot be selected. Typed asset leaves are filtered, retaining actual owner IDs and paths to nested matching buckets.
- Palettes and ASE support one atomic batch across all selected destinations. Missing buckets are listed for confirmation; shared templates stay unchanged.
- File > Import Assets > artefact type opens the shared form in a modal. The import section also offers Import Workspace (`.coldata`) and Import Catalogue (`.colcat`). Preserve every unrelated File command and its shortcut, including creation, picking, catalogue, sync, exports and legacy migration. There is no separate top-level Import menu.
- `WorkspaceImport.swift` owns the type list, form, import submenu, picker routing and transactions. Future types remain visible but not connected.
- Regression cases cover tree projection, independent copies, reference deduplication, multi-destination rollback and stale selections. Keyboard navigation skips unselectable rows; long bucket confirmations scroll.

Rick authorised the combined build. The final integrated build passed **1,307 tests, 0 failures**, installed at `/Applications/Colorgain.app` and relaunched with timestamp **18 October 2026, 19:40 BST**, release `06e4b29+`, build 357. The earlier reduced File menu was a mistake; every unrelated command and shortcut is now restored and verified in the running app. Log: `/tmp/colorgain-menus-build.log`. No commit was made.

## Update: Catalogue, Assets and Metadata menus

The three new main menus are installed. Catalogue routes to management, schema, member creation, search, sync and library export. Assets offers the shared import submenu, creation, Finder reveal, duplicate, favourite, rating, flag, delete and export actions. Metadata routes to Tags and the displayed palette's tag editor. Planned workflows inspired by Lightroom include smart collections, missing assets, image adjustments, stacking, previews, virtual copies, IPTC, keywords, metadata presets, XMP exchange and asset history. All unavailable command leaves are disabled and prefixed `! `. No image editing or metadata-writing engine was added by this menu work.

Native verification confirmed the restored File list, all three new menus, live Catalogue/Tags navigation, context-sensitive palette enablement and Assets > Import Assets > Palettes opening the shared modal. Its corrected title and tree-heading contrast were visually checked. Palette multi-destination selection survives cancelling its native file picker; Escape closes the modal. The rail ASE selector exposes the same actual tree, skips non-destination headings with keyboard navigation and warns when a selected owner needs an ASE bucket. No test imports or schema changes were made to the user's live catalogue. Returned to the original palette, leaving Assets open for inspection.

## Update: 18 October, grid selection and group commands

- Shared asset grids now use identity-based selection: plain click selects, Shift extends a range in visible order, Command toggles membership, and Command-A selects all. Arrow keys and Shift-arrow ranges work too. Plain selection no longer opens a preview; double-click opens the asset. Existing import checkboxes remain supported.
- Each viewport footer centres `N of M Selected`. Selection survives reordering and is pruned when filtering removes items.
- The new control left of Filter by Meta orders by name, creation date, modification date or capture date. Unknown dates remain last. This treats the requested Name/Date choices as ordering; name/date-range filtering was not added.
- Existing compatible commands use the active pane's selected group: palette duplicate, favourites, ratings, flags, tags, Finder reveal, copy and exports, plus palette/swatch/member deletion. Confirmation text names the count. Linked-asset and owner edit locks remain enforced. Unsupported image deletion and other planned `!` commands remain unavailable; design-pack export still requires one asset.
- The shared selection engine has regression coverage for toggling, reversed ranges, reordered ranges, filtering and missing anchors. Ordering tests cover natural names and unknown dates.

Built, installed and relaunched `/Applications/Colorgain.app`: **18 October 2026, 20:08 BST**, build **357**, release **06e4b29+**. **1,315 tests passed, 0 failed**. Log: `/tmp/colorgain-grid-selection-build.log`. No commit was made.

Live verification confirmed Shift-arrow range selection, count retention after Name A–Z ordering, `41 of 41 Selected` after Command-A, and a counted `Delete 3 Palettes` confirmation. Cancelled deletion without changing catalogue assets. Left ten cards selected with `10 of 41 Selected` visible. Command-click transitions are covered by the shared selection tests; native modifier-click automation was unavailable. Screenshot: `/tmp/colorgain-grid-selection-verified.jpg`.


## Update: 18 October, shared asset groups

`WorkspaceGroups.swift` centralises group records, index writes, membership actions, manager panel and modal, editor, branch picker, native menu and settings. An asset can belong to several groups. Grouping references the same original and never creates a copy or writes membership into the asset payload.

- Scopes: Global, My Library, Catalogue and Selected Branches. The last uses the actual workspace tree with Command/Shift multiselection and member-qualified bucket identities, including when branches share a schema template. User-facing terminology stays generic.
- Global and My Library records live in `.coldata`; catalogue/branch records live in `.colcat`. The same Global group and members appear under each applicable typed parent. Ungrouped is computed locally.
- Rail1 manager starts below Library. Native Groups menu offers Create, Manage and Settings. Context/halo actions accept selected palettes; group tree drops add references and Ungrouped drops remove applicable memberships. Group counts and slider editing controls use the existing tree renderer.
- The macOS-style Settings window > Library & Data > Groups hides all entry points when disabled, retaining records and leaving only Activate Groups in the native menu. The accidentally introduced legacy in-page Groups page and route were removed. Project guidance now explicitly requires the current native Settings window.
- Ownership changes migrate reference identities within the existing file transaction; a workspace alias map resolves older references held by other catalogue indexes. Connected remote and linked palettes resolve to their originals; missing sources retain their memberships.
- Palettes and Typography are wired. Schema asset-parent capability supports extending the same model to other asset types later.

Create/Edit Group now uses the existing Studio colour picker for an optional group border. It encloses the group and expanded children in the tree and outlines the group viewport. Clear Colour removes it. This is index metadata, not an asset edit.

The core Groups build passed **1,340 tests** and was installed at `/Applications/Colorgain.app`, build 357, release `06e4b29+`, **18 October 2026, 22:31 BST**. Native menu/Create Group were inspected. Live checking found the house dropdown needs its `changed` callback and the Name field needs explicit theme colours; both source fixes are included.

The subsequent colour-border/native-Settings build compiled and ran **1,342 tests**, with two timestamp round-trip comparison failures. Group timestamps now normalise to the file format’s millisecond precision; an isolated 10,000-round-trip check had zero mismatches. The next full rebuild stopped because another session modified `Schema.swift` at **22:44:11 BST** during compilation, adding catalogue structure/terminology fields. Per the concurrent-edit rule, Rick was asked whether to rebuild including that work or wait.

**Pending:** authorised combined rebuild, full self-tests, installed identity check, native Groups settings enable/disable test, branch-picker multiselection, colour-picker Select/Clear/cancel and border visual verification. The currently installed 22:31 build does not contain these final source fixes, colour borders or the native Settings move. No commit was made. Build log: `/tmp/colorgain-groups-build.log`.

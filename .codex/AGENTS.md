# Colorgain — Codex working guidance

App layout lookup: [Component registry](c_layout_registry.md) — canonical region names, hierarchy, source symbols and panel primitive. Read it before locating or changing app sections.

## Design authority

Adapted from `.claude/CLAUDE.md`, `c_design_guide.md`, `c_c_c_design_grid_app.md`, `c_c_design_layout.md`, `c_c_design_type.md` and `c_c_design_controls.md` on 2026-10-10. Use these rules before editing any native UI. Keep Codex guidance project-local here. Current explicit user instructions override reference rules.

## App grid

Use `Design.App`, never approximate its columns. Reference window 1440 × 900: 12 columns, outer margins 24, column gutters 16, header 64, footer 48. Area gutters are 32 after columns 3, 5 and 8; history's gutter remains 16. Page columns come from `Design.App.pageColumns`.

Rail1 occupies columns 1–3, Rail2 4–5, page 6–10, history 11–12 (expanded workspace; settings collapses Rail1). Closed rails give their space to the page. Do not alter protected header/divider positions. Align overlay edges to their owning control and underlying columns. Derive geometry from the current window, not screenshot pixels.

## Alignment and spacing

- Text on a horizontal row shares a baseline; use `.lastBaseline`, or `.bottom` for blocks. Never centre mixed-height text rows.
- Text starts on its column edge; numbers and actions end on the block's right edge.
- Adjacent columns align their first capital lines, measured from the fonts.
- Use a four-point rhythm: 4, 8, 12, 16, 24, 32, 48, 64, 96. Within groups 8–16; between groups 48–96.
- Dynamic text has fixed-height boxes so changing content cannot shift the grid beneath it.
- Empty columns are intentional. Fit copy to the space before moving margins.
- Explicit header exception: Rick requested icons optically centred with navigation text, with the rightmost glyph flush to the outer grid. Search, history, spacer, settings, window actions, all in the same ink.

## Type and controls

Use `Design.Text` styles (Helvetica Neue, Helvetica/Arial fallback), not ad-hoc system-font substitutions. Body 13, caption 13, and 13-point minimum for readable UI text; body strong Medium; section headers use the existing Header style. `TextSize` governs reading sizes; never below 11. Bold is reserved for the wordmark. Use `Design` colours; do not inherit macOS button text colours on custom light surfaces.

Text action buttons use the All Workflows reference: a leading diagonal arrow, left-aligned medium label and an underline beneath the label only. `ActionButtonSkin` is the shared renderer for SwissButton, ThemedButton and older ActionButton forms. No default boxes, fills, trailing arrow cells or centred labels. Group text actions from the left edge of their owning column; keep disabled, hover, pressed and keyboard-focus feedback. Icon controls, selection chips, tabs, sliders and pagination retain their semantic affordances. Dropdowns and panels keep square corners, without stock bezels. Control rows are 32 points. Menus use Card, Rule separators and Mist hover. Every actionable row/icon needs hover feedback, pointing-hand cursor and accessible naming. Keep section headings away from panel edges with measured padding; search dropdown titles align above the star column and use the page heading style and first heading baseline. Favourites precede recent searches with a divider.

## Verification and builds

Inspect the rendered result, including baseline, spacing, clipping and contrast, before declaring layout complete. Backslash toggles the native grid overlay. Check current branch/build target before building; Store code uses `./make_appstore.sh`, direct download `./build.sh`. Preserve existing trial data when launching: `--new-user --resume-new-user --no-splash`; never restart a trial with `--new-user` alone. Do not commit unless requested; after a Swift commit follow the project's build requirements.

## Workspace startup and development sessions

Startup resolves `.coldata` before its `.colcat` catalogue list; existing workspaces never enter new structure questions. Missing/access-denied entries remain recoverable. The implementation and launch commands are in [c_workspace_startup.md](c_workspace_startup.md). `--dev-on` / `--dev-off` persist the machine-local Development menu toggle; it defaults off and must remain off for first clean-build verification. Automatic resume requires completed setup and a valid last catalogue.

## `<swiss>` — project design skill

When Rick types `<swiss>` (for example, `<swiss> design me Tags`), apply this project-local Swiss design skill. It also governs settings-page work. Keep its authority here, not in global skills or configuration.

- **Visual master:** Settings > Halo on the normal app background. `SettingsSheet` in StudioSettings.swift is the shared stylesheet; use its title, index, section and divider helpers. Change shared styles once, never introduce per-page replicas.
- **Page title:** the large in-content title (Halo., Shortcuts., Tags., Catalogues., Schema.), 48-point Helvetica Neue Light via `titleStyle`. Its baseline is the second strong content guide (45 points), using the shared content origin. This is separate from the small protected `AreaHeader` above the app-wide divider; leave that header unchanged.
- **Index:** always a large two-digit number in the left pane. One fixed style and size for all numbers: `SettingsSheet.indexStyle` and `indexSize` (80-point regular). Never resize indices to fit individual sections. Align the visible top to the first right-pane section heading (`// Name`), using the next strong heading baseline and measured glyph bounds (see Rule 1 below).
- **Columns:** use `Design.App.pageColumns`. The left pane holds the index; the right pane holds working content. Keep labels and controls aligned to those column edges. Preserve square corners and black swatch borders.
- **Dividers:** 3-point ink rules span the page content width. Their bottom edge sits on the chosen grid guide: draw the thickness above the guide, never below. Section spacing derives from `Design.App.unit` (28), `gutter` (16) and `textBaseline` (17), not screenshot coordinates. Allow a full grid gap after the final control/row before the next divider.
- **Action balance:** derive button placement from the text baseline and reserve whole grid rows around actions. Grid anchors take precedence over the obsolete 24-point free-positioned gap.
- **Colour:** normal `Design.card` page ground. House yellow is `Design.houseYellow`, #F4BE00, for navigation selection panes; do not make pages yellow unless requested.
- **Verification:** inspect all changed pages and editing/selection hit areas in the installed native app, including scrolling. Toggle the backslash grid to check alignment. Preserve existing data and controls. Use the Store build on Store branches.

### Rule 1 — the visible grid is the authority

The earlier fractional Halo measurements were wrong as a design rule. Never propagate them, introduce a composition lift, or align a new page to another page without verifying both against the overlay.

- Source: `GridOverlay.draw` and `Design.App`. Content origin = app header + AreaHeader.height. The overlay draws a faint row-edge guide at `n * 28` and a strong text baseline at `n * 28 + 17`, in content-local points. At the reference window the content origin is (510,173) pt; scale by backingScaleFactor for screenshot pixels.
- Single-line text sits **above** a strong guide with its baseline on it. The page title baseline is row 1 (45 pt), intro heading row 0 (17 pt), intro description row 1 (45 pt). No glyph-top fitting may move these baselines. For multi-line paragraphs, anchor the FIRST LINE BASELINE to the strong grid line beneath that line, not the top of the text container. Use `SettingsSheet.paragraph`, which measures the actual text-layout first baseline. Subsequent lines follow normal paragraph leading within a fixed box.
- Section divider bottom = a strong guide (first 73 pt). The right heading baseline = the next strong guide (101 pt). The fixed 80-pt index shares the heading's visible top, measured from its glyph bounds; every section uses this same relationship. X remains from page columns: index x=0, right pane x=468 at the 906-pt reference content width.
- Lists and trees begin on faint row edges, use 28-pt rows, and draw text at row top +17 exactly like Rail 1. Schema's map starts at 224 pt; its first baseline is 241 pt. Level marks, names, counts, actions, row dividers, selection strips and elbow connectors must derive from that same row rect. Never shift only the labels. Scroll offsets naturally move these guides; verify at scroll origin.
- Inline controls and action glyphs centre on the text's optical centre (baseline minus 5 for body text), never the row-box centre. Buttons retain their house style, but their frames derive from the intended text baseline and measured font metrics. Swatches and reset icons share this optical centre.
- Thick rules grow upward from their strong guide. Thin list rules occupy the final point before the next faint row edge. All repeated sections keep the same phase, regardless of their height.
- Panel bounds follow the page columns and centre gutter. Row rules fill the panel, not its text inset. Selection grounds stay between the rules; they never cover the preceding divider.
- Verify with the grid on in the installed app: title/intro, every section heading, first and last list rows, controls, connectors and divider edges. Compare Schema and Shortcuts rows horizontally with Rail 1. A successful build does not verify geometry. Leave the app open after verification.

### Schema safety gate

Schema locks on each entry unless `Prefs.schemaSafetyLockDisabled` is explicitly saved. Keep the title and 48-point right padlock clear; blur and intercept the content below `SettingsSheet.headerGuide`. Reuse `SwissSlide`; incomplete travel must not unlock. Save the checkbox opt-out only after full travel. The open padlock restores protection and the default for future visits. Disable editors as well as intercepting pointer events; preserve keyboard/VoiceOver slider access and reduced-motion support.

### Settings rails and Schema scrollbars

Settings replaces Rail 1 with the diagonal grey/white cover immediately, without animation. Escape restores the pre-settings page (after cancelling any active shortcut recording). The Settings gear and menu resume the last settings section selected in this window; the Catalogues rail item still opens Catalogues explicitly. Schema rows keep full-width rules but inset their contents by a gutter; scrollbar tracks occupy separate gutters, never overlay the row actions. All app scroll views use FittedScrollView and the shared QuietScroller: house-yellow handles in a reserved 16-point gutter, never over the document. Page scroll frames extend into the outer margin to preserve canvas grid width. Short documents pass wheel events to their parent without bouncing.

### Selection ribbon primitive

Use `SelectionRibbon` in Design.swift for setup, Rail 2 and Schema yellow row panels: 14-point head, 10-point left notch, head entry 0.48 seconds, tail starts at 0.56 seconds and takes 0.30 seconds. `Rollover` owns row state and the shared clock; preserve the bottom divider and honour Reduce Motion. Do not copy the ribbon path or timing into individual pages.

### App manifest and key profiles

`AppDataStore` is the single atomic reader/writer of `colorgain.coldata` in the chosen app home. It migrates `catalogues.json` while retaining the original backup, preserves unknown manifest fields and refuses to overwrite invalid/newer data. Portable settings use `AppPreferences`; folder access, bootstrap location and OS permission state remain machine-local. `KeyProfiles` owns `Keys/*.colkeys`, versioned names/descriptions and both shortcut maps; the manifest's relative `keys` reference survives moving the home. Never overwrite an existing profile on import. `SwissFocusModal` owns the shared blurred backdrop, square shadowed card, Escape and focus restoration; forms use this instead of bespoke overlays.

### Global Assets and catalogue exchange

`AppHomeSeed` creates the manifest, Keys/default.colkeys, Assets pools/index, Global.colhis and Catalogues before new catalogue construction. App-wide unassigned assets live under app-home `Assets/{Palettes,Typography,Swatches,Profiles}`; member-owned assets stay inside their catalogue schema. `LibraryStore` composes the scopes for UI and splits saves. `AssetTransaction` journals both stores and recovers interrupted moves; commit the journal before deleting snapshots. Migration preserves the original catalogue under Backups/Before Global Assets. Global changes apply as deltas so saving a different catalogue cannot erase newer global assets.

Whole-catalogue imports create independent catalogues, with available names and no cross-catalogue duplicate comparison. Global assets are optional in catalogue exports and unticked by default during import. Partial imports reuse matching containers and preserve unselected work. Content matches preserve order, typography and metadata; colour-set similarity is not identity. History offers Catalogue/Global viewing; Global.colhis is the app-wide activity log, while catalogue .colhis retains reversible deltas, including cross-scope ownership moves.

### Appbridge

The header Appbridge route is the file workspace: library in Rail 1, selectable ASE spectra in Rail 2 and swatches in the page. Only Settings > Appbridge uses the standard settings menu in Rail 2. Never route the header workspace to the settings form. Settings shares the Shortcuts layout: 01 Adobe and 02 Procreate, large indices, shared rules and an expanding directory-grouped Adobe file list (no inner scrollbox; later sections move down). Procreate is a disabled layout scaffold until its file handler exists. File rows open previews and offer Duplicate, Detach and Delete (shared blurred warning modal naming the actual file and path; Move File To Trash confirms filesystem deletion, Cancel preserves it). Persist detached paths on folder connections and exclude them from scans and catalogue exports; explicitly importing them reattaches them. Its separate settings route uses the connection page and shared store, participates in last-section memory, and restores the prior page on Escape. `ASERegistry` owns each catalogue’s `<name>.colase`; `AppbridgeStore` binds to the active catalogue. File and folder locations are catalogue-scoped, while grants remain machine-local in `FolderAccess`. Migrate former app-wide links once into the active catalogue. New registries are empty. Missing files retain a warning link with no cached colours, with a shared blurred Locate/Remove recovery modal. Periodic stat checks invalidate moved/deleted files without hashing unchanged contents. ASE palette drops append a named group, preserving existing blocks byte for byte; coordinate writes, reject stale digests, save a .bak under app-home Backups/Appbridge and replace atomically. Protected presets offer Save An Editable Copy. Rail drags copy into ASE without removing library palettes. Retain source components, names, groups and swatch types; previews assume sRGB/generic CMYK because ASE has no embedded ICC profile. Disable library rename/drag/halo operations on external rows. Scan on a background queue, bound input sizes, skip symlinks, and compare all previously scanned monitored sources so one source's scan cannot consume another source's notification. Monitoring runs while the app is running. Ask for macOS notification permission only when its toggle is enabled.

Appbridge leads with New ASE File, Import ASE File and Connect Bucket Folder for user-owned libraries. Creation starts from Rail 2’s Create New ASE or Settings: focus a blank title field with a blinking block cursor; Return opens a folder picker labelled Save. Cancel keeps the draft name. Save never replaces an existing file, registers it in the active catalogue and selects it; no connected folder is required. Import opens the file picker immediately, without a bucket prerequisite or save dialog, and remembers each selected file in place. Export A Copy on the file page saves elsewhere without changing the original. Adobe-folder discovery is removed; existing connections remain user-controlled. New files are valid empty ASE libraries, immediately selected in Rail 2 and ready for palette drops.

Catalogue seeding and loading create `Library/ASE` plus `<catalogue-name>.colase`; the registry follows catalogue renames. New ASE files default to Library/ASE, or a user-chosen destination. External links are not copied on attachment. Existing AppBridge/ASE payloads migrate without deleting the original. Export selects registered files by directory, with group/all toggles, and harvests only checked bytes into Library/ASE alongside a portable .colase. Relative paths identify bundled files; originalPath preserves suggested restore destinations. Import validates every registry link against archive payloads, defaults to keeping selected files inside the new catalogue, and can restore copies after explicit directory selection. Never overwrite existing destination files; failures retain catalogue copies and links. ASEIcon is our native document mark, applied as a Finder custom icon to created/copied files; do not inject icon bytes into the ASE format.

Appbridge settings folder controls use two grid columns, full-height outlined buttons with state/plug glyphs, and breathing room before file rows. ASE filename rows have no hover background. Directory paths have a strong Directory prefix. Newly connected folders default monitoring and notifications on; preserve stored choices. Every Settings route uses collapsed Rail 1 geometry while retaining its previous workspace width for return.

### Register rails, indexed tree, settings picker and sound previews

Rail 1 adapts Design 08 Indexed into two-row entries: favourite before the name, target before the square spectrum and Halo to its right. No index, colour-count row or internal row dividers. Elbow connectors remain implemented behind `showsTreeConnectors`, disabled by default. Its expanded width occupies three grid columns. Rail 2 uses Design 03 Register: plain rows with name, vertically centred spectrum and count on one line. Rail 1 navigation/palettes and Rail 2 palette/settings navigation use the shared grey barber-pole strip over a subtle neutral ground. It slides into the existing left gutter on hover and remains locked on the active row; preserve text geometry, row height, dividers and Reduce Motion. Other selection surfaces retain their existing treatment; no zebra stripes or orange fill/outline. Keep the 28-point row grid, selection/rename/drag geometry and ASE missing-file actions consistent with row heights. Contrast and Appbridge share the register renderer.

`StudioColourPicker` replaces the native Halo colour panel with a full-window circular spiral and settings-target rail. Single clicks preview; Select or double-click commits only the selected target; Escape/Cancel writes nothing. Restore the previous page and focus on dismissal. `SwissDropdown.onPreview` previews sounds without persisting selection; the compact Sounds selectors align with their toggle above, with a speaker test icon to the right.

A palette dropped from Rail 2 into the library tree must not navigate to its destination. Pass `reveal: false` to the controller's copy/move path; preserve this through the optional notes prompt as well as the immediate-copy path. Rail 2 remains on its source list.

Header navigation aligns with the Rail 2 title inset (half a gutter beyond the expanded Rail 1 divider), with the picker and rectangle-picker icons immediately before Library. Copy format lives left of Search in the header; the footer retains copied-swatch history and status only.

Rail 2 Overview routes carry both project and schema-node IDs. Repeated Overview rows must never share selection or rollover identity; opening a project selects only its first Overview.

Palette pages put project status in the left AreaHeader metadata slot. Their colour-count content heading shares the first Rail 1 row baseline; swatches start on the strong guide at two grid units plus the text baseline below the content origin. Apply this template to every library palette.

Search displays selectable palette, project, ASE and colour matches in its dropdown instead of filtering the page while typing. Dismissal clears the query; choosing a result records the search, clears it and navigates to the result. Colour results scroll into view. Empty queries show saved searches.

Rectangle sampling overlays use explicit global display frames, including negative screen origins, and take keyboard focus on pointer entry. Capture is clipped to the originating display; each display keeps its own scale and capture ID.

### Proofing

`Proofing.swift` keeps original D50/2° Lab, exact patch IDs, import validation, profile predictions and measured comparisons separate; `StudioProofing.swift` uses SettingsSheet and the house grid. Bundled unmodified Fogra subsets carry attribution in `ProofingResources/SOURCE.txt`. Sessions preserve data/settings; exports record provenance and user tolerances. Never describe these results as certification. Missing patches/known incompatible conditions cannot pass. RGB previews never feed comparison maths.

Rick’s chart references are retained in `.codex/references/proofing/`: `density-and-error.png` (density vs ΔE operating range and component error), `heritage-distribution.png` (a*/b* sample distribution against reference points), `grouped-distribution.png` (same projection by sample group). Density optimisation needs measured density-series data; never invent a parabola or press adjustment from Lab alone. Grouped historical charts are design references, not bundled measurement datasets.

PrePress is the only active print-workflow page. The standalone Proofing page, Patches/Setup rail and its page-specific settings/chart controls were removed on 2026-10-13. Preserve shared proof models, scientific validation and saved calibration data used by other workflows. PrePress closes Rail 1 on entry and restores its preceding width on exit; Will It Print? retains its palette selection rail and history. Never present the retained density simulation as a measured proof or press adjustment.

### Visual monitor setup

`MonitorSetupView` is the retained shared visual monitor component for a Swiss modal. `StudioMonitorSetup.swift` owns tagged-sRGB visual patterns, a borderless selected-display window, keyboard exits and machine-local per-display UUID records. Keep results explicitly unmeasured; never write ICC profiles or calibration curves from visual checks. Display changes close the full-screen window safely. Retain the existing ColorSync profile.

Proof configurations are versioned `.colcal` JSON in each catalogue's `Library/Calibrations`. Preserve reference patches, measured data, settings, notes, embedded CMYK output ICC and explicitly separate density-model assumptions. Catalogue share archives carry the complete collection and imports restore it independently; never install those ICC bytes or apply another display's visual setup. Duplicate imports receive new IDs. Configuration export starts in the active catalogue’s Library/Calibrations folder, creating it when needed; exporting directly there must not create a second internal copy. Reset only the active proof, retaining saved configurations.

Settings and PrePress use `sectionAnchors` for the fixed AreaHeader tab strip. Anchor positions come from the actual section guides; scroll to guide + 1 so every numbered heading lands consistently below the header. Add trailing document space for the last anchor. PrePress uses shared page columns with Rail 1 collapsed. Header navigation always anchors to the fully expanded Rail 1 boundary and never follows animated rail widths. Register column headers sort the complete filtered dataset before slicing All/10/25/50/100 rows; missing numeric values stay last.

Library tree drops retain both member and palette-bucket IDs. Main Library lists only unassigned app-wide palettes; project-owned copies stay in their exact schema bucket. Settings > Library uses the Swiss sheet and portable `library.copyAllBuckets`, `library.keepOriginal` and `library.keepClaimed` preferences. Defaults: selected bucket only, retain the original, no claimed copy. Turning retention off clears and hides claimed-copy creation. Optional `Swatch.bucketID` and `PaletteClaim` provenance survive palette files, sync and catalogue exchange; older palettes infer their bucket from their folder. Claimed copies are independent, two-row Library entries prefixed by project/bucket; never treat them as live linked edits.

Palette halos and Swiss cascading context menus share `HaloAction` trees. The halo's delete slider is the confirmation; `onMenuSelect` routes context deletion through the single Swiss confirmation modal. Delete/Forward Delete in either Library rail uses that modal; Shift-click and Command-click share `PaletteSelection`, with a count/halo block at Rail 1’s base for batch actions. Associated claimed copies are removed by default via the independent Library preference; cleanup matches assignment identity and catalogue provenance, preserving unrelated copies and colours. Page swatch clicks open PaletteWheel’s shared preview in modal mode, centred over the page, with expand, monitor fullscreen and close controls; Escape contracts/exits fullscreen before closing. `Overlay.handleOverlayEscape` owns staged exits.

Fullscreen retains reference-width rails and a fixed header navigation origin; additional width belongs to the page. Library Rail 2 starts closed on All Colours, lists unclaimed palettes on the palette route and scopes project branches to the selected schema node. General settings owns explicit preference reset and setup-wizard actions; completed valid workspaces resume normally, independently of the development flag. Will It Print? keeps Rail 1 collapsed and adds Rail 3 after Rail 2 on the left, with a palette-only collection/project tree; History retains its own right rail, excluding claimed copies, typography, information and tags. Selection drives the combined 01 Palette settings/result section; 02 carries the note.

App Store Apple Menubar uses one native status item, shared picker controllers, `ColourCopies` history and `Prefs.copyFormat`. Its Swiss settings, sound scoping and print bloom chart are described in [c_apple_menubar.md](c_apple_menubar.md). Do not introduce a second colour conversion, sample or sound pipeline.

Page colour hover halos dismiss immediately on scrolling, forward the gesture to their owning page scroll view, and remain suppressed until a real pointer move. Shared QR exchange details live in [c_qr_sharing.md](c_qr_sharing.md).

Saved print settings, palette Delta controls and .colpro exchange use the shared [.coldata profile workflow](c_print_profiles.md). Dropdown values and menu rows use the 13-point body style.

Header background presses use native window dragging after control hit tests. Tab hit areas cover only the icon/label band, leaving space above and below draggable. Header utility glyphs share the 18-point `HeaderUtilityIcon` square and optical centre. Help sits immediately before Settings; entry collapses Rail 1 and closes the other rails, restoring preceding rail goals on exit. Initial help content is bundled Markdown in `HelpResources`, rendered by `StudioHelpPage`; both build targets must include these resources.

The `osx-full-app` branch trials the canvas-centred Library shell. Its current region names, dimensions, integration and prototype boundaries are in [c_full_app.md](c_full_app.md); explicit new workspace instructions supersede the old rail/page allocation for this shell.

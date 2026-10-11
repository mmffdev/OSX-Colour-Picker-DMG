# Colorgain — Codex working guidance

## Design authority

Adapted from `.claude/CLAUDE.md`, `c_design_guide.md`, `c_c_c_design_grid_app.md`, `c_c_design_layout.md`, `c_c_design_type.md` and `c_c_design_controls.md` on 2026-10-10. Use these rules before editing any native UI. Keep Codex guidance project-local here. Current explicit user instructions override reference rules.

## App grid

Use `Design.App`, never approximate its columns. Reference window 1440 × 900: 12 columns, outer margins 24, column gutters 16, header 64, footer 48. Area gutters are 32 after columns 2, 4 and 8; history's gutter remains 16. Page columns come from `Design.App.pageColumns`.

Rail1 occupies columns 1–2, Rail2 3–4, page 5–10, history 11–12. Closed rails give their space to the page. Do not alter protected header/divider positions. Align overlay edges to their owning control and underlying columns. Derive geometry from the current window, not screenshot pixels.

## Alignment and spacing

- Text on a horizontal row shares a baseline; use `.lastBaseline`, or `.bottom` for blocks. Never centre mixed-height text rows.
- Text starts on its column edge; numbers and actions end on the block's right edge.
- Adjacent columns align their first capital lines, measured from the fonts.
- Use a four-point rhythm: 4, 8, 12, 16, 24, 32, 48, 64, 96. Within groups 8–16; between groups 48–96.
- Dynamic text has fixed-height boxes so changing content cannot shift the grid beneath it.
- Empty columns are intentional. Fit copy to the space before moving margins.
- Explicit header exception: Rick requested icons optically centred with navigation text, with the rightmost glyph flush to the outer grid. Search, history, spacer, settings, window actions, all in the same ink.

## Type and controls

Use `Design.Text` styles (Helvetica Neue, Helvetica/Arial fallback), not ad-hoc system-font substitutions. Body 13, caption 11, body strong Medium; section headers use the existing Header style. `TextSize` governs reading sizes; never below 11. Bold is reserved for the wordmark. Use `Design` colours; do not inherit macOS button text colours on custom light surfaces.

Square controls and panels, no rounded corners or stock bezels. Control rows are 32 points. Menus use Card, Rule separators and Mist hover. Every actionable row/icon needs hover feedback, pointing-hand cursor and accessible naming. Keep section headings away from panel edges with measured padding; search dropdown titles align above the star column and use the page heading style and first heading baseline. Favourites precede recent searches with a divider.

## Verification and builds

Inspect the rendered result, including baseline, spacing, clipping and contrast, before declaring layout complete. Backslash toggles the native grid overlay. Check current branch/build target before building; Store code uses `./make_appstore.sh`, direct download `./build.sh`. Preserve existing trial data when launching: `--new-user --resume-new-user --no-splash`; never restart a trial with `--new-user` alone. Do not commit unless requested; after a Swift commit follow the project's build requirements.

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

Settings replaces Rail 1 with the diagonal grey/white cover immediately, without animation. Escape restores the pre-settings page (after cancelling any active shortcut recording). The Settings gear and menu resume the last settings section selected in this window; the Catalogues rail item still opens Catalogues explicitly. Schema rows keep full-width rules but inset their contents by a gutter; scrollbar tracks occupy separate gutters, never overlay the row actions. Schema handles use house yellow.

### Selection ribbon primitive

Use `SelectionRibbon` in Design.swift for setup, Rail 2 and Schema yellow row panels: 14-point head, 10-point left notch, head entry 0.48 seconds, tail starts at 0.56 seconds and takes 0.30 seconds. `Rollover` owns row state and the shared clock; preserve the bottom divider and honour Reduce Motion. Do not copy the ribbon path or timing into individual pages.

### App manifest and key profiles

`AppDataStore` is the single atomic reader/writer of `colorgain.coldata` in the chosen app home. It migrates `catalogues.json` while retaining the original backup, preserves unknown manifest fields and refuses to overwrite invalid/newer data. Portable settings use `AppPreferences`; folder access, bootstrap location and OS permission state remain machine-local. `KeyProfiles` owns `Keys/*.colkeys`, versioned names/descriptions and both shortcut maps; the manifest's relative `keys` reference survives moving the home. Never overwrite an existing profile on import. `SwissFocusModal` owns the shared blurred backdrop, square shadowed card, Escape and focus restoration; forms use this instead of bespoke overlays.

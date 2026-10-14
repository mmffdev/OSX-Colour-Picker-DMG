# App layout component registry

Canonical region names for Colorgain. Start here to locate a layout section before editing it. Source mappings describe `colorgain-main`; the canvas shell currently serves Library routes selected by `StudioFrame.canvasWorkspace`. Other routes retain legacy layouts until migrated.

## Region hierarchy

```text
App
├── Header
├── Workspace (horizontal layout)
│   ├── Rail1
│   │   ├── Panel A
│   │   └── Panel B …
│   ├── Viewport
│   │   ├── Viewport-Header
│   │   ├── Viewport-Actionbar
│   │   ├── Viewport-Page
│   │   └── Viewport-Footer
│   └── Rail2
│       ├── Panel C
│       └── Panel D …
├── Carousel
└── Footer
```

Rail1, Viewport and Rail2 are siblings. The native macOS title bar and menu bar sit outside this application-content hierarchy. Panel letters illustrate movable instances, not fixed ownership.

## Source register

| Region | Responsibility | Current source / lookup symbol |
|---|---|---|
| App | Window and root layout; owns all regions | [StudioWindow.swift](../StudioWindow.swift): `StudioWindowController`, `StudioFrame`; geometry in `StudioFrame.layout()` |
| Header | Logo, navigation, picker and shared utility actions | [StudioWindow.swift](../StudioWindow.swift): `StudioHeader`, `StudioFrame.header` |
| Rail1 | Left dock; independently scrolling panel stack, scrollbar in outer left gutter | [WorkspacePanels.swift](../WorkspacePanels.swift): `WorkspaceRail`; instance `StudioFrame.leftPanelRail` |
| Viewport | Flexible centre region between rails | [StudioWindow.swift](../StudioWindow.swift): `StudioFrame.layout()` canvas branch. Logical container; currently composed of sibling views, not a dedicated Viewport class |
| Viewport-Header | Existing page/palette title and metadata | [StudioWindow.swift](../StudioWindow.swift): `StudioPage.draw()`, `AreaHeader`; viewport expand arrow disabled in the canvas shell |
| Viewport-Actionbar | Filter/tab/action row below the title header | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceViewportBar(footer: false)`; instance **`StudioFrame.viewportHeader`** (older code name); `WorkspaceChannelControls` on the left, fixed appearance presets on the right |
| Viewport-Page | Scrollable palette/swatch canvas; Grid or List | [StudioWindow.swift](../StudioWindow.swift): `StudioFrame.page`, `StudioPage.scroll`, `StudioPage.grid`, `TileGrid`; half-gutter (8 pt) inner canvas padding in the workspace; adaptive text uses the chosen app background |
| Viewport-Footer | Fixed view controls: Grid/List left; format, size, Delta and profile right | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceViewportBar(footer: true)`, `StudioFrame.viewportFooter`. Controls are arranged by `StudioPage.layout()` through `workspaceToolbar`; profile control in [PrintProfileSelector.swift](../PrintProfileSelector.swift). Menus open upward |
| Rail2 | Right dock; independently scrolling panel stack, scrollbar in outer right gutter | [WorkspacePanels.swift](../WorkspacePanels.swift): `WorkspaceRail`; instance `StudioFrame.rightPanelRail` |
| Carousel | App-wide horizontal palette filmstrip; wheel scrolls without looping | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceFilmstrip`, nested `CarouselScroll` / `Strip`; instance `StudioFrame.filmstrip` |
| Footer | App-wide status / release information, separate from viewport controls | [StudioWindow.swift](../StudioWindow.swift): `StudioFooter` / `StudioFrame.footer`, visible on all routes beneath the Carousel (or directly beneath the workspace during image import). Owns release/status and copied-colour history. |

Image import source browsing shows the real user Home, startup disk and mounted volumes. Selecting or expanding an ungranted folder opens the macOS folder chooser; the From panel’s Choose Folder action also grants access. Persist grants through `FolderAccess`, never path-only permissions. Enumeration errors remain errors, not cached empty folders. Rails reserve their viewport-facing one-point border and extend to the app Footer when the Carousel is hidden.

Import prototypes `WorkspaceBranchTree` in `StudioWorkspace.swift`: Git-inspired branch lanes combine with greyscale depth tints from study 07. Open folders use progressively lighter rounded headers. Top-level folders share a continuous ring-to-ring trunk. Each depth indents by 14 pt (9 pt circles with 5 pt horizontal gaps); a transparent connector canvas draws each parent branch as one unsplit S-curve between node rings into a new child lane ending at the final direct child, never merging back. The tree lists folders only; image discovery and selection live in Viewport-Page. Loaded leaf folders have no expansion control. Final child nodes have a 16 pt outer ring; hover, selection and expanded nodes use the same ring with a filled 9 pt centre. Connectors meet circle/ring edges without passing through them. Trailing plus/minus controls replace triangles. Single-click folders open/close independently; native keyboard and modifier selection remain available. `image-source` is a sole `WorkspacePanel.fillsRail` panel: full Rail1 height, no fixed preferred height, collapse/move/resize controls or Panel-Footer. Its source list is laid out directly inside the panel: after filling the available height, the whole panel grows into Rail1's outer left scroll. No inner source scrollbar or duplicate gutter. Library and Import now share this branch renderer.

## Panel primitive and contents

| Component | Source / role |
|---|---|
| Panel | [WorkspacePanels.swift](../WorkspacePanels.swift): `WorkspacePanel`; reusable container, stable `panelID`, content view, remembered session height and collapsed state |
| Panel-Header | `WorkspacePanel.layout()`: 34-point header, identical for real and test panels, with no inter-panel gap; filled `WorkspaceDisclosure`, title and right-hand `PanelDragGrip` |
| Panel-Body | `WorkspacePanel.content`; Inspector and `WorkspaceScrollableContent` are wrapped in their own fitted scroll view; Catalogues already owns a scroll view |
| Panel-Footer | `PanelResizeGrip`: 18-point footer, centred 3×2 dot handle; changes panel height |
| Drop targets | `WorkspaceRail`, `PanelDropTarget`: 22-point slots, 4-point line, curved Drop Here tab, top/bottom edge variants; edge scrolling while dragging |
| Drag shade | `WorkspaceDragShade`, `StudioFrame.workspaceDragShade`: dims only the centre Viewport |
| Catalogues | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceCatalogues`, instance `cataloguePane`, panel ID `catalogues`, displayed as Library; starts in Rail1, can move |
| Inspector | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceInspector`, instance `inspectorPane`, panel ID `inspector`; starts in Rail2, can move |
| Test panels | [WorkspacePanelUITest.swift](../WorkspacePanelUITest.swift): `WorkspacePanelUITest.load(into:)`; Rail1 Panel A–E and Rail2 Panel A–E. Launch using [tools/test-panels.sh](../tools/test-panels.sh) with the app closed. Session-only; no catalogue records |

## Naming and maintenance

- Use these region names in tasks, reviews and future component names. “Page” means Viewport-Page; it does not mean the entire centre container.
- Always qualify Footer: Panel-Footer, Viewport-Footer or app Footer. The palette filmstrip is Carousel, even where older code calls it a footer.
- Do not confuse legacy `StudioFrame.rail1` (`LibraryRail`) / `rail2` (`PaletteTable`) with the new dock instances `leftPanelRail` / `rightPanelRail`.
- Update this registry when adding, moving, renaming or replacing a layout component. Record planned versus implemented regions explicitly; do not infer implementation from a name.
- Dimensions, interactions and migration scope are in [c_full_app.md](c_full_app.md). This register is the naming and source lookup authority.

## App appearance

The app Footer draws its continuous full-width top border inside its own bounds. Do not draw this border behind sibling regions in `StudioFrame`; rail and viewport layers can cover it.

Viewport-Actionbar is 52 pt high; Viewport-Footer remains 32 pt. All actionbar controls centre vertically, and channel controls start at the normal left inset whenever Import is absent. The actionbar owns a continuous full-width rectangular border, including its top edge; it must not inherit the inset title divider. `AppearancePresets.swift` owns five inline swatches on the actionbar's right: White, Cream, 50% Grey, Charcoal, Black. A yellow outline marks the selection. Click or plain L cycles/selects; `AppPreferences` stores only `theme.preset` in `.coldata`. L is ignored in text fields, sheets and overlays. There is no appearance editor, menu or saved-profile system.

`Design` adapts grounds, text and subtle rules; `Design.refreshSurfaces` refreshes cached layers, table/panel contents and AppKit controls. Palette samples remain original. Viewport-Footer controls align with the inset canvas content.

## Panel surface rules

All panel headers use `WorkspacePanelSurface` through `WorkspacePanel.draw`: a subtle vertical fade derived from the current background and text colours, never a fixed light gradient. Keep the shared 34 pt header geometry.

Tree/list selection backgrounds extend edge to edge across the panel body, touching both borders. Do not inset the scroll view to create text padding. `WorkspaceOutline` insets disclosure/cell contents by 8 pt; `WorkspacePanelRow` draws the full-width, softly graduated selection. Future panel trees must use these primitives and return `WorkspacePanelRow` from their row-view delegate. Keep scrollbars in their dedicated gutters, outside row content. Preserve readable text and restrained contrast in all five appearance presets.

## Palette analysis

`WorkspaceAnalysis.swift` owns the compact analysis components. Both rails are 360 pt, from `Design.App.railWidth`. Both analytics panels use the same movable, collapsible, resizable `WorkspacePanel` primitive.

- **Histograms**, ID `histograms`: `WorkspaceHistogramPane`, starts in Rail2. Reuses `HistogramView` and the existing colour-model conversions. Offers merged, per-channel and individual-channel plots, with a colour selector and the shared Expand action. Bright spikes are the selected colour; dim spikes count the palette. RGB/CMYK guard bands are advisory, not gamut limits or ΔE. Y′CbCr uses legal luma/chroma bounds separately.
- **Delta Bloom**, ID `bloom`: `WorkspaceBloomPane`, starts below Histograms in Rail2. Reuses `PrintBloomView`, `Rendering`, `PrintBuild` and `SavedPrintProfiles`. These are ICC predictions, not measured proofs. Printing condition, rendering intent, black point compensation, ΔE2000 tolerance and petal ordering are compact controls; the shared profile menu saves/edits/imports/exports `.coldata` print settings.
- **Expanded panels**: `WorkspaceExpandedPanel` replaces Viewport-Page with a 20% palette list / 80% analysis split. It retains the current filtered palette set. Selection hot-swaps the analysis; closing restores the original grid/list presentation. Both Delta Bloom and Histograms use this primitive; it accepts an arbitrary content view. Delta Bloom adds findings/fix guidance to the left of the chart. Its settings remain in Rail2, except the shared petal-order choice centred above the expanded Bloom. It leaves the header, actionbar, footer and carousel in place.
- **Viewport channel controls**: `WorkspaceChannelControls` selects an inherited/named channel profile and Master/channel preview. This is a presentation override, not a change to palette masters or profile assignments. Choices persist through `AppPreferences` in `.coldata`; print preview uses the same current print settings as Bloom.

Future work: tile edit settings should let users select per-card metadata fields, including channel values derived from the selected profile. Do not change palette tile metadata automatically as part of the analysis-panel migration.

### Expanded-panel rule

Use `WorkspaceExpandedPanel` for every palette-driven panel expansion: 20% palette list and 80% analysis, preserving route/filter/grid state. `WorkspaceExpandButton` sits at the top-right of the panel **body**, baseline-aligned with the palette title and equally inset. Never duplicate it in Panel-Header. Expanded content has one top-right × Close action, no extra header row. Escape closes the active expanded panel, after dismissing any menu/modal/sheet that owns Escape. Future expanded panels must register with the same root close handler.

Delta Bloom uses one `PrintBloomView` renderer at both sizes: touching rounded petals, proportional outer status rim and simulation clearance, circular ΔE centre without a rectangular ground, and a visible initial selection. Keep selected-colour captions aligned with the 12 pt content padding. Expanded Bloom reuses `PrintBloomFeedback` for prediction findings and next steps; no colour is changed by its guidance.

### Panel padding and inner scrolling

`WorkspacePanel` reserves bottom breathing room before Panel-Footer, matching the content's side padding (16 pt by default; analytical content declares its existing 12 pt inset through `WorkspacePanelContentMetrics`). `minimumContentHeight` describes the final rendered content edge, excluding this padding. Fixed-content panels default to that content extent plus padding, header and footer; drag resizing uses the same computed minimum, including when histogram channels change. Scrollable lists can request a taller initial viewport, while retaining the shared lower limit and bottom inset.

Panel body contents use equal horizontal padding against the available content width. Inner `WorkspacePanelScroll` lanes stay on the right in both rails, reserving 16 pt plus a 1 pt divider even when content fits, so overflow never shifts text or changes width. Wrappers around content that owns its own scroll view reserve no duplicate lane. `WorkspaceRailAwareContent` receives the inner-right policy independently of the outer rail side. The separate outer stack-scroll gutters stay on their outside edges: Rail1 left, Rail2 right. `fillsRail` panels are at least the rail viewport height and grow with their content extent into the outer stack scroll.

Delta Bloom and Histograms share master-colour spectra: a 20 pt docked strip sits below the palette title, above the controls and chart. The 64 pt expanded spectrum is centred below the chart, uses `TileGrid.paletteTileWidth` (clamped to available width), and bottom-aligns with the selected-colour block under the findings column. Outer status segments use true round stroke caps. The viewport title temporarily shows `Panel Name > Palette Name` while expanded; the normal route title is retained and restored on close.

Dropdown controls use `DropdownSkin`: faint full border, 4 pt corner radius and a 28 pt trailing arrow compartment. Current Settings fills its assigned field width; all carets align at the trailing edge. Preserve menu separators and control spacing. Delta Bloom places petal order directly below the docked spectrum and centred above the expanded chart.


Import Viewport-Actionbar uses `SwissCheckbox` (Design.swift): text-cap-height square, filled when selected, theme-aware ink and native checkbox keyboard/accessibility. `WorkspaceToggleChoiceControl` keeps All/New Images and Import/Link mutually exclusive without underlines. Filter by Meta remains a menu.

Shared text actions (`ActionButtonSkin`) resolve ink from `Design.ink`, never system label appearance. Rest, hover, pressed and disabled labels retain at least 4.5:1 contrast against `Design.card`; unreadable saved text colours fall back to readable ink. Disabled actions use an opaque, subdued foreground rather than a near-invisible alpha.

Import From contains Favourites above System, each with a divider/header and an independent branching folder outline sharing the outer Rail1 scroll. Empty favourites read “No favourites listed”. Each folder has a trailing star before its expansion control; filled stars remove saved favourites. `SwissContextMenu` offers Show in Finder and Add To/Remove From Favourites. `AppPreferences` persists ordered standardised folder paths under `Workspace.Import.FavouriteFolders` in `.coldata`; favourite roots browse their own children without changing System expansion.

Import sources reconcile mounted volumes on NSWorkspace mount/unmount/rename notifications and app activation. Existing root objects retain expansion, selection and loaded children; manually chosen extra roots remain. Disconnecting the selected drive cancels its preview scan and clears stale results without deleting saved favourites. Observers are released with the source pane.

The import source panel opts into `WorkspacePanel.pinsHeader`: From and its Include Nested Folders control row are hosted above the rail clip view and remain fixed. Favourites/System folder content alone scrolls in the existing outer-left scrollbar. `WorkspacePinnedPanelContent` supplies the fixed controls; its body extent excludes that row. Include Nested Folders uses the shared `SwissCheckbox` filled-square style.

Rail1’s Library panel has four 28 pt disclosure sections: Catalogues, Favs, Folders and My Palette's. Only Folders draws branch connectors; the other sections use flat icon rows. Existing palette favourites remain catalogue-owned; stars call the existing favourite toggle. All four lists size to their visible rows and scroll through the outer rail, with no nested list scrollbars. The shared panel reserves its default 16 pt bottom inset before the resize footer and derives minimum/default height from the rendered content extent. Catalogue identity, routes and remembered folder expansion are retained.

Expanded Rail1 and Rail2 now share the 360 pt `Design.App.railWidth` standard on panel and legacy routes, including Import. Histogram and Bloom controls/charts already derive their width from their panel bounds and fill the new width; existing side/bottom padding and scrollbar lanes remain. Collapsed settings rails keep their collapse behaviour.

Library branch rows retain their category marks alongside the node connectors: information, photography, palettes, assets, typography and tags, with folder/catalogue marks for their containers. Icons follow the row text colour on expanded depth tints; Import remains folder-name only.

`WorkspacePanel` exposes independent `resizable` and `draggable` flags (both default true). With `resizable:false`, height follows current content metrics plus bottom padding, ignores remembered drag height, removes the dotted resize footer and keeps one lower border. Library, Histograms and Delta Bloom use this content-sized mode. `draggable:false` hides the header move grip and blocks panel moves; all current panels retain the default true.

Expanded Library sections reserve the shared 16 pt bottom padding before the next section; My Palette's gets the primitive's final bottom inset. Favourite rows in Library and Import offer a square colour swatch before the star, opening the existing `StudioColourPicker` with a single favourite target and Clear Colour. Coloured backgrounds follow the same palette ID or standardised folder path into the main tree; only the favourites section edits them. Text, icons, stars and disclosures choose black/white against the saved colour. `Workspace.Library.Favourites.<catalogue-ID>` and `Workspace.Import.Favourites` store full ordered identity/title/optional-colour arrays through AppPreferences in `.coldata`; Import migrates the former path array and retains it for compatibility. Palette star membership also remains in its catalogue model.

Halo confirmation sliders derive the handle fill from the centre background and the track from Ring 1's background; chevrons use Ring 1's text ink. The Rectangle Picker quick key defaults to 3 (alongside 1 New Palette and 2 Picker), routed through the existing screen rectangle sampler and ignored while typing or an overlay owns input.

Library now separates unassigned app-owned palettes into a fourth internal section, My Palette's, after Folders. It is a flat list without branch nodes or expansion, retaining palette selection, stars and favourite colours. Project-owned palette buckets stay in Folders. Claimed app-owned copies join the flat section with their provenance labels. All four sections share the primitive's 16 pt bottom spacing (the last gets it from the parent). Storage is unchanged: `colorgain.coldata` points to `Assets/Assets.colcat`, which indexes separate `.colpal`/`.coltyp` documents; catalogue stores split out unassigned assets before saving.

Library palette rows and Viewport palette tiles publish `PaletteDrag.type`. The Library branch outline accepts copy drops onto palette buckets, project rows and ancestors that resolve to one destination; closed projects resolve to their first palette bucket. Ambiguous multi-project ancestors are not drop destinations. Visible valid targets gain a yellow outline during dragging. The shared assignment handler writes an independent project copy through the existing catalogue/global transaction, retaining the source and avoiding claimed copies for this direct drag. Palette colour counts occupy a right-aligned slot immediately before the star; favourite colour controls remain to the count's left. Plain viewport palette clicks open on release so dragging does not navigate first.

Library section order is Catalogues, Favs, Folders, My Palette's. Each uses a full-width `WorkspaceSectionHeader` disclosure button; collapsed bodies and their connector canvases leave the layout entirely while retaining tree expansion. Section collapse state persists through AppPreferences in `.coldata`. Content-sized panel height follows these section states.

Favs and Catalogues use flat icon rows, matching My Palette's; only Folders draws the branching circle rail. The catalogue plus action lives at the right of the inner Catalogues section header, leaving the outer Library header for panel controls.

Swatch tiles and palette cards draw the shared `ResultGlyph.warning` between the Delta label and Halo mark when any predicted Delta exceeds the active saved print profile tolerance. Swatches evaluate their own Delta; palette cards evaluate every palette entry, including colours beyond the preview strip. Profile changes refresh both the predictions and tolerance. Unknown/non-finite predictions do not manufacture a warning.

Histogram findings sit below the plot captions: Warnings defaults closed and lists only guard-band failures; opening it adds passing swatches after failures. Each warning row has a colour chip, name, shared verdict glyph and independent disclosure for affected channel values. Content height grows with the rows/details. The chart uses a 16 pt warning glyph inside its true channel-boundary zones; it never widens the data range to fit decoration. Metadata filter requests invalidate older page snapshots even while hidden, preventing stale results from replacing a newly selected palette.

Viewport Δ labels, split previews and warning triangles use `Rendering.of` for the actionbar’s selected profile/channel, never the dock’s independent print condition. Master Colours produces zero difference. Channel changes invalidate all cached previews, and entering a palette resolves its channel profile before rendering its swatches.

Library row presses retain keyboard focus in their outline. Plain Up/Down selects the previous/next visible row, scrolls it into view and follows the same navigation callback as a pointer selection. Favourite stars and colour controls retain their own actions.

Content-sized (`resizable:false`) and full-rail panels disable the inner vertical scrollbar and reserve no inner scrollbar lane or separator. Their content receives the full panel width, retaining normal content padding; the rail’s outer scrollbar handles stack overflow. Resizable panels retain their inner overflow lane.

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

## Panel primitive and contents

| Component | Source / role |
|---|---|
| Panel | [WorkspacePanels.swift](../WorkspacePanels.swift): `WorkspacePanel`; reusable container, stable `panelID`, content view, remembered session height and collapsed state |
| Panel-Header | `WorkspacePanel.layout()`: 34-point header, identical for real and test panels, with no inter-panel gap; filled `WorkspaceDisclosure`, title and right-hand `PanelDragGrip` |
| Panel-Body | `WorkspacePanel.content`; Inspector and `WorkspaceScrollableContent` are wrapped in their own fitted scroll view; Catalogues already owns a scroll view |
| Panel-Footer | `PanelResizeGrip`: 18-point footer, centred 3×2 dot handle; changes panel height |
| Drop targets | `WorkspaceRail`, `PanelDropTarget`: 22-point slots, 4-point line, curved Drop Here tab, top/bottom edge variants; edge scrolling while dragging |
| Drag shade | `WorkspaceDragShade`, `StudioFrame.workspaceDragShade`: dims only the centre Viewport |
| Catalogues | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceCatalogues`, instance `cataloguePane`, panel ID `catalogues`; starts in Rail1, can move |
| Inspector | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceInspector`, instance `inspectorPane`, panel ID `inspector`; starts in Rail2, can move |
| Test panels | [WorkspacePanelUITest.swift](../WorkspacePanelUITest.swift): `WorkspacePanelUITest.load(into:)`; Rail1 Panel A–E and Rail2 Panel A–E. Launch using [tools/test-panels.sh](../tools/test-panels.sh) with the app closed. Session-only; no catalogue records |

## Naming and maintenance

- Use these region names in tasks, reviews and future component names. “Page” means Viewport-Page; it does not mean the entire centre container.
- Always qualify Footer: Panel-Footer, Viewport-Footer or app Footer. The palette filmstrip is Carousel, even where older code calls it a footer.
- Do not confuse legacy `StudioFrame.rail1` (`LibraryRail`) / `rail2` (`PaletteTable`) with the new dock instances `leftPanelRail` / `rightPanelRail`.
- Update this registry when adding, moving, renaming or replacing a layout component. Record planned versus implemented regions explicitly; do not infer implementation from a name.
- Dimensions, interactions and migration scope are in [c_full_app.md](c_full_app.md). This register is the naming and source lookup authority.

## App appearance

Viewport-Actionbar and Viewport-Footer are both 32 pt high. The actionbar owns a continuous full-width rectangular border, including its top edge; it must not inherit the inset title divider. `AppearancePresets.swift` owns five inline swatches on the actionbar's right: White, Cream, 50% Grey, Charcoal, Black. A yellow outline marks the selection. Click or plain L cycles/selects; `AppPreferences` stores only `theme.preset` in `.coldata`. L is ignored in text fields, sheets and overlays. There is no appearance editor, menu or saved-profile system.

`Design` adapts grounds, text and subtle rules; `Design.refreshSurfaces` refreshes cached layers, table/panel contents and AppKit controls. Palette samples remain original. Viewport-Footer controls align with the inset canvas content.

## Panel surface rules

All panel headers use `WorkspacePanelSurface` through `WorkspacePanel.draw`: a subtle vertical fade derived from the current background and text colours, never a fixed light gradient. Keep the shared 34 pt header geometry.

Tree/list selection backgrounds extend edge to edge across the panel body, touching both borders. Do not inset the scroll view to create text padding. `WorkspaceOutline` insets disclosure/cell contents by 8 pt; `WorkspacePanelRow` draws the full-width, softly graduated selection. Future panel trees must use these primitives and return `WorkspacePanelRow` from their row-view delegate. Keep scrollbars in their dedicated gutters, outside row content. Preserve readable text and restrained contrast in all five appearance presets.

## Palette analysis

`WorkspaceAnalysis.swift` owns the compact analysis components. Rail1 is 280 pt; Rail2 is 340 pt. Both analytics panels use the same movable, collapsible, resizable `WorkspacePanel` primitive.

- **Histograms**, ID `histograms`: `WorkspaceHistogramPane`, starts in Rail2. Reuses `HistogramView` and the existing colour-model conversions. Offers merged, per-channel and individual-channel plots, with a colour selector and the shared Expand action. Bright spikes are the selected colour; dim spikes count the palette. RGB/CMYK guard bands are advisory, not gamut limits or ΔE. Y′CbCr uses legal luma/chroma bounds separately.
- **Delta Bloom**, ID `bloom`: `WorkspaceBloomPane`, starts below Histograms in Rail2. Reuses `PrintBloomView`, `Rendering`, `PrintBuild` and `SavedPrintProfiles`. These are ICC predictions, not measured proofs. Printing condition, rendering intent, black point compensation, ΔE2000 tolerance and petal ordering are compact controls; the shared profile menu saves/edits/imports/exports `.coldata` print settings.
- **Expanded panels**: `WorkspaceExpandedPanel` replaces Viewport-Page with a 20% palette list / 80% analysis split. It retains the current filtered palette set. Selection hot-swaps the analysis; closing restores the original grid/list presentation. Both Delta Bloom and Histograms use this primitive; it accepts an arbitrary content view. Delta Bloom adds findings/fix guidance to the left of the chart. Its settings remain in Rail2, except the shared petal-order choice centred above the expanded Bloom. It leaves the header, actionbar, footer and carousel in place.
- **Viewport channel controls**: `WorkspaceChannelControls` selects an inherited/named channel profile and Master/channel preview. This is a presentation override, not a change to palette masters or profile assignments. Choices persist through `AppPreferences` in `.coldata`; print preview uses the same current print settings as Bloom.

Future work: tile edit settings should let users select per-card metadata fields, including channel values derived from the selected profile. Do not change palette tile metadata automatically as part of the analysis-panel migration.

### Expanded-panel rule

Use `WorkspaceExpandedPanel` for every palette-driven panel expansion: 20% palette list and 80% analysis, preserving route/filter/grid state. `WorkspaceExpandButton` sits at the top-right of the panel **body**, baseline-aligned with the palette title and equally inset. Never duplicate it in Panel-Header. Expanded content has one top-right × Close action, no extra header row. Escape closes the active expanded panel, after dismissing any menu/modal/sheet that owns Escape. Future expanded panels must register with the same root close handler.

Delta Bloom uses one `PrintBloomView` renderer at both sizes: touching rounded petals, proportional outer status rim and simulation clearance, circular ΔE centre without a rectangular ground, and a visible initial selection. Keep selected-colour captions aligned with the 12 pt content padding. Expanded Bloom reuses `PrintBloomFeedback` for prediction findings and next steps; no colour is changed by its guidance.

### Panel padding and inner scrolling

Panel body contents use equal horizontal padding against the full available body width. `WorkspacePanelScroll` reserves no inner lane when the document fits. On overflow it adds a 16 pt scrollbar lane and a 1 pt dividing border, then reduces/repositions the content viewport; the same padding applies inside that viewport. Rail1 uses a left inner lane, Rail2 a right inner lane. `WorkspaceRailAwareContent` passes that side to contents which own their own scrolling (such as Catalogues). Moving a panel switches its inner scrolling side automatically. The rail's separate outer stack-scroll gutter is unchanged.

Delta Bloom and Histograms share master-colour spectra: a 20 pt docked strip sits below the palette title, above the controls and chart. The 64 pt expanded spectrum is centred below the chart, uses `TileGrid.paletteTileWidth` (clamped to available width), and bottom-aligns with the selected-colour block under the findings column. Outer status segments use true round stroke caps. The viewport title temporarily shows `Panel Name > Palette Name` while expanded; the normal route title is retained and restored on close.

Dropdown controls use `DropdownSkin`: faint full border, 4 pt corner radius and a 28 pt trailing arrow compartment. Current Settings fills its assigned field width; all carets align at the trailing edge. Preserve menu separators and control spacing. Delta Bloom places petal order directly below the docked spectrum and centred above the expanded chart.

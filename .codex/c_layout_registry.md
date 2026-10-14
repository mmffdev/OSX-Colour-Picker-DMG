# App layout component registry

Canonical region names for Colorgain. Start here to locate a layout section before editing it. Source mappings describe `osx-full-app`; the canvas shell currently serves Library routes selected by `StudioFrame.canvasWorkspace`. Other routes retain legacy layouts until migrated.

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
| Viewport-Actionbar | Filter/tab/action row below the title header | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceViewportBar(footer: false)`; instance **`StudioFrame.viewportHeader`** (older code name); currently Library Filter scaffold |
| Viewport-Page | Scrollable palette/swatch canvas; Grid or List | [StudioWindow.swift](../StudioWindow.swift): `StudioFrame.page`, `StudioPage.scroll`, `StudioPage.grid`, `TileGrid` |
| Viewport-Footer | Fixed view controls: Grid/List left; format, size, Delta and profile right | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceViewportBar(footer: true)`, `StudioFrame.viewportFooter`. Controls are arranged by `StudioPage.layout()` through `workspaceToolbar`; profile control in [PrintProfileSelector.swift](../PrintProfileSelector.swift). Menus open upward |
| Rail2 | Right dock; independently scrolling panel stack, scrollbar in outer right gutter | [WorkspacePanels.swift](../WorkspacePanels.swift): `WorkspaceRail`; instance `StudioFrame.rightPanelRail` |
| Carousel | App-wide horizontal palette filmstrip; wheel scrolls without looping | [StudioWorkspace.swift](../StudioWorkspace.swift): `WorkspaceFilmstrip`, nested `CarouselScroll` / `Strip`; instance `StudioFrame.filmstrip` |
| Footer | App-wide status / release information, separate from viewport controls | **Not yet an independent region in the new shell.** Status currently drawn in `WorkspaceFilmstrip.draw()` above its thumbnails. [StudioWindow.swift](../StudioWindow.swift): legacy `StudioFooter` / `StudioFrame.footer` is hidden during canvas routes. Keep this name reserved for the eventual standalone bottom status row |

## Panel primitive and contents

| Component | Source / role |
|---|---|
| Panel | [WorkspacePanels.swift](../WorkspacePanels.swift): `WorkspacePanel`; reusable container, stable `panelID`, content view, remembered session height and collapsed state |
| Panel-Header | `WorkspacePanel.layout()`: 34-point header, identical for real and test panels, with no inter-panel gap; filled `WorkspaceDisclosure`, title and right-hand `PanelDragGrip` |
| Panel-Body | `WorkspacePanel.content`; Inspector is wrapped in its own scroll view; Catalogues already owns a scroll view |
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

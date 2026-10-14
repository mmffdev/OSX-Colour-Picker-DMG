# Full-app workspace prototype

Branch: `osx-full-app` (App Store build). Rick authorised a new canvas-centred shell on 2026-10-13. This supersedes the old page-column layout for Library routes only; other tools retain their existing screens until migrated.

## Names and layout

The [app layout component registry](c_layout_registry.md) owns region names and source mappings. Rail1 is the 260-point left dock; Rail2 is the 280-point right dock. The flexible Viewport contains its Header, Actionbar, Page and Footer. The Carousel currently occupies a combined 120-point band with app status; the independent app Footer remains to be split out.

Catalogues uses a native disclosure tree with 28-point rows, 16-point indentation and house type/icons. Roots come from the existing controller. The active catalogue's schema filters Viewport-Page; palettes are not duplicated as tree rows. All Palettes includes project-owned palettes in the active catalogue. Selection updates Inspector; Open Swatches opens the palette. The Carousel shows all active-catalogue palettes, with wheel/trackpad movement clamped at both ends.

Window opens maximised on the leftmost connected screen on each launch, with the native macOS title bar and traffic lights. Header content does not drag the window. Help lives in the native menu bar; the Help book is pending. Minimum 1200 × 800. No type scaling. Tile columns adapt to available width.

## Prototype boundaries

The views consume LibraryController and SchemaTrial; they do not create or migrate catalogues. Catalogue tree expansion and canvas colour are currently session-local. Native outline rows retain keyboard disclosure and selection. Settings, Lab and PrePress retain their existing layouts; migrate those after shell review. Do not describe this skeleton as a completed application-wide redesign.

## Dockable panels

`WorkspacePanels.swift` owns the shared container: 34-point collapsible header, title/disclosure on the left, local drag handle on the right, and 18-point footer resize grip with a centred three-by-two dot handle. Panel headers meet the preceding footer directly, without extra stack spacing; all real and test panels share this geometry. Catalogues starts in Rail1 and Inspector in Rail2. Drag either panel to either rail; the drop position determines its order. During dragging, the centre viewport dims and both rails expose 22-point insertion slots above, between and below panels. Each slot has a four-point rule, curved central “Drop Here” tab and yellow active state. Escape or release outside a rail cancels; edge dragging continuously scrolls long stacks while held still. The top target has a flat border-flush top; the last slot always uses the mirrored bottom shape. Each insertion slot has one view: first/last slots are positioned at the rail edges when needed, never duplicated as overlays. Intermediate slots overlapping either edge band are suppressed. Run `./tools/test-panels.sh` with Colorgain closed to load five empty prototype panels per rail (Rail1/Rail2 Panel A–E). `WorkspacePanelUITest` supplies the session-only fixture behind `--ui-test-panels`; ordinary launches omit it. No catalogue or .coldata records are created. Use it to check collapse, resize, ordering, cross-rail moves, edge scrolling and cancellation. Each rail scrolls independently when its stack exceeds the available height. `WorkspaceRailScroll` places its scrollbar in a 16-point outer gutter, separated by a one-point border: left for Rail1, right for Rail2. Panels fill the remaining width without an inner stack-scrollbar gap. Panel layout is session-local in this prototype. The existing catalogue model and selection remain attached to their panel when moved. Tree rows use filled disclosure triangles and vertically centred icon/text cells.

## Page tool rows and presentation

Within the centre Page only, the existing title header is followed by a 24-point filter/navigation row. A fixed 32-point viewport footer above the global carousel holds Grid/List on the left and colour format, tile-size slider, Delta and print-profile controls in a right-aligned group. Footer menus open upward; the viewport title has no expand arrow. These reuse StudioPage's existing actions. Grid/List switch the same TileGrid dataset; List uses 64-point rows with compact colour previews, names, metadata, Delta and halo actions. Filters and selection survive presentation switches. Other tool screens retain their legacy presentation until migration.

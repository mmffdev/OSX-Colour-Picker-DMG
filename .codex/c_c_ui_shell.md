# Shell, tabs and viewport contract

The Library tab control cap extends one pixel over the content's top rule so its face joins the pane body like the title tab, without a detached lower line.

Parent: [UI framework](c_ui_framework.md). Check [Component registry](c_layout_registry.md) for placement and [styles.md](../styles.md) for appearance.

`StudioFrame` composes the window from `StudioHeader` (48 pt at wide widths, 94 pt when navigation wraps below 1720 pt), the single global colour-management Actionbar, Rail1 / viewport / Rail2, optional `WorkspaceFilmstrip` (120 pt), and `StudioFooter` (48 pt). Expanded rails are 360 pt. Header, rails and tab strip all derive their top from `Design.App.headerHeight(for:)`, so the single-row header leaves no empty band above the tabs. The global Actionbar is `StudioFrame.profileHeader` plus `WorkspaceChannelControls`; it is 40 pt per row and wraps when width requires. It sits above split page panes and is never captured as a per-pane view setting.

Multi Colour Select temporarily hides the global Actionbar and gives its height to the viewport. Escape or Done restores the Actionbar and its prior state.

Transform opens from a palette halo or context menu inside the clipped Viewport-Page and hides the global Actionbar and outer VP bars. Its page-local 58 pt `WorkspaceViewportBar` is the Transform VP-Actionbar, with Diagram Presets, Fit, zoom and Done icon controls. Diagram Presets opens RailInfo to save, apply, rename, remove, import and export portable `.colnode` flows. Panning may move graph content only within the viewport; it must never paint across a rail or app header. The underlying Library route stays selected; Done or Escape closes the canvas and restores the bars.

The viewport stack contains `WorkspaceViewportBar(footer:false)` (**VP-Actionbar**), shared tab/header, `StudioPage`, and `WorkspaceViewportBar(footer:true)` (**VP-Footer**, 42 pt). The VP-Actionbar uses `leadingControls`, `rightControls`, `preferredHeight`, `usesHeaderSurface`, and route configuration methods. General pages use 58 pt; Import uses one 40 pt gradient row aligned with panel headers. Props omit controls unavailable to a route. Never move colour-management Preset/Workflow/Target/Tolerance/Rendering Intent into VP-Actionbar.

Palette and Font library listings share the gradient VP-Actionbar. Their Import Palettes / Import Fonts action begins at the same inset; palette rating and flag controls immediately follow Import Palettes. Both place Name ordering, Filter by Meta and the Help hex at the right. Fonts omit Output Proof. At narrow widths the right filter pair and Help wrap together, while Import and palette review controls stay aligned on the first row.

`WorkspaceTabContour` owns the 33 pt S-curve, selected face, mirrored action cap, and barberpole. Its top overlaps the global Actionbar rule by 1 pt; its lower edge remains at the former 32 pt position, with no gap or double line. `LibraryPageLayout` uses it for multi-pane tabs and split capacity. `WorkspacePageTabHeader` uses the same drawing for single-page tabs; provide title, symbol, stripe colour and optional actions. Absent callbacks hide controls. The Library stripe starts from Rule grey and Import from `Design.houseYellow`; the shared renderer lightens either colour 20% toward white. The Actionbar owns the straight top rule: tabs stroke only their curves, so no second top border runs against the neighbouring panel. The tab host owns its lower border pixel so stripes cannot appear below the row. Import content begins after the shared tab row, without a second `AreaHeader` drawn through it.

The Carousel's horizontal scroller uses the same `QuietScroller` as vertical panel lanes: house-yellow knob, 16 pt reserved lane and 10 pt knob thickness. `QuietScroller` turns its knob inset with the scroll direction.

Designer → Palette replaces the old cNode subtab. Its 58 pt local actionbar offers Import Image, Save Recipe and Export Palette. Rail1 remains visible, Rail2 stays closed, and RailInfo opens beside Rail1 with the entire source → grade → extract → output journey in one scrolling panel. The viewport gives its width to side-by-side original/adjusted previews and a bottom `WorkspacePanel` of hue-ordered extracted swatches above VP-Footer. Save Recipe asks for a name, then writes settings-only `.colimg` to `workspace/Presets/Images` and registers it in `colorgain.coldata`; RailInfo's Saved Recipes selector applies those settings to the current image or imports an external recipe. Older image `.coltrans` files can be imported without their image links. Transform `.coltra` and `.colnode` presets live in `workspace/Presets/Transforms`. Export To selects My Library or an unlocked project palette bin, placing the new palette first.

The Designer Palette VP-Actionbar and tab row share one continuous seam. The row overlaps the bar's final pixel, so `ImagePaletteTopSeam` paints its full-width top rule *above* both tab views; neither the bar nor the comparison body adds a second line. The Adjusted pane's in-body width toggle uses the shared [expand/contract icon pair](c_c_ui_controls.md); it never reserves image space.

Session restoration cancels an in-progress rail slide before applying saved geometry. If Designer → Palette is the restored route, RailInfo must end at its requested full width without requiring a tab switch.

With no image, Original Reference centres the shared bordered Import Image button with its separated icon cell. The empty Adjusted pane shows a 6 pt yellow-on-transparent `ColourTargetBarberPole` around its frame; it clears when the graded image arrives. Neither empty preview prints a redundant No Image label.

`Design.rule` is the one structural border colour for grid cards, the main frame, rails, panels and tab contours. Black (`#000000`) and Charcoal (`#242424`) both use `#313131`; other themes retain their existing rule. Focus/selection outlines and icon strokes keep their semantic colours. Check the installed app in both dark presets when changing this token.

`StudioPage.assetProps` selects renderer, pagination, menus and filters. A route may hide the shared tab/header or footer through its configuration, but never leaves an empty replacement row. `TitleStrip` is a 24 pt drag region within the main header. `GridOverlay` verifies the 12-column grid and 28 pt beat; it is not page content.

For tabbed pages, `AreaHeader` centres its left and right labels vertically between the visible 32 pt tab bottom and the header rule. Rail headers retain their separate heading and label rows.

Opening RailInfo moves the viewport to the right while Rail2 stays fixed. During any rail slide, `StudioPage` freezes its expensive grid reflow, and the page plus `LibraryPageLayout` clip retained content to the moving viewport. Reflow once at the destination, then release the temporary clipping; grid cards must never paint over Rail2 during a Tags press.

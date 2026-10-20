# Shell, tabs and viewport contract

Parent: [UI framework](c_ui_framework.md). Check [Component registry](c_layout_registry.md) for placement and [styles.md](../styles.md) for appearance.

`StudioFrame` composes the window from `StudioHeader` (94 pt), the single global colour-management Actionbar, Rail1 / viewport / Rail2, optional `WorkspaceFilmstrip` (120 pt), and `StudioFooter` (48 pt). Expanded rails are 360 pt. The global Actionbar is `StudioFrame.profileHeader` plus `WorkspaceChannelControls`; it is 34 pt per row and wraps when width requires. It sits above split page panes and is never captured as a per-pane view setting.

The viewport stack contains `WorkspaceViewportBar(footer:false)` (**VP-Actionbar**), shared tab/header, `StudioPage`, and `WorkspaceViewportBar(footer:true)` (**VP-Footer**, 42 pt). The VP-Actionbar uses `leadingControls`, `rightControls`, `preferredHeight`, `usesHeaderSurface`, and route configuration methods. General pages currently use 52 pt; Import uses one 34 pt gradient row aligned with panel headers. Props omit controls unavailable to a route. Never move colour-management Preset/Workflow/Target/Tolerance/Rendering Intent into VP-Actionbar.

`WorkspaceTabContour` owns the 32 pt S-curve, selected face, mirrored action cap, and barberpole. `LibraryPageLayout` uses it for multi-pane tabs and split capacity. `WorkspacePageTabHeader` uses the same drawing for single-page tabs; provide title, symbol, stripe colour and optional actions. Absent callbacks hide controls. The Library stripe is Rule grey; Import is full `Design.houseYellow`. The tab host owns its lower border pixel so stripes cannot appear below the row. Import content begins after the shared tab row, without a second `AreaHeader` drawn through it.

`StudioPage.assetProps` selects renderer, pagination, menus and filters. A route may hide the shared tab/header or footer through its configuration, but never leaves an empty replacement row. `TitleStrip` is a 24 pt drag region within the main header. `GridOverlay` verifies the 12-column grid and 28 pt beat; it is not page content.

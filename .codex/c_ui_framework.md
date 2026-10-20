# UI framework — lazy-loading index

This is the start point for every native UI task. [styles.md](../styles.md) owns visual style, [Component registry](c_layout_registry.md) owns named regions and geometry, and [the HTML catalogue](../design/ui-primitives-catalogue/index.html) is the browsable inventory and review surface. Swift source is the implementation authority. Do not load every child below: read only the one that owns the work.

| Work | Load next |
|---|---|
| App header, global Actionbar, rails, viewport stack, tabs, barberpole or footers | [Shell and viewport](c_c_ui_shell.md) |
| Docked panels, subsection headers, panel content, resize/scroll or trees | [Panels and trees](c_c_ui_panels.md) |
| Grids, cards, palettes, swatches, previews or selection | [Assets and grids](c_c_ui_assets.md) |
| Buttons, dropdowns, filters, menus, overlays or interaction states | [Controls](c_c_ui_controls.md) |
| Colour, type, rhythm or motion | [styles.md](../styles.md), then its focused style contract |

For every task: (1) identify the region in the registry; (2) find its existing primitive in `UIPrimitives/` or the named source; (3) configure inclusion, exclusion and variants through props; (4) add a prop to the shared primitive if the case is missing; (5) update the owning child contract, registry and catalogue entry together; (6) build and inspect the installed Library and changed route at wide and narrow widths. Domain data and page content stay in feature files. The surrounding frame is never duplicated in a feature.

The global **Actionbar** is colour-management state above split panes. **VP-Actionbar** is page-specific filtering inside the viewport. Neither is an alias of the other.

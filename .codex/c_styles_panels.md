# Panels and content extent

Shared panel contract. Load through [styles.md](../styles.md) before changing a panel or any of its contents. Source authority: [Panel padding and inner scrolling](c_layout_registry.md#panel-padding-and-inner-scrolling), WorkspacePanel and WorkspacePanelContentMetrics.

## Padding belongs to the container

- WorkspacePanel adds 5 pt above its content and bottom breathing room of the content’s declared inset plus 5 pt: 21 pt by default, or 17 pt for analytical panels declaring 12 pt. These shared additions apply to all panels (Rick, 19 October 2026).
- minimumContentHeight ends at the final rendered content edge, including the final line's descenders. It excludes the container's bottom padding, header and footer.
- Never leave a stale fixed height after removing controls, moving profile settings, changing chart size or adding/removing text. Derive the extent from the same geometry used to lay out and draw the final content.
- Do not add a second bottom spacer inside a child to compensate for the container. Fixed-content panels hug the content plus shared padding; scrollable lists and fillsRail have explicit viewport rules.
- Delta Bloom: its last docked item is the summary beneath the chart. Its extent follows that summary, rather than the former profile form's fixed 500 pt height. Keep only the shared 12 pt gap below it.

## Shared geometry and surfaces

Use WorkspacePanelHeader for the shared gradient and single bottom separator, including the Preset actionbar. Do not recreate the gradient or layer another frame over it.

Use WorkspacePanel's 40 pt header, shared header/actions/help, disclosure, resize footer and WorkspaceRail layout. `WorkspaceSectionHeader` uses that same height for inner subdivisions. Do not draw duplicate top/side borders against existing frame rules. Tree/list selection backgrounds span the body; inset row contents instead of nesting scroll padding.

`WorkspaceRail` owns the seam between adjacent panels: the following `WorkspacePanelHeader` draws one top rule, and the preceding panel omits its bottom rule. The first panel in a rail draws no top rule, so moving a panel to the rail top cannot double the rail boundary. Collapsed headers use the same rule.

Inner scroll lanes stay on the right, reserving the house lane and divider as documented by WorkspacePanelScroll. A wrapper around content that owns a scroll view must not reserve a second lane. Outer rail gutters retain their existing outside edge. Read the component registry for expanded-panel and drag/drop contracts.

## Verify after every panel change

Inspect the installed panel from its first row to its last rendered line. Compare side inset and bottom breathing room; check no text is clipped, the next header starts after exactly one padding interval, and no blank region remains from removed controls. Recheck changed selections, chart modes, collapsed/expanded states and narrow widths. Check minimum/initial/resized heights through the shared metric; do not patch only one frame.

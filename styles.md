# Colorgain shared styles

Project-wide design entry point for Codex and Claude. Read this index before creating or changing UI, then load only the relevant references. Explicit current user instructions take precedence; this index and its dropdown contract supersede conflicting older examples. Keep working guidance in this project.

| When changing | Load |
|---|---|
| Any page, panel, rail, tree, grid, card or viewport section | [UI framework index](.codex/c_ui_framework.md), then its focused child contract |
| Any dropdown, dropup, menu or selector | [Dropdown and dropup contract](.codex/c_styles_dropdowns.md) |
| Any panel, section, content-height or padding change | [Panel contract](.codex/c_styles_panels.md) |
| Region placement, headers, rails, panels or tabs | [Component registry](.codex/c_layout_registry.md) |
| Grid, spacing or alignment | [Layout](.claude/c_c_design_layout.md), then [App grid](.claude/c_c_c_design_grid_app.md) if needed |
| Typography | [Type](.claude/c_c_design_type.md) |
| Colours or themes | [Colour](.claude/c_c_design_colour.md) |
| Other controls | [Controls](.claude/c_c_design_controls.md), using current `UIPrimitives/Design.swift` primitives and the project AGENTS.md overrides |
| Settings pages | [Settings design](.codex/c_settings_design.md) |

Use existing shared primitives and Design tokens. Change a shared primitive instead of inventing a local skin. Do not copy these contracts into agent files: link here. New detailed contracts belong in focused child files using the c_ depth convention. Verify the rendered installed app; compilation alone does not verify geometry.

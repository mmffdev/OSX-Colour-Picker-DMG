# Dropdowns and dropups

Shared contract agreed with Rick, 2026-10-17. Read through [styles.md](../styles.md) whenever creating or changing a selector, including a selector inside an editor popup.

## Appearance and primitives

- Use DropdownSkin / DropdownButton for triggers and SwissDropdown.MenuPanel for menus. AnalysisMenu retains NSPopUpButton data APIs but opens the house MenuPanel; never allow the native macOS menu to render.
- Header/actionbar triggers are borderless, left-aligned and sized to the selected text plus a small arrow, using InlineDropdownSkin. No outline or separated arrow compartment there. Form/settings triggers retain the faint Rule border, four-point corners and contained trailing chevron compartment. Menus use Card, square Rule edges, Mist hover, section headings/separators and a tick for selection. No dark translucent native menu, yellow native selection or stock bezel.
- Use content-sized, bounded widths. Profile-header triggers fit the full selected name and the header wraps to additional rows when needed; other bounded selectors retain an accessible full name; a control or menu must never stretch across spare page width.
- Every row/action has a readable accessible name, tooltip where needed, keyboard operation and pointing-hand/hover feedback. Preserve disabled and selected states.

## Anchoring

- Convert the actual trigger bounds to screen coordinates. Never anchor to the containing header, rail, page or whole form.
- Dropdowns open immediately below their own triggers, aligned with the trigger's left edge. Dropups open immediately above their triggers with the same alignment. Use MenuPanel.place(anchoredTo:preferAbove:within:) for window/screen clamping and scrolling; only flip when the intended direction cannot fit.
- Keep the trigger visible. Bound long lists to the available owning-window space and scroll with the house QuietScroller lane. Moving the window or changing layout must not leave a stale popup stranded elsewhere.
- Escape and outside click dismiss through Overlays. Nested editor dropdowns must retain their editor underneath. File/permission sheets retain their native interaction and must not dismiss the form beneath them.

## Alignment and page profile header

- Header labels and value text share one optical centre line. Each 40 pt page profile-header row uses 28 pt controls with equal six-point top/bottom padding; label baseline is the same as the controls' text baseline.
- The profile header occupies the page between the rails, level with the first 40 pt panel headers. Rails retain their original top. Reuse the frame's top/side rules; do not add a second border. Keep the single bottom separator.
- Preset starts at the same page inset as the palette tab icon below. Workflow, Target and Tolerance follow as a compact group; Rendering Intent is also visible for print and RGB ICC targets. Narrow pages wrap complete label/dropdown pairs onto additional 40 pt rows, like Viewport-Actionbar. The header grows and the page begins below it; the rails keep their original top. Preserve full selected names without horizontal scrolling.
- Preset lists custom saved setups first, with inline edit/export/remove actions, then grouped built-in targets. Save Profile and inline Edit actions replace the lower preset list with an adaptive draft form inside the same trigger-anchored dropdown. Keep My Profiles above it. Save selects the resulting profile and restores the list; Cancel or Escape discards the draft and restores the list. Nested selectors keep their editor underneath. The separate header editor icon is retired. Saved presets include the full viewing-proof state.

## Verification

Inspect the installed app at normal and narrow widths. Open every changed selector, including selectors inside its editor: check house styling, actual-trigger anchoring, compact width, selected ticks, centre line, long-list scrolling and dismissal. Keep unrelated data and working-tree changes intact.

The global profile header includes a borderless Black Point Compensation Off/On selector immediately after Rendering Intent for print and RGB ICC targets. It shares SavedPrintProfiles.current.blackPoint with the existing form checkbox, wraps as a complete label/value pair, and is enabled only for Relative Colorimetric, matching the conversion engine. Preserve RGB Numbers is not part of this UI.

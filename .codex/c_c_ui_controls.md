# Controls and interaction contract

Parent: [UI framework](c_ui_framework.md). Load [dropdown contract](c_styles_dropdowns.md) before changing a selector and [styles.md](../styles.md) for the type/colour system.

Use `ActionButtonSkin`/`SwissButton` for text actions; `PaletteAssetIcon` for compact accessible icon actions; `SwissCheckbox` for square checks; `SwissDropdown` or `InlineDropdownSkin` according to location; `WorkspaceChoiceControl` for underline-selected modes; `SwissContextMenu` for anchored actions; `SwissFocusModal` for protected-focus confirmations and forms, including its shared `colourField` swatch well. That field opens `StudioColourPicker`; Select or double-click commits only its modal draft, then the form's Save persists it. `SwissFocusModal` presents the card before processing its frozen backdrop blur, rendering the blur asynchronously at bounded resolution to keep button presses responsive. Their shared implementations live in `UIPrimitives/Buttons.swift`, `Controls.swift`, `Design.swift`, `PaletteAssetControls.swift`, `StudioContextMenu.swift` and `SwissFocusModal.swift`. Do not recreate these inside a page. The standard control row is 32 pt and body/control text is 13 pt.

Each control needs a meaningful label, hover and pressed state, keyboard focus and disabled treatment. Use the route's props to omit irrelevant controls entirely, not to leave inert switches. When a page needs a novel variant, add a prop to the nearest shared primitive and verify the existing Library route still renders correctly.

Clicking the backdrop outside a `SwissFocusModal` card dismisses the modal and discards its draft, like Cancel. Dropdowns and colour pickers above the modal remain independently interactive. The underlying page stays on its current route.

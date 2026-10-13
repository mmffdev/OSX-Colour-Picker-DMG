# Apple Menubar — App Store

Built in `codex/apple-menubar`, from the current uncommitted app baseline. `AppleMenubar.swift` is guarded by `APPSTORE`; the direct-download build has no status item or settings entry.

A single movable status item groups recent swatches, the shared `Prefs.copyFormat` selector and the Colorgain icon. The icon menu reuses `LibraryController` Picker and Rectangle Picker. Ten slots are shown initially; Settings → Apple Menubar → 01 Settings can hide them, choose 1–20, and mute menubar sounds. Empty slots remain disabled until real samples arrive.

`ColourCopies` retains twenty entries in portable app data; the footer displays its latest ten. Rectangle samples entered through the menubar are remembered without changing the clipboard. Clicking a swatch uses the selected format and preserves source CMYK where available. Format changes notify both surfaces. Sound uses the existing Copy/Pick effects and respects Sounds master/event switches.

Will It Print result headers sort the entire palette, with stable ties and missing predictions last. `PrintBloomView` keeps source palette order, uses a shared numeric ΔE radius scale and a dashed user-tolerance ring. Filled petals show master previews; their inner band shows the print prediction. Green/red outlines indicate whether ΔE holds, and unknown predictions remain neutral. These are profile predictions, never measurements or certification. Petal selection is linked to the table. The shared Swiss modal exposes palette, profile, rendering intent and tolerance controls.

New Palette creates an empty palette and saves it as the picker target without navigation. Its nonactivating naming bar offers Picker and Rectangle Picker beside the field. Return saves the name; Escape retains the saved default name. Rectangle capture appends to the target instead of creating another palette or reopening the workspace. The App Store app remains resident after closing its last window; Quit stays explicit.

Settings group spacing measures the wrapped description and snaps the next setting to the shared grid after one clear row. Library, General and Apple Menubar use this instead of fixed eight-row gaps. The expanded bloom uses five/three/four grid columns: chart, prediction controls, and a whole-palette comparison graph. All headings share the same strong guide and type style. The grid overlay can be shown inside the modal for verification.

# Saved print profiles

`PrintProfiles.swift` stores the versioned profile list, current settings and selected ID under `settings.prepress.printProfiles` in `colorgain.coldata`. Names/descriptions accompany the installed ICC condition name, rendering intent, BPC flag and ΔE00 tolerance. These are reusable settings presets, not generated ICC files. Missing ICC references are retained; unavailable predictions remain unknown rather than falling back to a different press.

`PrintProfileSelector` is shared by Will It Print? → 01 Palette (above its settings) and the palette header subtitle row. Its management menu provides Save, Edit, Duplicate, slider-confirmed Remove, Import and Export. Edit keeps identity; duplicate and import create independent identities and unique names. Removing an active saved entry retains the current settings. All persistence reads the existing .coldata manifest before writing, preserving unrelated settings and catalogue registrations.

`.colpro` is version-1 JSON identified by `colorgain.print-profile`, carrying one complete named preset. Its ICC condition is referenced by name, not embedded. Import validates size, schema and finite tolerances before updating .coldata; unsupported files leave saved data intact. The extension is registered in Info.plist for native file panels.

The shared `printProfilesChanged` notification updates PrePress results and invalidates palette prediction caches. Visible tile predictions are cached; each colour area is split exactly at its midpoint when Delta is on. ΔE appears beside the existing metadata halo, not in the colour block. Palette-card summaries use maximum ΔE; swatch rows show individual ΔE00. The Delta On/Off preference is also kept in .coldata. Dropdown values and menu rows use the shared 13-point body style.

`runPrintProfileTests` verifies persistence, preservation of unrelated .coldata entries, editing, duplication, removal, .colpro round trips and rejected imports. Native QA must check section-01 placement, narrow metadata rows, file-panel extensions and shared selector updates without altering real presets for test purposes.

# Settings design

Settings use the macOS-style `SettingsWindowController` in `SettingsWindow.swift`, with `SettingsPanel` and toolbar/section groups. New settings routes must open that window. Do not reintroduce legacy in-page settings. See [current authority](AGENTS.md#current-settings-authority). Shared Swiss workspace/modal styling remains in `styles.md`.

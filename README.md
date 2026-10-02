# MMFFDev Colour 3

A macOS colour app, written in Swift with AppKit and no dependencies. Pick colours from the screen, keep them in palettes and projects, build new ones on a colour wheel, check them for contrast, and hand them over as files a team can use.

## What it does

- **Pick any colour on screen** with the native loupe; the hex is copied to the clipboard and kept in the library.
- **Palettes and projects.** Group colours into palettes, palettes into projects, and star the ones you use most. Tag colours and palettes.
- **cLab.** Build a palette on the painters' colour wheel with nine harmony rules, dragging the colours and watching the result change.
- **cTools ▸ Contrast.** Score a text colour on a background by the WCAG 2 ratio or APCA, fix it to the nearest shade that passes, and preview it in your own words and fonts.
- **Typography palettes.** Keep text-and-background pairings, each with its wording and fonts, shown as real examples.
- **Export.** Copy in many formats, export palettes, or write a design pack: a stylesheet, a PNG per swatch, a proof sheet and a licence.
- **Sync** between Macs through a shared folder.

`--pick` launches the sampler with no window, prints the hex and exits, for binding to a global hotkey.

## Build from source

Requires the Xcode command line tools (`xcode-select --install`).

```bash
./build.sh        # compiles, runs the self-test, installs to ~/Applications/MMFFDev Colour 3.app
./make_dmg.sh     # compiles, runs the self-test, packages MMFFDev-Colour-3.dmg
./make_pkg.sh     # compiles, runs the self-test, packages MMFFDev-Colour-3.pkg
```

The build signs with a Developer ID from the keychain when there is one, and ad-hoc otherwise. `store_notary_credentials.sh` saves notarisation credentials once, from a `.env.notarytool` file that is never committed.

`./MMFFDevColour3 --self-test` (run by every build) exercises the library, sync, export and colour maths against a throwaway folder.

## Files

- `main.swift` — entry point, pick mode and the menu bar.
- `Model.swift`, `Sync.swift`, `Controller.swift` — the library, its sync and merge, and everything that changes it.
- `MainWindow.swift`, `Sidebar.swift`, `PaletteView.swift`, `AllSwatchesView.swift` — the window and its pages.
- `ColourFormats.swift`, `ColourNames.swift`, `ColourScience.swift` — colour values, names and the maths behind the wheel and contrast.
- `Lab.swift`, `LabContrast.swift`, `Typography.swift` — cLab, Contrast and Typography palettes.
- `Exporters.swift`, `Projects.swift`, `Tags.swift`, `HaloMenu.swift`, `Shortcuts.swift`, `SettingsWindow.swift`, `Prefs.swift`, `Helpers.swift`, `Palette.swift` — the rest of the app.
- `SelfTest.swift` — the self-test.
- `AppIcon.icns`, `tools/make_icon.swift` — the icon and the script that draws it. The script is kept out of the root so the build, which compiles every Swift file there, leaves it alone.

## History

This repository began with two earlier, smaller apps (MMFFDev Colour and MMFFDev Colour 2). Their source was removed once this one replaced them; it remains in the git history. The app can still bring in a library left behind by either.

# MMFFDev Colour 3

A macOS colour management and proofing app, written in Swift with AppKit. Its promise is one colour, defined once, proven everywhere: each colour is held as a master that belongs to no device, and every medium (screen, print, video, cinema, 3D) gets its own value with a figure for how faithful it is. Hex is one of those values, not the point.

The design behind this, and what is built and what is not, is in [COLOUR-MANAGEMENT.md](COLOUR-MANAGEMENT.md). Read it before any work on colour. The ideas list is [scratch.md](scratch.md).

## What it does

- **Pick any colour on screen** with the native loupe. A pick sRGB cannot hold is kept as Display P3.
- **New Colour** takes a colour as what it is: Display P3, a CMYK build for a press, Lab, ProPhoto RGB or a hex. It is kept exactly as typed.
- **Catalogues, projects and palettes.** A catalogue indexes projects, and each project is a folder of its own files that can be handed over, moved and imported. Every project has an Overview page holding its details. Star, tag, group and filter colours and palettes.
- **Colour profiles and channels.** A profile names the media a piece of work goes to (sRGB, Display P3, a press condition such as FOGRA39, Rec. 709, Rec. 2020, P3-D65, DCI-P3, ACEScg). Each swatch's Channels view shows the value for every channel, the difference from the master, and whether it is in range.
- **Purposes.** One palette can serve several kinds of work (web, print, video and so on), each with settings of its own.
- **Analysis.** A palette or a swatch read seven ways: as a list, round the hue circle, by lightness, as people with a colour vision deficiency see it, as a gradient, as pairs, and on light and dark grounds.
- **Gamut map and histograms.** See where colours sit and what each screen and press can hold, and how a swatch's values sit against the rest of its palette.
- **Colour Lab.** Build a palette on the painters' colour wheel with nine harmony rules, dragging the colours and watching the result change.
- **Tools ▸ Contrast.** Score a text colour on a background by the WCAG 2 ratio or APCA, fix it to the nearest shade that passes, and preview it in your own words and fonts.
- **Typography palettes.** Keep text and background pairings, each with its wording and fonts, shown as real examples.
- **History.** Every change is a step in the History rail. Click one to go back, or Play Back to watch the library build up. Steps can also be written into each project's file.
- **Export.** Copy in many formats, export palettes, or write a design pack: a stylesheet, a PNG per swatch, a proof sheet and a licence. The Adobe helper puts palettes straight into Adobe apps' swatch folders.
- **Sync** between Macs through a shared folder.
- **Updates** through Sparkle.

## Command line

- `--pick` launches the sampler with no window, prints the hex and exits, for binding to a global hotkey.
- `--self-test` exercises the library, sync, export and colour maths against a throwaway folder. Every build runs it.
- `--write-project-files` writes every project's files now. Add `--catalogue <name>` for a catalogue other than the current one.
- `--halo-demo` opens a window to try the halo menu on its own. Add `--snapshot <folder>` to save a picture of each dial and quit.

## Build from source

Requires the Xcode command line tools (`xcode-select --install`).

```bash
./build.sh        # compiles, runs the self-test, installs to /Applications/MMFFDev Colour 3.app
./make_dmg.sh     # compiles, runs the self-test, packages MMFFDev-Colour-3.dmg and writes the Sparkle update feed
./make_pkg.sh     # compiles, runs the self-test, packages MMFFDev-Colour-3.pkg
```

The app installs to `/Applications`, not `~/Applications`, because the Adobe helper only works from there. A copy left in `~/Applications` by an older build is removed.

The build stamps the commit's short hash into the app, and the window's footer shows it at the bottom right (for example "Release v3.0  8aee45d"). A "+" after the hash means the build had uncommitted Swift changes. Commit first, then build.

Signing lives in `signing.sh`. The build signs with a Developer ID from the keychain when there is one, and ad hoc otherwise. `store_notary_credentials.sh` saves notarisation credentials once, from a `.env.notarytool` file that is never committed.

## Files

Every Swift file in the root is compiled into the app, so scripts and other Swift that is not part of it are kept in folders.

**Entry and library**

- `main.swift`: entry point, the command line modes and the menu bar.
- `Model.swift`, `Sync.swift`, `Controller.swift`: the library, its sync and merge, and everything that changes it.
- `Catalogue.swift`, `ProjectFile.swift`, `LostProject.swift`: the catalogue on disk, each project's own files, and the page shown when a project's files cannot be found.
- `History.swift`, `HistoryRail.swift`: the history of steps and the rail that lists them.
- `FormMemory.swift`: what has been typed into project forms, so it need not be typed again.

**Colour**

- `ColourEngine.swift`: the master colour (CIE XYZ, D50) and its rendering into every space and press.
- `ColourIdentity.swift`: how each colour is keyed, as a plain hex or as a colour with its own source, master and kind.
- `ColourProfiles.swift`, `Purposes.swift`: named sets of channels, and what a palette is for.
- `ColourFormats.swift`, `ColourNames.swift`, `ColourScience.swift`: colour values, names, and the maths behind the wheel and contrast.
- `NewColour.swift`: typing a colour in as P3, CMYK, Lab, ProPhoto or hex.

**Window and pages**

- `MainWindow.swift`, `Sidebar.swift`, `ContextRail.swift`: the window, rail1 (the Catalogue) and rail2 (the context rail).
- `Overview.swift`: a project's Overview page.
- `PaletteView.swift`, `AllSwatchesView.swift`, `SwatchList.swift`, `PaletteGroups.swift`: palette pages in the grid and vertical views, with grouping and filtering.
- `Analysis.swift`, `GamutMap.swift`, `Histogram.swift`: the Analysis page, the gamut map and histograms.
- `Lab.swift`, `LabContrast.swift`, `Typography.swift`: Colour Lab, Contrast and Typography palettes.
- `PageHeader.swift`, `Buttons.swift`, `PaneGrip.swift`, `Modal.swift`, `HaloMenu.swift`, `Splash.swift`: the page header, the app's own buttons, the pane grips, centred questions, the halo menu and the splash screen.

**Everything else**

- `Exporters.swift`, `Projects.swift`, `Tags.swift`, `Shortcuts.swift`, `SettingsWindow.swift`, `Prefs.swift`, `Permissions.swift`, `Helpers.swift`, `Palette.swift`: export, projects, tags, shortcuts, settings, preferences, macOS permissions, shared helpers (including `TextSize`, the only source of UI font sizes) and the palette model.
- `AdobeHelper.swift`, `AdobeHelperRules.swift`: the app's side of the Adobe helper, and the rules it shares with the helper.
- `HaloDemo.swift`: the `--halo-demo` window.
- `SelfTest.swift`: the self-test.

**Folders**

- `helper/`: the Adobe helper itself, a small root process that can only write swatch files into Adobe's library folders.
- `help/`: the help pages (installing, adding palettes to Adobe apps, history).
- `installer/`: the `.pkg` installer's distribution file and welcome page.
- `icons/`: the icon for each kind of file the app keeps (`.colproject`, `.colpalette` and the rest).
- `vendor/Sparkle/`: the Sparkle update framework.
- `tools/make_icon.swift`: draws `AppIcon.icns`.
- `design/`, `assets/`: design reviews, mockups and icon studies. Not part of the build.

## History

This repository began with two earlier, smaller apps (MMFFDev Colour and MMFFDev Colour 2). Their source was removed once this one replaced them and remains in the git history. The app can still bring in a library left behind by either.

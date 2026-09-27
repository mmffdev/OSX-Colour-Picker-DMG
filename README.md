# MMFFDev Colour

A rapid-prototype macOS colour picker, written in Swift with AppKit. Point at any pixel on screen, grab its hex, and build up a library of swatches you can come back to.

This is a small tool built for our own use — intentionally minimal, no dependencies, one Swift file. If it's useful to you, help yourself.

## What it does

- **Pick any colour on screen** via the native `NSColorSampler` loupe.
- **Copies the hex to the clipboard** automatically (`#RRGGBB`, uppercase).
- **Plays the system camera shutter** on pick, so you know it fired.
- **Stores every pick in a library**, shown as a grid of swatches in the main window.
- **Click a swatch** to re-copy its hex. **Delete / right-click → Delete** to remove.
- **Survives restarts** — the library is JSON at `~/Library/Application Support/MMFFDev Colour/library.json`.

Two entry points:
- **Window mode** (default): opens the library window with a **Pick a Colour** button (⌘P).
- **Pick mode** (`--pick`): launches the sampler directly with no window, prints the hex to stdout, exits. Useful for binding to a global hotkey via Shortcuts, Raycast, Alfred, etc.

## Install

Two options from the latest [Release](https://github.com/mmffdev/OSX-Colour-Picker-DMG/releases):

- **DMG** (`MMFFDev-Colour.dmg`) — mount and drag **MMFFDev Colour.app** onto the **Applications** shortcut.
- **PKG** (`MMFFDev-Colour.pkg`) — double-click, step through Apple's installer; lands the app in `/Applications`. Handy for MDM / scripted deployment.

The app is ad-hoc signed — on first launch you may need to right-click → **Open** to get past Gatekeeper.

## Build from source

Requires Xcode command line tools (`xcode-select --install`).

```bash
./build.sh        # compiles and installs to ~/Applications/MMFFDev Colour.app
./make_dmg.sh     # compiles and packages a drag-to-Applications DMG
./make_pkg.sh     # compiles and packages a .pkg installer for /Applications
```

## Files

- `main.swift` — the whole app (pick mode + library window).
- `make_icon.swift` — generates the iconset from a procedural design.
- `build.sh` — compile + install to `~/Applications`.
- `make_dmg.sh` — compile + package as `MMFFDev-Colour.dmg`.
- `make_pkg.sh` — compile + package as `MMFFDev-Colour.pkg`.
- `Info.plist` — bundle metadata.
- `AppIcon.icns` — compiled icon.

## Version 2 — swatches

`v2/` is a separate app, **MMFFDev Colour 2**, that installs alongside the original. It adds named swatches (collections of colours), an All Colours / Swatches switch, sorting, and copy-all per swatch.

Install from `v2/MMFFDev-Colour-2.dmg` (drag to Applications) or `v2/MMFFDev-Colour-2.pkg` (installs to `/Applications`). Ad-hoc signed like the original, so right-click → **Open** on first launch.

```bash
v2/build.sh       # compiles, runs the self-test, installs to ~/Applications/MMFFDev Colour 2.app
v2/make_dmg.sh    # compiles, runs the self-test, packages v2/MMFFDev-Colour-2.dmg
v2/make_pkg.sh    # compiles, runs the self-test, packages v2/MMFFDev-Colour-2.pkg
```

- **New Swatch** (⌘N) creates a swatch with a default name and opens the name for editing. Rename later with the pencil or a double-click.
- **Picks go to** chooses which swatch new picks land in. A new swatch becomes the target automatically; the eyedropper on a swatch header does the same.
- **Copy all** on a swatch header copies its colours as `#FF0000, #FF6600, #0033FF`, in the order shown.
- **Sort** — Newest First, Oldest First, or Colour Order (by hue, light to dark, greys last).
- Right-click a colour to add it to a swatch, remove it from one, or delete it from the library.

Its library is `~/Library/Application Support/MMFFDev Colour 2/library.json`. On first launch it copies in the colours from the original app; **File → Import from MMFFDev Colour** pulls in anything picked there since. The original app's library is only ever read.

## Status

Prototype quality. It works, we use it daily, but there are no tests, no localisation, and no notarisation. Pull requests welcome if you want to push it further.

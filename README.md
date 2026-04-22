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

## Status

Prototype quality. It works, we use it daily, but there are no tests, no localisation, and no notarisation. Pull requests welcome if you want to push it further.

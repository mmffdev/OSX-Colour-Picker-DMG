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

- **Pick a Colour** (⌘P) starts a picking session: the loupe comes straight back after each pick so you can walk across a screen building a swatch. Press **Esc**, click back on the app window, or press ⌘P again to stop.
- **Palette from Image…** (⌘I), or drop an image onto the window, creates a swatch named after the file holding up to 8 colours found by k-means clustering (Core Image's `CIKMeans`). Top it up with the eyedropper — the new swatch is the pick target.
- **Export Library…** (⌘E) asks for a folder (with a New Folder button) and writes a `MMFFDev Colour 2 Export` subfolder containing `library.json` plus one text file per swatch and one for all colours, each a comma-separated hex list in the current sort order. Existing exports are never overwritten.
- **Catalogues** — separate libraries, each with its own colours and swatches, in the way Lightroom has catalogues. Switch, create or open one from **File ▸ Catalogue** or **Settings**. The app reopens the one used last. **Open Catalogue File…** turns any `library.json` — from an export or a backup — into a new catalogue; the original file is only read.
- **Sync** — in **Settings** (⌘,) choose a folder inside iCloud Drive, Dropbox or any shared drive, and choose the same folder on your other Mac. On opening, and whenever you return to the window, the app compares this Mac's copy with the synced one. If the synced copy has changes it lists them and offers **Merge**, **Use Synced Copy**, **Keep This Mac's** or **Not Now**. Changes made only on this Mac are sent without asking. **File ▸ Sync Now** (⇧⌘S) checks on demand.
  - **Merge loses nothing**: colours and swatches from both Macs are combined. A deletion made on one Mac is honoured on the other, but anything picked again afterwards is kept.
  - **Backups first**: both copies are saved, timestamped, before every merge or replacement — in the sync folder's `Backups` and on this Mac. Settings chooses how many to keep (default 50, or all).
  - Conflicted copies left behind by the cloud service are merged in and then moved to `Backups`, never deleted. An unreadable or still-downloading synced file stops the sync without changing anything.
  - Each catalogue syncs to its own folder: `<your folder>/MMFFDev Colour 2 Sync/<catalogue>/library.json`. Catalogues created on the other Mac appear in the list automatically.
- **New Swatch** (⌘N) creates a swatch with a default name and opens the name for editing. Rename later with the pencil or a double-click.
- **Picks go to** chooses which swatch new picks land in. A new swatch becomes the target automatically; the eyedropper on a swatch header does the same.
- **Copy all** on a swatch header copies its colours as `#FF0000, #FF6600, #0033FF`, in the order shown.
- **Sort** — Newest First, Oldest First, or Colour Order (by hue, light to dark, greys last).
- Right-click a colour to add it to a swatch, remove it from one, or delete it from the library.

The **Main** catalogue is `~/Library/Application Support/MMFFDev Colour 2/library.json`; other catalogues live beside it in `Catalogues/<name>/`. On first launch it copies in the colours from the original app; **File → Import from MMFFDev Colour** pulls in anything picked there since. The original app's library is only ever read.

## Version 3 — palettes, cards and exports

`v3/` is **MMFFDev Colour 3**, a third app that installs alongside the other two. It has its own library and copies your version 2 palettes in on first launch; version 2's library is only read. Design notes, research and the parked ideas are in [scratch.md](scratch.md).

A **swatch** is one colour. A **palette** is a named set of swatches. A **catalogue** is a whole library.

```bash
v3/build.sh       # compiles, runs the self-test, installs to ~/Applications/MMFFDev Colour 3.app
v3/make_dmg.sh    # compiles, runs the self-test, packages v3/MMFFDev-Colour-3.dmg
v3/make_pkg.sh    # compiles, runs the self-test, packages v3/MMFFDev-Colour-3.pkg
```

- **Sidebar** — Favourites at the top, then All Swatches, Palettes, and Custom Palettes. Each palette has a star, a count and its own identity colour. Click a name again to rename it; right-click for more.
- **Toolbar** — Pick, New Palette, Share, Settings and Search. Right-click it for Icon and Text, Icon Only or Text Only, and for Customise Toolbar, which also offers From Image, Build Palette, Paste Colours, Export and Sync.
- **Palette page** — one card per swatch, filled with the colour, with HEX, RGB, HSL, HSV and CMYK rows. Click the card to copy in the format chosen in Settings; click a row to copy that row. Scroll past the end to move to the next palette (⌘] and ⌘[ do the same).
- **All Swatches** — every colour in one even grid. Arrange by palette, colour group, hue, lightness, saturation, age or name. A bar under each tile shows which palette it belongs to.
- **Build Palette** (⇧⌘N) — name the palette in the bar across the top, click swatches to choose them, and watch them collect in the rail on the right. Saved palettes appear under Custom Palettes.
- **Make Palette** — right-click a swatch for complementary, analogous, triadic, split, tetradic, tints and shades, or a 50–950 scale.
- **New Palette from Clipboard** (⇧⌘V) — finds every hex colour in copied CSS, JSON or text.
- **Export** (⌘E) — CSS variables, SCSS, Tailwind v3 and v4, design tokens JSON, Swift, Android, Adobe ASE and ACO, GIMP, macOS colour list, PNG sheet, plain text. **Add to macOS Colour Panel** makes a palette available in every Mac app.
- **Projects** — sections in the sidebar that hold palettes (⌥⌘N to create one). The **+** on a project's header starts a palette inside it. Drag palettes to reorder them or move them between projects; drag project headers to reorder projects. Every palette row has star, duplicate and delete icons.
- **Tags** — on palettes (the field in the palette header) and on swatches (right-click ▸ Tags…). The Tags section in the sidebar lists them; choosing one shows the matching swatches. Search matches tags too.
- **Design Pack** (⌥⌘E) — one folder for a palette, a project or the whole catalogue: `pack.json`, a `README.md` listing every swatch, `LICENSE.md` from your Settings, `proof-sheet.png`, and per palette a `:root` CSS file, a sheet and a PNG per swatch. Drop it into a git checkout and tick *Commit and push with git*, or into any shared folder.
- **Settings** (⌘,) — General, Cards & Grid, Export (with the licence text for design packs), Catalogues (including Rename), Sync.

Catalogues, sync and backups work as in version 2, in a sync folder of their own (`MMFFDev Colour 3 Sync`). Catalogues can be renamed from Settings; the rename carries through to the sync folder and the other Mac follows it on its next sync.

Its library is `~/Library/Application Support/MMFFDev Colour 3/library.json`. To try the app without touching it, set `MMFFDEV_COLOUR3_HOME` to an empty folder.

## Status

Prototype quality. It works, we use it daily, but there are no tests, no localisation, and no notarisation. Pull requests welcome if you want to push it further.

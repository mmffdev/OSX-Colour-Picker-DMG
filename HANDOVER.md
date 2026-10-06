# Handover: MMFFDev Colour 3, 2026-10-05

For the next agent picking this up in another IDE. Read `.claude/CLAUDE.md` first: it holds the
project rules (build after every commit, the Vector backlog, the type scale, capitalised labels).

## Where things stand

- **Branch:** `redesign-001`, local only, never pushed. Cut from `v3-palettes-projects-sync` at `b83cdb0`.
- **Installed app:** `/Applications/MMFFDev Colour 3.app`, built from `8aee45d`. Footer reads `Release v3.0  8aee45d+`.
- **Self-tests:** 529 pass (`./build.sh` runs them).
- **`v3-palettes-projects-sync`** is pushed and sits at `b83cdb0`. `main` is 111 commits behind and holds the old Colour 2 app. Do not switch to it.

## Commits on redesign-001, oldest first

| Commit | What it did |
|---|---|
| `cd7560f` | Rail defaults narrower: rail1 220, rail2 220, History 260 (minimums 200, 200, 230); page minimum 560. In rail1 a palette's count and gear share one slot, gear on hover; strip 24 wide. |
| `32042d9` | "Wheel changes palette" is off by default (`Prefs.wheelChangesPalette`). It made the rails appear to scroll by themselves. |
| `7c904f7` | Halo button removed from swatches. A press on the colour block opens the halo, on the grid and in the vertical view. |
| `0c08698` | Theme modes (Match The Mac, Light, Dark), footer sun and moon switch, L key, Shift-L page-alone full screen, thin quiet scrollbars (`QuietScroller`), toolbar takes the background. |
| `cfd7f81` | History rail's table is transparent, so it shows the window background. |
| `8aee45d` | Grey quarter steps removed. L goes black, white, then back to the theme. Settings gained "My Own Colours": a background well and text Automatic, Black or White. |

## Open decisions with Rick, nothing built

1. **Light theme colour.** Recommended: a strictly neutral off-white, about `#F2F2F2`, with pure white kept under L. Rick had not answered. Today light is `#FFFFFF` (`Theme.background` in Helpers.swift).
2. **L key stops.** Now: black, white, theme. Rick was confused by the third stop. Options discussed: flip black and white only, or Black, Neutral Grey, White. Rick's favourite "grey" is the dark theme's charcoal, `#242424`, not a mid grey.
3. **Palette page redesign.** Rick's chosen mockup is `design/palette-review/palette-page-mockups/01-light.png`, with rail1 and rail2 kept. A first attempt to build the whole page in one go was rejected and discarded. Build one part at a time and show each. Rick then said "lets try another" and has not said which mockup. The earlier review is in `PALETTE-PAGE-DESIGNS.md`.
4. **rail1 at 220 is tight.** Palette names inside a project show about five letters. Options offered: thin the rows further, settle at 240, or flatten the project tree.

## Known problems, not fixed

- **Laptop: titles clipped under the toolbar.** On a 1440 by 810 screen "Catalogue", the page title and "History" are cut off at the top. Likely the content needs more height than the screen has. Not investigated.
- **History rows truncate** at narrow widths ("Set…", "Turn…").
- **Dragging a swatch on the grid** may open the halo, since the press on the colour is now the trigger. Untested.

## Not verified by hand

The agent never drives Rick's UI with real clicks or keys. These were checked only by code, self-tests or pixel sampling of a trial copy:

- L and Shift-L key presses, and the real jump to full screen.
- The footer theme switch, the Settings Theme tick boxes, the colour well and the text pop-up.
- The halo opening from a press on the colour.
- The wheel fix curing the "rails scroll by themselves" report.

## Working tree: files that are NOT this work

Another agent has uncommitted work here. Leave it alone and never commit it by accident:

- Modified: `Info.plist`, `build.sh`, `make_dmg.sh`, `make_pkg.sh` (file-type icons), `main.swift` (splash screen).
- Untracked: `Splash.swift`, `icons/`, `assets/`, `design/`, `.idea/`, `.claude/settings.json`.

`main.swift` is shared. To commit only your own lines of it, build the staged copy from `git show HEAD:main.swift` plus your edit, then `git update-index --cacheinfo`. Do not `git stash`: it takes the other agent's files with it.

This file, `HANDOVER.md`, is also uncommitted.

## How to work here

- **Build and install:** quit the app, run `./build.sh`, then `open -g -a "MMFFDev Colour 3"`. Commit first, then build.
- **Test without disturbing Rick:** a scratch copy of the app run with `MMFFDEV_COLOUR3_HOME=<copy of test data>` and `MMFFDEV_COLOUR3_SHOW=palette:<name>` (also `settings:<n>`, `halo:<name>`, `analysis:<name>`). It uses the preferences domain `com.mmffdev.mmffdevcolour3.trial`. `MMFFDEV_COLOUR3_PAGE_ALONE=1` shows the page-alone view without going full screen.
- **Theme code:** `Theme`, `ThemeMode`, `ThemeText` and `QuietScroller` in Helpers.swift; button greys in Buttons.swift; the L keys and page-alone view in MainWindow.swift (`plainKey`, `showPageAlone`); the Settings section in `ThemePanel`.
- **Image viewing was failing** in the last session, so screenshots were read by sampling pixels. If images work in the new IDE, look at Rick's screenshots directly.
- **Rick's register:** recommend first, name the one trade-off, plain business language, warmth. Options as a, b, c in chat. Every UI label capitalised. Tick boxes, never round radio buttons.

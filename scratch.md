# MMFFDev Colour 3 — scratch

Working notes for the version 3 redesign. Ideas, decisions, research, and what is parked.
Status marks: **[built]** in v3 now · **[next]** worth doing soon · **[later]** parked · **[no]** decided against.

---

## 1. Words

| Word | Means |
|---|---|
| **Swatch** | One colour. |
| **Palette** | A named set of swatches. (v2 called this a "swatch".) |
| **Custom palette** | A palette built by choosing swatches already in the library. |
| **Catalogue** | A whole library: all swatches and palettes. Like a Lightroom catalogue. |

The saved file still uses the v2 field names (`swatches`, `entries`) so v2 libraries open unchanged.

## 2. Layout

Three panes and a toolbar.

```
┌──────────────────────────────────────────────────────────────────────┐
│ ◧  Pick  New Palette              Share  Settings   🔍 Search        │  toolbar (customisable)
├────────────┬─────────────────────────────────────────┬───────────────┤
│ FAVOURITES │  Brand 2026   ★  ⌖   Sort ▾   Copy all  │  NEW PALETTE  │
│  ● Brand   │ ┌────────┐ ┌────────┐ ┌────────┐        │  ■ Steel Blue │
│ LIBRARY    │ │ Fiji   │ │        │ │        │        │  ■ Coral      │
│  ▦ All     │ │ HEX    │ │  card  │ │  card  │        │  ■ Ivory      │
│ PALETTES   │ │ RGB    │ │        │ │        │        │               │
│  ● Brand   │ │ HSL …  │ └────────┘ └────────┘        │  3 swatches   │
│  ● Sunset  │ └────────┘                              │  [ Save ]     │
│ CUSTOM     ├─────────────────────────────────────────┤               │
│  ● Web UI  │ 12 swatches · picks go to Brand 2026    │               │
└────────────┴─────────────────────────────────────────┴───────────────┘
   rail 1              content                            rail 3 (only while building)
```

### Rail 1 — sidebar **[built]**
- **Favourites** at the top: starred palettes.
- **Library ▸ All Swatches**: the view-all page.
- **Palettes**: everything picked, pasted or taken from an image.
- **Custom Palettes**: built with the palette builder. Hidden until there is one.
- Each palette row: identity dot, name (click again to rename), count, star, and an eyedropper mark on the pick target.
- Right-click: rename, favourite, send picks here, duplicate, export, add to macOS colour panel, delete.

### Toolbar **[built]**
Native `NSToolbar`, so the user gets Icon and Text / Icon Only / Text Only and Customise Toolbar for free, and the arrangement is remembered.
- Default set: sidebar toggle · Pick · New Palette · (space) · Share · Settings · Search.
- Also available to drag in: From Image, Build Palette, Paste Colours, Export, Sync Now.
- Pick is in the default set although it was not in the brief. Without it the core action is a menu item only.

### Palette page **[built]**
- Header: name, star, pick-target toggle, sort, copy all.
- One **card** per swatch, filled with the colour, text in black or white by contrast.
- Card rows: HEX, RGB, HSL, HSV, CMYK. Which rows show is a setting.
- **Click the card** copies in the format chosen in Settings. **Click a row** copies that row's value.
- Optional contrast line: ratio and WCAG grade against white and against black.
- **Wheel past the end** of a palette moves to the next one; past the top moves to the previous one.
  A palette that fits on screen changes on any wheel movement. Can be switched off.

### All Swatches page **[built]**
- A plain even grid, no section headers, like a paint chart.
- **Filter bar**: Arrange by (Palette, Colour Group, Hue, Lightness, Saturation, Newest, Oldest, Name) and Show (one colour group).
- **Palette bars**: a band along the bottom edge of each tile in the palette's identity colour.
  Tiles touch, so neighbours in the same palette form one continuous bar. Arranged by palette, the
  bar is taller and carries the palette name where the run starts. In other arrangements it is a thin
  band split between every palette that holds the colour.
- The identity colour is derived from the palette's id, so it never changes and matches the sidebar dot.

### Palette builder **[built]**
- Started from **Build Palette** on the All Swatches filter bar, the File menu, or the toolbar item.
- A bar appears across the top with the name field, Save and Cancel. Rail 3 opens on the right.
- Clicking tiles adds or removes them; chosen tiles show a tick. Rail 3 lists them with a remove button each.
- Save puts the palette in **Custom Palettes** and opens it.

## 3. Settings panels **[built]**

| Panel | Holds |
|---|---|
| **General** | Copy format for a click · hex in upper or lower case · sounds · keep picking until Esc · colours taken from an image · wheel changes palette |
| **Cards & Grid** | Rows shown on a card · show colour names · show contrast line · tile size · palette bars on or off |
| **Export** | Default format · variable prefix (`swatch` gives `--swatch-steel-blue`) · name by colour name or by number · hex case in exports |
| **Catalogues** | Open, create, open from file, show in Finder |
| **Sync** | Folder · ask or merge automatically · status · backups to keep |

Copy formats on offer: HEX, HEX without #, RGB, CSS `rgb()`, HSL, CSS `hsl()`, HSV, CMYK, Float RGB 0–1,
Linear RGB 0–1, SwiftUI `Color`, `NSColor`, `UIColor`.

## 4. Export **[built unless marked]**

| Format | For | Note |
|---|---|---|
| CSS variables `tokens.css` | web, vibe coders | `--swatch-<name>: #ff6600;` |
| SCSS variables | web | `$swatch-<name>` |
| Tailwind v4 `@theme` | web | `--color-<name>` generates `bg-<name>` etc. |
| Tailwind v3 config | web | `theme.extend.colors` |
| Design tokens JSON | Figma, token pipelines | 2025.10 format: value is an object with colour space, components, hex |
| Design tokens JSON, older | Style Dictionary era tools | value is a hex string |
| Swift | app developers | `enum BrandColours { static let steelBlue = Color(...) }` |
| Android `colors.xml` | app developers | |
| Adobe Swatch Exchange `.ase` | Photoshop, Illustrator, InDesign, Affinity | binary, written by hand |
| Adobe Color `.aco` | Photoshop, Clip Studio | Clip Studio reads ACO but not ASE |
| Adobe Color Book `.acb` | Photoshop colour libraries | RGB book; goes in Photoshop's Presets ▸ Color Books folder. Not yet opened in Photoshop |
| Adobe Color Table `.act` | Photoshop indexed colour, Save for Web | 256 colours at most, no names |
| After Effects script `.jsx` | After Effects | no swatch file exists, so a script builds a comp of tiles and a layer of named colour controls. Not yet run in After Effects |
| Procreate `.swatches` | illustrators on iPad | zip + JSON array of palettes, 30 colours each; longer palettes carry on in "Name 2". Not yet opened in Procreate |
| Sketch `.sketchpalette` | Sketch Palettes plugin users | simple JSON |
| Paint.NET `.txt` | Windows artists | 96 slots |
| JASC `.pal` | PaintShop Pro, pixel art tools | |
| Hex file `.hex` | Aseprite, Lospec | |
| GIMP palette `.gpl` | GIMP, Inkscape, Krita, Aseprite | Krita needs the `Name:` line |
| macOS colour list `.clr` | every Mac app's colour panel, incl. DaVinci Resolve | also "Add to macOS Colour Panel", which saves into `~/Library/Colors` |
| PNG swatch sheet | decks, mood boards, sharing | |
| Plain text | anywhere | |
| Krita `.kpl` | Krita | **[no]** GPL covers Krita |
| Affinity `.afpalette`, Clip Studio `.cls` | | **[no]** proprietary, no public spec; ASE and ACO cover them |
| `.cube` | | **[no]** it is a lookup table for grading, not a palette |

Names in exports are unique within a palette (`steel-blue`, `steel-blue-2`). When several palettes share a file the palette name goes in front.

## 4a. Projects, tags and the Design Pack **[built]**

### Projects
Projects are the main grouping in the sidebar. Each project is a section holding its palettes, in the
order the user keeps them. Palettes outside any project sit in a loose **Palettes** section.

- Every palette row carries its icons: **star · duplicate · delete**.
- Palettes drag to reorder within a project and across projects. Projects drag to reorder too.
- A project's header has a **+** for a new palette in it; right-click renames, exports or deletes it.
  Deleting a project drops its palettes into the loose list, nothing is lost.
- Sync: projects merge by id. Newer name wins, newer placement wins, a deletion on one Mac holds.
  "Keep This Mac's" now re-dates what it keeps, so the other Mac's deletion record cannot undo it.

### Tags
Free-form labels on swatches and on palettes, kept per item with a "newest set wins" sync rule.
- Palette tags are edited in the palette header. Swatch tags via right-click ▸ Tags….
- A **Tags** section in the sidebar lists every tag; choosing one shows the matching swatches in All Swatches.
  A tag on a palette counts for every swatch in it.
- Search matches tags. The Show menu in All Swatches lists tags under the colour groups.

### Design Pack
One folder that carries a palette, a project or the whole catalogue to any team, anywhere: dropped into
a git checkout, a shared drive, or just a folder. No sign-in to anything.

```
Brand 2026 Design Pack/
  README.md            what is inside; every palette and swatch listed with name, hex, RGB, HSL, CMYK, tags
  pack.json            the MMFFDev Colour pack format (below)
  LICENSE.md           the licence pack: text from Settings ▸ Export, with owner and year filled in
  proof-sheet.png      contact sheet of every palette in the pack
  brand-2026/
    brand-2026.css     :root { --swatch-steel-blue: #4f8093; … }  ready to drop into a codebase
    brand-2026.png     the palette's own sheet
    swatches/
      01-steel-blue-4f8093.png   one square PNG per swatch, numbered in palette order
      02-firebrick-c22832.png
```
A project pack has one such folder per palette; a catalogue pack nests them under a folder per project.

**pack.json** (version 1): `{ "format": "mmffdev-colour-pack", "version": 1, "generator", "exportedAt",
"name", "licence": {owner, text}, "projects": [ { "name", "palettes": [ { "name", "tags", "css", "sheet",
"swatches": [ { "name", "hex", "rgb", "hsl", "hsv", "cmyk", "float", "linear", "tags", "file" } ] } ] } ] }`.
Loose palettes appear under a project called "Palettes". Everything a reader needs is in the file; the
PNG and CSS paths are relative to the pack folder.

**Git.** When the chosen folder is inside a git repository, the export panel offers
"Commit and push with git". It runs `git add`, `git commit` and `git push` on that repository through the
git command line and reports any error. No GitHub API and no token: the user's own git set-up does the work.

**Decided against for now:** uploading to Google Drive or Dropbox through their APIs. Dropping the folder
into their synced folders does the same job with no sign-in.

## 5. Other features

| Feature | Who for | Status |
|---|---|---|
| Colour names, nearest of the 148 CSS names | everyone; makes search and exports readable | **[built]** |
| Search by name, hex or palette | everyone | **[built]** |
| Contrast against white and black, WCAG grade | web, UI | **[built]** |
| Make a palette from one swatch: complementary, analogous, triadic, split, tetradic, tints and shades, 50–950 scale | web, UI, illustrators | **[built]** |
| New palette from clipboard: finds every hex in pasted CSS, JSON or chat | vibe coders | **[built]** |
| Linear and float copy formats | 3D, shaders, video | **[built]** |
| Add palette to the macOS colour panel | anyone using a Mac app | **[built]** |
| Palette from image, drag and drop | photographers, artists | **[built]**, from v2 |
| Sync, backups, catalogues | everyone | **[built]**, from v2 |
| Contrast between any two swatches, with nearest passing colour | web, UI | **[next]** |
| Custom copy templates, e.g. `vec3({r}, {g}, {b})` | everyone; Sip and ColorSlurp have it | **[next]** |
| Rename a swatch, add a note | everyone | **[next]** needs a field on the colour and a sync rule |
| Drag to reorder swatches in a palette and in the builder | everyone | **[next]** |
| Drag a swatch out into another app | designers | **[next]** |
| Import ASE, GPL, ACO, CLR | anyone with existing libraries | **[next]** |
| Menu bar item and global hotkey | everyone; baseline in rival apps | **[next]** |
| Colour blindness preview of a palette | web, UI | **[later]** matrix maths in linear RGB |
| 50–950 scale in OKLCH rather than HSL | web | **[later]** more even steps, needs gamut clipping |
| Gradient between two swatches, export as CSS | web | **[later]** |
| Format chosen by the frontmost app | developers | **[later]** |
| APCA contrast as a second reading | web | **[later]** removed from the WCAG 3 draft in 2023; licence terms unchecked |
| Wide gamut: record Display P3 values | photo, video, illustration | **[later]** the hard one |
| Bigger name list | everyone | **[later]** xkcd list is CC0 (954 names); meodai list is MIT (about 32,000) |
| Pantone or RAL matching | print | **[no]** both are licensed. Let users import their own ASE instead |

## 6. Decisions and why

- **v3 is a separate app** beside v1 and v2, with its own library and its own sync folder name.
  v2 would drop the new fields (stars, custom mark) if it saved a v3 library, so they must not share a file.
- **First launch copies the v2 library in.** v2's file is only read.
- **Palette identity colour comes from the id**, not from the palette's contents, so it is stable when swatches change.
- **Stars sync by "newest choice wins"** and never raise the merge prompt by themselves.
- **CMYK is the naive conversion.** No ICC profile. Good for a starting value, not for press.
- **Rounded, not truncated.** Our HSV for `#4F8093` is 197, 46, 58. The reference screenshot shows 196, 46, 57 because that tool truncates.
- **Names are approximate** by design: nearest named colour, measured in Lab.

## 7. Research notes

What rival tools have in common, so users will expect it: menu bar access with a global hotkey, several copy
formats, ASE and CLR export, WCAG contrast.

What sets the better ones apart: custom copy templates, APCA, format chosen per app, OKLCH and P3 support.

| App | Worth noting |
|---|---|
| Sip | Palettes and sub-palettes, a colour dock, format per frontmost app, 24+ formats, contrast with one-click fix, colour blindness modes, team sharing |
| ColorSlurp | Projects, custom formats synced by iCloud, WCAG and APCA, OKLCH/LAB/P3, exports to Sketch, Procreate, ASE, CLR, CSS, Swift |
| Pastel | Drag colours into other apps, copy a palette as an image |
| Aquarelo | Steps between two colours, 36 formats |
| Coolors | Generator with locked colours, gradients, tints and shades, many exports |
| Adobe Color | Ten harmony rules, gradient from image, colour-blind-safe check |
| Paletton | Harmonies with five shades per hue, vision simulation |
| Figma | Variables with modes; imports and exports design tokens JSON natively |

Facts checked during research:
- Design tokens format reached its first stable version, 2025.10, on 28 October 2025. It is a community group report, not a W3C standard.
- WCAG 2 contrast: AA is 4.5:1 for body text and 3:1 for large text and UI parts. AAA is 7:1 and 4.5:1.
- Blender's RGB fields are linear; its hex field is sRGB. Unreal offers both "Hex Linear" and "Hex sRGB".
- Files in `~/Library/Colors/` appear in the system colour panel.

Not verified, check before relying on them: the Procreate JSON root shape, the Unity `.colors` layout, APCA licence terms,
whether Pastel's Mac version has a screen eyedropper.

## 8. Known gaps in this build

- Swatches cannot be renamed or reordered by hand yet.
- The toolbar's Share item shares the open palette, or every swatch when All Swatches is showing.
- The hotkey pick mode (`--pick`) adds to the current catalogue but does not sync by itself.
- Catalogues cannot be renamed or deleted from the app.

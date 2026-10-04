# MMFFDev Colour 3 — scratch

Working notes: what is built, what is on the table, and what to do next.
Reorganised 2026-10-03. Every idea from the old list and from Rick's new notes is kept; nothing was dropped.

**How to read it**

| Part | Holds | Numbering |
|---|---|---|
| **A** | Work done: what the app does today | A1 … A12 |
| **B** | Ideas: everything proposed and not finished | B1.1 … B12.x |
| **C** | What next: a recommended order | C1 … |
| **D** | Reference: words, formats, decisions, research | D1 … D6 |

**Marks on an idea**

| Mark | Means |
|---|---|
| ✅ | Already built. Listed so we stop re-proposing it. |
| ◐ | Partly built. The note says what is missing. |
| ○ | New. Not started. |
| ☁ | Needs the server (accounts, sharing, sync to our database). Cannot be done in the Mac app alone. |
| ⚠ | An earlier note in this file said no. Those notes were Claude's own calls in the first v3 build, never Rick's rulings, so they are open. |

---

# Part A — Work done

## A1. The app's shape
- Full-width toolbar; under it the sidebar, the page, and two right-hand rails (palette builder, History). Full-width footer.
- Sidebar tree: Library ▸ All Swatches · Tools ▸ Colour Lab, Contrast · Favourites · Projects · Palettes · Typography · Tags.
- Side panes drag to any width, remember it, and start at 260 (sidebar) and 320 (rails). Each has a curved notch at the bottom of its inner edge: drag to resize, double-click to reset.
- The window reopens on the screen, page and pane widths it was left with.
- Native toolbar: customisable, arrangement remembered.

## A2. Picking and collecting
- Screen picker, with a hotkey pick mode. Keep picking until Esc.
- Palette from an image, by drag and drop. Palette from the clipboard: finds every hex in pasted CSS, JSON or chat.
- Palette builder: choose swatches from All Swatches into a new palette.
- Make a palette from one swatch: complementary, analogous, triadic, split, tetradic, tints and shades, 50–950 scale.

## A3. Pages
- **All Swatches:** even grid; arrange by palette, colour group, hue, lightness, saturation, newest, oldest, name; palette bars under the tiles.
- **Palette, Grid view:** one card per swatch with HEX, RGB, HSL, HSV, CMYK, P3, Adobe RGB, Rec. 2020 and Lab rows (which rows show is a setting). Click copies. Optional WCAG line.
- **Palette, Vertical view:** one colour to a row with its values and its notes. Edit Notes and History open a full-height sheet centred on the page.
- Grid or Vertical is one choice that holds from palette to palette. Every palette has both.
- **Typography palettes:** pairings of text colour on background, with words and fonts, shown as real examples.
- Page header primitive on every page: title panel, action bar, project pill, padlock, barber-pole stripes for anything in a project.

## A4. Colour Lab and Contrast
- **Colour Lab:** artists' wheel, harmony rules (analogous, complementary, split, triad, square, compound, shades, monochromatic, custom), worked in OKLCH. Undo and redo. Add To Palette, Add To Project (with New Project).
- **Contrast:** any text colour against any background, WCAG 2 and APCA scoring, with fixes. Add To Typography.
- Saving from either tool always lands in the Palettes collection; a project gets its own copy as well.

## A5. Projects
- A project is a folder of its own on disk: `<Projects folder>/<Name>/Config/<Name>.config`, plain JSON. A lost file is reported, never silently remade.
- **A project owns its palettes.** A palette goes into a project, between projects, or back to Palettes as a copy. Palettes is the stock collection.
- Copying a palette that has notes asks: with notes, without, or cancel.
- Project padlock: nothing inside a locked project can change.
- Each project's tree starts with **Information ▸ Overview**.
- **New Project** is a centred prompt for the name only; the project opens on its Overview.
- **Overview** holds the project form: Project, Client, Studio, Rights, Colour, Notes. Save and Revert. Master templates under Fill From Template.
- **The form remembers.** Every field lists what was typed there before; every section can be filled whole from a saved set (Client under Company, Studio under Studio, and so on).
- **Organisation** in Settings: your own details, laid into every new project's Studio section, and on offer as My Organisation on any project.

## A6. Notes and history
- Notes on any swatch in any palette, kept with the palette entry and written into the project's file.
- History rail, like Photoshop's: every change is a step; go back, delete, play back. Project or Global view, switching with where you are.
- Per-swatch history in the swatch sheet: added, renamed, described, tagged, removed, with play back.
- Settings ▸ History: on or off per library, where it is kept, project history, steps to keep.

## A7. Tags
- Free-form labels on swatches and palettes; global or owned by a project; a tag editor; tags in search and in All Swatches' Show menu.

## A8. Export and handover
- 22 formats: CSS, SCSS, Tailwind v3 and v4, design tokens JSON (2025.10 and older), Swift, Android, ASE, ACO, ACB, ACT, After Effects script, Procreate, Sketch, macOS colour list, GIMP, Paint.NET, JASC, hex file, PNG sheet, plain text. Table in D3.
- **Add To Adobe Apps:** writes straight into Adobe's preset folders, through a background helper or a one-off folder unlock.
- **Design Pack:** one folder with README, pack.json, licence, proof sheet, and per-palette CSS and PNGs; optional git commit and push. Layout in D4.
- Add to the macOS colour panel.

## A9. Library, sync, catalogues
- Catalogues (whole libraries, like Lightroom). Sync between Macs through a shared folder, with merge rules and backups.
- Colour names: nearest of the 148 CSS names, measured in Lab. A colour can have its own name inside a palette.
- Search by name, hex, palette or tag.

## A10. Look and feel
- Settings ▸ Theme: sidebar selection colours; button hover and active colours; Reset To Default on each.
- Buttons and toggles are grey by default, taken from the background, so the controls never out-shout the colours.
- Background steps from white to black with ⌘[ and ⌘].
- One button, one toggle, one height (28). Type scale: 13 body, 11 caption, 22 title.

## A11. First run, install, updates
- First-open setup sheet and a Permissions pane. Installer offers all users or this user only.
- Signed with Developer ID and notarised. Sparkle updates from GitHub releases.

## A12. Help and backlog
- Help drafts: install, Add Palettes To Adobe Apps, History.
- Everything is logged in Vector under runway PR-23.

---

# Part B — Ideas

Rick's new notes are B1 to B10, in his order and his words, each checked against the code. B11 and B12 gather what was already on the table.

## B1. Brand governance and compliance — "the big one"

| # | Idea | Mark | Note |
|---|---|---|---|
| B1.1 | Brand rules engine: lock approved palettes, flag off-brand colour in uploaded artwork (a hex-match check on PNGs and PDFs) | ◐ | Locking exists (project padlock). The artwork check is new and very doable for PNG; PDF is harder. |
| B1.2 | Client approval portal: read-only link, approve or reject, comment, no account | ☁ | The headline server feature. |
| B1.3 | Approval status per swatch: draft, review, client-approved, locked | ○ | Can be built now, locally, and it sets up B1.2. Strong candidate. |
| B1.4 | Change-request workflow tied to a palette version | ☁ | Follows B1.2 and B6.2. |

## B2. Cross-medium fidelity — 2D, 3D, print, video

| # | Idea | Mark | Note |
|---|---|---|---|
| B2.1 | Intent profiles per palette: sRGB, Display P3, Adobe RGB, CMYK with a chosen ICC profile (FOGRA51, GRACoL), Rec. 709, Rec. 2020, ACEScg, Pantone/TCX/TPG | ◐ ⚠ | P3, Adobe RGB and Rec. 2020 values already show on cards. Missing: real ICC-profiled CMYK (today's CMYK is the naive conversion), Rec. 709, ACEScg. The Pantone part clashes with D5. |
| B2.2 | Gamut warning overlay with closest in-gamut match, ΔE driven | ○ | Pairs with B11.1 (the CIE diagram and gamut triangles). |
| B2.3 | Nearest Pantone, RAL, NCS, Toyo with a ΔE score | ⚠ | We ruled these out: the libraries are licensed. The safe route is still "import your own ASE", then match against that. Needs your ruling. |
| B2.4 | Ink coverage / TAC calculator for print | ○ | Small, once CMYK is profile-true (B2.1). |
| B2.5 | ACES / OCIO export for 3D and VFX (USD, Blender, Unreal, Maya, C4D) | ○ | |
| B2.6 | LUT export: a `.cube` from a palette, for Resolve and Premiere | ⚠ | We marked `.cube` "no" because a LUT is a grading transform, not a palette. You now want video and LUTs in. Needs a clear definition of what LUT a palette produces. |
| B2.7 | HDR-aware palettes: flag colours that clip in HDR10 or Dolby Vision | ○ | |

## B3. Design-system integration

| # | Idea | Mark | Note |
|---|---|---|---|
| B3.1 | Design tokens export: JSON, Tailwind, SCSS, Swift, Android, Figma variables | ✅ | All built except LESS, which is trivial to add. |
| B3.2 | Figma, Sketch, Penpot plugin: two-way push and pull with drift detection | ○ | A separate product per host. The second of your "three that stand out". |
| B3.3 | Code snippet generator: CSS custom properties, JS object, Python dict, GLSL uniform block | ◐ | CSS is built. JS, Python and GLSL are small additions; B11.6 (copy templates) would cover them all in one go. |
| B3.4 | Semantic token mapping: primary, surface, on-surface, disabled | ○ | Turns a palette into a usable system. High value for web users. |

## B4. Accessibility and inclusive design

| # | Idea | Mark | Note |
|---|---|---|---|
| B4.1 | Full WCAG 2.2 and APCA contrast matrix across every pair in a palette | ◐ | Both scores exist for one pair at a time. The every-pair grid is new. |
| B4.2 | Colour-blindness simulation per palette, with pass or fail flags | ○ | No code yet. A quick win. |
| B4.3 | Dark-mode and light-mode pairing: generate the counterpart palette | ○ | |
| B4.4 | Safe-pair suggestions from within the palette | ○ | Falls out of B4.1. |

## B5. Collaboration and handoff

| # | Idea | Mark | Note |
|---|---|---|---|
| B5.1 | Real-time multiplayer editing with presence | ☁ | |
| B5.2 | Inline annotations on swatches | ✅ | Built today: notes on every swatch, in the project's file. |
| B5.3 | Review links with expiry and password | ☁ | Same machinery as B1.2. |
| B5.4 | Handoff pack: one click makes a branded PDF spec sheet | ◐ | The Design Pack is built. A branded PDF is new and can be done locally. |
| B5.5 | Slack / Teams integration | ☁ | |
| B5.6 | Email digest for stakeholders | ☁ | |

## B6. Versioning that agencies need

| # | Idea | Mark | Note |
|---|---|---|---|
| B6.1 | Visual diff between versions, with ΔE deltas | ○ | History already holds every version, so this is a view on data we have. |
| B6.2 | Branching and variants: "Spring campaign" beside "Master brand" | ◐ | Copy To Project records where a copy came from. Named variants and Refresh From Original are not built. |
| B6.3 | Rollback to any point, with a note of why it changed | ◐ | Rollback is built. Capturing the reason is new. |
| B6.4 | Audit log export: who changed what, when, approved by whom | ◐ | Steps and times exist. "Who" needs accounts (☁). |

## B7. Colour science depth

| # | Idea | Mark | Note |
|---|---|---|---|
| B7.1 | Custom colour space: primaries, white point, transfer function | ○ | |
| B7.2 | Spectral data: `.csv` and `.cie` readings for paint and ink matching | ○ | Niche, but a real differentiator for print and packaging. |
| B7.3 | ΔE 2000, ΔE ITP and CAM16-UCS between any two colours | ◐ | A Lab distance is used internally. No tool shows it. A quick win. |
| B7.4 | Chromatic adaptation preview, D50 ↔ D65 | ○ | |
| B7.5 | Metamerism checker for print | ○ | Needs B7.2. |
| B7.6 | Harmony generator in a perceptual space | ✅ | Colour Lab works in OKLCH on an artists' wheel. |

### To explore: gamma, embedded profiles and LUTs (raised 2026-10-04)

- **Gamma encoding.** How each space's curve is written and read: the sRGB curve against a plain 2.2, video's 2.4 and BT.1886, cinema's 2.6, ProPhoto's 1.8, linear. Show the curve a channel uses, and what the same number means under another. A "what if this were read as 2.2" check for values that travel without a profile.
- **Reading image files.** JPEG, TIFF, PNG and others: read the embedded ICC profile, PNG's gAMA and cHRM and sRGB chunks, EXIF's colour space tag, and TIFF's tags, and say plainly what the file claims to be. Flag a file with no profile, since a bare "gamma 2.2" guess is where colour goes wrong. Picks and palettes taken from an image should keep that image's space, not be flattened to sRGB.
- **Writing image files.** Swatch PNGs and sheets that carry the right profile for the channel they are for, not untagged sRGB.
- **LUTs.** Read .cube (1D and 3D) and show what one does to a palette: before and after, with ΔE per swatch. Write a LUT that carries a palette from one channel to another. Preview a palette through a camera log curve or a show LUT. Ties in with OCIO configs for the rendering channel.
- **A real pixel histogram** for an image, with the cache-and-refresh honesty Photoshop has, once images are read properly.

## B8. Asset and context management

| # | Idea | Mark | Note |
|---|---|---|---|
| B8.1 | Reference images per palette: mood boards, briefs, product shots | ○ | Fits the Information pages (B12.1). |
| B8.2 | Usage examples: screenshots of the palette in use, tagged by medium | ○ | Same. |
| B8.3 | Client view: every palette across projects for one client | ○ | Client is already a named section on every project, so the data is there. |
| B8.4 | Search across everything, including "within ΔE 5 of #FF5733" | ◐ | Name, hex, palette and tag are built. Client and ΔE search are new. |
| B8.5 | Favourites, recently used, pinned | ◐ | Favourites are built. Recently used and pinned are new. |

## B9. Workflow and automation

| # | Idea | Mark | Note |
|---|---|---|---|
| B9.1 | API and webhooks | ☁ | |
| B9.2 | Bulk import: ASE, ACO, GPL, CSS, CSV, image | ◐ | Images and pasted CSS are built. Reading ASE, ACO, GPL, CLR and CSV files is not. Long overdue. |
| B9.3 | Auto-extract a palette from an image and match it to existing brand colours | ◐ | Extraction is built. Matching to existing colours is new. |
| B9.4 | Scheduled exports | ○ | |
| B9.5 | Zapier / Make connector | ☁ | |

## B10. Reporting and analytics

| # | Idea | Mark | Note |
|---|---|---|---|
| B10.1 | Palette usage analytics: which colours appear in delivered assets | ○ | Needs B1.1's artwork check first. |
| B10.2 | Client-facing reports as a monthly PDF | ○ | Builds on B5.4. |
| B10.3 | Time-in-review metrics | ☁ | Needs B1.2. |

## B11. Already on the table before today

| # | Idea | Mark | Note |
|---|---|---|---|
| B11.1 | CIE 1931 chromaticity diagram with the palette plotted on it, and gamut triangles (sRGB, P3, Adobe RGB, Rec. 709, Rec. 2020) | ○ | Raised today. The picture that makes B2.2 obvious at a glance. |
| B11.2 | Cone response curves | ○ | Raised today. |
| B11.3 | Histograms | ○ | Raised today. Of a palette, or of an image? To decide. |
| B11.4 | Video tools: P3, the video spaces, LUTs | ○ ⚠ | Raised today. See B2.6. |
| B11.5 | Menu bar item and global hotkey | ◐ | The hotkey pick exists. No menu bar item. Every rival has one. |
| B11.6 | Custom copy templates, such as `vec3({r}, {g}, {b})` | ○ | Sip and ColorSlurp have it. |
| B11.7 | Drag to reorder swatches in a palette and in the builder | ○ | |
| B11.8 | Drag a swatch out into another app | ○ | |
| B11.9 | Gradient between two swatches, exported as CSS | ○ | |
| B11.10 | 50–950 scale in OKLCH with gamut clipping | ○ | The colour maths is already there. |
| B11.11 | Copy format chosen by the frontmost app | ○ | |
| B11.12 | Record true Display P3 values when picking | ○ | "The hard one." Underpins B2. |
| B11.13 | Bigger name list: xkcd (954, CC0) or meodai (about 32,000, MIT) | ○ | |
| B11.14 | Send To Photoshop: open the palette there directly | ○ | |
| B11.15 | Rename and delete a catalogue from the app | ○ | Not rechecked today. |
| B11.16 | Windows port | later | Not before the Mac app is at release. |
| B11.17 | App Store edition | last | Never a design constraint. |
| B11.18 | Launch and sales: Lemon Squeezy, licence keys, launch page, help site | ○ | Logged in Vector under Launch And Sales. |

## B12. Raised while building, not finished

| # | Idea | Mark | Note |
|---|---|---|---|
| B12.1 | Information pages designed by the user from blocks: text, dates, people, addresses, images, swatches, palettes, typography | ○ | You are sleeping on it. Four decisions wait on you (Vector has them). |
| B12.2 | Rich text for the project description | ○ | Comes with B12.1. |
| B12.3 | Notes on typography pairings | ○ | Swatch notes are done; pairings are not. |
| B12.4 | Typography list as stock only, like Palettes | ○ | The same double listing Palettes had. |
| B12.5 | Department, Mobile Number and Extension on the Client section | ○ | Studio has them; Client does not. |
| B12.6 | Refresh From Original, for a project's copy of a palette | ○ | The link back is already recorded. |
| B12.7 | Sync all local data to our server database | ☁ | Every new store already carries an id and a date for this. |
| B12.8 | Settings window restored to its screen | ○ | Still uses the macOS restore that failed for the main window. |
| B12.9 | Theme the form's text boxes and pop-ups | ○ | They are still the system's standard controls. |
| B12.10 | Palettes, Typography and Tags buckets shown even when empty | ○ | Your scaffold sketch listed them. |
| B12.11 | Spare Sidebar button in the toolbar | ○ | Two sit side by side, one dimmed. |
| B12.12 | Help pages for projects, notes, lock and theme | ○ | |
| B12.13 | Hands-on proofs still owed | ○ | Seven features in Vector end with a check only you can do by hand. |

---

# Part C — What next

My recommendation, in order. Each step is chosen because it unlocks the ones after it.

| # | Do | Why it wins |
|---|---|---|
| **C1** | **Close the loop on today.** B12.13 hands-on proofs, then B12.4, B12.5, B12.8, B12.11. | A day of fast building needs one pass by a designer's eye before more goes on top. Small, and it protects trust in everything else. |
| **C2** | **The quick wins that need no server:** B7.3 ΔE between two swatches · B4.2 colour-blindness simulation · B4.1 every-pair contrast matrix · B9.2 import ASE, ACO, GPL, CLR. | Four features rivals already have or agencies ask for first. Each is days, not weeks, and all sit on colour maths we already own. |
| **C3** | **Approval status per swatch (B1.3)** with the reason captured on change (B6.3). | It is the local half of your "big one". It makes the app useful for sign-off today and gives the client portal something to show later. |
| **C4** | **Cross-medium fidelity, stage one:** B11.1 CIE diagram with gamut triangles, B2.2 gamut warnings, B11.12 true P3 picking. | Your first "stands out hardest" pick. Start with the picture and the warning; ICC-true CMYK and ACES follow. |
| **C5** | **Decide the Information pages (B12.1).** | It shapes B8.1, B8.2, B5.4 and B10.2, which are all "things on a page". Better decided before any of them is built. |
| **C6** | **The server:** accounts, sync (B12.7), then the client approval portal (B1.2) and review links (B5.3). | The biggest earner and the biggest build. Everything marked ☁ waits on it, so it gets its own plan, not a slot between features. |

**Three open questions before C4** (the earlier "no" notes were Claude's, not Rick's, and do not bind us)

1. **Pantone, RAL, NCS, Toyo (B2.3).** We said no because the libraries are licensed. Options: keep "bring your own ASE and we match against it", or pay for a licence. I recommend bring-your-own.
2. **LUTs (B2.6).** What should a LUT made from a palette do? My suggestion: a "palette look" that pulls an image's colours toward the palette, clearly labelled as a creative LUT and not a technical conversion.
3. **Your "quick wins this week" list.** Two are already done (APCA, design tokens JSON). ΔE and colour-blindness are in C2. LUT and ACES export wait on ruling 2. The public share link needs the server.

---

# Part D — Reference

## D1. Words

| Word | Means |
|---|---|
| **Swatch** | One colour. |
| **Palette** | A named set of swatches. (v2 called this a "swatch".) |
| **Custom palette** | A palette built by choosing swatches already in the library. |
| **Catalogue** | A whole library: all swatches and palettes. Like a Lightroom catalogue. |
| **Project** | A client or piece of work. It owns copies of palettes, its notes, its lock and its file. |
| **Stock** | The loose Palettes list: everything ever made, which projects copy from. |

The saved file still uses the v2 field names (`swatches`, `entries`) so v2 libraries open unchanged.

## D2. Settings panes

General · Organisation · Cards & Grid · Export · Shortcuts · Catalogues · Sync · History · Theme · Permissions.

Copy formats on offer: HEX, HEX without #, RGB, CSS `rgb()`, HSL, CSS `hsl()`, HSV, CMYK, Float RGB 0–1,
Linear RGB 0–1, SwiftUI `Color`, `NSColor`, `UIColor`.

## D3. Export formats

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
| Krita `.kpl` | Krita | decided against: GPL covers Krita |
| Affinity `.afpalette`, Clip Studio `.cls` | | decided against: proprietary, no public spec; ASE and ACO cover them |
| `.cube` | | an early note by Claude left it out; open, and wanted, see B2.6 |

Names in exports are unique within a palette (`steel-blue`, `steel-blue-2`). When several palettes share a file the palette name goes in front.

## D4. The Design Pack

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

## D5. Decisions and why

- **v3 is a separate app** beside v1 and v2, with its own library and its own sync folder name.
  v2 would drop the new fields (stars, custom mark) if it saved a v3 library, so they must not share a file.
- **First launch copies the v2 library in.** v2's file is only read.
- **Palette identity colour comes from the id**, not from the palette's contents, so it is stable when swatches change.
- **Stars sync by "newest choice wins"** and never raise the merge prompt by themselves.
- **CMYK is the naive conversion.** No ICC profile. Good for a starting value, not for press. (B2.1 would change this.)
- **Rounded, not truncated.** Our HSV for `#4F8093` is 197, 46, 58. The reference screenshot shows 196, 46, 57 because that tool truncates.
- **Names are approximate** by design: nearest named colour, measured in Lab.
- **Pantone and RAL matching:** an early note by Claude said no because both libraries are licensed. Not a ruling by Rick. Open, see B2.3.
- **Project and history files are plain JSON.** Never encrypted or hashed. No hidden folders.
- **Direct download is the product.** The App Store is the last thing we do, and never shapes a design.
- **A project owns its palettes** (2026-10-03). Copy on entry; Palettes is the stock collection that keeps everything.
- **Notes are keyed by the colour inside its palette**, not by its position, so sorting never moves them.
- **Local data will sync to our server database later.** Every record gets an id and a date now.
- **Controls stay grey.** This is a colour tool; the interface must not compete with the colours.

## D6. Research

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

Known gaps, carried over and not rechecked today:
- The toolbar's Share item shares the open palette, or every swatch when All Swatches is showing.
- The hotkey pick mode (`--pick`) adds to the current catalogue but does not sync by itself.
- Swatches cannot be reordered by hand (B11.7).

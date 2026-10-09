# Document icon proposals

Ten coordinated families, each containing all fourteen file types. Open `index.html` for the comparison gallery. `overview.png` compares all 140 designs; each family has a light/dark preview and an exact-pixel contact sheet at 16, 32, 128 and 512 px. These are design proposals; no file associations or app resources have been changed.

## Shared system

- Master grid: 64 × 64. Upright page bounds: x=10–54, y=3–61; folded top-right corner: 14 units. Symbol field: approximately x=18–46, y=21–48.
- Standard symbol stroke: 2.2 units; Technical uses 2; Etched uses 1.5. Stroke weight is consistent within each family. Solid and optical variants use filled silhouettes and enlarged counters.
- Core: one footer rule. Purpose: two rules. Sync: broken rule plus opposing arrows enclosing the payload. All six purposes use one restrained accent; their symbols carry the distinction without colour.
- Reserved badge area: x=41–51, y=51–59. Leave empty until an app badge is chosen. At 16 px, omit an added badge if it compromises the identifying symbol.
- Separate 16 and 32 px SVG drawings have snapped geometry, reduced detail and stronger silhouettes. Retina exports use the drawing for the logical size: `16@2x` therefore differs from `32` despite both being 32 physical pixels.
- Page and symbol colours are opaque; the surrounding canvas is transparent. A neutral edge defines the page on light and dark backgrounds. No embedded fonts, labels, logos, filters or external resources.

## Symbols

| Extension | Symbol |
|---|---|
| `.colproject` | Folder |
| `.colpalette` | Three short colour chips |
| `.colswatch` | One square colour chip |
| `.colhistory` | Clock |
| `.colcatalogue` | Three tall indexed volumes |
| `.coldata` | Collection tray with unfiled contents |
| `.colweb` | Browser window |
| `.colprint` | Printer with emerging sheet |
| `.colphoto` | Camera and round lens |
| `.colvideo` | Wide frame and play triangle |
| `.colcine` | Tall perforated film strip |
| `.col3d` | Isometric cube |
| `.colsyncproject` | Opposing arrows around a folder |
| `.colsynccatalogue` | Opposing arrows around indexed volumes |

## Colour values

Values are sRGB hexadecimal design colours, not measured colour samples. Palette chips use `#899EAE`, `#95A38B`, `#B1A185`; small optical variants reduce these to the family's ink/accent. Meaning does not depend on distinguishing these hues.

| Family | Page | Fold / inset | Ink | Accent |
|---|---|---|---|---|
| 01 Instrument | #F0F1EE | #D5D9D6 | #343C42 | #788D81 |
| 02 Graphite | #343A3D | #565F63 | #E1E6E5 | #A1B8B3 |
| 03 Technical | #EDF2F4 | #CED9DF | #375569 | #7393A6 |
| 04 Recess | #F3F2EE | #DADBD6 | #3F474B | #8C9888 |
| 05 Silhouette | #ECEFED | #CDD3D0 | #35433F | #809B91 |
| 06 Header | #F0F0EC | #CDD2CE | #3E4643 | #879D93 |
| 07 Seal | #F0F0EF | #D7D8D6 | #46505B | #8997A9 |
| 08 Etched | #F8F5ED | #E6E0D3 | #5B5549 | #A0957A |
| 09 Margin | #EEF0F0 | #D0D7D9 | #3E4C54 | #7B929E |
| 10 Plaque | #F0F1ED | #D3D8D1 | #39413D | #92A087 |

## Files and export convention

Each family's `svg/` contains `colprint.svg`, `colprint.16.svg`, `colprint.32.svg`, and equivalents for all types. `png/<extension>/` contains 16, 32, 64, 128, 256, 512 and 1024 logical-pixel exports, each at 1× and 2×. The 1024@2x export is a supplementary 2048 px asset, not a required macOS iconset slot.

All ten proposals include 140 vector masters, 280 optical SVGs and 1,960 transparent PNGs. macOS ICNS packaging and Windows/Linux association metadata should follow selection of a family. Pixel dimensions and alpha are checked; actual Finder appearance and user recognition have not been field-tested.

`generate.py` reproduces the assets using Python, Pillow and `rsvg-convert`. `manifest.json` records the family and file-type mappings.

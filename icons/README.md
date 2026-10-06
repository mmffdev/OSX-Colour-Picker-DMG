# Graphite document icons

Approved family: 02 / Graphite. All 14 document types are included, named after their extensions.

- `<extension>.icns`: ready for macOS app resources. Each contains 16, 32, 128, 256 and 512 pt artwork at 1× and 2×, up to 1024 physical pixels. PNG payloads preserve the original artwork and alpha.
- `<extension>.svg`: editable vector master.
- `optical/<extension>.16.svg` and `.32.svg`: separately drawn small-size masters.
- `png/<extension>/`: transparent exports at 16, 32, 64, 128, 256, 512 and 1024 px, plus each at 2×. The supplementary 1024@2x asset is 2048 px.

For macOS, copy the `.icns` files into the built app's `Contents/Resources` (or add them to the target's Copy Bundle Resources phase). Set each document type's `CFBundleTypeIconFile` to the matching filename, for example `colpalette.icns`. For exported UTIs, use the corresponding `UTTypeIconFile` where applicable. Files in this directory are ready to attach; build configuration and file associations have not been changed.

Use the optical artwork by logical size: `colpalette_16@2x.png` is a Retina 16 pt icon; `colpalette_32.png` is a 32 pt icon with different optical geometry.

Grid: 64 × 64; page x=10–54, y=3–61; 14-unit fold; 2.2-unit symbol strokes. Core files have one footer rule, purposes two, and sync files a broken rule. Reserved future app-badge area: x=41–51, y=51–59.

Colours (sRGB): page `#343A3D`, fold `#565F63`, symbols `#E1E6E5`, accent `#A1B8B3`, edge `#8E999A`. Palette-chip accents: `#899EAE`, `#95A38B`, `#B1A185`.

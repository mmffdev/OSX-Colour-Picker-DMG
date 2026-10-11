# Colour picker studies
Five interactive directions with light and dark variants. Run a static server here and open index.html. Hashes are #design-1-light through #design-5-dark. Each uses the same Colorgain shell and settings list. These studies do not modify native preferences; Apply stores prototype choices in localStorage.

1. Vector Spiral: the original 242 colours and coordinates, rendered as rectangular swatches.
2. Colour Atlas: the same palette ordered by hue in a rectangular field.
3. Tonal Columns: twelve hues and nine lightness levels.
4. Spectrum Studio: interactive saturation/value plane and hue strip.
5. Hue Collections: six labelled families with 25 shades each.

Reference data: MMFFDev - Platform/control-plane/frontend/app/vector/components/colourWheelData.ts. Interface settings match Prefs.swift: 14 halo values, 2 sidebar values, 4 button values. Theme defaults are illustrative; no native preferences are read.

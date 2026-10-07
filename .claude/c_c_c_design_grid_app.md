# The app window's frame

1440 × 900 reference, margins 24, gutters 16, twelve columns. Three rows: header 64, body, footer 48.

| Region | Columns | Notes |
|---|---|---|
| Library rail (rail1) | 1 to 2 | hairline on its right |
| Context rail (rail2) | 3 to 4 | hairline on its right; a table |
| Page | 5 to 10 | 34 top padding; its own six-column grid inside |
| History rail | 11 to 12 | hairline on its left |

A hidden rail gives its columns to the page. The page header is a Split within the six: title in 1 to 4, metadata and the arrow in 5 to 6, hairline beneath, 22 clear, then content. Swatch tiles are six across the page, 16 apart, Card ground, colour block 116 high over name and hex.

Rail names stay as they are in the code: rail1, rail2, page, History.

# Colorgain design guide

Agreed with Rick on 2026-10-07. The app owns its look: Swiss. One family, a strict grid, big light type over small dense type, black over warm grey, colour kept for the work, and space doing half the talking. The living specimen is the style sheet artifact, https://claude.ai/artifact/MDqEBgData3ov4eCsdNn52; this guide is its rules in words. No macOS control is used where the guide draws its own.

Load only the child a screen touches:

| Child | Holds |
|---|---|
| `c_c_design_type.md` | the family, six weights, the ten text styles, the diagonal arrow |
| `c_c_design_colour.md` | the six neutrals, the eight step colours, where colour may and may not go |
| `c_c_design_layout.md` | the 12-column grid, the four-point space beat, the alignment laws, the three page layouts |
| `c_c_design_controls.md` | buttons, slider, dropdown, field, tabs, choice, check, with their states |
| `c_c_design_elements.md` | headers, rails, footer |
| `c_c_c_design_grid_wizard.md` | the wizard's frame, measured |
| `c_c_c_design_grid_app.md` | the app window's frame, measured |

## The five laws, every screen

1. **Baseline justification.** Everything on one horizontal row sits on one line across its bottom: text baselines meet, and a control's bottom meets the text's baseline. Never centre a row vertically. In AppKit that is `NSStackView.alignment = .lastBaseline`, or `.bottom` for views with no baseline.
2. **Balance.** A big light title on one side earns a short dense paragraph on the other. Never two heavy things side by side.
3. **The right word count.** Write to the space. If a paragraph runs past its columns, cut words before moving a margin.
4. **Negative space.** Empty columns are part of the design. Fill a gap only when the screen is worse without it.
5. **One voice.** Every size is a weight of Helvetica Neue, every grey is from the six, every gap is on the beat. Nothing is improvised.

Rick's standard, verbatim: "balance is everything to me, using the right word count to balance space." Measure a screenshot before reporting any layout.

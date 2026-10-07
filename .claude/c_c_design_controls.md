# Controls

Every control is drawn by the app, in the family and the greys. No `NSButton` bezel, no `NSPopUpButton`, no `NSSlider` look survives into a screen. One height for a row of controls, 32, except the lead button at 34.

| Control | Shape | States |
|---|---|---|
| Primary button | ink fill, paper text, radius 4, 14 side padding, arrow on the right behind a hairline | hover #2C2C2C; pressed #000 and down 1pt; disabled 35% |
| Secondary | 1pt ink outline, no fill | hover Mist fill |
| Quiet | underlined text, 3pt offset, no box | hover darker |
| Icon | 32 square, Card fill, Rule outline, the arrow or a glyph | hover ink outline |
| Lead | ink fill, 150 minimum, arrow in its own 34 cell | one per screen at most |
| Slider | 1pt ink track, 14 hollow paper knob with ink outline, a glyph at each end saying which way is more, value as caption on the right | focus Orange ring |
| Dropdown | caption label above, value at 17 Regular on a hairline underline, chevron right; the menu is a Card with a Rule edge, 7/14 rows, Mist hover, tick on the chosen | open rotates the chevron |
| Text field | caption label above, 17 Regular, hairline underline, no box | focus doubles the underline in ink |
| Tabs | 17 Regular, Quiet; the chosen one Ink with a 1.5pt underline | |
| Choice | capitals Label in a 1pt ink outline, the chosen cell filled ink | |
| Check | 14 square, 1pt ink, filled ink with a paper tick when on | |

Focus is always a 2pt Orange ring, 2 outside. Everything on a row of controls obeys the baseline law.

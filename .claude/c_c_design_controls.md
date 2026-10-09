# Controls

Every control is drawn by the app, in the family and the greys. No `NSButton` bezel, no `NSPopUpButton`, no `NSSlider` look survives into a screen. One height for a row of controls, 32, except the lead button at 34.

| Control | Shape | States |
|---|---|---|
| Primary button | ink fill, Card text, square, 14 side padding, the arrow on the right behind a hairline | hover #2C2C2C; pressed #000 and down 1pt; disabled 35% |
| Secondary | 1pt ink outline, no fill, the same arrow cell on the right | hover reverse ink: ink fill, Card text |

Every boxed button carries the icon cell on its right, the arrow unless it shows a state (tick, cross): the primary is the guide, the secondary its outline twin (Rick, 2026-10-08). A quiet button is text and carries no cell.
| Quiet | underlined text, 3pt offset, no box | hover darker |
| Icon | 32 square, Card fill, Rule outline, the arrow or a glyph | hover ink outline |

No rounded corners anywhere: Swiss is square (Rick, 2026-10-07).
| Lead | ink fill, 150 minimum, arrow in its own 34 cell | one per screen at most |
| Slider | 1pt ink track, 14 hollow paper knob with ink outline, a glyph at each end saying which way is more, value as caption on the right | focus Orange ring |
| Dropdown | caption label above, value at 17 Regular on a hairline underline, chevron right; the menu is a Card with a Rule edge, 7/14 rows, Mist hover, tick on the chosen | open rotates the chevron |
| Text field | caption label above, 17 Regular, hairline underline, no box | focus doubles the underline in ink |
| Tabs | 17 Regular, Quiet; the chosen one Ink with a 1.5pt underline | |
| Choice | capitals Label in a 1pt ink outline, the chosen cell filled ink | hover reverse ink on the cell |

Every button and every drawn cell that takes a click turns the pointer into a hand, and the outlined kinds reverse to ink under it, so nothing clickable has to be guessed at (Rick, 2026-10-09).
| Check | 14 square, 1pt ink, filled ink with a paper tick when on | |

A permission row: heading over caption, flush left with the words above it, the action flush right on the heading's baseline, and a hairline under the row that carries the state: ink when allowed, Rule when not, Orange while macOS is being asked. No dots.

Focus is always a 2pt Orange ring, 2 outside. Everything on a row of controls obeys the baseline law.

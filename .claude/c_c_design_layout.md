# Layout

## The grid

Twelve columns always. The wizard: margins 48, gutters 24. The app window: margins 24, gutters 16. Every edge lands on a column; the style sheet's Show Grid proves it.

## The beat

Every gap is a multiple of 4: 4, 8, 12, 16, 24, 32, 48, 64, 96. Within a group 8 to 16. Between groups 48 to 96. Section to section 96.

## The alignment laws

1. **Across the bottom.** A horizontal row is justified along its bottom edge: baselines meet, a control's bottom meets the baseline beside it, a big title's baseline is the row's line. `NSStackView.alignment = .lastBaseline`; `.bottom` for views with no baseline. Never `.centerY` for a row that holds text.
2. **Left to the column.** Text starts on a column edge, never indented inside it.
3. **Right to the column.** Numerals and actions sit flush to their block's right edge.
4. **One axis per row.** A row is either text on a baseline or blocks on a bottom edge; never mixed heights centred.
5. **Across the top, between columns.** Where a title sits beside a column of words, the capitals of the words' first line sit level with the capitals of the title, measured from the fonts, not the line boxes.

## Three page layouts

**Split.** Title in columns 1 to 5 or 1 to 6; words, fields and the action in 7 or 8 to 12; a caption footnote back in columns 1 to 4 at the bottom. The wizard's default.

**Four Up.** Four cells of three columns, hairlines between, a small index number above each, heading then one line of body. For principles, options, choices.

**Index.** A large section number in column 1, the title from 2 to 6, a quiet caption in 9 to 12, then a labelled row of cards from column 3 across. For lists of catalogues, projects, palettes.

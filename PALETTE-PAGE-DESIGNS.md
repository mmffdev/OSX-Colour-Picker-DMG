# Palette page: five directions and the missed opportunities

A design review, 2026-10-04. Nothing here is built or agreed. The mocks are static and live on the
canvas "Palette Page Designs": https://claude.ai/artifact/VYjkEyzaYUkP29SvTXQSMv (private to Rick).
Each direction is drawn in dark and in light, with the Red Ribbon — Shades palette and its real values.

## What is wrong today

- **Three columns of chrome before any colour.** rail1 and rail2 together take about a quarter of a wide window, and far more of a laptop's.
- **Everything is on at once.** Values, contrast, histogram, channels and history all show for every swatch, so a first-time user meets about forty numbers per colour.
- **Flat hierarchy.** Labels, values and captions sit within two points of each other, so nothing says "read me first".
- **Tight spacing.** Sections are separated by about the same gap as the rows inside them, so groups do not read as groups.
- **rail1 truncates what it exists to show.** Four levels of indent leave room for "Red Ri…".

## The five directions

| | Direction | The idea | Best for | Cost |
|---|---|---|---|---|
| 1 | Calm | Today's page with rail2 folded into four controls above the cards, a flatter rail1 and a clear type scale | Least change, quickest to build | Options are one click further away |
| 2 | Inspector | A clean grid of swatches; everything about the chosen swatch reads in a panel on the right | Studios working one colour at a time | Comparing two swatches' numbers needs a second click |
| 3 | Specimen Sheet | One row per colour in a ruled table with grouped columns, under four summary tiles | Scientific and print users, export and audit | Least visual; the colours themselves are small |
| 4 | Focus | The palette strip is the navigation; one colour at a time is explained in plain words | Teaching and new adopters | Slowest for an expert scanning a whole palette |
| 5 | Workbench | Both rails kept but narrower; rail2 becomes a summary of the choices made; swatches are ruled rows with one set of column headings | People who like today's layout | Still three columns |

Recommendation: build 1 as the default page, take the inspector from 2 as the way to see everything
about one swatch, and offer 3 as the list view. 4 is the first-run and teaching view.

## What all five share

- **Type scale of four.** Page title 28, section heading 17, body 13, caption 11. Numbers in a fixed-width face with aligned digits.
- **Spacing in steps of 4.** 24 between cards, 40 to 48 page margin, 28 to 44 between sections, so a section gap is always larger than a row gap.
- **Palette name is the page title; the purpose is a chip beside it.** One line answers "what am I looking at, and for what".
- **One sentence for the verdict.** "All 5 In Range" with the profiles named, instead of a row per profile.
- **rail1 flattened.** Projects list as names with a count; palettes sit directly under a project. No Information and Palettes buckets inside each project.

## Missed opportunities

Each is something the page does not do today, and what it would look like.

1. **Progressive disclosure.** Show name, HEX and contrast by default; the rest on choosing a swatch. Looks like direction 2's inspector.
2. **Palette health at a glance.** Three or four tiles: in range, text on white, text on black, and later the closest pair of colours. Looks like the tiles in 2 and 3.
3. **Plain-language explainers.** A line beside each value saying what it is, switchable off in Settings. Looks like the Values list in 4.
4. **Contrast you can see.** A sample of real text in the colour on white and on black beside the ratio, not only the number. Looks like the As Text blocks in 4.
5. **Contrast between the palette's own colours.** Which pairs in this palette work together as text and background. A small matrix under the swatches; the Contrast tool already draws one.
6. **A purpose chip in the title.** Changing purpose from the title, with the rail2 list as the long form.
7. **Column chooser and saved views.** "Print check", "Web handover" as named sets of columns and panels per purpose. Looks like the Columns control in 3.
8. **Collapsible rail1.** An icon rail of about 76 points with labels, opening the tree on demand. Looks like 3.
9. **Click any value to copy, one copy affordance.** Drop the copy icon on every row; show it on hover and say so once at the foot of the page.
10. **Compare two swatches.** Choose two and see the difference in every space and the Delta E between them. A two-column inspector.
11. **Empty and first-run states.** A new palette shows three ways to add a colour with one line each, not an empty grid.
12. **Density setting.** Comfortable and Compact, so experts can have today's density by choice, not by default.
13. **Sheet export.** The Specimen Sheet as a PDF or CSV for a client or a printer, with the purpose and profile in its heading.
14. **Keyboard travel.** Arrow keys move between swatches, Space opens the inspector, a number key switches purpose.
15. **Status in words in the footer.** "Saved", "Synced 16:21" beside the release line, so the History rail is not the only proof of a save.

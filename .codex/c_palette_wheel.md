# Palette wheel

`PaletteWheel.swift` is a native AppKit overlay. `StudioFrame` launches from a colour-halo header button immediately after Projects; there is no edge notch. The wheel anchors to the right edge of collapsed Rail 1 and centres between the page title divider and footer. Opening snapshots panel goals and page expansion, collapses Rail 1 and hides Rail 2/history; dismissal restores the previous states, including already-closed panels.

- `items` snapshots the current catalogue's colour palettes at opening, using the same colour-managed display table as the rails.
- `currentID` aligns the current palette. `onOpen` opens its ID through normal page navigation.
- `edge` describes the receiving area's edge: left opens right, right opens left, top opens down, bottom opens up. Set `anchor` in overlay coordinates and `availableRect` to exclude protected headers/footer.
- Tab opens the wheel outside text fields, modal overlays, shortcut recording and setup. Shift-Tab retains focus navigation. Scroll either way; arrows step. Click any spoke to open its palette immediately; the hub or Return opens the indicated palette. Escape or an outside click dismisses it.
- Spectra share one width: 92 points normally, adapting together down to 44 in short windows to preserve names and info icons; labels use TextSize.body. Nine square-ended spokes span 180 degrees and connect beneath a half-circle hub with a plain smaller inset and static +45° grey/app-background stripes in the outer ring, 10 points on and 10 off. Spoke length adapts to short windows; every palette remains reachable. The surrounding page stays uncovered. The receiving edge clips spokes behind the rail, including half of the endpoint spokes; masked portions cannot be clicked.
- Opening unfolds over 460ms, closing takes 200ms. Scrolling settles to a detent after a short idle. Reduce Motion removes interpolation and preserves fractional trackpad input.

`runPaletteWheelTests` runs in the existing self-test suite. Build this branch with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./make_appstore.sh`.

Click a spoke’s circled info icon to reveal one Bézier-connected colour block per palette entry, using its palette name and sRGB display hex. The tree stays open as the mouse moves away. Scroll within the blocks for larger lists. I shows details of the indicated spoke. Only outside clicks, choosing a palette (including Return), or Escape close the wheel; Tab and hub clicks do not dismiss it. Colour descriptions are also available in the selected control’s accessibility help.

While open, a cached Gaussian-blurred page snapshot softens the background below the protected page header. Colour blocks centre vertically in the available page area and carry soft offset shadows.

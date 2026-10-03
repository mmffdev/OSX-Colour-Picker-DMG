# The master colour

A design for Rick to approve. Nothing here is built.
Written 2026-10-03, after the product was defined as a full colour management and proofing system for 2D, 3D, video, graphic design and print.

## 1. The decision

Stop treating a colour as a hex. Give every colour a **master**: a definition that belongs to no screen, press or file format. Hex, CMYK, Rec. 709, ACEScg and the rest become **renderings** of that master, each with a figure for how faithful it is.

This is the foundation every channel feature stands on. It is cheaper to lay now than after proofing, LUTs and print are built on top of hex.

## 2. What is wrong today

A swatch **is** an 8-bit sRGB hex. Three consequences:

| Problem | What it costs |
|---|---|
| The picker reads the screen in full quality, then squeezes it into sRGB hex | A vivid colour on a P3 screen is lost the moment it is picked |
| Imported print and Lab values would be converted to hex and discarded | A print shop's CMYK build cannot be kept, only approximated |
| The hex is the colour's identity in the library, sync, history and project files | Two different colours that round to the same hex cannot both exist |

The hex appears about 280 times across 22 source files. This is the largest single change the app has had.

## 3. What a colour becomes

Three things, kept together:

| Part | What it is | Example |
|---|---|---|
| **Identity** | An id of its own, never its value | `3F2A…` |
| **Source** | The colour exactly as it was given, in the space it was given in | "Display P3: 0.92, 0.20, 0.14" or "CMYK, FOGRA39: 0, 90, 85, 0" or "Lab: 52, 68, 48" or "#E93627" |
| **Master** | The same colour in CIE Lab (D50), the common language | Lab 52.1, 68.3, 47.9 |

**Why keep the source as well as the master.** The source is the truth as the user gave it. A printer who types a CMYK build must get exactly that build back, not a round trip through maths. The master exists so that any two colours can be compared and any colour can be translated.

**Why Lab (D50).** It is the standard meeting point of colour management: every ICC profile converts to and from it. It can describe every colour the eye sees, so nothing is clipped. It is also what a spectrophotometer reading and Adobe's Lab swatches give us directly.

## 4. Renderings and proofs

A rendering is worked out, not stored. For each channel the app shows the value to use, the difference from the master, and whether the channel can show the colour at all.

| Channel | Renderings | How |
|---|---|---|
| Screen and web | sRGB hex, Display P3 | Standard profiles, built into macOS |
| Print | CMYK through a chosen press profile; ink total | ICC profiles: FOGRA39, FOGRA51, GRACoL, SWOP |
| Video | Rec. 709, Rec. 2020, HDR | Built into macOS; LUT export later |
| 3D and VFX | ACEScg, linear | Built into macOS; OCIO export later |
| Physical | Nearest reference in a library the user supplies | ΔE match against imported books |

The difference is measured in ΔE 2000, one figure everywhere: about 1 is the smallest the eye sees, above 2 is plainly a different colour.

**Pinned values.** A channel's worked-out value can be replaced by an approved one. An agency's signed-off CMYK build is rarely what a profile gives. The pinned value is what gets delivered; the proof still shows how far it sits from the master. This is what a print shop will judge us on.

## 5. What you would see

- Nothing breaks. Every existing colour looks and copies exactly as it does now.
- A swatch's sheet gains a **Channels** view: one line per channel with its value, its ΔE, and a warning when it is out of range.
- Picking on a P3 screen keeps the full colour.
- Importing a swatch file keeps the CMYK and Lab values it carries.

## 6. Carrying existing work over

- Every hex in every library becomes a colour with source "sRGB hex" and a master worked out from it. No colour changes.
- Palettes, notes, tags, history and project files are re-pointed from the hex to the new id.
- Library and project files move to a new version. The app reads the old version and writes the new one.

## 7. The stages

| Stage | Delivers | Visible to you |
|---|---|---|
| 1 | The new colour record, the carry-over, sync and file versions, self-tests | Nothing changes, by design |
| 2 | Picker keeps wide gamut; import of ASE, ACO, GPL, CLR keeps source values | Truer picks; your existing libraries come in |
| 3 | Channels and proofs on every swatch; the Gamut tool (paused today) lands here | The first enterprise feature |
| 4 | Pinned values and approval status | Sign-off |
| 5 | Delivery packs per channel: print swatches, LUT, OCIO, spec sheet | Handover |

## 8. Risks

| Risk | How it is handled |
|---|---|
| Two Macs on different versions syncing one library | The older app refuses a newer library with a clear message; it never writes over it |
| A mistake in the carry-over damages a library | A backup is taken before the first upgrade; self-tests prove every colour, palette, note and step survives |
| The change is large | Stage 1 keeps "the sRGB hex of a colour" available to all existing code, so pages keep working while the foundation moves under them |
| Press profiles: may we ship them with the app? | Not yet verified. Until it is, the user points the app at profiles already on their Mac |

## 9. Decisions for Rick

1. **Master in Lab (D50), with the source kept beside it.** Recommended. The alternative, storing spectral data as the master, is truer still but only a few users can supply it; it fits later as another kind of source.
2. **Pinned values from stage 4, not stage 1.** Recommended. The record is designed for them now; the screens come with approval.
3. **Older versions cannot open upgraded libraries.** Recommended, with the backup and the refusal message. The alternative, writing both formats, doubles the risk of the two drifting apart.
4. **Which press profiles first.** I suggest FOGRA39 and FOGRA51 for Europe, GRACoL and SWOP for the US. Tell me which presses your network actually runs.

# Colour management: what this product is, and how its colour works

The reference for the product's direction and its colour foundation. It records what Rick defined, what was proposed, the questions raised and the answers given, so the reasoning is never lost.

**Status on 2026-10-03:** sections 1 and 2 are Rick's definition. Rick approved the design the same day ("I agree with your findings. Build it"), adding that a palette selects a named profile because one project can need different options per palette. Section 8 says what is built and what is not.

Backlog: runway PR-23, objective "Colour Management And Proofing". Ideas list: [scratch.md](scratch.md).

---

## 1. What the product is

Defined by Rick, 2026-10-03.

1. A **full enterprise colour management and proofing system**.
2. For **everything colour, in every area**: 2D, 3D, video, graphic design, print shops.

All channels matter equally. **Hex must not be the primary promise.** CMYK, LUTs, video and 3D colour, and print proofing are crucial, not add-ons.

**Nothing colour in the current app is sacred.** Only the organisation details and the project form data must be kept.

## 2. The promise

**One colour, defined once, proven everywhere.**

A brand colour is not a hex. It is a colour a person approved, which then has to survive a screen, a press, a grade and a render. The product holds the master and shows, for each channel, the value to use and how faithful it is.

| Step | What the product does |
|---|---|
| Define | Hold the master colour, independent of any device |
| Translate | Give the right value for each channel, through real profiles |
| Proof | Show how far each channel drifts, and the closest colour it can reach |
| Approve | Record who signed off what, and when |
| Deliver | Hand each team its own pack |

| Channel | Needs | In the app today |
|---|---|---|
| Screen and web | sRGB, Display P3, design tokens | Strong |
| Print | CMYK through ICC profiles, ink limits, spot references | A naive CMYK figure only |
| Video | Rec. 709, Rec. 2020, HDR, LUTs | Values on cards only |
| 3D and VFX | ACEScg, linear values, OCIO | Nothing |
| Physical | Spectral readings, reference libraries such as Pantone and RAL | Nothing |

## 3. What is wrong with the foundation today

A swatch **is** an 8-bit sRGB hex.

| Problem | What it costs |
|---|---|
| The picker reads the screen at full quality, then squeezes the result into sRGB hex | A vivid colour on a P3 screen is lost at the moment it is picked |
| Imported print and Lab values would be turned into hex and discarded | A print shop's CMYK build cannot be kept, only approximated |
| The hex is the colour's identity in the library, sync, history and project files | Two different colours that round to the same hex cannot both exist |

The hex appears about 280 times across 22 source files.

## 4. The master colour (proposed)

A colour becomes these parts, kept together:

| Part | What it is | Example |
|---|---|---|
| **Identity** | An id of its own, never its value | `3F2A…` |
| **Source** | The colour exactly as it was given, in the space it was given in | "Display P3: 0.92, 0.20, 0.14" · "CMYK, FOGRA39: 0, 90, 85, 0" · "Lab: 52, 68, 48" · "#E93627" |
| **Master** | The same colour in CIE XYZ, adapted to D50, as floating-point numbers | X 0.412, Y 0.213, Z 0.019 |
| **Kind** | Surface or light (section 5) | Surface |
| **Spectral data** | Optional: the measured reflectance of an ink or paint | A spectrophotometer reading |

**Why keep the source.** It is the truth as the user gave it. A printer who types a CMYK build must get exactly that build back, never a round trip through maths.

**Why XYZ and not Lab.** Both describe every colour the eye sees and convert to each other exactly. Lab measures everything against a white ceiling, so it cannot hold an HDR highlight or a 3D light value. XYZ has no ceiling. A print-only tool could use Lab; a tool that also serves video and 3D cannot.

**Why not spectral data as the master.** It is the physical truth of an ink, and it is the only thing that catches two colours matching under one light and not another. It cannot describe a colour made of light, and few users can supply it. So it is an optional extra on the colours that have it.

**White point.** The master is XYZ adapted to D50, the convention every ICC profile uses. Screen and video spaces are D65; conversion between the two uses the Bradford method, which is the standard and is exact in both directions. The white point is written into the file, so it is never ambiguous.

**Precision.** Full 64-bit floating point. Files are text, so the numbers read back exactly as written. One colour is three numbers, so the precision costs nothing.

## 5. Two kinds of colour

| Kind | What it is | Who lives here |
|---|---|---|
| **Surface** | Ink or paint. It has no brightness of its own and depends on the light it is seen under | Print shops, packaging, paint |
| **Light** | Emitted by a screen or a render. It has a real brightness, which can exceed white | Colourists, HDR, 3D |

Each colour carries its kind. That one flag is what lets the same tool serve a press and a colourist honestly.

## 6. Bit depth

Bit depth is how finely a channel is sliced when a colour is written into a file. It belongs to the **delivery**, never to the colour.

| Depth | Steps per channel | Where it is used |
|---|---|---|
| 8-bit | 256 | Web, hex, most screens, JPEG |
| 10-bit | 1,024 | HDR10 video, broadcast, P3 displays |
| 12-bit | 4,096 | Dolby Vision, cinema |
| 16-bit | 65,536 | Photoshop, print masters, TIFF |
| 16-bit float | Continuous | OpenEXR "half", the standard in VFX |
| 32-bit float | Continuous | Photoshop 32-bit, EXR, ACES, HDR work |

Integers stop at white. Float can go above it, which is how HDR and 3D describe a highlight brighter than paper.

**Rule:** the master is stored in 64-bit float and is never rounded. Each delivery picks its own depth at the moment of export.

## 7. Rules for working with colour

These came from a review of the design (section 10) and are part of it.

### 7.1 The right space for each job
The master is for storing the truth. It is never used to judge or blend, because equal steps in XYZ do not look like equal steps to the eye.

| Job | Space | Measure |
|---|---|---|
| Nearest colour, print matching, proofs | CIE Lab (D50) | ΔE 2000 |
| Gradients, scales, harmonies | OKLab / OKLCH | Colour Lab already works here |
| Differences between HDR video colours | ICtCp | ΔE ITP |

ΔE 2000 in plain terms: about 1 is the smallest difference the eye sees; above 2, two colours side by side are plainly not the same.

### 7.2 Rendering intent
A colour that is valid as a master may be outside what a channel can show. How it is brought in is the rendering intent, chosen per channel and always shown beside the value.

| Intent | What it does | Used for |
|---|---|---|
| **Relative colorimetric**, with black point compensation | Keeps every in-range colour exactly; brings an out-of-range colour to the nearest edge | **The default for swatches.** A brand colour that is in range must not move |
| **Absolute colorimetric** | As above, and also shows the colour on that paper's own white | The proof view |
| **Perceptual** | Compresses everything to fit, shifting even in-range colours | Images, when the product handles them. Not single colours |

### 7.3 Print conditions
There is no such thing as "the CMYK value" of a colour. A CMYK figure means something only with its print condition.

- **A bare CMYK value never appears.** Every figure names its condition: the profile, the intent, the ink limit.
- **The condition is chosen by choosing the profile.** Ink limit and black generation are baked into each ICC profile when it is made; they are not dials turned at conversion. FOGRA39 at 300% and at 330% are two profiles.
- **Total ink is reported for every build**, with a warning when it passes the condition's limit.
- **A hand-built recipe is a pinned value** (7.4).
- **Custom black generation is out of scope at first.** It needs a profile-making engine, a product in itself.
- The naive CMYK figure on today's cards is exactly the meaningless value this rule forbids. It goes.

### 7.4 Pinned values
A channel's worked-out value can be replaced by an approved one. An agency's signed-off CMYK build is rarely what a profile gives. The pinned value is what gets delivered; the proof still shows how far it sits from the master.

## 7.5 Colour profiles: where the options are captured

Added by Rick on approval. Options are captured once, as high up as they make sense, and flow down.

| Level | Holds | Where |
|---|---|---|
| **House** | The studio's named profiles, and which is the default | Settings, Colour |
| **Project** | The profile its palettes work to | The project's Overview page, on the action bar |
| **Palette** | A profile of its own, when it differs from its project's | The palette's action bar |
| **Delivery** | Format and bit depth | At export (not built) |

A **colour profile** is a named set of channels: screen, video and rendering spaces, and at most one print condition (a press profile and a rendering intent). Five come with the app: Screen And Web, Print, Video, Rendering And Effects, Every Channel. A profile in use is copied into the library and into the project's file, so both stay whole when they travel. An edit in Settings shows at once, because the newer copy is the one used.

## 8. Stages

| Stage | Delivers | State on 2026-10-03 |
|---|---|---|
| 1 | The master colour record; existing colours carried over; files and sync on the new record; self-tests | **Built.** Every colour has a master, and a colour that is not a plain sRGB value has a key of its own and carries its source, master and kind through files, sync, history and export |
| 2 | The picker keeps wide gamut; importing ASE, ACO, GPL and CLR keeps the values those files carry | **Part built:** the picker keeps Display P3, and New Colour takes P3, CMYK for a press, Lab or hex. Imports still read hex only |
| 3 | Channels and proofs on every swatch; rendering intents; the Gamut tool | **Built:** profiles, and the Channels view in every swatch's sheet. The Gamut tool is still paused |
| 4 | Print conditions, ink reporting, pinned values, approval status | **Part built:** press profile, three intents and black point compensation per profile, total ink shown, the card's CMYK row built for the press. No ink limit warning, no pinned values, no approval |
| 5 | Delivery per channel: print swatches, LUT, OCIO, spec sheet, each at its own bit depth | Not built |

### What is built (2026-10-03)

- **The colour engine** (`ColourEngine.swift`): the master in XYZ (D50), 64-bit; exact conversion to and from sRGB, Display P3, Adobe RGB, Rec. 709, Rec. 2020 and ACEScg by matrix maths with Bradford adaptation; Lab (D50); the CIEDE2000 difference, checked against published figures; press profiles read from the Mac and run through the system's engine; a rendering per channel with its value, difference and range.
- **Existing colours carried over without rewriting anything.** A colour known by its hex has that hex as its sRGB source; its master is worked out from it. No library file changed.
- **Colour profiles** (`ColourProfiles.swift`), section 7.5: house, project and palette levels, kept in the library and the project file, with sync rules.
- **The Channels view:** a swatch's sheet lists its source, master, kind and profile, then every channel with the master and the channel's colour side by side, the value, the difference and In Range or Out Of Range.
- **Settings, Colour:** make, name, duplicate and delete profiles; tick their channels; choose the press profile and intent; choose the house default.
- Light colours above white are held whole in ACEScg; the engine is ready for them, though nothing in the app can make one yet.

### The five gaps, filled (2026-10-03)

- **A colour is more than its hex** (`ColourIdentity.swift`). A plain sRGB colour keeps `#RRGGBB` as its key, so no existing library changed. Any other colour gets a key of its own (`c:` and an id) and its record carries `source`, `master` and `kind`. Older code that hands a key to something expecting a hex gets the sRGB colour it shows as; cards draw it in Display P3. The picker keeps a pick sRGB cannot hold as Display P3. **New Colour** (File menu, Shift-Command-K, or the plus on a palette's bar) takes Display P3, a CMYK build for a press, Lab or a hex, and keeps it exactly as typed.
- **Black point compensation** is worked out by the app: the master is scaled so black lands on the press's darkest black and white takes no ink. A tick per profile, off to begin with.
- **Absolute colorimetric** is worked out by the app from the paper white read out of the press profile's own data. It is the second of three intents in every profile.
- **Video values in legal range** (64 to 940): a tick per profile, covering Rec. 709 and Rec. 2020. Every video value names its range.
- **The CMYK row on cards is the build for a real press:** the print condition of the profile the palette uses, or the system's Generic CMYK when the profile has no print channel. Its tooltip names the condition. The design pack names the condition beside each palette. A press profile that is not on the Mac gives a dash, never a made-up build.

### Added 2026-10-04

- **Cinema:** P3-D65 (streaming and HDR grading, gamma 2.6) and DCI-P3 (projection, the theatre's own white, gamma 2.6, written as 12-bit codes).
- **Photo:** ProPhoto RGB as a channel and as a way to type a colour in. Never written in 8 bits.
- **The video signal:** Rec. 709 and Rec. 2020 rows carry Y′CbCr beside their RGB codes, in the range the profile asks for. Y′CbCr is a way of writing a video colour, not a space of its own, so it is a readout and a histogram, not a channel.
- **Palette pages:** grouping and filtering, four switchable columns per swatch in the vertical view (Histogram, Channels, Notes, History), and histograms for every set of values a card shows, with safe zones.

### What is not built, and why it matters

- **Imports read hex only.** ASE, ACO, GPL and CLR files can carry CMYK, Lab and wide values; the importers still reduce them to sRGB. The identity work makes keeping them possible; it has not been done.
- **Exports of a colour beyond sRGB give its nearest sRGB value.** CSS, tokens, swatch files and PNGs know only sRGB today. Delivery per channel is stage 5.
- **Harmonies, shades and contrast work from the sRGB colour a keyed colour shows as.** A shade of a P3 colour is an sRGB shade.
- **Press profiles are not shipped with the app.** The app uses what is on the Mac: the system's Generic CMYK, and Adobe's set when Adobe apps are installed (FOGRA39, GRACoL, SWOP and others).
- **No ink limit warning, pinned values or approval status** (stage 4), and nothing yet makes a light colour above white.

**Paused work.** A Gamut tool was started on 2026-10-03 before this design existed: the CIE 1931 chromaticity diagram, gamut triangles for sRGB, Display P3, Adobe RGB and Rec. 2020, a palette plotted on it, and a print-shift check using ΔE 2000. It is kept in a git stash named "Gamut tool, paused 2026-10-03", with two self-tests failing. It returns at stage 3, rebuilt on the master colour.

## 9. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| 1 | The master: XYZ (D50) in float, source kept, spectral optional, surface or light | **Agreed by Rick, 2026-10-03** |
| 2 | Bit depth chosen per delivery, never stored | **Agreed by Rick, 2026-10-03** |
| 3 | Existing palettes: convert them or start clean | **Agreed: convert.** Done without rewriting any file |
| 4 | Which press profiles first | FOGRA39 and FOGRA51 for Europe, GRACoL and SWOP for the US. To be set by the presses Rick's network runs |
| 5 | Reference libraries (Pantone, RAL, NCS, Toyo) | Match against libraries the user supplies, until licensing is looked into |
| 6 | What a LUT made from a palette does | To be defined. One suggestion: a creative "palette look", clearly labelled as not a technical conversion |

**Not yet verified:** whether press profiles may be shipped inside the app. Until it is, the user points the app at profiles already on their Mac.

## 10. The discussion, in order

**2026-10-03, Rick sets the direction.** After reviewing the ideas list he defined the product (section 1) and asked "what is it really, and what do we do to cover these channels?" The answer is section 2, with the finding that the hex-based foundation contradicts the definition.

**Design first.** Rick chose to have the master colour designed and approved before any channel feature is built. A first design proposed Lab (D50) as the master.

**"Nothing is sacred."** Rick ruled that anything colour can go; only organisation and project form data must be kept. He asked what the master format should be and whether to move to 16 or 32 bit. That removed the need to protect the old hex library and led to two changes: XYZ in float replaced Lab as the master, because Lab cannot hold HDR; and bit depth was moved out of the colour and into delivery (section 6).

**Five review points, raised by Rick.** Each was checked against the design:

| # | Point | Was it covered | Outcome |
|---|---|---|---|
| 1 | XYZ is not perceptually uniform; Lab or OKLab is better for nearest colour and gradients | Yes, though not written down | Section 7.1 makes it a rule |
| 2 | Gamut boundaries remain downstream; a rendering intent is needed | **No. A gap** | Section 7.2 |
| 3 | CMYK is not a single target: profile, total ink limit, black generation | Half: profile yes, ink and black no | Section 7.3 |
| 4 | White point matters; standardise and be consistent | Half: stated vaguely | Section 4, "White point" |
| 5 | Precision: 16-bit integer or 32-bit float | Yes | Section 4, "Precision": 64-bit float, exact in text files |

**Approval.** Asked how the options would be captured, Claude proposed capturing each once at the highest level that makes sense: house, project, colour, delivery. Rick agreed and added that a project can need different options per palette, so a palette selects a named profile (section 7.5). He approved the design and said to build it.

**Earlier "no" notes.** Notes in the old scratch file said no to Pantone and RAL matching, to `.cube` export and left CMYK naive. Those were Claude's own calls in the first v3 build on 2026-10-01, never Rick's rulings. Under the product definition all three are open and wanted.

## 11. Words

| Word | Means |
|---|---|
| **Master** | A colour's definition, independent of any device |
| **Source** | The colour as the user gave it |
| **Rendering** | The master expressed for one channel |
| **Channel** | A way a colour is delivered: screen, print, video, 3D, physical |
| **Gamut** | The range of colours a device or standard can show |
| **ICC profile** | A file describing how one device or press reproduces colour |
| **Print condition** | A profile, an intent and an ink limit, together |
| **Rendering intent** | The rule for bringing an out-of-range colour into range |
| **ΔE** | A number for how different two colours look |
| **White point** | The white a colour space is built round: D50 for print, D65 for screens |
| **Bit depth** | How finely a channel is sliced in a file |
| **HDR** | High dynamic range: brightness above ordinary white |
| **LUT** | A lookup table that transforms the colours of an image, used in grading |
| **ACES, OCIO** | The film and VFX industry's colour standard, and the tool that applies it |
| **TAC** | Total area coverage: the sum of the four inks, which a press limits |
| **Spectral data** | How much of each wavelength a surface reflects |

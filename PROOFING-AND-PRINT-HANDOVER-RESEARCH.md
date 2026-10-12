# Proofing, image palettes and print handover

Research and product decisions recorded on **12 October 2026**, Europe/London.

This document brings tonight’s code review, licence checks, printer research and export discussion into one reading order: what a customer needs, what a printer expects, how image analysis fits, what must travel in an export, and what remains to build. Printer instructions are source evidence, not universal defaults or instructions to change our app’s UI.

## 1. The intended customer workflow

**Import artwork or a palette → identify its source colours → choose the printing condition → predict or measure the result → approve an exact version → export the evidence.**

Rick confirmed the proposed image workflow: import an image, extract its palette, and check those colours against a chosen print profile.

A useful handover must preserve both the original colours and the result under the selected conditions. It must say whether that result is a profile prediction, an instrument measurement, or an approved physical sample. A screen preview alone cannot verify a printed sheet.

This extends the product direction in [COLOUR-MANAGEMENT.md](COLOUR-MANAGEMENT.md): define the master colour, translate it for a channel, record its fidelity, approve it and deliver the appropriate pack.

## 2. What actual printers ask customers to supply

Research used printers’ published customer-facing guides, not direct conversations with their prepress teams. Requirements depend on the product, material and printing process; confirm the selected job’s current specification.

| Printer | Artwork requirement | Colour and profile requirement |
| --- | --- | --- |
| [Packlane — custom boxes](https://packlane.com/support/printing-101) | Use its packaging templates and artwork workflow. Its [3D-tool guidance](https://packlane.com/support/how-do-i-order-on-the-website-and-design-on-the-3d-tool) asks for outlined fonts, embedded images, flattened transparency and 300 ppi raster artwork. | Recommends CMYK and Coated GRACoL 2006. Pantone colours are converted to CMYK; it does not offer colour matching. |
| [HelloPack — packaging and labels](https://hellopack.com/en/artwork-guidelines) | High-resolution PDF, preferably PDF/X-4; embedded images/fonts or outlined text; 3 mm bleed; separate artwork, dieline and finishing layers. | Its public checklist specifies CMYK without naming an exact ICC profile. Barcodes and QR codes use 100% K. |
| [Packly — custom packaging](https://www.pack.ly/en/help-center/post/printing-files-guidelines-and-suggestions) | Adobe PDF High Quality Print preset; unchanged original dieline retained on a separate layer; product-specific bleed and safe areas. | Most products use CMYK, with RGB/Pantone converted. Some products, including tissue paper, use a dedicated single-colour palette. It also publishes an [output-profile download](https://landing.pack.ly/it/help-center/articolo/profilo-colore), dated January 2021 and tagged FOGRA39. |
| [Inprint Group — custom boxes](https://www.inprintgroup.co.uk/blog/artwork-setup-for-custom-boxes-print-profiles-tolerances-and-essential-pre-press-requirements/) | Vector dieline on a separate layer, separate finishing layers, embedded/outlined fonts and 300 dpi images. Its guide recommends 3–5 mm bleed and 5–7 mm safe zones. | Recommends ISO Coated v2 / FOGRA39 or PSO Coated v3 / FOGRA51 for appropriate carton workflows. Stock, coatings and process affect colour reproduction. |
| [Solopress — general commercial artwork guide](https://www.solopress.com/support-guides/supplying-artwork/) | Prepared PDF; editable InDesign work should be packaged with fonts/images and accompanied by a reference PDF. | Specifies CMYK and FOGRA39. This is general artwork guidance rather than a dedicated packaging specification. |

The differences extend to ink recipes. [Packlane’s black guidance](https://packlane.com/support/how-should-i-set-up-black-or-gray-color-builds) recommends C60 M40 Y40 K100 for large black areas, whereas Packly’s CMYK-product guide recommends C40 M30 Y0 K100. Neither should become a universal rich-black preset. Black text, barcodes, white ink, varnish and foil need their own production rules.

### Specialist flexographic packaging

[Alert Packaging’s HD flexographic guide](https://www.alertpackaging.com/wp-content/uploads/2021/10/Alert-Packaging-HD-Flexographic-Artwork-Guide-V1b.pdf) explicitly dates itself to **16 August 2017**, despite its later upload path. Treat it as a useful specialist example whose exact requirements need reconfirming.

It requests layered Illustrator artwork, Pantone references, linked images, outlined fonts and separate CxF files for special colours. It provides substrate-specific profiles, prefers GMG OpenColor formats, offers ICC alternatives with reservations, and specifies calibrated, measured proof verification. Its guide includes D50/2° viewing data and a Delta E 2000 acceptance threshold below 2 for colour quality approval. These are that printer’s stated requirements, not a general tolerance for all jobs.

**Research conclusion:** the deliverable is usually artwork prepared to a printer’s specification. A palette, a loose ICC file or our native share archive does not replace the packaging artwork and dieline.

## 3. What “proof approval” means

Keep these records separate:

| Record | What it establishes |
| --- | --- |
| Artwork/layout approval | The specified version has the correct text, layout, orientation, dieline and production elements. |
| Profile prediction | The colours have been evaluated through a specified ICC engine/profile with recorded settings. |
| Measured proof | Instrument readings have been compared with reference values under recorded measurement conditions. |
| Physical-sample approval | A named person accepted an identified printed sample, material and finish. |

[Packlane sends a digital PDF proof for approval before production](https://packlane.com/support/will-i-see-a-proof-for-my-order-how-do-i-know-if-my-art-is-printable), while its colour policy does not guarantee screen-to-print matching. This demonstrates why digital approval must not automatically mean measured colour approval.

The tool should store the artwork/palette version, approver, date, approval scope and any reference sample. Changing the colours, profile, material or settings should create a new evaluation rather than overwrite the original approval record.

## 4. ICC profiles: embedded, separate and identified

An ICC profile describes a colour space or output condition. It is not the palette and does not contain our proof-result history. FOGRA characterisation data and an ICC generated for that printing condition are also distinct assets.

| File/workflow | How the profile can travel |
| --- | --- |
| PSD, TIFF and other supported image files | The actual ICC can be embedded when saving. Photoshop has an Embed Color Profile option. |
| InDesign | The document can carry profiles; linked images can have their own profiles and must accompany an editable handover. |
| Print PDF | Can carry image profiles and an output-intent profile describing the intended printing condition. |
| Palette/proof package | Must record the exact profile identity. Include the ICC itself when the workflow requires it and redistribution is permitted. |

Sources: [Photoshop embedding](https://helpx.adobe.com/photoshop/desktop/adjust-color/color-profiles/embed-color-profiles.html), [Adobe colour-managed documents](https://helpx.adobe.com/photoshop/using/color-managing-imported-images.html), [PDF output intents](https://helpx.adobe.com/acrobat/using/output-intents-pdfs-acrobat-pro.html), [ICC introduction](https://preview.color.org/getting-started/).

An embedded RGB source profile tells us how to interpret image pixels; it need not be the intended press profile. Keep source and destination roles explicit. The printer may supply the required output profile before the designer prepares the artwork.

Embedding is normal technical practice, but redistribution permission is specific to the profile’s licence. Tonight’s review did not establish a blanket Adobe-profile prohibition. The product needs a controlled profile-inclusion policy, not an assumption that all profiles may be shared or that none may be embedded.

## 5. Analysing an image for its palette and print result

### Existing foundation

`Controller.importPalette(from:)` already loads an image and creates a palette through `extractPalette` in [Palette.swift](Palette.swift). The extractor uses Core Image clustering, selects distinct colours and suppresses likely edge blends. Rectangle screen sampling uses the same extractor.

The current path converts the sampled image to an **8-bit sRGB bitmap** and returns hex values. That is useful for design palettes but can lose wide-gamut/source precision. There is no dedicated image-to-proof workflow on the Proofing page yet.

### Proposed professional workflow

1. **Import and identify.** Start with supported raster formats; record filename, file digest, dimensions, bit depth, source colour model and embedded profile identity. Validate decoder support for PSD composites separately; image extraction does not preserve PSD layers or analyse an InDesign document’s objects.
2. **Resolve colour interpretation.** Honour the embedded source profile. If missing, show the assumption and allow an explicit source-profile choice. Never silently interpret an untagged CMYK file as a known press condition.
3. **Choose the sample.** Offer a region selection, palette size, transparency/background exclusion and manual selection of small but important brand colours. Exclude fully transparent pixels; make partial-alpha compositing background explicit.
4. **Extract without prematurely clipping.** Use a suitably precise, colour-managed working representation and retain source values alongside D50 XYZ/Lab. An sRGB preview must not become the sole stored colour definition.
5. **Review the palette.** Give each colour a stable ID and name, with sample location/region and prominence information where available. Record extraction method/version and settings so the result can be reproduced.
6. **Choose the print job.** Select the agreed output ICC, rendering intent, material, print process, ink-review limit and tolerance. For an already separated CMYK image, distinguish preserving its original recipe from generating a new separation.
7. **Predict and inspect.** Show original versus predicted colour, generated CMYK where available, ΔL*/Δa*/Δb*/ΔE, and tolerance/ink warnings. Keep all source colours, including those that cannot meet the requested tolerance.
8. **Save and export.** Link the exact palette version to a dated result snapshot and its provenance. A later recalculation creates a new record.

An extracted palette is a summary of image colours, not a complete artwork preflight. It cannot establish font embedding, effective resolution for every placed object, separations, overprint, trapping or dieline correctness. A photograph of a printed swatch is also not a spectrophotometer reading: illumination, camera processing and source profiling affect its pixels.

## 6. What must be retained in an export

### Confirmed gap

Current `.colcal` configurations and `.colproof` sessions retain source datasets and settings but **omit the calculated result snapshot**. Reopening recalculates results. CSV keeps numeric results, but is not the complete editable/archive record. This omission was identified after the initial code review and remains unfixed.

### Proposed result snapshot

Store a versioned record containing:

- Result ID, creation time and exact palette/artwork version or digest.
- Original reference patches and measured/source values, matched by stable IDs.
- Every evaluated or unevaluated patch, predicted/measured Lab, CMYK where available, component differences, Delta E, status and issue.
- Summary, difference formula, parameters, tolerances and ink-review limits used at evaluation time.
- Source/output profile identities and digests; rendering intent and black-point-compensation setting.
- Engine/algorithm version, application build, measurement conditions and relevant instrument metadata.
- Approval scope, author/date and physical-sample reference when present.

The original snapshot must remain viewable when an ICC or engine is unavailable. Recalculation must require suitable matching inputs and create a new result. Missing/mismatched profiles must never quietly become a pass. Legacy files without snapshots must remain clearly identified as input-only records.

### Export choices

| Choice | Proposed contents |
| --- | --- |
| Palette only | Named source colours and IDs in the requested supported palette format. |
| Palette with proof | One `.colshr` native share containing palette data, configuration, saved results, profile identity and any permitted profile payload. |
| Printer handover | Familiar companion files: palette/colour references, PDF/CSV report, permitted ICC, and CxF where supported/requested; printer/job specification and approval record. Artwork/dielines are supplied separately unless explicitly attached. |
| Proof report | Readable saved result report; preserve its evaluation date and provenance rather than label a new calculation as the old result. |

Consolidate the overlapping session/configuration actions around `.colcal`, retaining a legacy `.colproof` reader. Register configurations and results by ID in `.colcat` so catalogue renames, deletion, tombstones and migration understand them. Catalogue exports should carry the entire saved collection. An unsaved active proof needs an explicit inclusion/save decision; it must not be silently assumed to be archived.

The existing `Library/Calibrations` folder and `.colcal` name are compatibility choices; a proof configuration is not itself a measured display calibration.

## 7. Engines, exchange libraries and licences

Detailed checks, exact standalone archive hashes and original licence copies are in [the engine pivot notes](.codex/c_colour_engine_pivot.md).

| Component | Verified position | Proposed role |
| --- | --- | --- |
| Apple APIs currently called | The installed SDK does not mark `CGColor.converted`/`CGColorCreateCopyByMatchingToColorSpace` or `CGColorSpaceCreateWithICCData` deprecated. Older ICC-profile APIs are deprecated. | Native profile discovery/display integration can remain; replacing the transform engine is a deliberate product decision. |
| [LittleCMS core](https://github.com/mm2/Little-CMS/blob/master/LICENSE) | MIT; notices must be retained. | Leading candidate for one shared ICC-transform backend. Validate v2/v4 profiles, intents, paper white, scaling and BPC before migration. |
| [LittleCMS optional speed plugins](https://littlecms.com/plugin/) | GPL3/commercial terms differ from the core. | Exclude until separately assessed/licensed. |
| [ArgyllCMS/ArgyllPRO](https://www.argyllcms.com/commercialuse.html) | Package is AGPL3; author offers commercial licensing and advises securing suitable terms before closed-source integration. | Candidate for live instrument acquisition, calibration and profiling. Rick acknowledged the commercial-licence route. No integration exists yet. |
| [Standalone icclib V3.2.0](https://www.argyllcms.com/icclibsrc.html) | Its actual `License4.txt` contains the MIT grant, although the page calls it BSD-like. | Evaluate ICC profile inspection/read/write and conversion against LittleCMS. Choose one main transform engine rather than duplicate numerical paths. |
| [Standalone cgatslib V3.2.0](https://www.argyllcms.com/icclibsrc.html) | Its actual `License4.txt` also contains the MIT grant. | Candidate for broader CGATS/IT8 import/export, multiple tables and custom fields, retaining our validation and input bounds. |

The standalone licences apply to those exact archives, not arbitrary newer code extracted from the AGPL package. Neither standalone library provides instrument drivers. Argyll compatibility and vendor firmware/calibration-data permissions depend on the specific meter; see [oeminst](https://www.argyllcms.com/doc/oeminst.html).

## 8. Measurement, monitor setup and the chart references

Print exchange and device control are separate problems. CGATS and CxF carry data; they do not constitute one universal spectrometer-control protocol. The proposed canonical measurement record retains patch IDs, original spectra/values, wavelengths/units, illuminant, observer, geometry, M condition, backing, instrument identity, timestamps and provenance. Unknown conditions remain unknown. See [print interoperability and monitor plans](COLOUR-MANAGEMENT.md#12-print-measurement-interoperability).

Rick owns a Datacolor Spyder; the exact model remains unconfirmed. Display measurement and reflective print measurement require separate capabilities. The implemented visual monitor guide helps inspect shadows, highlights, greys, gradients and clipping; it remains **visually adjusted, unmeasured** and does not generate an ICC or calibration curves. Device-based calibration is planned.

The supplied reference charts are retained under [.codex/references/proofing](.codex/references/proofing): density versus Delta E operating range, colour-error components, a*/b* distribution and grouped historical distributions. The historical pictures are design references, not imported measured datasets.

The current density graph is an editable quadratic simulation, separate from ProofEngine and excluded from proof reports. Its numbers do not derive from measured density series. Move it into a separate simulation workspace; a real operating range requires actual density/colour-difference samples and a documented fitting method. Do not infer press adjustments from a single Lab reading or an image palette.

The a*/b* projection is not a full three-dimensional gamut boundary. Charts need legends, relevant data and linked selection; expanded charts already have data/control panels and expand/contract controls.

## 9. Reference datasets and tonight’s verified fixes

[Fogra permits redistribution of unchanged characterisation data with attribution](https://fogra.org/en/downloads/work-tools/characterisation-data). Bundled FOGRA39/51/52 MediaWedge subsets contain 72 patches each. FOGRA39’s known D50/2° and M0 conditions are attached as loader provenance; its original file remains unchanged. FOGRA51/52 declare M1. Incompatible known modes cannot pass a measured comparison.

Additional Fogra and ColorChecker downloads are recorded in [reference-data/colour-targets/SOURCES.txt](reference-data/colour-targets/SOURCES.txt). The ColorChecker source’s redistribution licence was not specified; those reference downloads have not been shipped with the app. Match ColorChecker reference data to the actual chart generation.

| Item | Current status |
| --- | --- |
| Direct-build Fogra resource loading could depend on the developer’s `.build` folder | Fixed: shared app-bundle loader; no runtime `Bundle.module` fallback; direct Xcode resources declared. |
| Bundled FOGRA39 unnecessarily required D50/2° confirmation | Fixed with known-target provenance and mode validation. |
| CSV Name could override ID because of header order | Fixed: explicit identifier alias priority; repeated-name regression coverage. |
| Inspect swatch click silently added to Library | Removed. |
| English status text used as logic | Replaced with typed proof statuses. |
| Embedded ICC rehashed every batch | Registered once per evaluation. Parsing had already been cached. |
| Large patch lists created excessive native controls | Rail and register reuse visible controls, including All rows. |
| ASE archive paths broke when `/var` enumerated as `/private/var` | Fixed using consistent canonical paths, retaining exact registry links. |
| Pagination/house-button redesign | Rick excluded it from these changes; appearance left unchanged. |
| Engine replacement, saved-result snapshots and configuration/catalogue migration | Still pending. Current configurations still embed ICC bytes automatically. |

Verification after the fixes: **744 direct-build tests and 742 Store-build tests passed**. The Store app was installed; rail scrolling, linked selection and All-row control reuse were checked in the native app. Those checks do not certify print accuracy or constitute hardware calibration.

## 10. Build order

1. Preserve immutable proof-result snapshots and bind them to exact palette/image versions.
2. Consolidate configuration persistence and catalogue registration, with non-destructive legacy migration.
3. Add printer/job specifications and a controlled embedded/separate/profile-identity export policy.
4. Evaluate and validate one ICC backend; record the engine/version in all new evaluations.
5. Connect image extraction to proofing, strengthening source-profile handling and retained precision first.
6. Add requested CGATS/CxF interoperability and standard printer-facing reports.
7. Move monitor setup/simulations to clearly scoped workspaces, retaining convenient Proofing links.
8. Add hardware acquisition/calibration after model compatibility, licence and macOS/Store requirements are resolved.

These are proposed implementation steps, not claims that the missing workflows are already built.

# Proofing engine pivot and licence review

Reviewed 2026-10-12. Rick accepted the proofing review except pagination and house-button changes; leave those controls unchanged.

## Apple API status

The actual call is `CGColorCreateCopyByMatchingToColorSpace` (`CGColor.converted`), plus `CGColorSpaceCreateWithICCData`. The installed macOS SDK declares both available, without deprecation attributes. `CGColorSpaceCreateWithICCProfile` and `CGColorSpaceCopyICCProfile` are deprecated; the app does not use them. ColorSync transform APIs are also available. Do not describe the whole Apple ICC system as deprecated.

## Recommended pivot

Use LittleCMS 2 core behind one ICC-transform adapter for XYZ/Lab ↔ CMYK, rendering intents, black-point compensation and soft-proofing. Retain Apple APIs for installed-profile discovery and native display drawing. Pin the release and source hash; preserve its licence in both app bundles; exclude optional speed plugins unless separately licensed. LittleCMS is a transform engine, not a Spyder driver.

Core licence: [upstream MIT licence](https://github.com/mm2/Little-CMS/blob/master/LICENSE). Allows commercial distribution and modification with copyright/permission notice retained. The [optional speed plugins](https://littlecms.com/plugin/) have GPL3/commercial terms; do not assume they share the core licence.

Instrument integration: [ArgyllCMS commercial terms](https://www.argyllcms.com/commercialuse.html) identify AGPL3 for the package and offer ArgyllPRO commercial licensing. The author advises securing suitable terms before developing a closed-source integration. Obtain a quote covering device acquisition/calibration, executable or source embedding, redistribution, macOS and the Store edition. No Argyll code or runtime is currently incorporated. Spyder model and vendor firmware/calibration-data requirements remain to be identified; [oeminst](https://www.argyllcms.com/doc/oeminst.html) documents separately owned instrument data.

## Standalone Argyll libraries

Rick requested assessment of these separately. Downloaded the official standalone V3.2.0 archives and read each `License4.txt`, plus the core source headers. Both contain the MIT grant (free commercial use, modification and redistribution with notices), although the [download page](https://www.argyllcms.com/icclibsrc.html) calls them BSD-like. These findings apply to the exact standalone packages, not arbitrary newer files taken from the AGPL Argyll tree.

| Library | Use here | Archive SHA-256 |
| --- | --- | --- |
| `cgatslib` | Candidate for CGATS/IT8 import and export, multiple tables and custom fields. Preserve our bounds, exact IDs, metadata and validation above its C API. | `8ae1db49848ade1248763df61d0eff09e31b8d35d436b181c327ba222e4421f2` |
| `icclib` | Candidate for ICC inspection/read/write and profile lookups. Compare with LittleCMS on required ICC v2/v4 fixtures before choosing one primary transform engine. The web README is stale; evaluate the actual archive. | `c6e3849d73c861083d1062f3b992a762a02d12412eed6da8aedbfa488a0c5ee6` |

Original licence copies: [icclib](references/licences/ICCLib-V3.2.0-License4.txt), [cgatslib](references/licences/CGATSLib-V3.2.0-License4.txt). No library code has been incorporated. These libraries do not supply live instrument drivers/calibration. Prefer `cgatslib` as the first independent interoperability evaluation; retain LittleCMS as the transform recommendation pending comparison.

## Migration sequence

1. Pin and vendor only LittleCMS core after this recommendation is selected; use one adapter and transform cache shared by app proofing/rendering.
2. Validate with known ICC fixtures and reference Lab/XYZ values, including absolute/relative intent, paper white, black-point compensation, CMYK percentage scaling and out-of-gamut colours. Engine changes legitimately change predictions: record engine/version in reports and saved configurations. Do not preserve the current manual absolute/BPC approximations blindly.
3. Consolidate saves around `.colcal`, retaining a legacy `.colproof` reader. Register proof assets by UUID in `.colcat`; migrate loose configurations without deleting originals; coordinate writes, renames, deletions and tombstones with catalogue ownership.
4. Replace automatic profile embedding with name + SHA-256 + media-white identity. Require the exact installed profile before recalculating predictions. Missing/mismatched profiles must remain unevaluated. Strip third-party ICC bytes from new shared exports; maintain a local legacy reader and backups. Do not claim an Adobe-specific licence prohibition without inspecting that profile's applicable terms.
5. Move density into a separate simulation workspace, still reachable from Proofing and excluded from proof results/reports. A real density operating range requires a measured series.
6. Move visual monitor setup under Colour Management settings, retaining a Proofing shortcut and machine-local, explicitly unmeasured records.

## Completed in this review pass

- Shared app-bundle Fogra loader; SwiftPM resource accessor removed. Direct Xcode resource declaration added. Bare-binary tests use an explicit fixture directory; packaged tests require actual bundle resources.
- Known bundled FOGRA39 enriched with D50/2° and M0 provenance; original resource bytes unchanged. FOGRA51/52 remain M1.
- Alias priority chooses explicit IDs before display names regardless of CSV header order.
- Typed proof states; Inspect no longer writes to Library; embedded ICC registered once per evaluation; patch rail and register reuse visible controls.
- Regression coverage for all three Fogra files, M0/M1 mismatch, repeated CSV display names and bounded row controls.
- Corrected ASE archive relative paths when Foundation enumerates `/var` through `/private/var`; retained exact registry paths.

The engine replacement and catalogue/configuration migration remain planned, not implemented by this pass.

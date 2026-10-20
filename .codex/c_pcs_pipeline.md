# PCS conversion pipeline

Decision: Rick selected Apple ColorSync on 17 October 2026. This supersedes the earlier LittleCMS replacement recommendation in [engine research](c_colour_engine_pivot.md). No Adobe CMM or new third-party engine is bundled.

## Contract

`ColourEngine.swift` owns `PCSConversion`, the shared ICC boundary. The persisted master remains Double XYZ D50 with Y=1; exact source values remain separate. The adapter uses Apple's Generic XYZ ICC profile, device-to-PCS / PCS-to-device sequences, best quality, and Float32 buffers. CMYK/RGB/grey components use 0…1; percentages are presentation only. Conversion rejects nonfinite/malformed input and unavailable profiles. Device outputs are clipped to their encoded range; the master is never overwritten.

- `PrintBuild`, `ICCRGBRendering`, `MonochromePrint` and `ProofEngine` use this adapter.
- ColorSync owns rendering intents, media-white handling and black-point compensation. No manual black lift or paper-white multiplication surrounds the transform.
- BPC is enabled only for relative colorimetric separation. **Validation issue:** standalone tests on macOS 26.3.1 (a) reproduce substantial neutral casts with BPC on. See [investigation and reproduction](c_c_pcs_bpc_investigation.md). Do not dismiss these casts as normal profile variation, claim BPC is validated, or apply hand-tuned corrections.
- Read generated recipes back colorimetrically: relative after relative/perceptual separation, absolute for absolute evaluation. Disable BPC on readback. A perceptual inverse can conceal the actual separation error.
- Fixed CMYK recipes retain their inks. Their appearance is evaluated for the selected condition; an unavailable profile cannot pass just because the source name matches.
- Built-in RGB/video/HDR mathematical encodings remain separate. This work does not convert HDR into bounded ICC values, change the master format, introduce spectral-to-observer approximations, or replace per-display native colour management.

## Identity and caching

The bounded transform cache is keyed by the source/destination ICC SHA-256, intent and effective BPC. Prepared profiles retain their CGColorSpace identity. A recursive lock serialises transform creation/use. Installed profile file identity is checked before cached-space reuse, and bytes are reloaded on profile-list refresh. Imported ICC identity checks remain in `ICCProfileLibrary`.

Predicted proof results capture engine, macOS version/build, pipeline version, PCS convention and target ICC digest at evaluation. CSV exports use this captured provenance, not whichever file happens to exist at export. New proof configurations capture conversion provenance; old files decode with unknown provenance. Measurement comparisons do not claim an ICC conversion engine.

## Verification

Self-tests cover D50 sRGB white and red primary against independent values, matrix/ICC agreement, channel scaling, invalid inputs, missing profiles, absolute paper-white readback, BPC shadow ordering, colorimetric readback of perceptual separations, retained recipes and cache resets. BPC shadow ordering does not establish neutral preservation; the investigation above identifies the missing regression coverage. Existing ΔE reference tests remain authoritative. Build and inspect the installed app when authorised; an explicit no-build request takes precedence.

Public API references: [ColorSync transforms](https://developer.apple.com/documentation/colorsync/color-transforms), [transform creation](https://developer.apple.com/documentation/colorsync/colorsynctransformcreate(_:_:)), [Apple BPC sample](https://developer.apple.com/library/archive/samplecode/convertImage/Listings/convertImage_main_c.html). Local SDK headers specify buffer and profile-sequence contracts.

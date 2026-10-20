# ColorSync BPC investigation, 17 October 2026

Status: reproducible unexpected neutral cast in standalone ColorSync transforms on this Mac. No validated fix. App conversion code, installed application and running session were not changed during this investigation. No app build, install or relaunch was performed.

## Environment and scope

- macOS 26.3.1 (a), build 25D771280a, arm64.
- Relative colorimetric, Float32, best quality; BPC off for CMYK-to-XYZ readback.
- Both Apple's Generic XYZ input and built-in sRGB input reproduce the cast.
- FOGRA39, Apple Generic CMYK and Japan Color 2001 Coated reproduce it.
- Not yet reproduced on another macOS release or another machine. This is not evidence that all ColorSync conversions or all Apple colour management are defective.

FOGRA39 SHA-256: `da2b9b593e27cba2563cbc8596071c5c8f2395d3dbb4434538bac2bc9d58ce77`.

## Evidence

Neutral sRGB (0.5, 0.5, 0.5), with predicted Lab calculated from returned D50 XYZ:

| Target | BPC off L*, a*, b* | BPC on L*, a*, b* |
| --- | --- | --- |
| Coated FOGRA39 | 53.15, −0.19, −0.40 | 54.16, +3.59, −8.21 |
| Generic CMYK | 53.28, −0.54, −0.61 | 53.60, +3.01, −8.91 |
| Japan Color 2001 Coated | 53.25, +0.12, −0.24 | 54.67, +3.71, −8.29 |

For FOGRA39, BPC produces CMYK `(0.524926, 0.449424, 0.300191, 0.129839)`. Independently reading these inks through LittleCMS 2.19 yields Lab approximately `(54.12, +4, −8)`. The cast is in the generated ink recipe, not just our display conversion or ΔE maths.

LittleCMS 2.19's own relative+BPC conversion of middle grey (128/255) through the same profile yields Lab approximately `(54.90, 0, 0)`. Its no-BPC result is `(53.73, +1, 0)`. This reference used Pillow's 8-bit RGB/CMYK/Lab buffers, so it confirms the large chroma discrepancy, not exact floating-point agreement or engine superiority. Some lightness change from BPC is expected.

## Isolation checks

- Read-only `ColorSyncProfileVerify` returned true with no errors or warnings for all five profiles used: Generic XYZ, sRGB, Coated FOGRA39, Generic CMYK and Japan Color 2001 Coated. This checks structural usability/conformance, not colour accuracy. No repair or profile modification was performed.
- Best versus normal conversion quality did not resolve it.
- Extended range absent, false or true on profile sequences did not resolve it; the app adapter probe also reproduces it with extended-range conversion options.
- Direct `ColorSyncTransformConvert` and Apple's `vImageConverter_CreateWithColorSyncCodeFragment` path, using full conversion data, produce the same cast.
- Source-only BPC reproduces the cast; destination-only BPC has no effect in this two-profile sequence. Moving the flag is not a validated fix.
- A separate normalized Lab-input probe also reproduced a chroma shift.
- The extracted FOGRA39 BPC component is `[0, 0.1066192]`, the two-value luminance form documented in the SDK.
- D50 neutral XYZ at Y=0.5 becomes approximately `(0.49669, 0.49727, 0.49999)` after BPC and ink readback. These near-equal XYZ coordinates are not D50 neutral. This is a clue about white-point handling, not proof of an internal Apple implementation fault.

The profile sequence follows [Apple's published BPC conversion sample](https://developer.apple.com/library/archive/samplecode/convertImage/Listings/convertImage_main_c.html). The remaining uncertainty is whether an undocumented API requirement or an OS implementation issue explains the generated sequence. Do not claim the exact internal cause yet.

## Reproduction

Run from the repository root; neither script builds or launches Colorgain:

```sh
swift tools/diagnose_colorsync_bpc.swift '/Library/Application Support/Adobe/Color/Profiles/Recommended/CoatedFOGRA39.icc'
python3 tools/diagnose_bpc_reference.py '/Library/Application Support/Adobe/Color/Profiles/Recommended/CoatedFOGRA39.icc'
```

The Swift script accepts multiple installed CMYK paths, prints OS/profile digests and both XYZ/sRGB neutral ramps. The Python reference needs Pillow, used from the existing Codex workspace runtime during this investigation. It is not a new app dependency. No ICC files are bundled or installed by either script.

## Next implementation gate

1. Reproduce the standalone case on a second macOS release and retain profile hashes. Prepare an Apple report with the minimal script and expected neutral behaviour.
2. Validate any corrected ColorSync API usage against neutral ramps, saturated patches, black/white endpoints and an independent engine. Do not patch the observed cast with hand-tuned matrices or replace the full pipeline on this evidence alone.
3. If BPC remains unreliable, expose an explicit unavailable state for the affected path or implement a separately validated backend. Do not silently ignore a saved BPC selection or substitute perceptual intent.
4. Add neutral-chroma regression coverage before claiming BPC support. Existing finite-value and shadow-ordering self-tests passed this failure and are insufficient. Include provenance and invalidate cached results if conversion behaviour changes.

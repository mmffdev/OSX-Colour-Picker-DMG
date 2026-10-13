# Offline QR colour exchange

`ColourQR.swift` owns a name and ordered XYZ masters. D50, 2° and relative Y=1 are explicit in files and fixed by the QR transport version. `.colqr` stores minimal name/XYZ JSON with explicit colour conventions; the QR carries only one name and ordered XYZ binary64 triples, compressed with zlib and checked with a 128-bit SHA-256 digest. The transport version fixes D50, 2° and relative Y=1. Original RGB/CMYK components, profile references, individual palette colour names and proof data are excluded at Rick’s request. Legacy full-record codes remain readable in `colorgain://qr/1/…`.

No colour is reconstructed from the photographed preview. Minimal QR import creates fresh XYZ source records preserving exact master values, then adds the shared name and colour order to a new Library palette or the selected existing picker target, in one controller transaction. Normal catalogue persistence and exchange carry these records. Unknown source CMYK profiles are not invented.

QR generation uses Core Image, H correction, four-module clear margins and crisp integer module scaling. The centre colour-wheel logo is allowed only when Vision successfully decodes the final branded image. Failure retries without branding; large payloads offer the complete colour file. No automatic hosting or network request occurs.

`SharingUI.swift` owns generation, review, file/image/clipboard import and the camera scanner. Camera opt-in is machine-local and separate from macOS authorization. It is exposed in Sharing settings, Import and the optional initial permissions panel. AVFoundation capture runs only in the scanner; Vision runs serially at most five times per second. Frames are discarded rather than queued, are never saved, and capture stops on closure or successful detection. Store entitlement: `com.apple.security.device.camera`.

`TileHoverHalo.swift` supplies fixed View / Print / QR / Copy actions over page colour blocks, sharing Halo ring-one colours. Palette blocks have Open Swatches as a fifth action. Metadata retains existing navigation. Print comparison is an on-demand preview under `PrintCondition.current`, with actual colour above predicted colour and ΔE00 below; it is not a measured proof.

Regression entry point: `runColourQRTests` in the existing self-test. Verify the installed app visually and preserve existing camera preferences and catalogue data during testing.

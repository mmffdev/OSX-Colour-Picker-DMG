# ICC.1:2022 architecture review for Colorgain

Reviewed `assets/ICC/ICC.1-2022-05.pdf` visually at PDF pages 7 and 12 and against the relevant text, plus `COLOUR-MANAGEMENT.md` and `ColourEngine.swift`. This is an interpretation for Colorgain, not an ICC conformance assessment.

## The diagram's useful message

Figure 1 (PDF p. 7; printed page vii) shows device encodings connected through a shared reference colour space. Its practical scaling point is strong: each device mode needs a transform to/from the common interface, rather than a bespoke transform for every device pair. ICC's PCS is that interoperability bridge. It is not a universal model of physical stimulus or appearance: section 0.3 (PDF pp. 5–6; printed pp. v–vi) fixes the PCS around D50, the CIE 1931 2° observer and specified measurement conventions, and explains that viewing conditions and reference medium matter particularly for perceptual rendering.

Figure 4 (PDF p. 12; printed page xii) is a conceptual host architecture: an application and graphics/imaging libraries call a colour-management framework, which can route work to a default CMM or third-party CMMs, using profiles. It is not a mandate that every ICC application implement a plug-in CMM system. ICC.1 specifies profile format and the architecture in which it can operate; it does not require Colorgain to host multiple engines. The profile header's “preferred CMM type” is optional (section 7.2.3, PDF p. 34), and profiles still provide required tags for standard processing (section 0.6, PDF p. 12). The framework/CMM seam is a useful software boundary and future flexibility, not a v4 prerequisite.

The standard also defines more than ordinary device profiles. DeviceLink profiles encode a direct device-to-device transform (section 0.8, PDF p. 12 and following text). Supporting ICC profiles in general does not imply support for every profile class, tag, rendering path or version; feature availability needs to be tested per engine and profile.

## Verified current support

- `ColourEngine.swift` represents the master as floating-point XYZ adapted to D50, and uses explicit RGB matrices/Bradford adaptation for its enumerated RGB spaces. That is a coherent internal reference for the currently supported conversions and is aligned with the ICC PCS white convention. It does not by itself make every `XYZ` value a complete ICC PCS record: ICC PCS encoding, observer, media-relative/absolute semantics and profile transforms still matter.
- Press conversions use macOS ColorSync via Core Graphics ICC colour spaces. The app discovers installed press/output profiles through ColorSync and returns unavailable when a named profile cannot be resolved. This is real system CMM execution for these paths, not an in-app ICC parser or a Colorgain-pluggable CMM architecture.
- For print, `PrintBuild.of` applies the app's current absolute-white and black-point adjustments around a ColorSync conversion. Current app behavior should therefore be described as “ColorSync-backed profile conversion with app-side handling for these options,” not as proof that all profile intents/options are delegated to ColorSync or that its output is an independent press measurement.
- `COLOUR-MANAGEMENT.md` identifies important gaps accurately: ink-limit warnings, approved/pinned values, broad delivery, HDR/LUT, 3D/OCIO and physical measurement/spectral workflows are not complete. A standard PCS transform cannot fill those product and evidence gaps by itself.

## Useful architecture direction

Keep the existing XYZ D50 master and make the transform boundary explicit. A small internal transform service can take source/target profile identity, profile class, requested intent/options and engine identity, then return encoded values plus the reverse-rendered result and a structured unavailable/unsupported reason. ColorSync can remain the implemented provider. This makes engine provenance and later independent comparisons possible without claiming that ICC v4 demands replacement or plug-in CMMs.

Separate four questions in the product and diagnostics:

1. **Profile availability/structure:** can this exact profile be found and read, and what class/colour spaces/tags does it expose?
2. **Transform capability:** can the selected engine perform this source, destination, intent and option combination?
3. **Predicted rendering:** what does the selected transform predict, under its declared assumptions?
4. **Measured/approved evidence:** has the real device or output been independently measured and accepted?

This separation supports a focused Profile Doctor and honest proofing. A profile being installed or transformable does not establish that the device is currently calibrated, that a press meets a condition, or that the output matches the master. Record profile digest, transform intent and options, OS/engine version and evaluation time with reproducible results; do not label a round trip as validation of physical accuracy.

Prioritise coverage of profile classes and transforms the app actually promises: common RGB and CMYK device profiles, each intent the UI offers, missing profiles, malformed profiles, unsupported tags/classes, and source-preserving import/export. Add DeviceLink, multichannel and iccMAX only against named workflows and independent fixtures. Spectral relighting/metamerism requires retained spectral samples plus observer/illuminant and measurement metadata; ICC.1's fixed PCS cannot derive those samples from XYZ or CMYK values.

## Proposed changes (not current support)

- Add an engine/provider boundary around transform execution and capture provenance. This is a maintainability and reproducibility proposal; the current implementation is ColorSync-backed.
- Add explicit profile capability diagnostics and fixtures for intents, profile classes, malformed/unsupported content and round trips. Do not equate structural parsing with transform support.
- Add output-condition comparison and delivery preflight only after transform semantics, profile identity, intent/BPC behavior and serialization are independently verified.
- Preserve the measurement distinction in the UI: predicted profile rendering, measured verification and human approval are separate states.

## Limits of this review

This review examines selected architecture sections and figures of ICC.1:2022, not every normative clause, amendment, system ColorSync behavior, or app conversion path. It does not establish ICC conformance, numerical accuracy, profile security, spectral capability, or a requirement for any particular third-party CMM.

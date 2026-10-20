# Colorgain: ICC review for discussion

Reviewed 16 October 2026. Starting point: [ICC getting started](https://www.color.org/getting-started/). Three GPT-6 Astra agents independently reviewed standards/engine, workflows/settings, and implementation/data contracts; the coordinating agent checked key findings and reconciled recommendations.

**Recommendation:** strengthen the evidence behind our colour results before expanding the number of formats and controls. The strongest near-term opportunities are measurement-condition checks, trustworthy intent/BPC handling, profile identity throughout the workflow, and delivery preflight. Spectral tools and selective iccMAX support are valuable next steps.

This is a research and discussion document, not an approved implementation plan or Vector backlog. Evidence describes the current working tree on `colorgain-main`, based on commit `06e4b29`, including existing uncommitted changes. Static inspection was used; no app build, instrument measurement, numerical engine comparison or certification was performed. Code line numbers are snapshot references.

## Prioritised action list

Discussion order added 16 October 2026. These are proposed work items, not implementation approval. The numbering below follows the discussion list; items 4 and 5 correspond to findings F5 and F4 respectively.

1. **Fix proof checks** — prevent a Passed result when measurement modes, backing or viewing conditions conflict.
2. **Correct observer options** — clearly label estimates; changing 2° to 10° needs more than white-point adaptation.
3. **Validate rendering intents and BPC** — make settings behave consistently across RGB, CMYK and greyscale.
4. **Preserve colour during import/export** — retain wide-gamut values and respect the colour space declared in imported tokens.
5. **Use exact ICC identities everywhere** — prevent different profiles with identical names being treated as interchangeable.
6. **Build an ICC Profile Doctor** — inspect profiles, supported transforms, missing information and compatibility.
7. **Add output comparison** — compare a palette across presses, papers and profiles, showing colour shifts and ink totals.
8. **Build delivery preflight and packs** — export the correct values, profiles, precision and conversion details for each recipient.
9. **Save approval evidence** — retain measurements, conditions, tolerances, approver and the exact result approved.
10. **Expand display readiness** — record the active display profile, intended workflow and measured verification separately from visual checks.
11. **Improve HDR settings** — save reference white, peak luminance, signal range and metadata with each delivery preset.
12. **Build spectral and metamerism tools** — compare measured materials under different lights and observers.
13. **Evaluate specialist ICC support** — selectively add iccMAX, DeviceLink and multichannel printing.

Recommended sequence: 1–5 establish the foundation, then Profile Doctor and output comparison become the next visible tools.

### Where the first five would go

These placements are proposals using existing app surfaces.

| Item | Behaviour | App placement |
| --- | --- | --- |
| 1. Proof checks | Compare reference and reading conditions before calculating a verdict; show incompatibility or missing declarations and preserve imported precision | PrePress → Verify A Proof and Check A Colour; carry the same status into labels and reports |
| 2. Observer options | Identify white-adaptation estimates clearly; prevent unsupported 10° results being presented as true observer conversions | Lab's existing illuminant/observer selector and numeric readouts; retain original conditions beside imported measurements in PrePress |
| 3. Intent/BPC | Apply one tested conversion policy; explain or disable unsupported combinations; refresh all results from the same transform | Existing profile editor opened from Colour Target and Histogram/Delta Bloom controls; existing PrePress print controls; shared conversion engine underneath |
| 4. Colour-preserving exchange | Interpret declared source spaces, retain full values, and make export conversion/limitations explicit | Existing palette import/export and design-pack flows; native palette files retain complete colour records; keep Appbridge's existing byte-preservation behaviour |
| 5. Exact ICC identity | Resolve the exact profile bytes, distinguish same-name profiles and recover missing/changed dependencies without substitution | Existing ICC Profiles panel and Locate action, Colour Target, saved profiles and proof/report dependencies; digest remains an inspectable detail |

## Item 1 implementation — 17 October 2026

Implemented only the proof-condition checks. Items 2–5 remain unchanged.

- Verify A Proof and Check A Colour share condition comparison logic. Explicit illuminant, observer, measurement-mode and backing conflicts block evaluation/approval. Contradictory condition declarations are rejected.
- The active proof page requires the four conditions above. Missing declarations show Needs Confirmation and list the exact assumptions. Confirmation supplies missing facts only; it cannot override declared conflicts, and resets when the measurement or selected comparison conditions change.
- Raw imported Lab precision, original metadata and file hashes remain intact. Single-colour imports require exactly one patch. A failed replacement import clears the previous result.
- Reports and labels carry the validation status and confirmed assumptions; incompatible proofs have no calculated differences in their exports. Existing numerical tolerances and colour-conversion maths were not changed.
- Native QA uses an isolated catalogue and locally generated comparison files at `/tmp/colorgain-proof-demo`. These are controlled fixtures derived from the bundled reference, not new instrument measurements. The files demonstrate a matching M1 condition, wrong M0, wrong backing, undeclared conditions and a D65/10° single reading.

The installed direct-download app passed 1,114 checks with zero failures (the bare-binary build check passed 1,104; bundled-helper checks account for the additional coverage). The signed app was installed as `/Applications/MMFFDev Colour 3.app`, build `06e4b29+`. An isolated native-source snapshot was used for installation because concurrent unrelated edits interrupted the original build. Coverage includes compatible complete data, explicit conflicts despite confirmation, missing declarations, metadata aliases, missing/duplicate patches and excessive numerical drift. Native verification covers passing, blocking, confirmation, full-precision single readings and exported evidence. This validates item 1's condition handling; it does not certify the complete workflow against ISO 12647-7.

## 1. What we already have

The 3 October status in `COLOUR-MANAGEMENT.md` is historical. Several features it calls absent now exist. Keep its product direction, but do not use its old feature table as today's inventory.

| Area | Current evidence | What remains |
| --- | --- | --- |
| Master colour | `ColourEngine.swift:15–76`: floating-point XYZ D50, original source and surface/light kind | More complete measurement and luminance provenance |
| ICC library | `ICCProfileLibrary.swift:5–71`: SHA-256 identity, file references, bounded parsing, class/version and copyright metadata; `:96–120`: bounded folder traversal and exact-byte relocation | Full profile diagnostics and consistent use of that identity outside the library |
| Installed profiles | `ColourEngine.swift:520–533`: ColorSync discovery | Older press selections still use names |
| Real ICC conversion | `ColourEngine.swift:624–648`, `ICCProfileLibrary.swift:165–189`: CMYK and linked RGB targets use actual profile transforms | Unify intent/BPC semantics and validate predictions independently |
| HDR and VFX | `ColourTargetSpaces.swift:4–31`: PQ, HLG, ACES2065-1, ACEScct, linear targets and declared reference contexts | Saved/exported luminance context and metadata interoperability |
| Measured proofing | `Proofing.swift:1–108,175–200`, `PrePress.swift:379–395,718–739`: CGATS/CSV, patch matching, condition checks in the shared engine, reports | Active page does not consistently use those checks; compliance claims need an audit |
| Monitor setup | `StudioMonitorSetup.swift:10–56`: visual checks, local records and explicit unmeasured status | Purpose-specific readiness and measured verification records |
| Approvals | `PrePress.swift:762–780`: approve/reject text is copied | Persistent approval evidence linked to colour, condition and measurement |

## 2. Findings to address first

### F1 — A proof can reach Passed without matching measurement conditions

**High confidence, static control-flow finding.** `PrePress.swift:710–716` rejects explicitly different illuminants/observers but permits absent declarations. `:379–388` computes the verdict from patch checks without calling `ProofEngine.conditionsIssue`. The shared engine already checks mode/backing mismatches and asks for D50/2° confirmation when declarations are absent (`Proofing.swift:175–188`). That protection is not consistently used by the active Verify A Proof page.

The single-reading import also takes the first Lab patch without equivalent viewing-condition checks and rounds it to two decimal places (`PrePress.swift:750–757`).

**Proposed change:** one shared evaluation gate for every measured workflow. Preserve raw precision and provenance; distinguish declared conditions, user-confirmed assumptions, incompatible data and missing information. Do not issue a definitive pass when required conditions are unresolved. See [ICC measurement guidance](https://color.org/whitepapers/ICC_White_Paper3_Measurement_v2.pdf).

**Acceptance evidence:** identical patch values with M0/M1 mismatch, conflicting backing or undeclared conditions cannot silently produce the same qualified pass as compatible measurements. Existing valid files still work after explicit confirmation where appropriate.

### F2 — An observer choice currently overstates what white adaptation can do

**High confidence, implementation/meaning mismatch.** `ColourEngine.swift:278–328` offers 2° and 10° whites, but `XYZ.adapted(to:)` applies Bradford using white chromaticities only. `StudioLab.swift:156–166,328` uses this path for the displayed illuminant/observer values.

Changing the white in a chromatic adaptation model does not reconstruct a material's response under a different observer. [ICC WP55](https://archive.color.org/files/whitepapers/ICC_White_Paper_55_Profiling_with_D65_%2B_10deg.pdf) distinguishes chromatic adaptation from material adjustment and explains why conversions between colorimetric conditions can only be estimates without the underlying information.

**Proposed change:** label the current result as an adaptation estimate and constrain unsupported observer claims. Later calculate measured material colour from retained spectra using the selected illuminant and observer. An explicitly documented material-adjustment estimate may be offered for a defined workflow; it must not look like a fresh spectral measurement.

**Acceptance evidence:** switching 2°/10° never presents a white-only transform as a measured observer conversion; a future spectral implementation is checked against independent reference data.

### F3 — Intent labels, paper simulation and BPC need one validated contract

**Confirmed routing differences; numerical impact remains to be measured.** `RenderingIntent.system` maps absolute to relative (`ColourEngine.swift:481`). Print applies its own paper-white treatment and black lift (`:624–639`). BPC is applied whenever intent is not perceptual, including absolute. Linked RGB rendering uses the same system mapping without the print-specific correction (`ICCProfileLibrary.swift:168–185`). It can therefore describe an absolute intent while routing through a relative transform. The profile editor exposes this combination: `WorkspaceAnalysis.swift:31,42–46,62–79,101` includes linked RGB targets, copies the selected intent and presents the intent control.

[ICC WP40](https://archive.color.org/files/WP40-Black_Point_Compensation_2010-07-27.pdf) describes BPC and generally excludes it from absolute proofing. The [ICC white-paper index](https://www.color.org/whitepapers/) notes that ISO 18619 supersedes WP40. This review does not claim ISO 18619 compliance or a quantified error in today's predictions.

**Proposed change:** route every ICC target through a single adapter with explicit supported intent/BPC combinations. Disable or explain unsupported combinations. Compare paper white, dark colours, neutrals, saturated colours and round trips against a pinned reference engine and known profiles.

The existing [engine-pivot review](.Codex/c_colour_engine_pivot.md) already recommends evaluating LittleCMS core. This research supports completing that evaluation; it does not justify automatically replacing it with iccDEV. Also correct the help text promising the “nearest edge”: ICC colorimetric out-of-gamut handling is not a universal nearest-colour solver. [ICC introduction](https://www.color.org/getting-started/).

### F4 — Profile identity is strong in the new library but weaker in older paths

**High confidence.** The linked library identifies exact bytes. Installed press discovery deduplicates by localized name and old lookups resolve that name (`ColourEngine.swift:508–515,590–597`). `ColourSource.press` is a string (`:35–36`); a name alone does not identify the bytes used to create a master or approval.

**Proposed change:** reuse one profile reference containing digest, display name and recoverable location throughout source records, presets, saved proof sessions and reports. Migrate legacy names explicitly; ambiguous or missing matches remain unresolved. Keep intended output profiles separate from the actual display profile used to view them.

**Acceptance evidence:** two different ICCs with the same name remain distinct; replacing a file does not silently recalculate old evidence; old approvals keep the original result and engine/profile identities.

### F5 — Imports and delivery still lose colour meaning in some paths

**Concrete examples:** `Importers.swift:59–66` reads token components as RGB hex without using their declared `colorSpace`. A Display P3 or Lab token can consequently acquire the wrong interpretation. `Exporters.swift:548,553` builds ordinary export palettes using `displayHex`; CSS/tokens and the ASE/ACO writers consequently work from that projection. A higher-bit container cannot restore precision already reduced to hex.

Native palette documents already have a richer preservation path (`Importers.swift:47–50,209–214`). Appbridge also retains ASE source components and existing file bytes (`Appbridge.swift:19–33,105–113`). Preserve these distinctions: not every import/export path loses the master.

**Proposed change:** preserve supported source encodings and exact values, explicitly reject or explain unsupported ones, and show any deliberate conversion. Delivery needs a manifest naming target, profile digest, intent, BPC, depth/range and engine version. Embedding/referencing profiles is format-specific; follow the [ICC embedding technical note](https://archive.color.org/files/technotes/ICC-Technote-ProfileEmbedding.pdf) and verify each target format before claiming interoperability.

**Acceptance evidence:** a wide-gamut source survives import → native save → reopen; exports are checked in an independent consumer, including missing-profile and unsupported-space cases.

## 3. Tools worth building

These are product proposals inferred from the research, not ICC requirements.

| Tool | What the user gets | Suggested order |
| --- | --- | --- |
| Measurement preflight | Conditions, missing patches, duplicate IDs, instrument metadata and compatibility before a verdict | First: fixes F1 and can reuse the existing importer |
| ICC Profile Doctor | Existing library plus required tags, transform availability by intent, malformed-data diagnostics and a downloadable diagnostic report | First/next: keep structural validity, transform support and measured accuracy separate |
| Compare Output Conditions | Same palette through two exact profiles; predicted ΔE, ink totals, paper/black simulation and explicit intent/BPC | Next: after F3 is validated |
| Delivery Preflight And Pack | What can be faithfully exported, explicit losses, profile requirements, values and a reproducible manifest | Next: source preservation first |
| Display Readiness | Selected display, active ICC, purpose, last measured verification and current limitations | Next: extend the honest visual setup already present |
| Approval Evidence | Persistent measured/predicted status, raw reading, condition, tolerance, approver and immutable result snapshot | Next: beyond the current copied note |
| Spectral And Metamerism Lab | Retained measured spectra, colour under different lights/observers, pair comparisons and uncertainty | Later: substantial new data contract and numerical validation |
| Transform Bench | Internal reference comparisons, round trips, performance and regression corpus | Start internally alongside F3; expose diagnostics later |
| DeviceLink / Multichannel Inspector | Inspect specialised profiles and explain unsupported paths before any conversion support | Later: scoped enterprise demand and fixtures |

A sampled gamut plot is useful, but name its sampling assumptions. A triangle or sparse shell is not proof that every interior colour is printable, and round-trip ΔE alone is not an independent measurement of accuracy.

The spectral tool needs a new record, not just another illuminant dropdown: sample wavelengths/range/interval, units, reflectance versus emission, instrument, measurement conditions, raw readings and derivation. Add repeat-reading averages and drift checks before promising uncertainty estimates. `ColourDefinition` and `ProofPatch` currently lack that complete spectral contract. See [ICC spectral-estimation resources](https://www.color.org/resources/spectral/spectral_estimation/).

## 4. Settings changes for discussion

| Setting area | Proposed contract | Where it belongs |
| --- | --- | --- |
| Workflow preset | Purpose, target, supported intent/BPC, tolerance metric and value; expose assumptions | House default → project → palette, with explicit override |
| Profile identity | Exact profile reference; missing/changed/unsupported state; no silent substitute | Portable preset reference; local access grant separately |
| Measurement conditions | Illuminant, observer, M condition, geometry, backing, instrument and declaration/assumption status | Measurement/approval record; defaults must not overwrite imported facts |
| Viewing environment | Purpose, surround, intended illumination/luminance and evidence source | Named setup; actual display association stays local |
| HDR context | Reference white, peak/display assumptions, transfer, signal range and metadata provenance | Target/delivery preset; measured display capability separate |
| Output delivery | Format, encoding, depth, profile embedding/reference policy and explicit conversion losses | Export preset, not the master colour |
| Ink policy | Declared condition/TAC and warning policy, including unknown limit | Print condition; do not imply a slider changes the ICC separation |
| Diagnostics | Engine/version, profile digest, supported transforms and evaluation state | Inspectable details and reports |
| Approval | Separate predicted match, measured match and human approval | Saved evidence; never infer approval from a green ΔE |

Resolve an existing default-policy disagreement explicitly: `COLOUR-MANAGEMENT.md:7.2` recommends relative+BPC, while `PrintProfileSettings` and nil channel BPC currently default off (`PrintProfiles.swift:7–10`, `ColourEngine.swift:659–660`). Choose tested workflow defaults; do not silently reinterpret saved presets.

Do not adopt a universal D50/500-lux or D65/sRGB setup for every task. The starting article's reference print environment is not a blanket monitor-calibration instruction. Preserve the current visual setup's unmeasured wording; add purpose-specific guidance with [ICC display-calibration guidance](https://www.color.org/displaycalibration/) as supporting material.

## 5. ICC resources we can use

| Resource | Practical adoption | Limit or condition |
| --- | --- | --- |
| [iccDEV](https://github.com/InternationalColorConsortium/iccDEV) | Evaluate profile inspection, validation, round-trip and iccMAX reference tools; build an independent fixture workflow | Pin a revision, inspect licence/build dependencies and test outputs; not a certification stamp |
| [ICC profile security](https://www.color.org/profilesecurity/) | Add malformed-profile regression fixtures and extend bounds/semantic validation | The listed scanner is member-access; do not assume it is an embeddable public dependency |
| [Profile viewing/testing](https://www.color.org/profileview/) | Discover independent assessment methods and reference checks | Viewing a profile is different from verifying the device it characterises |
| [CMYK characterisation registry](https://registry.color.org/cmyk-registry/) | Broaden reference-condition discovery beyond our Fogra subset; retain dataset identity | A dataset is not a unique separation profile; multiple profiles can use different black generation |
| [Three-component encoding registry](https://registry.color.org/rgb-registry/) | Audit built-in matrices/curves and encode image state, reference medium and viewing context | Encoding definitions include more than primaries and white; dated entries require checking their governing standard |
| [Colorimetry data](https://registry.color.org/colorimetry-data/) | Evaluate published observer/illuminant data and weighting tables for spectral calculations | Pin datasets/method/range/interval and review reuse terms; do not improvise interpolation or fluorescence handling |
| [Metadata registry](https://registry.color.org/dicttype-metadata/) | Read useful HDR context and present provenance | Descriptive metadata must not automatically override a transform |
| [Profile registry](https://registry.color.org/profile-registry/) | Official discovery, publisher links and intended-use metadata | Download availability does not imply permission to bundle/resell |

For a concrete iccDEV evaluation, assess `iccDumpProfile`, `iccRoundTrip`, `iccApplyProfiles` and `iccApplyToLink` against the [official CLI reference](https://github.com/InternationalColorConsortium/iccDEV/blob/master/docs/tools-cli-reference.md). These are candidates for our internal harness; they have not been installed or tested here. Review the [licence](https://github.com/InternationalColorConsortium/iccDEV/blob/master/LICENSE.md) and pin a reviewed commit rather than relying on mutable `master` or a CI “latest” build.

The [ICC malformed-profile corpus](https://www.color.org/security/malformedprofiles/) has a no-redistribution restriction. Acquire permitted fixtures locally or create our own redistributable cases; do not ship that downloaded corpus in the app or repository. This is separate from the member-only scanner.

One particularly current addition: the registry lists optional HDR display metadata registered on 2 October 2026. [DCV](https://registry.color.org/dicttype-metadata/dcv) describes display colour volume, [DRWL](https://registry.color.org/dicttype-metadata/drwl) reference white luminance, and [DERH](https://registry.color.org/dicttype-metadata/derh) headroom. These are worth inspecting for Display Readiness; do not present their presence as measured verification.

## 6. What to adopt selectively

**ICC v4 remains the interoperability baseline.** The [v4 specification page](https://www.color.org/v4spec/) identifies ICC.1:2022, profile version 4.4, and lists later amendments. Its Adaptive Gain Curve note explicitly anticipates further changes. Read the applicable specification and amendments together before implementing HDR tags.

**iccMAX is a targeted extension.** Evaluate a bounded use case such as spectral material comparison or multichannel output, with a named interoperability subset and real recipient software. Do not promise arbitrary iccMAX execution from accepting a version-5 file. The current library intentionally keeps later versions inspect-only. Use [iccMAX specifications](https://www.color.org/iccmax/) and the [ICC white-paper catalogue](https://www.color.org/whitepapers/) to select the relevant conformance subset.

**Retain extended values.** The [negative PCSXYZ technical note](https://archive.color.org/files/technotes/Guidelines_on_the_use_of_negative_PCSXYZ_values.pdf) explains why adaptation can produce negative components. Validate the internal master, ICC bridge and export boundaries separately; clipping rules for a particular file encoding must not silently clip the master.

**Add saturation intent only for a supported purpose.** It may be useful for graphics and charts, but should not become the default for brand matching. Intent availability should reflect real transform support.

**Check individual distribution terms.** For example, the [PSOuncoated v3 FOGRA52 registry entry](https://registry.color.org/profile-registry/PSOuncoated_v3_FOGRA52) distinguishes permitted use/embedding/exchange from restricted distribution or alteration. Retain publisher links and exact references; assess actual terms before bundling. This is not a blanket prohibition on ICC profiles.

## 7. Evidence and delivery order

1. **Make results trustworthy:** shared measurement gates; observer labels; supported intent/BPC combinations; audit proof-report standards wording. `PrePress.swift:721` currently names ISO 12647-7:2016 and says all differences are CIEDE2000, although separate hue/chroma quantities are calculated (`:97–102`). Clause coverage, equations, required conditions and current edition must be checked against the full standard before treating the report as a conformance statement. This review did not perform that audit.
2. **Make results reproducible:** unified profile identity, engine provenance, source-preserving imports and immutable approval evidence. Keep existing files recoverable during migrations.
3. **Make the product more useful:** Profile Doctor, output comparison, Display Readiness and Delivery Preflight, built on the same evaluated results.
4. **Expand into physical/specialised workflows:** spectra and metamerism, then selective iccMAX/DeviceLink/multichannel support after fixtures and recipient compatibility are proven.

For implementation, validate both shipping targets and their file-access rules. This report adds no dependencies and changes no application behaviour.

## 8. Decisions for Rick

- Should the first implementation pass focus on the four trust issues F1–F4, before adding visible tools?
- Which tool is the strongest product differentiator next: Profile Doctor, Delivery Preflight, or Spectral And Metamerism Lab?
- Which real press, display, instrument and receiving application can supply our first end-to-end validation workflow?
- Should saved approvals be immutable evidence snapshots, with a separate “re-evaluate with current engine” action? Recommendation: yes.
- Should the planned LittleCMS adapter remain the primary engine direction, with iccDEV used first for diagnostics/reference comparisons? Recommendation: evaluate that combination before choosing a replacement.

## 9. Coverage and limits

Reviewed the starting article and relevant linked branches: ICC v4/iccMAX specifications, technical notes, white papers, profile tools/security/testing, display calibration, characterisation/encoding/colorimetry/profile/metadata registries and iccDEV. Followed selected underlying documents where they materially affected recommendations. Administrative, membership, events, unrelated industries and every archive entry were not exhaustively reviewed. Member-only tools and paid normative standards were not independently audited.

Sources include older explanatory papers as well as current registry/specification pages. A webpage's current availability does not make every historical sentence current policy. The starting article itself mixes older discussion with newer iccMAX material; resolve implementation decisions against the current applicable specification. Recommendations above are our synthesis, not an ICC endorsement of Colorgain.

## Palette comparison interface — 17 October 2026

Implemented the agreed global Output Proof and Viewing Illuminant dropdowns in Viewport-Actionbar, replacing the footer Delta switch. Palette cards, palette swatches and compact/expanded previews share labelled Original / Output Proof / selected illuminant rows. Missing targets remain unavailable; D50, D65 and A never create a synthetic colour shift and explicitly require spectral data. Selections persist in app preferences across navigation. The active global print condition is retained when swatches are selected, keeping chart values aligned with the selected proof target.

This implements the comparison interface discussed alongside item 2. It does **not** implement spectral relighting or complete the separate Lab observer correction in F2.


## Settings organisation and Spectral Viewing — 17 October 2026

Proposed organisation following Rick’s request; this section is a design and implementation specification, not a claim of implemented settings or spectral support.

Group the Settings navigation without changing existing page identities:

| Group | Pages |
| --- | --- |
| App & Interaction | General, Shortcuts, Halo, Sounds; Apple Menubar on the Store target |
| Library & Data | Library, Catalogues, Tags, Schema |
| Colour Management | Profiles & Proofing, Measurements & Spectral Viewing, Display & Viewing Environment |
| Connections & Sharing | Appbridge, Sharing |

Colour Management owns durable defaults, linked resources and capability status. The actionbar retains live Output Proof and Viewing Illuminant choices. Existing profile editors and ICC library remain the shared owners; settings should link to/reuse them rather than introduce duplicate stores or editors.

Measurements & Spectral Viewing should contain:

- Enable Spectral Viewing, default off. Until a validated calculation and import workflow exists, show an explicit Not Yet Supported state rather than an operational toggle or file picker that cannot finish.
- Import Spectral Measurements, initially a documented CxF reflectance subset; spectral CGATS can follow. File extension alone is not validation. Require actual wavelength/reflectance samples; a CxF file containing only Lab/RGB values cannot enable relighting.
- Import review: sample IDs, wavelength coverage/spacing, units, measurement conditions, provenance and validation problems. Preserve original data and unknown metadata; reject unsuitable data without publishing partial records.
- Explicit sample-to-swatch linking with conflict review; never assign measurements by nearest RGB alone. Coverage is per swatch, not enabled globally by the presence of one file.
- A defined observer and built-in standard illuminants D50, D65 and A. Keep imported measurement facts separate from calculation defaults. No invented “D*” standard label.
- Availability and diagnostics: which swatches have usable measurements, which cannot be calculated, and why. Unsupported fluorescence or material/measurement models must remain unavailable rather than receive an ordinary reflectance prediction.

Profiles & Proofing groups viewing-profile management, ICC references, tested rendering-intent/black-point-compensation defaults, output-proof defaults and difference tolerances. Display & Viewing Environment groups display association, calibration status and declared viewing assumptions; never imply that a settings value measures or calibrates the display.

Delivery order: establish capability/data contracts and validated reference calculations; implement bounded import and durable measurement storage through the existing file-management architecture; implement review/linking; then expose the enable/import controls and actionbar simulation. Verify predictions against independent reference values, including observer/illuminant changes and invalid or missing samples. Screen presentation remains a prediction, not proof of a physical match.


### Settings navigation implementation

The four groups and their route subtabs are now implemented, retaining existing settings pages and stores. Colour Management contains the three pages above. Profiles & Proofing reuses the existing Preset editor and global Output Proof preference. Spectral and display pages explicitly describe current capability limits; the spectral importer, storage, linking and calculation remain future work. Unsupported illuminant choices are disabled. See [ICC PDF architecture review](ICC-PDF-REVIEW.md) for the supplied standard’s relevant architecture findings and limits.


The separate native Settings window (gear / Command-comma) now groups its existing panels too: App & Interaction (General, Cards & Grid, Shortcuts, Theme, Halo, Permissions, Store-only Edition), Library & Data (Organisation, Catalogues, Projects, Schema, History), Colour Management (Colour, Proofing, Measurements & Spectral Viewing, Display & Viewing Environment), Connections & Sharing (Sync, Export). Each existing panel keeps its controls and any inner sections. New spectral controls explicitly remain disabled; no incomplete importer is exposed as working.


Profile-header follow-up: full selected names determine trigger widths. At Rick’s request, complete label/control pairs wrap onto extra rows like Viewport-Actionbar; header height is derived from the same geometry. This replaces the earlier horizontal-scroll proposal.


### Spectral viewing delivery — 17 October 2026

Operational scope: bounded CxF3-core reflectance import with staged review, original-byte retention and export, explicit catalogue/palette/swatch links, material confirmation, source removal, workspace persistence, optional activation, and D50/D65/A calculation for CIE 1931 2° or CIE 1964 10°. Global preview controls carry through palette and swatch views; missing/invalidated links stay unavailable. Settings owns Measurements and Swatch Links sections.

This is a supported CxF subset, not full ISO/XSD compliance or instrument control. Inputs cover at least 380–730 nm at 1/2/5/10 nm intervals, fractions 0–1; fluorescence, transmission, emission and missing spectral tails are unsupported. ICC LWL 10 nm tables are integrity-checked. Twelve independent 1 nm CIE integrations verify a synthetic fixture, with maximum absolute XYZ discrepancy 0.00104796 (white Y = 1); that is fixture agreement, not a general accuracy bound.

The display uses a fixed D65 reference and includes the illuminant cast; it does not model ambient adaptation. Out-of-display-gamut predictions clip. 10° spectral XYZ is computed directly, but standard 2° RGB encoding makes its screen rendering approximate, not an exact observer conversion. This does not resolve unrelated existing non-spectral observer-conversion limitations. No preview is a physical approval. See [sources and method](ProofingResources/Spectral/SPECTRAL-REFERENCES.md) and [UJ-004](UserJourney.md#uj-004--preview-a-measured-material-under-different-illuminants).

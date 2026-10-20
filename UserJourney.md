# Colorgain user journeys

This is the growing source for Colorgain's help journeys. Each journey explains what you want to achieve, what you do, what Colorgain does, and what you leave with. Entries describe implemented behaviour; help publication is a separate step.

| Journey | What it helps you do | Status |
| --- | --- | --- |
| [UJ-001 — Check the conditions of a measured proof](#uj-001--check-the-conditions-of-a-measured-proof) | Establish whether a measurement can be compared with the selected printing reference, then review and export the result | Implemented; direct-download app verified 17 October 2026 |
| [UJ-002 — Compare one measured colour with a master](#uj-002--compare-one-measured-colour-with-a-master) | Check a sample against a catalogue colour and copy a human decision with its measurement conditions | Implemented; condition blocking and imported precision verified 17 October 2026 |
| [UJ-003 — Find settings and check spectral availability](#uj-003--find-settings-and-check-spectral-availability) | Navigate grouped settings and inspect spectral readiness | Implemented; see UJ-004 for the measurement workflow |
| [UJ-004 — Preview a measured material under different illuminants](#uj-004--preview-a-measured-material-under-different-illuminants) | Import spectral reflectance, link an actual material sample and compare D50, D65 and A | Implemented; import, linking, activation and mixed comparison rows verified natively 17 October 2026 |
| [UJ-005 — Work in a smaller window](#uj-005--work-in-a-smaller-window) | Keep palettes visible and switch between Library and Analysis rails | Implemented; minimum-size native layout and rail switching checked 17 October 2026 |
| [UJ-006 — Navigate the workspace and My Library](#uj-006--navigate-the-workspace-and-my-library) | Switch catalogues and find shared palettes and ICC profiles separately from catalogue files | Implemented; native navigation verified |

## UJ-001 — Check the conditions of a measured proof

**Your goal:** “I have a measured proof. I want to know whether its readings can be compared fairly with the printing condition I selected, and what the checks show.”

**Where you start:** More Tools → PrePress → Verify A Proof.

**What you need:** the printing condition the proof is meant to simulate and a CGATS or CSV measurement file. The file needs patch IDs and Lab readings. Ideally, it also declares the illuminant, observer, measurement mode and backing used when measuring.

### Your journey

| Step | What you do | What Colorgain does and shows |
| --- | --- | --- |
| 1. Choose the reference | Under **Condition**, select the printing condition the proof simulates, such as FOGRA51. | Loads the bundled reference values and shows its measurement conditions and expected control strip. |
| 2. Import your readings | Under **Measure**, choose **Import Measurement…**, select your file and open it. | Reads the file, retains its original values and declarations, and matches patches by ID rather than their order in the file. Shows the filename, patch coverage, declared conditions and available instrument information. |
| 3. Check compatibility | Read **Condition check** and the explanation underneath it. | Compares the declared illuminant, observer, measurement mode and backing with the reference. It distinguishes matching conditions, missing declarations and explicit conflicts. |
| 4. Resolve missing information | If **Needs Confirmation** appears, check the listed assumptions against your measurement records. Choose **Confirm Missing Conditions** only when you know those assumptions are correct. | Allows evaluation using those assumptions and marks them **Confirmed By User**. It keeps the original file declarations unchanged. If you cannot establish the missing conditions, leave the result unevaluated and obtain better information or a replacement measurement. |
| 5. Review the result | Open **Result** and inspect the checks, values and limits. | With compatible or explicitly confirmed conditions, evaluates the seven existing proof checks. Shows **Passed · 7 Of 7 Checks** when they all pass, or explains a failure or unavailable check. Incompatible conditions leave the result **Not Evaluated**, with no passing marks or calculated differences. |
| 6. Keep the evidence | Choose **Export Report…** for a CSV report, or open **Label** and choose **Save Label As PDF…**. Select a destination and save. | Writes the result and condition-validation status. Any user-confirmed assumptions travel with the report or label. An incompatible comparison stays marked unevaluated in the exported evidence. |

### When something needs attention

| What you see | What it means | What you do next |
| --- | --- | --- |
| **Incompatible Conditions**, followed by **Not Evaluated** | A declared condition conflicts with the reference—for example, M0 readings against an M1 reference, or black backing against white backing. | Check that you selected the correct reference and measurement. Obtain compatible readings if necessary. The confirmation button cannot override a declared conflict. |
| **Needs Confirmation** | One or more required conditions are absent from the file. The listed values are assumptions waiting for your confirmation. | Establish the facts from your measurement records. Confirm only those known facts; otherwise obtain a properly described measurement. |
| Missing patches | The file does not contain readings for every expected reference patch ID. | Export a complete measurement with matching IDs. A partial strip cannot produce a complete pass. |
| A duplicate-ID, contradictory-declaration or invalid-file error | The file cannot be used reliably as supplied. | Correct the source/export and import it again. A failed replacement import clears the previous result rather than leaving an old pass visible. |
| **Outside Proof Tolerances** | The comparison has enough information to run, but a numerical check or patch-coverage requirement fails. | Inspect the explanation and affected checks before deciding what needs correcting. |

### What you leave with

You have an on-screen result and, if you save them, a CSV report or PDF label. They distinguish file-declared conditions from assumptions you confirmed. Confirming missing information records your statement; it does not measure or independently verify those conditions.

Importing readings does not change your catalogue's master colours. Choosing another reference or importing another measurement clears the previous confirmation, so the next comparison must establish its conditions again. These imported readings and confirmations belong to the current page session; this journey does not provide an automatically saved proof-session record.

A pass here means the seven implemented checks passed with the stated conditions. It is not, by itself, certification of the entire proofing workflow.

### Example to discuss

With FOGRA51 selected, two files contain identical Lab readings. One declares M1 and white backing; the other declares M0 and white backing. The first can proceed to the numerical checks. The second is blocked even though its colour numbers are identical: the declared measurement conditions do not match.

### Editorial evidence

Reviewed 17 October 2026 against the implemented behaviour and native demonstration. Source: [proof workflow](PrePress.swift), [shared condition checks and import validation](Proofing.swift), [regression checks](SelfTest.swift). This entry covers ICC review action **1**; observer conversion, rendering-engine changes, general colour exchange and exact ICC identity remain separate work.

## UJ-002 — Compare one measured colour with a master

**Your goal:** “I want to compare a printed sample with a colour in my catalogue, then record my decision and the conditions behind it.”

**Where you start:** More Tools → PrePress → Check A Colour.

**What you need:** a catalogue palette containing the master colour, the tolerance you intend to apply, and one measured Lab reading. You can type the reading or import a one-patch CGATS or CSV file.

### Your journey

| Step | What you do | What Colorgain does and shows |
| --- | --- | --- |
| 1. Select the master | Under **Master**, select the palette, colour and tolerance. | Shows the catalogue master and prepares to compare against it. The master itself remains unchanged. |
| 2. Set the comparison context | Under **Measure**, select the printing condition and measurement mode/backing for the comparison. | Uses D50/2° Lab as the comparison context and checks imported declarations against the selected mode/backing. Selecting a printing condition does not establish that the master was physically measured under it. |
| 3. Supply one reading | Type the sample's Lab values, or choose **Import Reading…** and open a one-patch file. | Retains imported decimal precision and the original measurement metadata. A multi-patch file is rejected so the app cannot silently choose the wrong sample. |
| 4. Resolve the conditions | Read the condition status under **Decide**. Confirm listed missing conditions only when you know they are correct. | Blocks comparison and disables **Approve And Copy Record** and **Reject** while conditions are incompatible or unresolved. An explicitly declared D65/10° reading cannot be confirmed into a D50/2° reading. |
| 5. Review the difference | With conditions resolved, inspect the colour difference and tolerance result. | Calculates ΔE00 and explains whether the sample is lighter/darker, redder/greener or yellower/bluer than the master. The preview is an aid to inspection. |
| 6. Make your decision | Choose **Approve And Copy Record** or **Reject**. | Records your decision on the page and copies a text record to the clipboard. The record includes the comparison, conditions, confirmed assumptions and, for an imported reading, its source identity and exact sample values. It does not decide approval for you. |

### What you leave with

You have a decision record on the clipboard to paste into your job notes or another document. **It is not yet saved as a permanent swatch approval.** Paste and retain it where you keep the job's evidence before closing the session.

Editing a reading removes its association with the imported file and requires its conditions to be confirmed again as a manually entered reading. Changing the selected measurement context also clears its confirmation. Replacing a reading clears the earlier decision; a failed import cannot leave an old sample ready for approval.

### Example to discuss

You import a reading that declares D65 and a 10° observer. Colorgain keeps the full Lab values but shows **Incompatible Conditions** and disables the decision buttons. Obtain an appropriate D50/2° reading or a properly documented conversion outside this workflow; changing the comparison label cannot convert the original measurement.

### Editorial evidence

Reviewed 17 October 2026. Imported D65/10° blocking, disabled decisions and retained decimal precision were checked in the native app. Source: [Check A Colour](PrePress.swift) and [condition comparison](Proofing.swift). Permanent approval storage is future work and must not be described as available in help.


## UJ-003 — Find settings and check spectral availability

**Your goal:** “I want to find the right settings without searching a long list, and understand whether I can preview a material under different lights.”

**Where you start:** the Settings gear or App menu → Settings… (Command-comma).

**What you need:** an open workspace. No measurement file is required to inspect the feature’s status.

| Step | What you do | What Colorgain does and shows |
| --- | --- | --- |
| 1. Choose a group | Select App & Interaction, Library & Data, Colour Management or Connections & Sharing. | Shows the relevant subtabs. Existing settings and their saved values remain available in their groups. Some subtabs contain a further row of section choices. |
| 2. Set output comparison | Select Colour Management → Proofing, then change Show Output Proof. | Updates the same global setting used by the palette actionbar. The chosen output comparison carries through palette and swatch views. It is a predicted comparison, not a measured approval. |
| 3. Check spectral readiness | Select Measurements & Spectral Viewing. | Shows the measurement import, observer and activation controls. Swatch Links explicitly associates measurements with catalogue swatches; see UJ-004. |
| 4. Understand display assumptions | Select Display & Viewing Environment. | Explains that Colorgain does not calibrate or measure the display, and selecting an illuminant does not establish an unmeasured material’s appearance. |
| 5. Return later | Close Settings and reopen it. | Returns to your selected group and subtab. Output Proof is saved automatically; there is no separate Save action for it. |

### What you leave with

You can locate the existing settings through groups and subtabs, and control the global Output Proof comparison. Spectral viewing requires supported reflectance measurements and explicit swatch links. Importing an ordinary RGB or Lab palette cannot activate it. Normal remains available; enabling Spectral Viewing unlocks D50, D65 and A.

### Editorial evidence

Reviewed 17 October 2026 in the native direct-download debug app. Verified all four group layouts, Colour Management subtabs, disabled spectral activation, Settings reopening on the selected subtab, and a Proofing change appearing as Output Proof: On in the workspace. Sources: [native settings](SettingsWindow.swift), [embedded settings routes](StudioSettings.swift), [comparison controls](DeltaWarningButton.swift). Updated for the operational spectral workflow on 17 October 2026; its verification scope is recorded in UJ-004.


## UJ-004 — Preview a measured material under different illuminants

**Your goal:** “I want to explore how my measured ink, paint or other opaque material could appear under daylight or incandescent illumination.”

**Where you start:** Settings → Colour Management → Measurements & Spectral Viewing.

**What you need:** the material’s actual spectral reflectance measurement in the supported CxF3-core subset, and its catalogue palette swatch. Samples must cover at least 380–730 nm at 1, 2, 5 or 10 nm spacing, using fractions from 0 to 1. RGB/Lab values alone, fluorescent materials, transparent materials and emitted light are unsuitable for this workflow.

| Step | What you do | What Colorgain does and shows |
| --- | --- | --- |
| 1. Import | In Measurements, choose **Import Spectral Measurements…** and select your CxF file. | Validates its spectral data and shows a review before saving. Rejects malformed or unsupported data without replacing existing measurements. |
| 2. Keep the source | Check the review and choose **Add Measurements**, or **Cancel Import**. | Add retains the original file, sample identifiers, reflectance samples and declared metadata in your workspace. It neither changes master colours nor guesses links from RGB. |
| 3. Identify the material | In **Swatch Links**, select the measured sample, palette and swatch. Read its wavelength coverage, declared conditions, source identity and calculated XYZ values. | Shows any existing link. Missing measurement conditions remain explicitly undeclared. |
| 4. Link | Confirm **This Is An Opaque, Non-Fluorescent Material**, then choose **Link Sample To Swatch**. | Saves an explicit association scoped to this workspace, catalogue, palette and colour definition. Your confirmation records a material assumption; it does not verify the physical sample. |
| 5. Enable | Return to Measurements, choose the **Observer**, then turn on **Enable Spectral Viewing**. | Validates its reference tables and unlocks the actionbar illuminants. Observer changes recalculate from the spectrum. |
| 6. Compare | In the palette actionbar choose **D50**, **D65** or **A** under Viewing Illuminant. Optionally turn **Output Proof** on. | Keeps Original first, optional Output Proof second, and the illuminant prediction in its own aligned row. Unlinked swatches show **No Measurement**. Choices carry through the palette and compact/expanded swatch views. |
| 7. Return or manage | Choose **Normal** to hide the illuminant row. In Settings, remove a swatch link, export its original CxF or remove a source when needed. | Export preserves the original source bytes. Removing a source removes its dependent links, after confirmation, without changing catalogue master colours. Turning the feature off returns the actionbar to Normal. |

### When something needs attention

A file with only RGB/Lab values cannot describe spectral reflectance. Obtain an appropriate measurement export; changing its extension cannot supply missing data. Measurements starting at 400 nm or using 20 nm intervals are outside this importer’s supported subset. Colorgain does not invent the missing wavelengths.

A link is invalidated if its colour definition changes. Recheck the physical association and relink deliberately. A measurement linked in one palette is not automatically trusted in another. Newer spectral metadata this version cannot safely edit makes that section read-only, preserving the original records.

### What you leave with

Your imported original files, measurements, links, observer and activation state are retained in the workspace automatically. Master colours remain unchanged. The actionbar choices are global app preferences.

The result is an approximate screen preview in a fixed D65 display context, including the illuminant cast. It is not a prediction of your eye’s adaptation to the room, a display calibration or a physical approval. Display-gamut clipping can hide differences. Calculated 10° XYZ values are mapped through standard 2° RGB for an approximate preview; this is not an exact observer conversion.

### Editorial evidence

Reviewed 17 October 2026 against [spectral models](SpectralViewing.swift), [settings](SettingsWindow.swift), [shared rows](DeltaWarningButton.swift), [palette/swatch rendering](PaletteWheel.swift) and [regression checks](SpectralTests.swift). Twelve ICC weighting-table cases are checked against independent 1 nm CIE integration; the synthetic fixture’s maximum absolute XYZ discrepancy is 0.00104796 (white Y = 1), not a universal accuracy guarantee. Native installed-build checks covered CxF review and saving, explicit linking, activation, D50 with a linked and an unlinked colour, and the three-row combination with Output Proof. Compact/expanded swatch routing is implemented but was not separately exercised in that native walkthrough. Reference provenance and restrictions: [Spectral references](ProofingResources/Spectral/SPECTRAL-REFERENCES.md).

## UJ-005 — Work in a smaller window

**Your goal:** “I want to keep working with my palettes when the app window is smaller.”

**Where you start:** Library or Palettes, with an open workspace.

**What you need:** a window at or above the supported minimum width of 1200 points.

| Step | What you do | What Colorgain does and shows |
| --- | --- | --- |
| 1. Resize | Make the window narrower. | Moves Layout and the picker controls to a separate row within the existing header. Keeps text readable and avoids overlapping navigation. |
| 2. Browse | Continue using the Library rail. | At narrow widths, shows one full-width rail at a time, leaving more working space for palettes. Filters stay grouped; Output Proof and Viewing Illuminant remain available. |
| 3. Inspect | Use **Show Analysis Rail**, the right sidebar icon beside Grid/List in the viewport footer. | Shows the analysis panels and hides the Library rail at narrow widths. The palette and comparison choices remain selected. |
| 4. Return or clear space | Use **Show Library Rail**, or use the active rail’s **Hide** control. | Switches back to Library or hides both rails to give the viewport more space. Hover tooltips name each action. |
| 5. Widen | Enlarge the window again. | Returns to the wide-window rail choices. The temporary narrow-window choice does not overwrite those choices. |

### What you leave with

You can browse and inspect colours without squeezing the palette between two expanded sidebars. These rail choices belong to the current window session; they do not change catalogue colours or measurement records. Navigation uses underline feedback, without filled background blocks.

### Editorial evidence

Reviewed 17 October 2026 against [responsive geometry and rail controls](StudioWorkspace.swift), [header and workspace layout](StudioWindow.swift) and [filter geometry](PaletteAssetControls.swift). Native checks used a 1200 × 800 content area and verified the header, complete palette card and switching to Analysis. Automated geometry checks cover widths 1200, 1366, 1440, 1600 and 1920. This entry does not claim separate native verification at every intermediate width.


### Library comparison scope — 17 October 2026

When browsing the palette library, the user sees Output Proof only. Turning it on compares Original and Output Proof; turning it off restores the ordinary colour strip. The library never shows spectral illuminant rows or missing-measurement cells, even if D50, D65 or A was previously selected. Measurements and links are retained. Viewing Illuminant remains on the selected palette page and its swatch views for the next design step.


## UJ-006 — Navigate the workspace and My Library

**Your goal:** Find catalogue files, library palettes and ICC profiles without confusing their roles.

| What you do | What Colorgain does |
| --- | --- |
| Expand Catalogues and open its catalogue dropdown. | Lists available catalogues. Import Catalogue… appears after a divider and opens the existing catalogue chooser. |
| Select a catalogue. | Opens it and uses its name above its file tree. |
| Expand My Favourites. | Shows the current catalogue’s existing favourite links. |
| Browse the section named after your catalogue. | Shows its collections, projects and schema groups; Library is no longer mixed into those files. |
| Press the pin beside a catalogue file-tree node. | Focuses that section on the chosen node and its children. Only one node is pinned; My Library and favourites remain separate. |
| Press Back above the focused branch. | Restores the full catalogue file tree without moving files. |
| Expand My Library → Library → Palettes. | Shows the library palette entries previously presented separately as My Palettes, including retained claimed copies. Selecting Palettes opens the catalogue’s full palette view. |
| Expand My Library → Library → ICC Profiles. | Shows the existing profile search, linking controls, Refresh and system/linked profiles. Selecting a profile retains its details and target/locate/remove actions. |
| Open Schema settings. | Shows the fixed Workspace Structure reference alongside the editable catalogue structure. Workspace navigation is not a set of editable catalogue folders. |

**What you leave with:** One navigation home for the active catalogue, its favourites, library palettes and ICC profiles. Palette assets and catalogue folders stay where they were. Section and tree expansion choices are retained through the existing workspace preferences.

**Editorial evidence:** Reviewed 17 October 2026 against the installed build: Workspace heading, catalogue choices and Import Catalogue divider, renamed catalogue section, My Library position, expanded Palettes entries and embedded ICC search/link/refresh controls were verified natively. Build self-tests: 1,243 passed, 0 failed. Additional native verification in the 05:58 BST installed build covered Catalogues collapsing, equal collapsed section heights, ICC standard row geometry and the footer divider/background. Pinning Colorgain and returning through Back were exercised in the preceding installed build of the same focus implementation. Schema reference was checked in source; no new catalogue import or data migration was exercised.

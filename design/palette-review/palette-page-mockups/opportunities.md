# Colorgain palette-page design review

2026-10-04 · Static concepts only. No application implementation or behaviour changes.

## What the screenshots suggest

The interface has a coherent neutral character and useful colour-led navigation. The pressure comes from hierarchy, not simply a shortage of pixels. Tiny labels, values, controls and history entries compete at similar sizes; meanwhile, large areas below the active content remain empty. Increasing every gap would preserve that problem at a larger scale.

The main opportunity is to decide what is needed **now**, what belongs to the **selected colour**, and what is available **on demand**. These mockups keep the catalogue tree, palette identity, neutral chrome and visible source colours. They remove the permanent second navigation rail and repeated per-colour histories from the default page.

## Five alternatives

| Direction | What changes | Best use | Trade-off |
|---|---|---|---|
| 01 Refined familiar | Palette strip, readable rows, selected-colour inspector. Purpose controls move above the palette. | Least disruptive everyday workspace. | Inspector takes horizontal space; below 860 px it moves below the list in the study. |
| 02 Colour first | Five samples above one shared detail area. Names and HEX remain visible; additional values follow selection. | Small studios, creative review and learning the palette. | Less convenient for comparing several numeric channels at once. |
| 03 Precision table | One aligned table with common headers, consistent precision and measurement context. | Scientific comparison, enterprise checking and repeatable review. | More technical first impression; best offered as a saved view rather than the only entry point. |
| 04 Purpose workspace | A visible purpose row and explicit source/target pairing. Unevaluated targets stay empty. | Output preparation and profile reasoning. | Adds a deliberate evaluation step; target-setting behaviour needs product validation. |
| 05 Guided studio | A short review → output → export sequence and optional contextual help. | Education and first use. | Experienced users need an easy way to hide guidance and retain their preferred view. |

Each direction has matching dark and white-theme PNGs. All app actions are inert. The comparison viewer's design/theme selectors are the only working controls.

## Typography and spacing

Proposed working scale, expressed in logical pixels/points rather than screenshot pixels:

- Page title: 25, semibold. Section title: 14, semibold. Colour names and controls: 12–13. Secondary labels: 11–12. Do not reproduce the current screenshot's tiny text as a density target.
- Content inset: 30 at desktop widths, 23 in the narrower study, 18 for a compact preview. Section separation: 24–32. Related label/value gaps: 6–10.
- Navigation rows: at least 32 high. Swatch list rows: approximately 77 high, with a 43-square sample. A dense option should be deliberate, not the only option.
- Numeric text: tabular/monospaced only where it aids comparison. Names and descriptions retain the system sans-serif. Align common quantities under shared headers.
- Dark surfaces: neutral charcoal, with clear boundaries between sidebar and work area. White theme: white work area and light neutral navigation; no tinted background that competes with colour samples.

These are starting measurements for review, not approved accessibility specifications or native implementation tokens. Test at the user's actual display scale before committing.

## Rail 1: keep its identity, reduce its burden

The study uses a 208 px catalogue rail, reducing to 184 px in the narrower desktop layout. This is a visual comparison range, not a recommendation to lock the width. A future native design should permit resizing and remember it. At 1440 logical pixels, 208 px uses about 14% of the width; at 1024, 184 px uses about 18%.

Show the active project's palettes in the tree. Keep the full palette library under **All palettes** instead of repeating the same long list below the project list. Preserve Favourites for cross-project access. Search belongs near the top, so navigation does not depend on recognising truncated names.

Before choosing a width, test realistic long project names, localised labels, 100+ palettes, deeply nested projects and keyboard navigation. A narrow icon-only rail would sacrifice recognisability. In production, full names should be available without requiring pointer hover. The compact study collapses the tree into a location label only to keep the review usable on small screens; that is not a proposed mobile application design.

## Missed opportunities to review

### 1. A clear default view, with a visible path to depth

**Appearance:** start with name, colour, HEX and relevant status; place “Show all measurements” or a named view beside the section title. The selected-colour inspector contains channels, notes and detailed contrast. Histograms and history are available through named sections.

**Why:** professional depth can remain complete without being simultaneously visible. Consider saved “Essential”, “Measurement” and “Proof” views. Do not hide gamut warnings or invalid data when simplifying.

### 2. Explain source, target and viewing assumptions together

**Appearance:** “Source: sRGB → Target: Display P3”, followed by intent and evaluation state. A target without a result gets a clear placeholder, never a duplicate of the source pretending to be a proof.

**Why:** numeric accuracy without context is easy to misunderstand. For future output views, make profile identity/version, intent, adaptation and relevant viewing assumptions inspectable. Keep unknown, unevaluated, out-of-gamut and acceptable results distinct.

The mock's contrast ratios are calculated from the shown sRGB HEX values against pure white/black. No Display P3 or print conversions have been invented. Ratios are rounded for display; thresholds should always use unrounded values. The conversion settings in direction 04 are a proposed UI, not confirmed existing behaviour.

### 3. Turn unexplained status into an answer

**Appearance:** replace terse phrases such as “All 5 Hold” with an explicit result and scope, for example “5 of 5 within the selected target gamut” only after evaluation. A detail disclosure explains the profile and criterion.

**Why:** beginners need the meaning; professionals need the conditions. Pair status colour with words and, where useful, a symbol. Do not reuse a general “pass” label across contrast, gamut and colour-difference checks.

### 4. Teach beside the relevant decision

**Appearance:** a dismissible “What is a profile?” explanation beside output settings, as in direction 05. Brief definitions can expand into a worked example without covering the palette.

**Why:** a guided first project can reduce the learning burden more effectively than a tour of every toolbar icon. Guidance should be optional, keyboard accessible and remembered per workspace; the underlying workflow stays the same for everyone.

### 5. Make enterprise trust visible without enterprise clutter

**Appearance:** a compact palette details disclosure for owner, revision, source profile and review state. An optional review panel shows what changed and who approved it. Keep full history out of every swatch row.

**Why:** studios and larger teams need handoff confidence. These are opportunities, not claims that access control, approvals or immutable audit records already exist. Clarify the actual collaboration model before adding status that implies governance.

### 6. Separate a palette from its destinations

**Appearance:** purpose tabs or a concise purpose selector. The same source palette remains visible while target settings change. A proof summary belongs to the destination, not to a permanent mutation of the original colour.

**Why:** this expresses the app's central promise and prevents the newcomer from treating six purposes as six unrelated palettes. Test whether novice users understand this relationship before choosing tabs versus a selector.

### 7. Reserve attention for actionable exceptions

**Appearance:** one summary near the relevant target, with affected swatches clearly indicated. Successful rows remain visually quiet; errors include a next step.

**Why:** twenty green badges can obscure one serious warning. Review how unknown profiles, missing files, unavailable transforms and sync conflicts should appear before polishing success states.

### 8. Treat theme as viewing context

**Appearance:** identical data and layout across both themes, with neutral surfaces and a consistent sample size. A future optional neutral surround could be independent of the navigation theme.

**Why:** the surround changes perceived colour. Do not suggest that matching on-screen appearance alone validates an output. Keep colour-management state separate from cosmetic theme choice.

## Suggested review exercise

Compare 01 and 02 first for the default page; use 03 as a possible specialist view and borrow the explicit output context from 04. Treat 05's guidance as an optional layer, rather than a separate simplified product.

Ask an experienced colour professional and a first-time studio user to locate a colour, identify its source profile, find a target result, choose readable text, and explain what has not yet been checked. Observe hesitation before asking for aesthetic preferences. Then repeat with long names, 30 swatches and a warning state.
